/// Kokoro ships voices named `<lang><gender>_<name>`, e.g. `af_heart` is an
/// American English female voice called "Heart". The sidecar only knows the raw
/// ids, so the presentation names are derived here.
class Voice {
  const Voice({
    required this.id,
    required this.displayName,
    required this.accent,
    required this.accentCode,
    required this.isFemale,
  });

  factory Voice.fromId(String id) {
    final langCode = id.isNotEmpty ? id[0] : 'a';
    final genderCode = id.length > 1 ? id[1] : 'f';
    final raw = id.contains('_') ? id.split('_').sublist(1).join(' ') : id;

    return Voice(
      id: id,
      displayName: _titleCase(raw),
      accent: _accents[langCode] ?? 'Other',
      accentCode: langCode,
      isFemale: genderCode == 'f',
    );
  }

  final String id;
  final String displayName;

  /// Human-readable language/accent group, used to section the voice picker.
  final String accent;
  final String accentCode;
  final bool isFemale;

  String get gender => isFemale ? 'Female' : 'Male';

  /// Two-letter monogram shown in the voice picker avatar.
  String get initials => displayName.isEmpty ? '?' : displayName[0].toUpperCase();

  String get subtitle => '$accent - $gender';

  static const _accents = <String, String>{
    'a': 'American English',
    'b': 'British English',
    'e': 'Spanish',
    'f': 'French',
    'h': 'Hindi',
    'i': 'Italian',
    'j': 'Japanese',
    'p': 'Portuguese (BR)',
    'z': 'Mandarin',
  };

  /// Display order for the accent sections - English first, then alphabetical.
  static const accentOrder = <String>['a', 'b', 'e', 'f', 'i', 'p', 'h', 'j', 'z'];

  static String _titleCase(String value) {
    return value
        .split(RegExp(r'[\s_]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  /// A short line the app can speak when previewing the voice.
  String get previewLine => switch (accentCode) {
    'e' => 'Hola, soy $displayName. Puedo leer tu documento en voz alta.',
    'f' => 'Bonjour, je suis $displayName. Je peux vous lire ce document.',
    'i' => 'Ciao, sono $displayName. Posso leggerti questo documento.',
    'p' => 'Ola, eu sou $displayName. Posso ler este documento para voce.',
    'h' => 'Namaste, main $displayName hoon.',
    'j' => 'こんにちは、$displayName です。',
    'z' => '你好，我是 $displayName。',
    _ => 'Hello, I am $displayName. This is how your document will sound.',
  };

  @override
  bool operator ==(Object other) => other is Voice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
