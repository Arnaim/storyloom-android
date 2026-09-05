import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/database.dart';
import '../engine/gemini_api.dart';
import '../models/story.dart';
import 'widgets.dart';

/// The immersive story screen: narration + dialogue, suggested actions,
/// free-form input, continue/regenerate, and world-state side panels.
class PlayerRoute extends StatefulWidget {
  const PlayerRoute({super.key, required this.story});

  final Story story;

  @override
  State<PlayerRoute> createState() => _PlayerRouteState();
}

class _PlayerRouteState extends State<PlayerRoute> {
  late Story _story;
  late int _storyId;
  final List<StoryMessage> _messages = [];
  List<StoryNPC> _npcs = const [];
  List<Quest> _quests = const [];
  List<InventoryItem> _inventory = const [];
  List<Memory> _memories = const [];

  final _input = TextEditingController();
  final _scroll = ScrollController();

  bool _loading = true;
  bool _busy = false;
  bool _streaming = false;
  String _stream = '';
  bool _immersive = false;
  bool _actionMode = false; // input mode: narrated action vs spoken dialogue
  int _localSeq = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _story = widget.story;
    _storyId = widget.story.id;
    _localSeq = widget.story.lastMessageSeq;
    _reload(scrollToBottom: true);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload({bool scrollToBottom = false}) async {
    final db = AppDatabase.instance;
    final story = await db.getStory(_storyId);
    final results = await Future.wait([
      db.messagesForStory(_storyId),
      db.npcsForStory(_storyId),
      db.questsForStory(_storyId),
      db.inventoryForStory(_storyId),
      db.memoriesForStory(_storyId),
    ]);
    if (!mounted) return;
    setState(() {
      if (story != null) _story = story;
      _messages
        ..clear()
        ..addAll(results[0] as List<StoryMessage>);
      _npcs = results[1] as List<StoryNPC>;
      _quests = results[2] as List<Quest>;
      _inventory = results[3] as List<InventoryItem>;
      _memories = results[4] as List<Memory>;
      _loading = false;
      if (_story.lastMessageSeq > _localSeq) _localSeq = _story.lastMessageSeq;
    });
    if (scrollToBottom) {
      _jumpToBottom(animated: false);
    }
  }

  void _onChunk(String delta) {
    if (delta.trim().isEmpty) return;
    setState(() => _stream += delta);
    _jumpToBottom(animated: true);
  }

  void _jumpToBottom({required bool animated}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (animated) {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  // ------------------------------------------------------------------- //
  // Actions
  // ------------------------------------------------------------------- //
  Future<void> _send(String text,
      {bool isContinue = false, bool isAction = false}) async {
    final trimmed = text.trim();
    if (_busy || (trimmed.isEmpty && !isContinue)) return;
    FocusScope.of(context).unfocus();
    final engine = context.read<AppState>().engine;

    setState(() {
      _busy = true;
      _stream = '';
      _streaming = true;
      _error = null;
    });
    if (!isContinue && trimmed.isNotEmpty) {
      final actionFlag = isAction || StoryMessage.isActionSyntax(trimmed);
      final clean = StoryMessage.stripActionSyntax(trimmed);
      _localSeq += 1;
      _messages.add(StoryMessage(
        storyId: _storyId,
        seq: _localSeq,
        role: 'user',
        kind: actionFlag ? 'action' : 'speech',
        content: clean,
      ));
      _input.clear();
      _jumpToBottom(animated: false);
    }
    try {
      await engine.runTurn(
        _storyId,
        trimmed,
        isContinue: isContinue,
        isAction: isAction,
        onChunk: _onChunk,
      );
    } on AiException catch (e) {
      _fail('Couldn\'t continue the story.\n${e.message}');
    } catch (e) {
      _fail('Something went wrong generating the story.\n$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _streaming = false;
          _stream = '';
        });
        await _reload(scrollToBottom: false);
      }
    }
  }

