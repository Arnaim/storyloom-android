import 'dart:io';
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

/// A deterministic, layered gradient banner used as a scenario "cover" when
/// no image exists. Diagonal blend + soft radial glow + faint rings.
class GenreBanner extends StatelessWidget {
  const GenreBanner({super.key, required this.label, this.height = 120, this.icon});

  final String label;
  final double height;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = gradientColorFor(label);
    final dark = Color.lerp(c, Colors.black, 0.45)!;
    final light = Color.lerp(c, Colors.white, 0.25)!;
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [dark, c, light.withValues(alpha: 0.9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Radial glow
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.1,
                  colors: [Colors.white.withValues(alpha: 0.22), Colors.transparent],
                  center: const Alignment(-0.4, -0.6),
                ),
              ),
            ),
          ),
          // Faint concentric rings
          Positioned(
            right: -height * 0.35,
            bottom: -height * 0.55,
            child: Container(
              width: height * 1.4,
              height: height * 1.4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.14),
                  width: 10,
                ),
              ),
            ),
          ),
          Positioned(
            left: -height * 0.4,
            top: -height * 0.6,
            child: Container(
              width: height * 1.2,
              height: height * 1.2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                  width: 8,
                ),
              ),
            ),
          ),
          if (icon != null)
            Icon(icon, size: height * 0.5, color: Colors.white.withValues(alpha: 0.9))
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                label.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontSize: min(26, height * 0.34),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.5,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
        ],
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

/// A scenario "cover": bundled asset art, a picked/generated image file
/// (absolute path), or the deterministic genre banner as fallback.
class ScenarioCover extends StatelessWidget {
  const ScenarioCover({super.key, required this.scenario, this.height = 120});

  final Scenario scenario;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cover = scenario.coverArt;
    if (cover != null && cover.isNotEmpty) {
      final isFile = cover.startsWith('/') || cover.startsWith('file:');
      return SizedBox(
        height: height,
        width: double.infinity,
        child: isFile
            ? Image.file(
                File(cover.startsWith('file:')
                    ? Uri.parse(cover).toFilePath().replaceFirst(Platform.isWindows ? '/': '', '')
                    : cover),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => GenreBanner(
                  label: scenario.genre.isNotEmpty ? scenario.genre : scenario.title,
                  height: height,
                ),
              )
            : Image.asset(
                cover,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => GenreBanner(
                  label: scenario.genre.isNotEmpty ? scenario.genre : scenario.title,
                  height: height,
                ),
              ),
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
    final accent = gradientColorFor(
        scenario.genre.isNotEmpty ? scenario.genre : scenario.title);
    return DecoratedBox(
      decoration: glowCard(accent.withValues(alpha: 0.35)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Card(
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ScenarioCover(scenario: scenario, height: 104),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        scenario.isSample ? 'STORYLOOM' : 'YOURS',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
      ),
    );
  }
}

class StoryTile extends StatelessWidget {
  const StoryTile({
    super.key,
    required this.story,
    required this.onTap,
    this.onDelete,
  });

  final Story story;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

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
      onLongPress: onDelete != null
          ? () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete story?'),
                  content: Text(
                      'This will permanently delete "${story.title}" and all its messages.'),
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
              if (confirmed == true) onDelete?.call();
            }
          : null,
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