import 'dart:math';

import 'package:flutter/material.dart';

import '../models/scenario.dart';
import '../models/story.dart';
import 'theme.dart';

Color gradientColorFor(String seedText) {
  var hash = 0;
  for (final code in seedText.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return genreGradients[hash % genreGradients.length];
}

/// A simple deterministic gradient banner used as a scenario "cover".
class GenreBanner extends StatelessWidget {
  const GenreBanner({super.key, required this.label, this.height = 120, this.icon});

  final String label;
  final double height;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = gradientColorFor(label);
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c, c.withValues(alpha: 0.55)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: icon != null
            ? Icon(icon, size: height * 0.5, color: Colors.white.withValues(alpha: 0.85))
            : Text(
                label.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: min(28, height * 0.38),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
      ),
    );
  }
}

class TagChip extends StatelessWidget {
  const TagChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: scheme.onSecondaryContainer,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A scenario "cover": the bundled cover art when present, otherwise the
/// deterministic genre banner.
class ScenarioCover extends StatelessWidget {
  const ScenarioCover({super.key, required this.scenario, this.height = 120});

  final Scenario scenario;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cover = scenario.coverArt;
    if (cover != null && cover.isNotEmpty) {
      return SizedBox(
        height: height,
        width: double.infinity,
        child: Image.asset(cover, fit: BoxFit.cover),
      );
    }
    return GenreBanner(
      label: scenario.genre.isNotEmpty ? scenario.genre : scenario.title,
      height: height,
    );
  }
}

class ScenarioCard extends StatelessWidget {
  const ScenarioCard({super.key, required this.scenario, this.onTap});

  final Scenario scenario;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScenarioCover(scenario: scenario, height: 96),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    scenario.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    scenario.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StoryTile extends StatelessWidget {
  const StoryTile({super.key, required this.story, required this.onTap});

  final Story story;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final world = story.currentState;
    final location = (world['world'] as Map<String, dynamic>?)?['current_location'] as String? ?? '';
    final subtitle = [
      if (location.isNotEmpty) location,
      '${story.turnCount} turn${story.turnCount == 1 ? '' : 's'}',
    ].join(' · ');
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: gradientColorFor(story.title).withValues(alpha: 0.75),
        foregroundColor: Colors.white,
        child: Text(story.title.isNotEmpty ? story.title[0].toUpperCase() : '?'),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(story.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

// Decoration helpers for message cards.
const mapKindIcon = <String, IconData>{
  'location': Icons.place_outlined,
  'loot': Icons.inventory_2_outlined,
  'relationship': Icons.favorite_outline,
  'quest': Icons.flag_outlined,
  'system_event': Icons.info_outline,
  'event': Icons.info_outline,
};