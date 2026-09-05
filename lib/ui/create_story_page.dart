import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/database.dart';
import '../models/character.dart';
import '../models/scenario.dart';
import 'player_page.dart';
import 'settings_page.dart';
import 'widgets.dart';

/// Story creator: build a custom scenario from scratch.
///
/// Two modes:
///  - 1-on-1 roleplay: you + one character, dialogue-first, no RPG systems.
///  - Full story: a complete scenario with world, rules, opening and a cast.
class CreateStoryPage extends StatefulWidget {
  const CreateStoryPage({super.key});

  @override
  State<CreateStoryPage> createState() => _CreateStoryPageState();
}

class _CreateStoryPageState extends State<CreateStoryPage> {
  bool _oneOnOne = true;

  final _title = TextEditingController();
  final _description = TextEditingController();
  final _world = TextEditingController();
  final _rules = TextEditingController();
  final _tone = TextEditingController();
  final _opening = TextEditingController();

  // 1-on-1 character fields
  final _charName = TextEditingController();
  final _charAppearance = TextEditingController();
  final _charPersonality = TextEditingController();
  final _charSpeech = TextEditingController();
  final _charBackstory = TextEditingController();
  String? _charImage;

  // Full-story cast + player role
  final List<Map<String, dynamic>> _npcs = [];
  final _playerRole = TextEditingController();

  String? _coverImage;
  bool _mature = false;
  bool _starting = false;

