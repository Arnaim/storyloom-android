import '../data/database.dart';
import '../models/story.dart';

/// Port of the backend's `memory_service.py`, backed by [AppDatabase].
const int maxPinned = 15;

Future<List<Memory>> loadMemories(int storyId) =>
    AppDatabase.instance.memoriesForStory(storyId);

String currentSummary(List<Memory> memories) {
  for (final m in memories.reversed) {
    if (m.kind == 'summary') return m.text;
  }
  return '';
}

/// Trim/normalize whitespace the way the backend's summary routine expects.
String transcriptForSummary(List<StoryMessage> rows) {
  final lines = <String>[];
  for (final m in rows) {
    if (m.isUser) {
      lines.add('Player: ${m.content}');
    } else if (m.isSystem) {
      lines.add('[${m.content}]');
    } else {
      final c = m.activeContent;
      lines.add(c.length > 600 ? c.substring(0, 600) : c);
    }
  }
  return lines.join('\n');
}

Future<void> pinCandidates(int storyId, int currentSeq, List<String> candidates) async {
  if (candidates.isEmpty) return;
  final db = AppDatabase.instance;
  final all = await db.memoriesForStory(storyId, activeOnly: false);
  var existingLow = all.map((m) => m.text.toLowerCase()).toList();

  for (final cand in candidates) {
    final c = cand.trim();
    if (c.isEmpty) continue;
    final clow = c.toLowerCase();
    if (existingLow.any((ex) => clow.contains(ex) || ex.contains(clow))) continue;
    await db.insertMemory(Memory(
      storyId: storyId,
      kind: 'fact',
      text: c,
      importance: 0.8,
      createdSeq: currentSeq,
    ));
    existingLow.add(clow);
  }

  // Keep the pin set bounded (most important survive).
  final allFacts = await db.memoriesForStory(storyId, activeOnly: true);
  final facts = allFacts.where((m) => m.kind == 'fact').toList()
    ..sort((a, b) {
      final cmp = b.importance.compareTo(a.importance);
      return cmp != 0 ? cmp : b.id.compareTo(a.id);
    });
  for (final stale in facts.sublist(facts.length > maxPinned ? maxPinned : facts.length)) {
    await db.setMemoryActive(stale.id, false);
  }
}

Future<int> turnsSinceLastSummary(int storyId, int lastMessageSeq) async {
  final lastSeq = await AppDatabase.instance.lastSummarySeq(storyId) ?? 0;
  return (lastMessageSeq - lastSeq).clamp(0, 1 << 30);
}

Future<void> saveSummary(int storyId, int currentSeq, String text) async {
  final db = AppDatabase.instance;
  final all = await db.memoriesForStory(storyId, activeOnly: false);
  for (final old in all.where((m) => m.kind == 'summary')) {
    await db.setMemoryActive(old.id, false);
  }
  await db.insertMemory(Memory(
    storyId: storyId,
    kind: 'summary',
    text: text,
    importance: 1.0,
    createdSeq: currentSeq,
  ));
}