  Future<void> _regenerate() async {
    if (_busy) return;
    final engine = context.read<AppState>().engine;
    setState(() {
      _busy = true;
      _stream = '';
      _streaming = true;
      _error = null;
    });
    try {
      await engine.regenerate(_storyId, onChunk: _onChunk);
    } on AiException catch (e) {
      _fail('Could not regenerate.\n${e.message}');
    } catch (e) {
      _fail('Could not regenerate.\n$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _streaming = false;
          _stream = '';
        });
        await _reload(scrollToBottom: false);
      }
    }
  }

  Future<void> _beginStory() async {
    if (_busy || _messages.isNotEmpty) return;
    final engine = context.read<AppState>().engine;
    setState(() {
      _busy = true;
      _streaming = true;
      _error = null;
      _stream = '';
    });
    try {
      await engine.generateOpening(_storyId);
    } on AiException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('Could not begin the story.\n$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _streaming = false;
        });
        await _reload(scrollToBottom: true);
      }
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _error = message);
    _jumpToBottom(animated: true);
  }

  // ------------------------------------------------------------------- //
  // Build
  // ------------------------------------------------------------------- //
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _immersive
          ? Theme.of(context).scaffoldBackgroundColor
          : null,
      appBar: _immersive ? null : _buildAppBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _messages.isEmpty && !_streaming
              ? _buildEmpty()
              : _buildStory(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_story.title,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          if (_location.isNotEmpty)
            Text(_location,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.primary)),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Immersive',
          icon: const Icon(Icons.fullscreen),
          onPressed: () => setState(() => _immersive = true),
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          enabled: !_busy && _messages.isNotEmpty,
          onSelected: (v) {
            switch (v) {
              case 'world':
                _openInfo();
              case 'continue':
                _send('', isContinue: true);
              case 'regenerate':
                _regenerate();
              case 'restart':
                _confirmRestart();
              case 'delete':
                _confirmDelete();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'world',
                child: ListTile(leading: Icon(Icons.inventory_2_outlined),
                    title: Text('World / Items'), contentPadding: EdgeInsets.zero)),
            PopupMenuItem(value: 'continue',
                child: ListTile(leading: Icon(Icons.play_arrow_outlined),
                    title: Text('Continue scene'), contentPadding: EdgeInsets.zero)),
            PopupMenuItem(value: 'regenerate',
                child: ListTile(leading: Icon(Icons.refresh),
                    title: Text('Regenerate last'), contentPadding: EdgeInsets.zero)),
            PopupMenuItem(value: 'restart',
                child: ListTile(leading: Icon(Icons.restart_alt_outlined),
                    title: Text('Restart story'), contentPadding: EdgeInsets.zero)),
            PopupMenuItem(value: 'delete',
                child: ListTile(leading: Icon(Icons.delete_outline, color: Colors.redAccent),
                    title: Text('Delete story', style: TextStyle(color: Colors.redAccent)),
                    contentPadding: EdgeInsets.zero)),
          ],
        ),
      ],
    );
  }

  String get _location {
    final world = _story.currentState['world'];
    if (world is Map && world['current_location'] is String) {
      return world['current_location'] as String;
    }
    return '';
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories_outlined,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text('Every story begins with a single scene.',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _beginStory,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow),
              label: Text(_busy ? 'Writing…' : 'Begin the story'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStory() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              ListView(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  for (final m in _messages) ...[
                    GestureDetector(
                      onLongPress: () => _showMessageMenu(m),
                      child: _MessageView(
                        message: m,
                        onSuggestion: _send,
                        onRegenerate: _messages.lastIndexWhere((x) =>
                                !x.isUser && x.kind == 'narration') ==
                            _messages.indexOf(m)
                            ? (m.variants.isNotEmpty && !_busy ? _regenerate : null)
                            : null,
                        isLastAssistantMessage: _messages.lastIndexWhere((x) =>
                                !x.isUser && x.kind == 'narration') ==
                            _messages.indexOf(m),
                        onRewind: _rewindAndSend,
                        messageSeq: m.seq,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_streaming && _stream.isNotEmpty)
                    _StreamTail(text: _stream),
                  const SizedBox(height: 8),
                ],
              ),
              if (_immersive)
                Positioned(
                  top: 0,
                  left: 8,
                  child: SafeArea(
                    child: IconButton.filledTonal(
                      tooltip: 'Exit immersive',
                      icon: const Icon(Icons.fullscreen_exit),
                      onPressed: () => setState(() => _immersive = false),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_error != null) _ErrorBanner(message: _error!, onRetry: _retryLast),
        _buildInputBar(),
      ],
    );
  }

  void _retryLast() {
    if (_error == null) return;
    final lastUser = _messages.lastWhere((m) => m.isUser,
        orElse: () => _messages.isEmpty
            ? StoryMessage(storyId: _storyId, seq: 0, role: 'user', content: '')
            : StoryMessage(storyId: _storyId, seq: 0, role: 'user', content: ''));
    if (lastUser.seq == 0) {
      _beginStory();
    } else {
      _send(lastUser.content, isAction: lastUser.isUserAction);
    }
  }

  /// Long-press menu on any message: delete it (and everything after), or
  /// rewind the world to right after this message.
  Future<void> _showMessageMenu(StoryMessage m) async {
    if (_busy) return;
    final isLast = m.seq == _messages.last.seq;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                m.isUser
                    ? (m.isUserAction ? 'Your action' : 'You said')
                    : m.isSystem
                        ? m.content
                        : (m.speaker.isNotEmpty ? m.speaker : 'Narration'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            if (!isLast)
              ListTile(
                leading: const Icon(Icons.undo),
                title: const Text('Return to this point'),
                subtitle: const Text('Delete everything after this message and continue from here'),
                onTap: () => Navigator.pop(ctx, 'rewind'),
              ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Delete from here',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              subtitle: Text(isLast
                  ? 'Remove this message'
                  : 'Remove this message and everything after it'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'rewind') {
      _rewindToPoint(m.seq);
    } else if (action == 'delete') {
      _confirmDeleteFrom(m.seq);
    }
  }

  /// Pure rewind (no new action) — returns the world to right after [seq].
  Future<void> _rewindToPoint(int seq) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Return to this point?'),
        content: const Text(
            'The story continues from this moment. Everything after it is removed, '
            'and the world is restored to how it was.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Return')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final engine = context.read<AppState>().engine;
    setState(() {
      _busy = true;
      _streaming = true;
      _error = null;
      _stream = '';
    });
    try {
      await engine.rewindTo(_storyId, seq, '', onChunk: _onChunk);
    } on AiException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('Could not return to that point.\n$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _streaming = false;
          _stream = '';
        });
        await _reload(scrollToBottom: false);
      }
    }
  }

  Future<void> _confirmDeleteFrom(int seq) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete from here?'),
        content: const Text(
            'This message and everything after it will be permanently removed. '
            'The world stays as it is right now.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await AppDatabase.instance.deleteMessagesAfterSeq(_storyId, seq - 1);
    await _reload(scrollToBottom: false);
  }

  Widget _buildInputBar() {
    final scheme = Theme.of(context).colorScheme;
    final canContinue = !_busy && _messages.any((m) => !m.isUser);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(_actionMode ? Icons.directions_run : Icons.chat_bubble_outline,
                    size: 14, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _actionMode
                        ? 'Action mode — narrate what you do: *i gazed at her*'
                        : 'Speech mode — say it out loud. Type *like this* for a quick action.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Say / Do mode toggle
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6, left: 2),
                    child: Tooltip(
                      message: _actionMode
                          ? 'Switch to speech'
                          : 'Switch to action (*like this*)',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: _busy
                            ? null
                            : () => setState(() => _actionMode = !_actionMode),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: _actionMode
                                ? scheme.primary
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_actionMode
                                      ? Icons.directions_run
                                      : Icons.chat_bubble_outline,
                                  size: 16,
                                  color: _actionMode
                                      ? scheme.onPrimary
                                      : scheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(_actionMode ? 'Do' : 'Say',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: _actionMode
                                            ? scheme.onPrimary
                                            : scheme.onSurfaceVariant,
                                      )),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (canContinue)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6, left: 4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _busy ? null : () => _send('', isContinue: true),
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.skip_next, size: 18),
                              Text('Continue',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: !_busy,
                      minLines: 1,
                      maxLines: 4,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: _actionMode
                            ? '*i gazed at her*'
                            : 'What do you say?',
                        border: InputBorder.none,
                        filled: false,
                      ),
                      onSubmitted: (v) {
                        if (v.trim().isNotEmpty) {
                          _send(v, isAction: _actionMode);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    height: 44,
                    width: 44,
                    child: IconButton.filled(
                      tooltip: 'Send',
                      onPressed: _busy
                          ? null
                          : () {
                              if (_input.text.trim().isNotEmpty) {
                                _send(_input.text, isAction: _actionMode);
                              }
                            },
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.2),
                            )
                          : const Icon(Icons.arrow_upward),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openInfo() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StoryInfoSheet(
        story: _story,
        npcs: _npcs,
        quests: _quests,
        inventory: _inventory,
        memories: _memories,
      ),
    );
  }

  void _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete story?'),
        content: Text(
            'This will permanently delete "${_story.title}" and all its messages.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await AppDatabase.instance.deleteStory(_storyId);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _confirmRestart() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restart story?'),
        content: Text(
            'This will reset "${_story.title}" to the beginning. All progress will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restart'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _restartStory();
    }
  }

  Future<void> _restartStory() async {
    if (_busy) return;
    final engine = context.read<AppState>().engine;
    setState(() {
      _busy = true;
      _streaming = true;
      _error = null;
      _stream = '';
    });
    try {
      await engine.restartStory(_storyId);
    } on AiException catch (e) {
      _fail('Could not restart the story.\n${e.message}');
    } catch (e) {
      _fail('Could not restart the story.\n$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _streaming = false;
        });
        await _reload(scrollToBottom: true);
      }
    }
  }

  Future<void> _rewindAndSend(int targetSeq, String actionText) async {
    if (_busy) return;
    final engine = context.read<AppState>().engine;
    setState(() {
      _busy = true;
      _streaming = true;
      _error = null;
      _stream = '';
    });
    try {
      await engine.rewindTo(_storyId, targetSeq, actionText, onChunk: _onChunk);
    } on AiException catch (e) {
      _fail('Could not rewind and continue.\n${e.message}');
    } catch (e) {
      _fail('Could not rewind and continue.\n$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _streaming = false;
          _stream = '';
        });
        await _reload(scrollToBottom: false);
      }
    }
  }

}

