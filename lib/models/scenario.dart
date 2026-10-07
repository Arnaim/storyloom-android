/// A scenario definition (premise, world, NPCs…) plus JSON helpers.
class Scenario {
  Scenario({
    required this.id,
    required this.title,
    required this.description,
    required this.genre,
    required this.tags,
    required this.premise,
    required this.openingScene,
    required this.worldDescription,
    required this.rules,
    required this.tone,
    required this.narratorStyle,
    required this.contentRating,
    required this.rpgEnabled,
    required this.playerRole,
    required this.npcs,
    required this.locations,
    required this.lore,
    required this.openingSuggestions,
    required this.isSample,
    required this.playCount,
    this.author = 'Storyloom',
    this.coverArt,
    this.backgroundArt,
    this.seedVersion = 0,
    this.forks = const [],
  });

  final int id;
  final String title;
  final String description;
  final String genre;
  final List<String> tags;
  final String premise;
  final String openingScene;
  final String worldDescription;
  final String rules;
  final String tone;
  final String narratorStyle;
  final String contentRating; // general | mature
  final bool rpgEnabled;
  final String playerRole;
  final List<Map<String, dynamic>> npcs;
  final List<Map<String, dynamic>> locations;
  final List<Map<String, dynamic>> lore;
  final List<String> openingSuggestions;
  final bool isSample;
  final int playCount;
  final String author;
  final String? coverArt;
  final String? backgroundArt;
  final int seedVersion;
  final List<Fork> forks;

  String get ratingLabel => contentRating == 'mature' ? 'Mature' : 'General';

  Scenario copyWith({String? coverArt, String? backgroundArt, int? seedVersion, List<Fork>? forks}) => Scenario(
        id: id,
        title: title,
        description: description,
        genre: genre,
        tags: tags,
        premise: premise,
        openingScene: openingScene,
        worldDescription: worldDescription,
        rules: rules,
        tone: tone,
        narratorStyle: narratorStyle,
        contentRating: contentRating,
        rpgEnabled: rpgEnabled,
        playerRole: playerRole,
        npcs: npcs,
        locations: locations,
        lore: lore,
        openingSuggestions: openingSuggestions,
        isSample: isSample,
        playCount: playCount,
        author: author,
        coverArt: coverArt ?? this.coverArt,
        backgroundArt: backgroundArt ?? this.backgroundArt,
        seedVersion: seedVersion ?? this.seedVersion,
        forks: forks ?? this.forks,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'genre': genre,
        'tags': tags,
        'premise': premise,
        'opening_scene': openingScene,
        'world_description': worldDescription,
        'rules': rules,
        'tone': tone,
        'narrator_style': narratorStyle,
        'content_rating': contentRating,
        'rpg_enabled': rpgEnabled ? 1 : 0,
        'player_role': playerRole,
        'npcs': npcs,
        'locations': locations,
        'lore': lore,
        'opening_suggestions': openingSuggestions,
        'is_sample': isSample ? 1 : 0,
        'play_count': playCount,
        'author': author,
        'cover_art': coverArt,
        'background_art': backgroundArt,
        'seed_version': seedVersion,
        'forks': forks.map((f) => f.toJson()).toList(),
      };

  factory Scenario.fromJson(Map<String, dynamic> j) => Scenario(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: (j['title'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
        genre: (j['genre'] as String?) ?? '',
        tags: _strList(j['tags']),
        premise: (j['premise'] as String?) ?? '',
        openingScene: (j['opening_scene'] as String?) ?? '',
        worldDescription: (j['world_description'] as String?) ?? '',
        rules: (j['rules'] as String?) ?? '',
        tone: (j['tone'] as String?) ?? '',
        narratorStyle: (j['narrator_style'] as String?) ?? '',
        contentRating: (j['content_rating'] as String?) ?? 'general',
        rpgEnabled: (j['rpg_enabled'] == 1 || j['rpg_enabled'] == true),
        playerRole: (j['player_role'] as String?) ?? '',
        npcs: _mapList(j['npcs']),
        locations: _mapList(j['locations']),
        lore: _mapList(j['lore']),
        openingSuggestions: _strList(j['opening_suggestions']),
        isSample: (j['is_sample'] == 1 || j['is_sample'] == true),
        playCount: (j['play_count'] as num?)?.toInt() ?? 0,
        author: (j['author'] as String?) ?? 'Storyloom',
        coverArt: (j['cover_art'] as String?) ?? '',
        backgroundArt: (j['background_art'] as String?) ?? '',
        seedVersion: (j['seed_version'] as num?)?.toInt() ?? 0,
        forks: _forks(j['forks']),
      );

  static List<String> _strList(dynamic v) =>
      v is List ? v.whereType<String>().toList() : const [];

  static List<Map<String, dynamic>> _mapList(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : const [];

  static List<Fork> _forks(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => Fork.fromJson(
              Map<String, dynamic>.from(e))).toList()
      : const [];
}

/// A story fork — a branch point the player can enter when triggers fire.
class Fork {
  const Fork({
    required this.id,
    required this.label,
    this.triggers = const [],
    this.leadsTo,
    this.openingScene,
  });

  final String id;
  final String label;
  final List<ForkTrigger> triggers;
  final String? leadsTo; // branch to switch to; null = same branch, record choice
  final String? openingScene; // branch-specific opening variant

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'triggers': triggers.map((t) => t.toJson()).toList(),
        'leads_to': leadsTo,
        'opening_scene': openingScene,
      };

  factory Fork.fromJson(Map<String, dynamic> j) => Fork(
        id: (j['id'] as String?) ?? j['id'].toString(),
        label: (j['label'] as String?) ?? '',
        triggers: (j['triggers'] as List?)
                ?.map((e) => ForkTrigger.fromJson(
                    Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
        leadsTo: j['leads_to'] as String?,
        openingScene: j['opening_scene'] as String?,
      );
}

/// A condition that must be true for a fork to become available.
class ForkTrigger {
  const ForkTrigger({
    required this.type,
    this.npc,
    this.key,
    this.op,
    this.value,
  });

  final String type; // 'relationship' | 'fact' | 'flag' | 'turns' | 'tone'
  final String? npc; // NPC name (for relationship)
  final String? key; // fact/flag key
  final String? op; // '<' | '>' | '==' | '>=' | '<=' | '!='
  final dynamic value; // comparison value

  Map<String, dynamic> toJson() => {
        'type': type,
        if (npc != null && npc!.isNotEmpty) 'npc': npc,
        if (key != null && key!.isNotEmpty) 'key': key,
        if (op != null && op!.isNotEmpty) 'op': op,
        if (value != null) 'value': value,
      };

  factory ForkTrigger.fromJson(Map<String, dynamic> j) => ForkTrigger(
        type: (j['type'] as String?) ?? 'relationship',
        npc: j['npc'] as String?,
        key: j['key'] as String?,
        op: j['op'] as String?,
        value: j['value'],
      );
}