import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/database.dart';
import '../engine/cover_art.dart';
import '../engine/gemini_api.dart';
import '../models/character.dart';
import '../models/scenario.dart';
import 'player_page.dart';
import 'settings_page.dart';
import 'widgets.dart';

/// Scenario detail: description, premise, cast, and "Begin story" with an
/// optional character-creation sheet.
class ScenarioPage extends StatefulWidget {
  const ScenarioPage({super.key, required this.scenario});

  final Scenario scenario;

  @override
  State<ScenarioPage> createState() => _ScenarioPageState();
}

class _ScenarioPageState extends State<ScenarioPage> {
  bool _starting = false;
  bool _generatingCover = false;
  late Scenario _scenario = widget.scenario;

  Scenario get scenario => _scenario;

  /// Generates AI cover art for this scenario with the user's Gemini key.
  Future<void> _generateCover() async {
    if (_generatingCover) return;
    final apiKey = context.read<AppState>().settings.apiKey.trim();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Add a Gemini API key in Settings first.')));
      return;
    }
    setState(() => _generatingCover = true);
    try {
      final service = CoverArtService(apiKey: apiKey);
      final bytes = await service.generate(CoverArtService.promptFor(scenario));
      final path = await service.saveCover(scenario.id, bytes);
      await AppDatabase.instance.updateScenarioCover(scenario.id, path);
      final updated = await AppDatabase.instance.getScenario(scenario.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cover art added!')));
      if (updated != null) setState(() => _scenario = updated);
    } on AiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cover generation failed:\n$e')));
    } finally {
      if (mounted) setState(() => _generatingCover = false);
    }
  }

  Future<void> _beginFlow() async {
    final app = context.read<AppState>();
    if (app.settings.apiKey.trim().isEmpty) {
      final go = await _askForKey();
      if (go != true || !mounted) return;
      if (context.read<AppState>().settings.apiKey.trim().isEmpty) return;
    }

    final character = await _showCharacterSheet();
    if (!mounted || character == null) return;

    setState(() => _starting = true);
    try {
      final engine = context.read<AppState>().engine;
      final storyId = await engine.createStory(scenario, character);
      await engine.generateOpening(storyId);
      final story = await AppDatabase.instance.getStory(storyId);
      if (!mounted || story == null) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PlayerRoute(story: story)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not start the story.\n$e'),
          action: SnackBarAction(label: 'Settings', onPressed: () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsPage()));
          }),
        ),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<bool?> _askForKey() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('API key required'),
        content: const Text(
          'Storyloom needs an API key to generate stories. '
          'You can add one in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context, true);
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()));
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<Character?> _showCharacterSheet() {
    return showModalBottomSheet<Character>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CharacterSheet(
        playerRole: scenario.playerRole,
        suggestions: scenario.openingSuggestions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMature = scenario.contentRating == 'mature';
    return Scaffold(
      appBar: AppBar(title: const Text('Scenario')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // Hero header: cover with a gradient scrim and the title overlaid.
          Stack(
            children: [
              ScenarioCover(scenario: scenario, height: 200),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        scheme.surface.withValues(alpha: 0.55),
                        scheme.surface,
                      ],
                      stops: const [0.45, 0.8, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: _RatingBadge(mature: isMature),
              ),
              Positioned(
                top: 12,
                left: 12,
                child: _CoverButton(
                  busy: _generatingCover,
                  hasArt: scenario.coverArt != null && scenario.coverArt!.isNotEmpty,
                  onTap: _generateCover,
                ),
              ),
            ],
          ),
          Transform.translate(
            offset: const Offset(0, -18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    scenario.title,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      TagChip(scenario.genre),
                      for (final t in scenario.tags.take(5)) TagChip(t),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    scenario.description,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: scheme.primary),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'PREMISE',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(scenario.premise, style: Theme.of(context).textTheme.bodyMedium),
                  if (scenario.playerRole.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'YOUR ROLE',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(scenario.playerRole, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                  if (scenario.rules.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'WORLD RULES',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(scenario.rules, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                  if (scenario.npcs.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _sectionLabel(
                        'CAST · ${scenario.npcs.length} CHARACTERS (tap to read full profile)',
                        scheme),
                    const SizedBox(height: 8),
                    for (final n in scenario.npcs) _NpcCard(npc: n),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _starting ? null : _beginFlow,
                    icon: _starting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_stories_outlined),
                    label: Text(_starting ? 'Summoning the scene…' : 'Begin Story'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You will choose or create your character next. '
                     'Generate with your own API key.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, ColorScheme scheme) => Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
      );
}

/// Small pill button on the cover: "AI art" (generate) or "refresh" when art
/// already exists. Shows a spinner while generating.
class _CoverButton extends StatelessWidget {
  const _CoverButton({
    required this.busy,
    required this.hasArt,
    required this.onTap,
  });

  final bool busy;
  final bool hasArt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.6, color: Colors.white),
              )
            else
              Icon(hasArt ? Icons.refresh : Icons.auto_awesome,
                  size: 14, color: Colors.white),
            const SizedBox(width: 5),
            Text(
              busy ? 'Painting…' : (hasArt ? 'Redo art' : 'AI art'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.mature});

  final bool mature;

  @override
  Widget build(BuildContext context) {
    final color = mature ? const Color(0xFFE0527A) : Colors.tealAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        mature ? 'Mature / 18+' : 'General',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Expandable cast card: collapsed shows avatar + name + role; expanded shows
/// the character's full profile (description, personality, speech style,
/// backstory) so players can actually read who they'll meet.
class _NpcCard extends StatefulWidget {
  const _NpcCard({required this.npc});

  final Map<String, dynamic> npc;

  @override
  State<_NpcCard> createState() => _NpcCardState();
}

class _NpcCardState extends State<_NpcCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final npc = widget.npc;
    final scheme = Theme.of(context).colorScheme;
    final name = ((npc['name'] as String?) ?? '').trim();
    final role = ((npc['profession_class'] as String?) ?? '').trim();
    final desc = ((npc['description'] as String?) ?? '').trim();
    final personality = ((npc['personality'] as String?) ?? '').trim();
    final speech = ((npc['speech_style'] as String?) ?? '').trim();
    final backstory = ((npc['backstory_hook'] as String?) ?? '').trim();

    final fields = <(String, String)>[
      if (desc.isNotEmpty) ('About', desc),
      if (personality.isNotEmpty) ('Personality', personality),
      if (speech.isNotEmpty) ('Speech', speech),
      if (backstory.isNotEmpty) ('Backstory', backstory),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: gradientColorFor(name).withValues(alpha: 0.45),
                    child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        if (role.isNotEmpty)
                          Text(role,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.primary)),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(Icons.expand_more,
                        size: 20, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 180),
                crossFadeState: _expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: const SizedBox(width: double.infinity),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (label, text) in fields) ...[
                        Text(label.toUpperCase(),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  letterSpacing: 1,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurfaceVariant,
                                )),
                        const SizedBox(height: 2),
                        SelectableText(text,
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom-sheet character creator. Returns null when dismissed via drag-down,
/// or blank when the user picks "Start as a traveler".
class _CharacterSheet extends StatefulWidget {
  const _CharacterSheet({required this.playerRole, required this.suggestions});

  final String playerRole;
  final List<String> suggestions;

  @override
  State<_CharacterSheet> createState() => _CharacterSheetState();
}

class _CharacterSheetState extends State<_CharacterSheet> {
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _pronouns = TextEditingController();
  final _occupation = TextEditingController();
  final _appearance = TextEditingController();
  final _personality = TextEditingController();
  final _background = TextEditingController();
  final _gender = TextEditingController();
  final _origin = TextEditingController();

  @override
  void dispose() {
    for (final c in [
      _name, _age, _pronouns, _occupation, _appearance,
      _personality, _background, _gender, _origin,
    ]) {
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
            Text('Create your character',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            if (widget.playerRole.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Role: ${widget.playerRole}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      )),
            ],
            const SizedBox(height: 12),
            TextField(controller: _name,
                decoration: const InputDecoration(labelText: 'Name *')),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(controller: _age,
                      decoration: const InputDecoration(labelText: 'Age'),
                      keyboardType: TextInputType.text),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(controller: _pronouns,
                      decoration: const InputDecoration(labelText: 'Pronouns')),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(controller: _gender,
                      decoration: const InputDecoration(labelText: 'Gender')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(controller: _origin,
                      decoration: const InputDecoration(labelText: 'Origin')),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(controller: _occupation,
                decoration: const InputDecoration(labelText: 'Occupation')),
            const SizedBox(height: 10),
            TextField(controller: _appearance,
                decoration: const InputDecoration(labelText: 'Appearance'),
                minLines: 2, maxLines: 3),
            const SizedBox(height: 10),
            TextField(controller: _personality,
                decoration: const InputDecoration(labelText: 'Personality'),
                minLines: 2, maxLines: 3),
            const SizedBox(height: 10),
            TextField(controller: _background,
                decoration: const InputDecoration(labelText: 'Background'),
                minLines: 2, maxLines: 3),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, Character()),
                    child: const Text('Start as a traveler'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _name.text.trim().isEmpty
                        ? null
                        : () => Navigator.pop(context, _build()),
                    child: const Text('Enter the world'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Character _build() => Character(
        name: _name.text.trim(),
        age: _age.text.trim(),
        gender: _gender.text.trim(),
        pronouns: _pronouns.text.trim(),
        occupation: _occupation.text.trim(),
        origin: _origin.text.trim(),
        appearance: _appearance.text.trim(),
        personality: _personality.text.trim(),
        background: _background.text.trim(),
      );
}