/// Parses a narration into prose + dialogue blocks and renders them with
/// distinct typography so the screen reads like an interactive novel.
class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.message,
    required this.onSuggestion,
    required this.onRegenerate,
    required this.isLastAssistantMessage,
    required this.onRewind,
    required this.messageSeq,
  });

  final StoryMessage message;
  final void Function(String, {bool isContinue}) onSuggestion;
  final VoidCallback? onRegenerate;
  final bool isLastAssistantMessage;
  final void Function(int targetSeq, String actionText) onRewind;
  final int messageSeq;

  @override
  Widget build(BuildContext context) {
    if (message.isUser) return _buildUser(context);
    if (message.isSystem) return _buildSystem(context);
    return _buildNarration(context);
  }

  Widget _buildUser(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isAction = message.isUserAction;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isAction
              ? scheme.tertiaryContainer.withValues(alpha: 0.7)
              : scheme.primaryContainer,
          borderRadius: BorderRadius.circular(18),
          border: isAction
              ? Border.all(color: scheme.tertiary.withValues(alpha: 0.5))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(isAction ? 'ACTION' : 'YOU',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: isAction ? scheme.tertiary : scheme.primary)),
            const SizedBox(height: 2),
            SelectableText(
                isAction ? '\u2731 ${message.content}' : message.content,
                style: TextStyle(
                    color: isAction
                        ? scheme.onTertiaryContainer
                        : scheme.onPrimaryContainer,
                    fontStyle: isAction ? FontStyle.italic : FontStyle.normal,
                    height: 1.35)),
          ],
        ),
      ),
    );
  }

  Widget _buildSystem(BuildContext context) {
    final icon = mapKindIcon[message.kind] ?? Icons.info_outline;
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: scheme.secondary),
            const SizedBox(width: 6),
            Flexible(
              child: SelectableText(
                message.content,
                style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNarration(BuildContext context) {
    final blocks = _splitNarration(message.activeContent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final b in blocks) ..._cellFor(b, context),
        if (message.suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in message.suggestions)
                ActionChip(
                  label: Text(s),
                  onPressed: () {
                    if (isLastAssistantMessage) {
                      onSuggestion(s);
                    } else {
                      _showRewindChoice(context, s);
                    }
                  },
                ),
              if (onRegenerate != null)
                ActionChip(
                  avatar: const Icon(Icons.refresh, size: 16),
                  label: const Text('Regenerate'),
                  onPressed: onRegenerate,
                ),
            ],
          ),
        ] else if (onRegenerate != null)
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              tooltip: 'Regenerate',
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: onRegenerate,
            ),
          ),
      ],
    );
  }

  void _showRewindChoice(BuildContext context, String actionText) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Rewind to this point'),
              subtitle: const Text('Delete later messages and continue from here'),
              onTap: () {
                Navigator.pop(ctx);
                onRewind(messageSeq, actionText);
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_forward),
              title: const Text('Continue from now'),
              subtitle: const Text('Add as new action at current timeline end'),
              onTap: () {
                Navigator.pop(ctx);
                onSuggestion(actionText);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _cellFor(_NarrationBlock block, BuildContext context) {
    final theme = Theme.of(context);
    if (block.isDialogue) {
      return [
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
            border: Border(
              left: BorderSide(color: theme.colorScheme.primary, width: 3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(block.speaker!,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      color: theme.colorScheme.primary)),
              const SizedBox(height: 2),
              SelectableText('"${block.quote}"',
                  style: TextStyle(
                      fontSize: 15.5,
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                      color: theme.colorScheme.onSurface)),
            ],
          ),
        ),
        if (block.trailing != null && block.trailing!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SelectableText(block.trailing!.trim(),
                style: TextStyle(fontSize: 15, height: 1.45)),
          ),
      ];
    }
    return [
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: SelectableText(
          block.prose ?? '',
          style: TextStyle(fontSize: 15.5, height: 1.55),
        ),
      ),
    ];
  }
}

