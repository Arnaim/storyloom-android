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

  String get ratingLabel => contentRating == 'mature' ? 'Mature' : 'General';

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
      );

  static List<String> _strList(dynamic v) =>
      v is List ? v.whereType<String>().toList() : const [];

  static List<Map<String, dynamic>> _mapList(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : const [];
}