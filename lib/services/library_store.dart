import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/library_entry.dart';

/// The recents shelf: which documents were opened, and where narration stopped.
class LibraryStore extends ChangeNotifier {
  LibraryStore._(this._prefs, this._entries);

  static const _key = 'library_entries';
  static const _maxEntries = 60;

  final SharedPreferences _prefs;
  List<LibraryEntry> _entries;

  static Future<LibraryStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final entries = LibraryEntry.decodeList(prefs.getString(_key));
    return LibraryStore._(prefs, entries);
  }

  /// Most recently opened first, with documents whose file has been moved or
  /// deleted filtered out.
  List<LibraryEntry> get entries {
    final live = _entries.where((e) => File(e.path).existsSync()).toList()
      ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    return List.unmodifiable(live);
  }

  bool get isEmpty => entries.isEmpty;

  LibraryEntry? byPath(String path) {
    for (final entry in _entries) {
      if (_samePath(entry.path, path)) return entry;
    }
    return null;
  }

  /// Records an open, preserving any narration position already stored.
  Future<LibraryEntry> touch(String path) async {
    final existing = byPath(path);
    final entry = (existing ?? LibraryEntry(
      path: path,
      title: _titleFrom(path),
      openedAt: DateTime.now(),
    )).copyWith(openedAt: DateTime.now());

    await _upsert(entry);
    return entry;
  }

  Future<void> saveProgress(
    String path, {
    int? lastPage,
    int? sentenceIndex,
    int? sentenceCount,
    int? pageCount,
  }) async {
    final existing = byPath(path);
    if (existing == null) return;
    await _upsert(
      existing.copyWith(
        lastPage: lastPage,
        sentenceIndex: sentenceIndex,
        sentenceCount: sentenceCount,
        pageCount: pageCount,
      ),
    );
  }

  Future<void> remove(String path) async {
    _entries = _entries.where((e) => !_samePath(e.path, path)).toList();
    await _persist();
  }

  Future<void> clear() async {
    _entries = const [];
    await _persist();
  }

  Future<void> _upsert(LibraryEntry entry) async {
    final next = _entries.where((e) => !_samePath(e.path, entry.path)).toList()..insert(0, entry);
    if (next.length > _maxEntries) next.removeRange(_maxEntries, next.length);
    _entries = next;
    await _persist();
  }

  Future<void> _persist() async {
    await _prefs.setString(_key, LibraryEntry.encodeList(_entries));
    notifyListeners();
  }

  static bool _samePath(String a, String b) =>
      Platform.isWindows ? a.toLowerCase() == b.toLowerCase() : a == b;

  /// "quarterly-report_v2.pdf" reads better as "Quarterly Report V2".
  static String _titleFrom(String path) {
    var name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    name = name.replaceAll(RegExp(r'[_\-]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.isEmpty) return 'Untitled document';
    return name
        .split(' ')
        .map((w) => w.length <= 1 ? w.toUpperCase() : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}