class _NarrationBlock {
  const _NarrationBlock.prose(this.prose)
      : isDialogue = false,
        speaker = null,
        quote = null,
        trailing = null;
  const _NarrationBlock.dialogue(this.speaker, this.quote, this.trailing)
      : isDialogue = true,
        prose = null;

  final bool isDialogue;
  final String? prose;
  final String? speaker;
  final String? quote;
  final String? trailing;
}

final _dialogueRe = RegExp(r'^\s*([^:"\n]{1,45}?):\s*[“"](\S.*?)[”"]\s*(.*)$');

List<_NarrationBlock> _splitNarration(String text) {
  final lines = text.split('\n');
  final blocks = <_NarrationBlock>[];
  final prose = StringBuffer();
  void flushProse() {
    final p = prose.toString().trim();
    if (p.isNotEmpty) {
      for (final para in p.split('\n\n')) {
        final t = para.trim();
        if (t.isNotEmpty) blocks.add(_NarrationBlock.prose(t));
      }
    }
    prose.clear();
  }

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) {
      if (prose.isNotEmpty) flushProse();
      continue;
    }
    final m = _dialogueRe.firstMatch(line);
    if (m != null) {
      flushProse();
      blocks.add(_NarrationBlock.dialogue(
        m.group(1)!.trim(),
        m.group(2)!.trim(),
        m.group(3),
      ));
    } else {
      prose.write(line);
      prose.write('\n');
    }
  }
  flushProse();
  return blocks;
}

