import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/database.dart';
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

  Scenario get scenario => widget.scenario;

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
        title: const Text('Connect Gemini first'),
        content: const Text(
          'Storyloom needs your own Gemini API key to generate stories. '
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
          ScenarioCover(scenario: scenario, height: 170),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        scenario.title,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    _RatingBadge(mature: isMature),
                  ],
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
                  _sectionLabel('CAST', scheme),
                  const SizedBox(height: 6),
                  for (final n in scenario.npcs.take(6)) _NpcRow(npc: n),
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
                  'Generate with your own Gemini API key.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
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

class _NpcRow extends StatelessWidget {
  const _NpcRow({required this.npc});

  final Map<String, dynamic> npc;

  @override
  Widget build(BuildContext context) {
    final name = (npc['name'] as String?) ?? '?';
    final desc = (npc['description'] as String?) ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: gradientColorFor(name).withValues(alpha: 0.4),
            child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (desc.isNotEmpty)
                  Text(
                    desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
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