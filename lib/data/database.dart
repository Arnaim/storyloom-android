import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/character.dart';
import '../models/scenario.dart';
import '../models/story.dart';
import 'seed_scenarios.dart';

/// Single-user local database. Everything the web backend stored in Postgres
/// lives here in SQLite, exposed as small query functions the engine calls.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'storyloom.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE scenarios (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            description TEXT,
            genre TEXT,
            tags TEXT,
            premise TEXT,
            opening_scene TEXT,
            world_description TEXT,
            rules TEXT,
            tone TEXT,
            narrator_style TEXT,
            content_rating TEXT DEFAULT 'general',
            rpg_enabled INTEGER DEFAULT 0,
            player_role TEXT,
            npcs TEXT,
            locations TEXT,
            lore TEXT,
            opening_suggestions TEXT,
            is_sample INTEGER DEFAULT 0,
            play_count INTEGER DEFAULT 0,
            author TEXT DEFAULT 'Storyloom',
            cover_art TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE stories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            scenario_id INTEGER NOT NULL,
            character TEXT,
            status TEXT DEFAULT 'active',
            turn_count INTEGER DEFAULT 0,
            last_message_seq INTEGER DEFAULT 0,
            current_state TEXT,
            created_at INTEGER,
            updated_at INTEGER,
            last_played_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            story_id INTEGER NOT NULL,
            seq INTEGER NOT NULL,
            role TEXT NOT NULL,
            kind TEXT DEFAULT 'narration',
            speaker TEXT DEFAULT '',
            content TEXT DEFAULT '',
            variants TEXT,
            active_variant INTEGER DEFAULT 0,
            suggestions TEXT,
            meta TEXT,
            UNIQUE(story_id, seq)
          )
        ''');
        await db.execute('''
          CREATE TABLE npcs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            story_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            details TEXT,
            relationship_value REAL DEFAULT 0,
            emotional_state TEXT DEFAULT '',
            status TEXT DEFAULT 'alive',
            location TEXT DEFAULT ''
          )
        ''');
        await db.execute('''
          CREATE TABLE quests (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            story_id INTEGER NOT NULL,
            title TEXT,
            description TEXT DEFAULT '',
            status TEXT DEFAULT 'active',
            created_seq INTEGER DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE inventory_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            story_id INTEGER NOT NULL,
            name TEXT,
            description TEXT DEFAULT '',
            quantity INTEGER DEFAULT 1
          )
        ''');
        await db.execute('''
          CREATE TABLE memories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            story_id INTEGER NOT NULL,
            kind TEXT DEFAULT 'fact',
            text TEXT,
            importance REAL DEFAULT 0.5,
            active INTEGER DEFAULT 1,
            created_seq INTEGER DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE world_snapshots (
            story_id INTEGER NOT NULL,
            seq INTEGER NOT NULL,
            snapshot TEXT NOT NULL,
            PRIMARY KEY (story_id, seq)
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE scenarios ADD COLUMN cover_art TEXT');
          // Replace the old sample pack with the current one. There is no UI
          // for user-created scenarios yet, so clearing all rows is safe.
          await db.delete('scenarios');
          final batch = db.batch();
          for (final s in SeedScenarios.all) {
            batch.insert('scenarios', {
              ..._scenRow(Scenario.fromJson(
                  {...s, 'is_sample': true, 'id': 0, 'play_count': 0})),
              'id': null,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
          await batch.commit(noResult: true);
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS world_snapshots (
              story_id INTEGER NOT NULL,
              seq INTEGER NOT NULL,
              snapshot TEXT NOT NULL,
              PRIMARY KEY (story_id, seq)
            )
          ''');
        }
      },
    );
  }

  // ------------------------------------------------------------------- //
  // Scenarios
  // ------------------------------------------------------------------- //
  Map<String, Object?> _scenRow(Scenario s) => {
        'title': s.title,
        'description': s.description,
        'genre': s.genre,
        'tags': jsonEncode(s.tags),
        'premise': s.premise,
        'opening_scene': s.openingScene,
        'world_description': s.worldDescription,
        'rules': s.rules,
        'tone': s.tone,
        'narrator_style': s.narratorStyle,
        'content_rating': s.contentRating,
        'rpg_enabled': s.rpgEnabled ? 1 : 0,
        'player_role': s.playerRole,
        'npcs': jsonEncode(s.npcs),
        'locations': jsonEncode(s.locations),
        'lore': jsonEncode(s.lore),
        'opening_suggestions': jsonEncode(s.openingSuggestions),
        'is_sample': s.isSample ? 1 : 0,
        'play_count': s.playCount,
        'author': s.author,
        'cover_art': s.coverArt,
      };

  Future<void> seedIfEmpty() async {
    final db = await instance.db;
    final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM scenarios WHERE is_sample = 1'));
    if ((count ?? 0) > 0) return;
    final batch = db.batch();
    for (final s in SeedScenarios.all) {
      batch.insert('scenarios', {
        ..._scenRow(Scenario.fromJson(
            {...s, 'is_sample': true, 'id': 0, 'play_count': 0})),
        'id': null,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Scenario>> listScenarios() async {
    final db = await instance.db;
    final rows = await db.query('scenarios', orderBy: 'is_sample DESC, title COLLATE NOCASE');
    return rows.map((r) => Scenario.fromJson(_decodeScenarioRow(r))).toList();
  }

  /// Persists a new (or replaces an existing) scenario row. Used by the
  /// story creator for user-built scenarios (is_sample = 0).
  Future<int> insertScenario(Scenario s) async {
    final db = await instance.db;
    return db.insert('scenarios', {
      ..._scenRow(s),
      'id': s.id > 0 ? s.id : null,
    });
  }

  Future<void> deleteScenario(int id) async {
    final db = await instance.db;
    await db.delete('scenarios', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateScenarioCover(int id, String path) async {
    final db = await instance.db;
    await db.update('scenarios', {'cover_art': path},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<Scenario?> getScenario(int id) async {
    final db = await instance.db;
    final rows = await db.query('scenarios', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Scenario.fromJson(_decodeScenarioRow(rows.first));
  }

  Future<void> incrementScenarioPlayCount(int id) async {
    final db = await instance.db;
    await db.rawUpdate('UPDATE scenarios SET play_count = play_count + 1 WHERE id = ?', [id]);
  }

  Map<String, dynamic> _decodeScenarioRow(Map<String, Object?> r) => {
        'id': r['id'],
        'title': r['title'],
        'description': r['description'],
        'genre': r['genre'],
        'tags': _decodeList(r['tags']),
        'premise': r['premise'],
        'opening_scene': r['opening_scene'],
        'world_description': r['world_description'],
        'rules': r['rules'],
        'tone': r['tone'],
        'narrator_style': r['narrator_style'],
        'content_rating': r['content_rating'],
        'rpg_enabled': r['rpg_enabled'] == 1,
        'player_role': r['player_role'],
        'npcs': _decodeMapList(r['npcs']),
        'locations': _decodeMapList(r['locations']),
        'lore': _decodeMapList(r['lore']),
        'opening_suggestions': _decodeList(r['opening_suggestions']),
        'is_sample': r['is_sample'] == 1,
        'play_count': r['play_count'],
        'author': r['author'],
        'cover_art': r['cover_art'],
      };

  // ------------------------------------------------------------------- //
  // Stories
  // ------------------------------------------------------------------- //
  static List<dynamic> _decodeList(dynamic v) {
    if (v == null) return const [];
    try {
      return jsonDecode(v as String) as List<dynamic>;
    } catch (_) {
      return const [];
    }
  }

  static List<Map<String, dynamic>> _decodeMapList(dynamic v) {
    final list = _decodeList(v);
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Map<String, dynamic> _decodeMap(dynamic v) {
    if (v == null) return const {};
    try {
      final d = jsonDecode(v as String);
      return d is Map ? Map<String, dynamic>.from(d) : const {};
    } catch (_) {
      return const {};
    }
  }

  Future<int> createStory(Story s) async {
    final db = await instance.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert('stories', {
      'title': s.title,
      'scenario_id': s.scenarioId,
      'character': jsonEncode(s.character?.toJson() ?? {}),
      'status': s.status,
      'turn_count': s.turnCount,
      'last_message_seq': s.lastMessageSeq,
      'current_state': jsonEncode(s.currentState),
      'created_at': now,
      'updated_at': now,
      'last_played_at': now,
    });
    return id;
  }

  Future<Story?> getStory(int id) async {
    final db = await instance.db;
    final rows = await db.query('stories', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return _storyFromRow(rows.first);
  }

  Future<List<Story>> listStories() async {
    final db = await instance.db;
    final rows = await db.query('stories', orderBy: 'last_played_at DESC');
    return rows.map(_storyFromRow).toList();
  }

  Story _storyFromRow(Map<String, Object?> r) => Story(
        id: r['id'] as int,
        title: (r['title'] as String?) ?? '',
        scenarioId: (r['scenario_id'] as num?)?.toInt() ?? 0,
        character: Character.fromJson(_decodeMap(r['character'])),
        status: (r['status'] as String?) ?? 'active',
        turnCount: (r['turn_count'] as num?)?.toInt() ?? 0,
        lastMessageSeq: (r['last_message_seq'] as num?)?.toInt() ?? 0,
        currentState: _decodeMap(r['current_state']),
        createdAt: (r['created_at'] as num?)?.toInt() ?? 0,
        updatedAt: (r['updated_at'] as num?)?.toInt() ?? 0,
        lastPlayedAt: (r['last_played_at'] as num?)?.toInt() ?? 0,
      );

  Future<void> updateStory(Story s) async {
    final db = await instance.db;
    await db.update(
      'stories',
      {
        'title': s.title,
        'character': jsonEncode(s.character?.toJson() ?? {}),
        'status': s.status,
        'turn_count': s.turnCount,
        'last_message_seq': s.lastMessageSeq,
        'current_state': jsonEncode(s.currentState),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'last_played_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [s.id],
    );
  }

  Future<void> touchPlayed(int id) async {
    final db = await instance.db;
    await db.update(
      'stories',
      {'last_played_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteStory(int id) async {
    final db = await instance.db;
    for (final table in ['npcs', 'quests', 'inventory_items', 'memories', 'messages']) {
      await db.delete(table, where: 'story_id = ?', whereArgs: [id]);
    }
    await db.delete('world_snapshots', where: 'story_id = ?', whereArgs: [id]);
    await db.delete('stories', where: 'id = ?', whereArgs: [id]);
  }

  /// Removes every world-state row for a story (used by "restart"): the story
  /// row itself and its scenario link are kept.
  Future<void> deleteWorldData(int storyId) async {
    final db = await instance.db;
    for (final table in ['npcs', 'quests', 'inventory_items', 'memories']) {
      await db.delete(table, where: 'story_id = ?', whereArgs: [storyId]);
    }
    await db.delete('world_snapshots', where: 'story_id = ?', whereArgs: [storyId]);
  }

  Future<void> deleteMessageById(int id) async {
    final db = await instance.db;
    await db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllMessages(int storyId) async {
    final db = await instance.db;
    await db.delete('messages', where: 'story_id = ?', whereArgs: [storyId]);
  }

  Future<void> deleteMessagesAfterSeq(int storyId, int seq) async {
    final db = await instance.db;
    await db.delete('messages', where: 'story_id = ? AND seq > ?', whereArgs: [storyId, seq]);
  }

  // ------------------------------------------------------------------- //
  // Messages
  // ------------------------------------------------------------------- //
  Future<int> insertMessage(StoryMessage m) async {
    final db = await instance.db;
    return db.insert('messages', _msgRow(m), conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Map<String, Object?> _msgRow(StoryMessage m) => {
        'story_id': m.storyId,
        'seq': m.seq,
        'role': m.role,
        'kind': m.kind,
        'speaker': m.speaker,
        'content': m.content,
        'variants': jsonEncode(m.variants),
        'active_variant': m.activeVariant,
        'suggestions': jsonEncode(m.suggestions),
        'meta': jsonEncode(m.meta),
      };

  Future<List<StoryMessage>> messagesForStory(int storyId, {int? limit}) async {
    final db = await instance.db;
    final rows = await db.query(
      'messages',
      where: 'story_id = ?',
      whereArgs: [storyId],
      orderBy: 'seq DESC',
      limit: limit,
    );
    final list = rows.map(_msgFromRow).toList().reversed.toList();
    return list;
  }

  Future<List<StoryMessage>> messagesAfterSeq(int storyId, int seq) async {
    final db = await instance.db;
    final rows = await db.query(
      'messages',
      where: 'story_id = ? AND seq > ?',
      whereArgs: [storyId, seq],
      orderBy: 'seq ASC',
    );
    return rows.map(_msgFromRow).toList();
  }

  Future<List<StoryMessage>> messagesBeforeSeq(int storyId, int seq) async {
    final db = await instance.db;
    final rows = await db.query(
      'messages',
      where: 'story_id = ? AND seq <= ?',
      whereArgs: [storyId, seq],
      orderBy: 'seq ASC',
    );
    return rows.map(_msgFromRow).toList();
  }

  StoryMessage _msgFromRow(Map<String, Object?> r) => StoryMessage(
        id: r['id'] as int,
        storyId: r['story_id'] as int,
        seq: (r['seq'] as num).toInt(),
        role: (r['role'] as String?) ?? 'assistant',
        kind: (r['kind'] as String?) ?? 'narration',
        speaker: (r['speaker'] as String?) ?? '',
        content: (r['content'] as String?) ?? '',
        variants: _decodeListString(r['variants']),
        activeVariant: (r['active_variant'] as num?)?.toInt() ?? 0,
        suggestions: _decodeListString(r['suggestions']),
        meta: _decodeMap(r['meta']),
      );

  List<String> _decodeListString(dynamic v) {
    final list = _decodeList(v);
    return list.whereType<String>().toList();
  }

  Future<void> updateMessageField(
    int messageId, {
    List<String>? suggest,
    List<String>? variants,
    int? activeVariant,
    String? content,
  }) async {
    final db = await instance.db;
    final data = <String, Object?>{
      if (suggest case final s?) 'suggestions': jsonEncode(s),
      if (variants case final v?) 'variants': jsonEncode(v),
      'active_variant': ?activeVariant,
      'content': ?content,
    };
    if (data.isEmpty) return;
    await db.update('messages', data, where: 'id = ?', whereArgs: [messageId]);
  }

  // ------------------------------------------------------------------- //
  // NPCs / Quests / Inventory / Memories
  // ------------------------------------------------------------------- //
  Future<List<StoryNPC>> npcsForStory(int storyId) async {
    final db = await instance.db;
    final rows = await db.query('npcs',
        where: 'story_id = ?', whereArgs: [storyId], orderBy: 'name COLLATE NOCASE');
    return rows
        .map((r) => StoryNPC(
              id: r['id'] as int,
              storyId: storyId,
              name: (r['name'] as String?) ?? '',
              details: _decodeMap(r['details']),
              relationshipValue: (r['relationship_value'] as num?)?.toDouble() ?? 0,
              emotionalState: (r['emotional_state'] as String?) ?? '',
              status: (r['status'] as String?) ?? 'alive',
              location: (r['location'] as String?) ?? '',
            ))
        .toList();
  }

  StoryNPC? findNpc(List<StoryNPC> npcs, String name) {
    final low = name.trim().toLowerCase();
    for (final n in npcs) {
      if (n.name.toLowerCase() == low || low.contains(n.name.toLowerCase())) return n;
    }
    return null;
  }

  Future<void> upsertNpc(StoryNPC npc) async {
    final db = await instance.db;
    if (npc.id > 0) {
      await db.update(
        'npcs',
        {
          'name': npc.name,
          'details': jsonEncode(npc.details),
          'relationship_value': npc.relationshipValue,
          'emotional_state': npc.emotionalState,
          'status': npc.status,
          'location': npc.location,
        },
        where: 'id = ?',
        whereArgs: [npc.id],
      );
    } else {
      await db.insert('npcs', {
        'story_id': npc.storyId,
        'name': npc.name,
        'details': jsonEncode(npc.details),
        'relationship_value': npc.relationshipValue,
        'emotional_state': npc.emotionalState,
        'status': npc.status,
        'location': npc.location,
      });
    }
  }

  Future<List<Quest>> questsForStory(int storyId) async {
    final db = await instance.db;
    final rows = await db.query('quests',
        where: 'story_id = ?', whereArgs: [storyId], orderBy: 'created_seq ASC, id ASC');
    return rows
        .map((r) => Quest(
              id: r['id'] as int,
              storyId: storyId,
              title: (r['title'] as String?) ?? '',
              description: (r['description'] as String?) ?? '',
              status: (r['status'] as String?) ?? 'active',
              createdSeq: (r['created_seq'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  Quest? findQuest(List<Quest> quests, String title) {
    final low = title.trim().toLowerCase();
    for (final q in quests) {
      if (q.title.toLowerCase() == low || q.title.toLowerCase().contains(low)) return q;
    }
    return null;
  }

  Future<void> upsertQuest(Quest q) async {
    final db = await instance.db;
    if (q.id > 0) {
      await db.update(
        'quests',
        {'title': q.title, 'description': q.description, 'status': q.status},
        where: 'id = ?',
        whereArgs: [q.id],
      );
    } else {
      await db.insert('quests', {
        'story_id': q.storyId,
        'title': q.title,
        'description': q.description,
        'status': q.status,
        'created_seq': q.createdSeq,
      });
    }
  }

  Future<List<InventoryItem>> inventoryForStory(int storyId) async {
    final db = await instance.db;
    final rows = await db.query('inventory_items',
        where: 'story_id = ?', whereArgs: [storyId], orderBy: 'name COLLATE NOCASE');
    return rows
        .map((r) => InventoryItem(
              id: r['id'] as int,
              storyId: storyId,
              name: (r['name'] as String?) ?? '',
              description: (r['description'] as String?) ?? '',
              quantity: (r['quantity'] as num?)?.toInt() ?? 1,
            ))
        .toList();
  }

  InventoryItem? findItem(List<InventoryItem> items, String name) {
    final low = name.trim().toLowerCase();
    for (final i in items) {
      if (i.name.toLowerCase() == low || low.contains(i.name.toLowerCase())) return i;
    }
    return null;
  }

  Future<void> upsertItem(InventoryItem item) async {
    final db = await instance.db;
    if (item.id > 0) {
      final qty = item.quantity;
      if (qty <= 0) {
        await db.delete('inventory_items', where: 'id = ?', whereArgs: [item.id]);
      } else {
        await db.update(
          'inventory_items',
          {'name': item.name, 'description': item.description, 'quantity': qty},
          where: 'id = ?',
          whereArgs: [item.id],
        );
      }
    } else {
      await db.insert('inventory_items', {
        'story_id': item.storyId,
        'name': item.name,
        'description': item.description,
        'quantity': item.quantity,
      });
    }
  }

  Future<List<Memory>> memoriesForStory(int storyId, {bool activeOnly = true}) async {
    final db = await instance.db;
    final rows = await db.query(
      'memories',
      where: activeOnly ? 'story_id = ? AND active = 1' : 'story_id = ?',
      whereArgs: [storyId],
      orderBy: 'importance DESC, id ASC',
    );
    return rows
        .map((r) => Memory(
              id: r['id'] as int,
              storyId: storyId,
              kind: (r['kind'] as String?) ?? 'fact',
              text: (r['text'] as String?) ?? '',
              importance: (r['importance'] as num?)?.toDouble() ?? 0.5,
              active: (r['active'] == 1),
              createdSeq: (r['created_seq'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  Future<int> insertMemory(Memory m) async {
    final db = await instance.db;
    return db.insert('memories', {
      'story_id': m.storyId,
      'kind': m.kind,
      'text': m.text,
      'importance': m.importance,
      'active': m.active ? 1 : 0,
      'created_seq': m.createdSeq,
    });
  }

  Future<void> setMemoryActive(int memoryId, bool active) async {
    final db = await instance.db;
    await db.update('memories', {'active': active ? 1 : 0},
        where: 'id = ?', whereArgs: [memoryId]);
  }

  Future<int?> lastSummarySeq(int storyId) async {
    final db = await instance.db;
    final rows = await db.query(
      'memories',
      where: 'story_id = ? AND kind = \'summary\'',
      whereArgs: [storyId],
      orderBy: 'created_seq DESC',
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['created_seq'] as num?)?.toInt() ?? 0;
  }

  // ------------------------------------------------------------------- //
  // World snapshots (for rewind-to-point)
  // ------------------------------------------------------------------- //

  /// Saves the full world state (state map + npcs + quests + items) as it was
  /// right after the turn ending at [seq]. Replaces any snapshot at that seq.
  Future<void> saveWorldSnapshot(int storyId, int seq, Map<String, dynamic> snapshot) async {
    final db = await instance.db;
    await db.insert(
      'world_snapshots',
      {'story_id': storyId, 'seq': seq, 'snapshot': jsonEncode(snapshot)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Deletes snapshots newer than [seq] (abandoned timeline after a rewind).
  Future<void> deleteSnapshotsAfterSeq(int storyId, int seq) async {
    final db = await instance.db;
    await db.delete('world_snapshots',
        where: 'story_id = ? AND seq > ?', whereArgs: [storyId, seq]);
  }

  /// Restores NPCs, quests and inventory from a [worldSnapshotAt] payload.
  Future<void> restoreWorldData(int storyId, Map<String, dynamic> snapshot) async {
    final db = await instance.db;
    final batch = db.batch();
    batch.delete('npcs', where: 'story_id = ?', whereArgs: [storyId]);
    batch.delete('quests', where: 'story_id = ?', whereArgs: [storyId]);
    batch.delete('inventory_items', where: 'story_id = ?', whereArgs: [storyId]);
    for (final n in (snapshot['npcs'] as List? ?? const [])) {
      if (n is Map) {
        batch.insert('npcs', {
          ...Map<String, dynamic>.from(n),
          'id': null,
          'story_id': storyId,
          'details': jsonEncode(n['details'] ?? {}),
        });
      }
    }
    for (final q in (snapshot['quests'] as List? ?? const [])) {
      if (q is Map) {
        batch.insert('quests', {...Map<String, dynamic>.from(q), 'id': null, 'story_id': storyId});
      }
    }
    for (final i in (snapshot['items'] as List? ?? const [])) {
      if (i is Map) {
        batch.insert('inventory_items',
            {...Map<String, dynamic>.from(i), 'id': null, 'story_id': storyId});
      }
    }
    await batch.commit(noResult: true);
  }

  /// Number of assistant narration messages at or before [seq].
  Future<int> countNarrationsUpTo(int storyId, int seq) async {
    final db = await instance.db;
    final count = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) FROM messages WHERE story_id = ? AND seq <= ? AND role = 'assistant' AND kind = 'narration'",
        [storyId, seq]));
    return count ?? 0;
  }

  /// Latest snapshot at or before [seq], or null when none exists.
  Future<Map<String, dynamic>?> worldSnapshotAt(int storyId, int seq) async {
    final db = await instance.db;
    final rows = await db.query(
      'world_snapshots',
      where: 'story_id = ? AND seq <= ?',
      whereArgs: [storyId, seq],
      orderBy: 'seq DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _decodeMap(rows.first['snapshot']);
  }
}