class _StreamTail extends StatelessWidget {
  const _StreamTail({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final b in _splitNarration(text))
          if (!b.isDialogue)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: SelectableText(b.prose!,
                  style: TextStyle(fontSize: 15.5, height: 1.55)),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: SelectableText('"${b.quote}"',
                  style: const TextStyle(
                      fontSize: 15.5, fontStyle: FontStyle.italic, height: 1.4)),
            ),
        const _BlinkingCursor(),
      ],
    );
  }
}

class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.1, end: 1.0).animate(_c),
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text('▍',
            style: TextStyle(
                fontSize: 20, color: Theme.of(context).colorScheme.primary)),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: ListTile(
        leading: Icon(Icons.error_outline, color: scheme.onErrorContainer),
        title: Text(message,
            style: TextStyle(color: scheme.onErrorContainer, fontSize: 13)),
        trailing: FilledButton(
          onPressed: onRetry,
          style: FilledButton.styleFrom(backgroundColor: scheme.onErrorContainer),
          child: Text('Try again',
              style: TextStyle(color: scheme.errorContainer)),
        ),
      ),
    );
  }
}

class _StoryInfoSheet extends StatelessWidget {
  const _StoryInfoSheet({
    required this.story,
    required this.npcs,
    required this.quests,
    required this.inventory,
    required this.memories,
  });

