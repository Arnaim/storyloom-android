import 'package:flutter/material.dart';

import '../data/database.dart';
import '../models/scenario.dart';
import '../models/story.dart';
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

class _DiscoverTab extends StatelessWidget {
  const _DiscoverTab({required this.scenarios});

  final List<Scenario> scenarios;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: scenarios.length,
      itemBuilder: (context, i) {
        final sc = scenarios[i];
        return ScenarioCard(
          scenario: sc,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ScenarioPage(scenario: sc)),
            );
          },
        );
      },
    );
  }
}