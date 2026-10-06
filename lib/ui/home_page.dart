import 'package:flutter/material.dart';

import '../data/database.dart';
import '../models/scenario.dart';
import '../models/story.dart';
import 'create_story_page.dart';
import 'player_page.dart';
import 'scenario_page.dart';
import 'settings_page.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _loading = true;
  List<Story> _stories = [];
  List<Scenario> _scenarios = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppDatabase.instance;
    final stories = await db.listStories();
    final scenarios = await db.listScenarios();
    if (!mounted) return;
    setState(() {
      _stories = stories;
      _scenarios = scenarios;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Storyloom',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
          ),
          actions: [
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
                _load();
              },
            ),
          ],
          bottom: TabBar(
            tabs: const [
              Tab(text: 'My Stories'),
              Tab(text: 'Discover'),
            ],
            labelStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _LibraryTab(stories: _stories, onChanged: () => _load()),
                  _DiscoverTab(scenarios: _scenarios),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'create_story',
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateStoryPage()),
            );
            _load();
          },
          icon: const Icon(Icons.add),
          label: const Text('New story'),
        ),
      ),
    );
  }
}

class _LibraryTab extends StatelessWidget {
  const _LibraryTab({required this.stories, required this.onChanged});

  final List<Story> stories;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    if (stories.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories_outlined,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text('No stories yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Pick one from Discover to begin',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => onChanged(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: stories.length,
        itemBuilder: (context, i) {
          final s = stories[i];
          return StoryTile(
            story: s,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlayerRoute(story: s),
                ),
              ).then((_) => onChanged());
            },
            onDelete: () async {
              await AppDatabase.instance.deleteStory(s.id);
              onChanged();
            },
          );
        },
      ),
    );
  }
}

class _DiscoverTab extends StatefulWidget {
  const _DiscoverTab({required this.scenarios});

  final List<Scenario> scenarios;

  @override
  State<_DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<_DiscoverTab> {
  String _selectedGenre = '';

  /// Derive the set of genres actually present in the seed pack so the
  /// filter chips always match what's available.
  List<String> get _genres {
    final set = <String>{};
    for (final s in widget.scenarios) {
      final g = s.genre.trim();
      if (g.isNotEmpty) set.add(g);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<Scenario> get _filtered {
    if (_selectedGenre.isEmpty) return widget.scenarios;
    return widget.scenarios
        .where((s) => s.genre.trim() == _selectedGenre)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final genres = _genres;
    return Column(
      children: [
        // Genre filter bar
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: genres.length + 1, // +1 for "All"
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final all = i == 0;
              final genre = all ? null : genres[i - 1];
              final selected = all
                  ? _selectedGenre.isEmpty
                  : _selectedGenre == (genre ?? "");
              final label = all ? "All" : genre!;
              return FilterChip(
                selected: selected,
                label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                onSelected: (_) => setState(() {
                  _selectedGenre = all ? '' : genre!;
                }),
                showCheckmark: false,
                side: BorderSide(
                  color: selected
                      ? scheme.primary
                      : scheme.outlineVariant.withValues(alpha: 0.4),
                  width: selected ? 1.4 : 1,
                ),
                selectedColor: scheme.primaryContainer,
                labelStyle: TextStyle(
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 12,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                shape: const StadiumBorder(),
              );
            },
          ),
        ),
        const Divider(height: 1),
        // Scenario grid
        Expanded(
          child: _filtered.isEmpty
              ? Center(
                  child: Text('No stories match "$_selectedGenre"',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final sc in _filtered)
                          SizedBox(
                            width: 340,
                            child: ScenarioCard(
                              scenario: sc,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          ScenarioPage(scenario: sc)),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