  final Story story;
  final List<StoryNPC> npcs;
  final List<Quest> quests;
  final List<InventoryItem> inventory;
  final List<Memory> memories;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, scrollController) => DefaultTabController(
        length: 4,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: TabBar(
                tabs: [
                  Tab(text: 'World'),
                  Tab(text: 'Companions'),
                  Tab(text: 'Quests'),
                  Tab(text: 'Items'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _WorldTab(story: story, memories: memories),
                  _CompanionsTab(npcs: npcs),
                  _QuestsTab(quests: quests),
                  _ItemsTab(inventory: inventory),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorldTab extends StatelessWidget {
  const _WorldTab({required this.story, required this.memories});

  final Story story;
  final List<Memory> memories;

  @override
  Widget build(BuildContext context) {
    final state = story.currentState;
    final player = state['player'] is Map ? state['player'] as Map : null;
    final world = state['world'] is Map ? state['world'] as Map : null;
    final facts = state['facts'] is List ? state['facts'] as List : null;
    final flags = state['flags'] is Map ? state['flags'] as Map : null;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (player != null) ...[
          _h(context, 'PLAYER'),
          for (final e in player.entries)
            if (e.value != null && e.value.toString().isEmpty == false)
              _kv(e.key, e.value),
          const SizedBox(height: 12),
        ],
        _h(context, 'WORLD'),
        if (world == null || world.isEmpty)
          _kv('status', 'The story has not located you yet.')
        else
          for (final e in world.entries)
            if (e.value != null && e.value.toString().isNotEmpty)
              _kv(e.key, e.value),
        const SizedBox(height: 12),
        _h(context, 'ESTABLISHED FACTS'),
        if (facts == null || facts.isEmpty)
          _kv('—', 'Nothing recorded yet.')
        else
          for (final f in facts)
            _kv('•', f),
        const SizedBox(height: 12),
        _h(context, 'FLAGS'),
        if (flags == null || flags.isEmpty)
          _kv('—', 'None.')
        else
          for (final e in flags.entries) _kv(e.key, e.value),
        const SizedBox(height: 12),
        _h(context, 'MEMORIES'),
        if (memories.isEmpty)
          _kv('—', 'No pinned memories yet.')
        else
          for (final m in memories.take(10))
            _kv(m.kind == 'summary' ? 'SUMMARY' : 'MEMORY', m.text),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Turn ${story.turnCount} · ${story.title}',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _h(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.w800)),
      );

  Widget _kv(String k, dynamic v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(
                '$k:'.toUpperCase(),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(child: Text(v.toString(), style: const TextStyle(fontSize: 13.5))),
          ],
        ),
      );
}

class _CompanionsTab extends StatelessWidget {
  const _CompanionsTab({required this.npcs});

  final List<StoryNPC> npcs;

  @override
  Widget build(BuildContext context) {
    if (npcs.isEmpty) {
      return const Center(child: Text('No companions introduced yet.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: npcs.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, i) {
        final n = npcs[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: gradientColorFor(n.name).withValues(alpha: 0.4),
            child: Text(n.name.isEmpty ? '?' : n.name[0].toUpperCase()),
          ),
          title: Text(n.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text([
            n.relationshipLabel,
            if (n.emotionalState.isNotEmpty) n.emotionalState,
            if (n.status.isNotEmpty && n.status != 'alive') '(${n.status})',
          ].join(' · ')),
        );
      },
    );
  }
}

class _QuestsTab extends StatelessWidget {
  const _QuestsTab({required this.quests});

  final List<Quest> quests;

  @override
  Widget build(BuildContext context) {
    if (quests.isEmpty) {
      return const Center(child: Text('No quests yet.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: quests.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, i) {
        final q = quests[i];
        final icon = q.status == 'completed'
            ? Icons.check_circle_outline
            : q.status == 'failed'
                ? Icons.cancel_outlined
                : Icons.flag_outlined;
        return ListTile(
          leading: Icon(icon,
              color: q.status == 'completed'
                  ? Colors.greenAccent
                  : q.status == 'failed'
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary),
          title: Text(q.title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text([
            q.status.toUpperCase(),
            if (q.description.isNotEmpty) q.description,
          ].join('\n')),
        );
      },
    );
  }
}

class _ItemsTab extends StatelessWidget {
  const _ItemsTab({required this.inventory});

  final List<InventoryItem> inventory;

  @override
  Widget build(BuildContext context) {
    if (inventory.isEmpty) {
      return const Center(child: Text('No items yet.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: inventory.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, i) {
        final it = inventory[i];
        return ListTile(
          leading: const Icon(Icons.inventory_2_outlined),
          title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: it.description.isEmpty ? null : Text(it.description),
          trailing: Text('×${it.quantity}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
        );
      },
    );
  }
}