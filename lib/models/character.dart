/// The player character profile (the user always controls this character).
class Character {
  Character({
    this.name = '',
    this.age = '',
    this.gender = '',
    this.pronouns = '',
    this.occupation = '',
    this.origin = '',
    this.appearance = '',
    this.personality = '',
    this.background = '',
    this.attributes = const {},
  });

  final String name;
  final String age;
  final String gender;
  final String pronouns;
  final String occupation;
  final String origin;
  final String appearance;
  final String personality;
  final String background;
  final Map<String, dynamic> attributes;

  bool get isBlank => name.trim().isEmpty && appearance.trim().isEmpty;

  Map<String, dynamic> toJson() => {
        'name': name,
        'age': age,
        'gender': gender,
        'pronouns': pronouns,
        'occupation': occupation,
        'origin': origin,
        'appearance': appearance,
        'personality': personality,
        'background': background,
        'attributes': attributes,
      };

  factory Character.fromJson(Map<String, dynamic>? j) {
    if (j == null) return Character();
    return Character(
      name: (j['name'] as String?) ?? '',
      age: (j['age'] as String?) ?? '',
      gender: (j['gender'] as String?) ?? '',
      pronouns: (j['pronouns'] as String?) ?? '',
      occupation: (j['occupation'] as String?) ?? '',
      origin: (j['origin'] as String?) ?? '',
      appearance: (j['appearance'] as String?) ?? '',
      personality: (j['personality'] as String?) ?? '',
      background: (j['background'] as String?) ?? '',
      attributes: Map<String, dynamic>.from(j['attributes'] as Map? ?? const {}),
    );
  }
}