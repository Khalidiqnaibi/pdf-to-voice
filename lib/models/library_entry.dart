import 'dart:convert';

/// A document the user has opened before, with enough state to put them back
/// exactly where the narration stopped.
class LibraryEntry {
  const LibraryEntry({
    required this.path,
    required this.title,
    required this.openedAt,
    this.pageCount = 0,
    this.lastPage = 1,
    this.sentenceIndex = 0,
    this.sentenceCount = 0,
  });

  final String path;
  final String title;
  final DateTime openedAt;
  final int pageCount;

  /// Page the viewer was showing when the document was closed.
  final int lastPage;

  /// Index into the narration script, so playback resumes mid-paragraph.
  final int sentenceIndex;
  final int sentenceCount;

  /// 0..1 through the narration, falling back to page position when the
  /// document has not been prepared for narration yet.
  double get progress {
    if (sentenceCount > 0) return (sentenceIndex / sentenceCount).clamp(0.0, 1.0);
    if (pageCount > 0) return ((lastPage - 1) / pageCount).clamp(0.0, 1.0);
    return 0;
  }

  bool get isStarted => progress > 0.001;
  bool get isFinished => progress > 0.995;

  LibraryEntry copyWith({
    String? title,
    DateTime? openedAt,
    int? pageCount,
    int? lastPage,
    int? sentenceIndex,
    int? sentenceCount,
  }) {
    return LibraryEntry(
      path: path,
      title: title ?? this.title,
      openedAt: openedAt ?? this.openedAt,
      pageCount: pageCount ?? this.pageCount,
      lastPage: lastPage ?? this.lastPage,
      sentenceIndex: sentenceIndex ?? this.sentenceIndex,
      sentenceCount: sentenceCount ?? this.sentenceCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'title': title,
    'openedAt': openedAt.toIso8601String(),
    'pageCount': pageCount,
    'lastPage': lastPage,
    'sentenceIndex': sentenceIndex,
    'sentenceCount': sentenceCount,
  };

  static LibraryEntry? fromJson(Map<String, dynamic> json) {
    final path = json['path'];
    if (path is! String || path.isEmpty) return null;
    return LibraryEntry(
      path: path,
      title: json['title'] as String? ?? path.split(RegExp(r'[\\/]')).last,
      openedAt: DateTime.tryParse(json['openedAt'] as String? ?? '') ?? DateTime.now(),
      pageCount: (json['pageCount'] as num?)?.toInt() ?? 0,
      lastPage: (json['lastPage'] as num?)?.toInt() ?? 1,
      sentenceIndex: (json['sentenceIndex'] as num?)?.toInt() ?? 0,
      sentenceCount: (json['sentenceCount'] as num?)?.toInt() ?? 0,
    );
  }

  static String encodeList(List<LibraryEntry> entries) =>
      jsonEncode(entries.map((e) => e.toJson()).toList());

  static List<LibraryEntry> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(LibraryEntry.fromJson)
          .whereType<LibraryEntry>()
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