  @override
  void dispose() {
    for (final c in [
      _title, _description, _world, _rules, _tone, _opening,
      _charName, _charAppearance, _charPersonality, _charSpeech,
      _charBackstory, _playerRole,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<String?> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
          source: ImageSource.gallery, maxWidth: 1024, imageQuality: 82);
      if (picked == null) return null;
      // Copy into the app documents dir so it survives gallery cleanup.
      final docs = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(p.join(docs.path, 'covers'));
      if (!imagesDir.existsSync()) imagesDir.createSync(recursive: true);
      final dest = p.join(imagesDir.path,
          'cover_${DateTime.now().millisecondsSinceEpoch}${p.extension(picked.path)}');
      await File(picked.path).copy(dest);
      return dest;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not load image: $e')));
      }
      return null;
    }
  }

  Future<void> _addNpc() async {
    final npc = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NpcEditorSheet(),
    );
    if (npc != null && (npc['name'] as String? ?? '').trim().isNotEmpty) {
      setState(() => _npcs.add(npc));
    }
  }

  Future<void> _createAndStart() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Give your story a title first.')));
      return;
    }
    if (_oneOnOne && _charName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name your character first.')));
      return;
    }

    final scenarioId = await _persistScenario();
    final scenario = await AppDatabase.instance.getScenario(scenarioId);
    if (scenario == null || !mounted) return;

    final app = context.read<AppState>();
    if (app.settings.apiKey.trim().isEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('API key required'),
          content: const Text(
              'Storyloom needs an API key to generate stories. You can add one in Settings.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SettingsPage()));
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
      if (context.read<AppState>().settings.apiKey.trim().isEmpty) return;
    }

    // Reuse the scenario page's character creator for the player persona.
    Character? character;
    if (mounted) {
      character = await showModalBottomSheet<Character>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _PlayerCharacterSheet(
          hint: _oneOnOne
              ? 'Who are you in this story?'
              : scenario.playerRole,
        ),
      );
    }
    if (!mounted || character == null) return;

    setState(() => _starting = true);
    try {
      final engine = context.read<AppState>().engine;
      final storyId = await engine.createStory(scenario, character);
      await engine.generateOpening(storyId);
      final story = await AppDatabase.instance.getStory(storyId);
      if (!mounted || story == null) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => PlayerRoute(story: story)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start the story.\n$e')));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<int> _persistScenario() async {
    final npcs = _oneOnOne
        ? <Map<String, dynamic>>[
            {
              'name': _charName.text.trim(),
              'description': _charAppearance.text.trim(),
              'personality': _charPersonality.text.trim(),
              'speech_style': _charSpeech.text.trim(),
              'backstory_hook': _charBackstory.text.trim(),
              if (_charImage != null) 'image': _charImage,
            },
          ]
        : _npcs;

    final worldText = _oneOnOne
        ? (_world.text.trim().isEmpty
            ? 'An intimate, character-driven story focused on the relationship '
                'between the player and ${_charName.text.trim()}. The world '
                'adapts freely around their interactions.'
            : _world.text.trim())
        : _world.text.trim();

    final openingText = _opening.text.trim().isEmpty
        ? (_oneOnOne
            ? 'A first meeting or an ordinary moment between the player and '
                '${_charName.text.trim()} that naturally opens the story.'
            : '')
        : _opening.text.trim();

    final scenario = Scenario(
      id: 0,
      title: _title.text.trim(),
      description: _description.text.trim().isEmpty
          ? (_oneOnOne
              ? 'A 1-on-1 story with ${_charName.text.trim()}.'
              : 'A story of your own making.')
          : _description.text.trim(),
      genre: _oneOnOne ? '1-on-1 Roleplay' : 'Custom Story',
      tags: const [],
      premise: _description.text.trim(),
      openingScene: openingText,
      worldDescription: worldText,
      rules: _rules.text.trim(),
      tone: _tone.text.trim(),
      narratorStyle: _oneOnOne
          ? 'Warm, character-focused narration that centers dialogue and '
              'small moments with ${_charName.text.trim()}. Keep the pace '
              'personal and reactive.'
          : '',
      contentRating: _mature ? 'mature' : 'general',
      rpgEnabled: false,
      playerRole: _playerRole.text.trim(),
      npcs: npcs,
      locations: const [],
      lore: const [],
      openingSuggestions: const [],
      isSample: false,
      playCount: 0,
      author: 'You',
      coverArt: _coverImage,
    );

    return AppDatabase.instance.insertScenario(scenario);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Create a story')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Mode selector
          Row(
            children: [
              Expanded(
                child: _ModeCard(
                  selected: _oneOnOne,
                  icon: Icons.person_outline,
                  title: '1-on-1 roleplay',
                  subtitle: 'You and one character, up close',
                  onTap: () => setState(() => _oneOnOne = true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ModeCard(
                  selected: !_oneOnOne,
                  icon: Icons.auto_stories_outlined,
                  title: 'Full story',
                  subtitle: 'World, cast and plot, like the built-ins',
                  onTap: () => setState(() => _oneOnOne = false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Cover picker
          GestureDetector(
            onTap: () async {
              final img = await _pickImage();
              if (img != null) setState(() => _coverImage = img);
            },
            child: Container(
              height: 140,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border:
                    Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: _coverImage != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(_coverImage!), fit: BoxFit.cover),
                        Positioned(
                          right: 8,
                          top: 8,
                          child: _IconPill(
                            icon: Icons.close,
                            onTap: () => setState(() => _coverImage = null),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              size: 32, color: scheme.onSurfaceVariant),
                          const SizedBox(height: 6),
                          Text('Add a cover image (optional)',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _title,
            decoration: const InputDecoration(
                labelText: 'Story title *', hintText: 'The Midnight Cafe'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _description,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: _oneOnOne
                  ? 'What is this story about?'
                  : 'Premise / description',
              hintText: _oneOnOne
                  ? 'A slow-burn story between you and a retired musician…'
                  : 'A kingdom on the brink, a heist gone wrong…',
            ),
          ),

          if (_oneOnOne) ...[
            const SizedBox(height: 20),
            _SectionLabel('YOUR CHARACTER'),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () async {
                    final img = await _pickImage();
                    if (img != null) setState(() => _charImage = img);
                  },
                  child: Container(
                    width: 64,
                    height: 64,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.surfaceContainerHighest,
                      border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.6)),
                    ),
                    child: _charImage != null
                        ? Image.file(File(_charImage!), fit: BoxFit.cover)
                        : Icon(Icons.person_add_alt_1,
                            color: scheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _charName,
                    decoration: const InputDecoration(
                        labelText: 'Character name *',
                        hintText: 'Mira, the cafe owner'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _charAppearance,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Appearance',
                  hintText: 'Tall, silver-streaked hair, tired kind eyes…'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _charPersonality,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Personality',
                  hintText: 'Dry humor, guarded, softens with patience…'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _charSpeech,
              decoration: const InputDecoration(
                  labelText: 'Speech style',
                  hintText: 'Quiet, clipped sentences, rare warmth'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _charBackstory,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Backstory / lore',
                  hintText: 'Once toured with a famous band, then vanished…'),
            ),
          ] else ...[
            const SizedBox(height: 20),
            _SectionLabel('WORLD'),
            const SizedBox(height: 8),
            TextField(
              controller: _world,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                  labelText: 'World description',
                  hintText: 'Where does this take place? What makes it special?'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _rules,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                  labelText: 'World rules (optional)',
                  hintText: 'Magic exists but is outlawed. The city never sleeps…'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tone,
              decoration: const InputDecoration(
                  labelText: 'Tone (optional)',
                  hintText: 'Cozy mystery, slow tension, warm humor'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _playerRole,
              decoration: const InputDecoration(
                  labelText: 'Who is the player? (optional)',
                  hintText: 'A newly arrived courier with a secret'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _opening,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                  labelText: 'Opening scene (optional)',
                  hintText: 'Where and how the story begins'),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text('CAST  ·  ${_npcs.length} CHARACTERS',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant)),
                ),
                IconButton.filledTonal(
                  tooltip: 'Add character',
                  onPressed: _addNpc,
                  icon: const Icon(Icons.person_add_alt),
                ),
              ],
            ),
            for (final n in _npcs) ...[
              const SizedBox(height: 8),
              _NpcSummaryRow(
                npc: n,
                onDelete: () => setState(() => _npcs.remove(n)),
              ),
            ],
          ],

          const SizedBox(height: 20),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mature content (18+)'),
            subtitle: const Text('Adult themes, handled seriously'),
            value: _mature,
            onChanged: (v) => setState(() => _mature = v),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _starting ? null : _createAndStart,
            icon: _starting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_stories),
            label: Text(_starting ? 'Summoning the scene…' : 'Create & begin'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.6)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.4),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: selected ? scheme.primary : scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant));
  }
}

class _IconPill extends StatelessWidget {
  const _IconPill({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }
}

class _NpcSummaryRow extends StatelessWidget {
  const _NpcSummaryRow({required this.npc, required this.onDelete});
  final Map<String, dynamic> npc;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final name = (npc['name'] as String?) ?? '';
    final role = (npc['profession_class'] as String?) ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor:
                gradientColorFor(name).withValues(alpha: 0.45),
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              role.isEmpty ? name : '$name · $role',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// Bottom-sheet editor for one cast member (full-story mode).
class _NpcEditorSheet extends StatefulWidget {
  @override
  State<_NpcEditorSheet> createState() => _NpcEditorSheetState();
}

class _NpcEditorSheetState extends State<_NpcEditorSheet> {
  final _name = TextEditingController();
  final _role = TextEditingController();
  final _description = TextEditingController();
  final _personality = TextEditingController();
  final _speech = TextEditingController();
  final _backstory = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _role, _description, _personality, _speech, _backstory]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        top: 8,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add a character',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name *')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                    controller: _role,
                    decoration: const InputDecoration(
                        labelText: 'Role / class',
                        hintText: 'Captain of the guard')),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _description,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Description', hintText: 'Looks, presence, manner'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _personality,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Personality',
                  hintText: 'How they think and act, quirks and fears'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _speech,
              decoration: const InputDecoration(
                  labelText: 'Speech style', hintText: 'Formal? Rough? Warm?'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _backstory,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Backstory / secrets (optional)'),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _name.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(context, {
                            'name': _name.text.trim(),
                            'profession_class': _role.text.trim(),
                            'description': _description.text.trim(),
                            'personality': _personality.text.trim(),
                            'speech_style': _speech.text.trim(),
                            'backstory_hook': _backstory.text.trim(),
                          }),
                  child: const Text('Add'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Minimal player-persona sheet (reuses Character model).
class _PlayerCharacterSheet extends StatefulWidget {
  const _PlayerCharacterSheet({required this.hint});
  final String hint;

  @override
  State<_PlayerCharacterSheet> createState() => _PlayerCharacterSheetState();
}

class _PlayerCharacterSheetState extends State<_PlayerCharacterSheet> {
  final _name = TextEditingController();
  final _appearance = TextEditingController();
  final _personality = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _appearance.dispose();
    _personality.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        top: 8,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your character',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            if (widget.hint.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(widget.hint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary)),
            ],
            const SizedBox(height: 12),
            TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Your name (optional)')),
            const SizedBox(height: 10),
            TextField(
                controller: _appearance,
                minLines: 2,
                maxLines: 3,
                decoration:
                    const InputDecoration(labelText: 'Appearance (optional)')),
            const SizedBox(height: 10),
            TextField(
                controller: _personality,
                minLines: 2,
                maxLines: 3,
                decoration:
                    const InputDecoration(labelText: 'Personality (optional)')),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, Character()),
                  child: const Text('Skip'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    Character(
                      name: _name.text.trim(),
                      appearance: _appearance.text.trim(),
                      personality: _personality.text.trim(),
                    ),
                  ),
                  child: const Text('Begin'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
