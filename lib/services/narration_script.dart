import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

/// One spoken unit: a sentence, plus the boxes to light up on the page while it
/// is being read.
class Sentence {
  const Sentence({
    required this.index,
    required this.pageNumber,
    required this.text,
    required this.lineRects,
    required this.bounds,
  });

  /// Position in the document-wide narration script.
  final int index;
  final int pageNumber;

  /// Normalised text handed to the speech engine.
  final String text;

  /// One box per visual line, in PDF page coordinates (origin bottom-left).
  final List<PdfRect> lineRects;

  /// Union of [lineRects]; used to scroll the sentence into view.
  final PdfRect bounds;

  /// Rough reading time, used to size the progress rail before the audio for a
  /// sentence has been rendered.
  Duration get estimatedDuration =>
      Duration(milliseconds: (400 + text.length * 55).clamp(600, 30000));
}

/// The full narration for a document.
class NarrationScript {
  NarrationScript(this.sentences, this.pageCount)
    : _firstOnPage = _buildPageIndex(sentences, pageCount);

  static final empty = NarrationScript(const <Sentence>[], 0);

  final List<Sentence> sentences;
  final int pageCount;
  final List<int> _firstOnPage;

  bool get isEmpty => sentences.isEmpty;
  bool get isNotEmpty => sentences.isNotEmpty;
  int get length => sentences.length;

  Sentence operator [](int index) => sentences[index];

  /// Sentences that fall on [pageNumber] (1-based), for page-level highlighting.
  Iterable<Sentence> onPage(int pageNumber) =>
      sentences.where((s) => s.pageNumber == pageNumber);

  /// Index of the first sentence at or after [pageNumber]; used when the user
  /// jumps the viewer to a page and then presses play.
  int firstIndexOnPage(int pageNumber) {
    if (sentences.isEmpty) return 0;
    final page = pageNumber.clamp(1, pageCount);
    return _firstOnPage[page - 1];
  }

  static List<int> _buildPageIndex(List<Sentence> sentences, int pageCount) {
    // For each page, the first sentence index at or after it. Pages with no
    // extractable text inherit the next page's starting point.
    final result = List<int>.filled(pageCount < 1 ? 1 : pageCount, sentences.length);
    for (var i = sentences.length - 1; i >= 0; i--) {
      final page = sentences[i].pageNumber;
      if (page >= 1 && page <= result.length) result[page - 1] = i;
    }
    for (var i = result.length - 2; i >= 0; i--) {
      if (result[i] == sentences.length) result[i] = result[i + 1];
    }
    return result;
  }
}


/// Progress report while a document is being prepared for narration.
class ScriptProgress {
  const ScriptProgress(this.pagesDone, this.pagesTotal, this.sentencesFound);

  final int pagesDone;
  final int pagesTotal;
  final int sentencesFound;

  double get fraction => pagesTotal == 0 ? 0 : (pagesDone / pagesTotal).clamp(0.0, 1.0);
}

/// Builds a [NarrationScript] from a PDF.
///
/// The work is two passes per page: normalise pdfium's raw text into something
/// worth speaking (keeping a map back to the original character indices so the
/// highlight boxes stay correct), then cut that into sentences.
class ScriptBuilder {
  ScriptBuilder({this.maxSentenceChars = 320});

  /// Kokoro renders a sentence in one shot, so very long "sentences" (common in
  /// papers with inline citations) are cut on a soft boundary to keep the
  /// latency between highlight jumps reasonable.
  final int maxSentenceChars;

  bool _cancelled = false;
  void cancel() => _cancelled = true;

  /// Runs the text pipeline without a PDF: normalise, split, filter.
  ///
  /// Exposed so the segmentation rules can be tested against raw pdfium-style
  /// text (hard line breaks, hyphenation, ligatures) without a document.
  @visibleForTesting
  List<String> segment(String rawPageText) {
    final normalized = _normalize(rawPageText);
    return _splitIntoSentences(normalized.text)
        .map((r) => normalized.text.substring(r.start, r.end).trim())
        .where(_isWorthSpeaking)
        .toList();
  }

  Future<NarrationScript> build(
    PdfDocument document, {
    void Function(ScriptProgress)? onProgress,
  }) async {
    final sentences = <Sentence>[];
    final pages = document.pages;

    for (var i = 0; i < pages.length; i++) {
      if (_cancelled) break;

      try {
        final pageText = await pages[i].loadStructuredText();
        _appendPage(pageText, pages[i].pageNumber, sentences);
      } catch (_) {
        // A page that fails to yield text (scanned image, damaged xref) simply
        // contributes nothing to the narration.
      }

      onProgress?.call(ScriptProgress(i + 1, pages.length, sentences.length));
      // Yield so the "preparing" UI keeps animating on large documents.
      if (i % 4 == 3) await Future<void>.delayed(Duration.zero);
    }

    return NarrationScript(List.unmodifiable(sentences), pages.length);
  }

  void _appendPage(PdfPageText pageText, int pageNumber, List<Sentence> out) {
    final normalized = _normalize(pageText.fullText);
    if (normalized.text.trim().isEmpty) return;

    final ranges = _splitIntoSentences(normalized.text);
    final charRects = pageText.charRects;

    for (final range in ranges) {
      final text = normalized.text.substring(range.start, range.end).trim();
      if (!_isWorthSpeaking(text)) continue;

      final rects = _lineBoxes(charRects, normalized.sourceIndex, range.start, range.end);
      if (rects.isEmpty) continue;

      var bounds = rects.first;
      for (final r in rects.skip(1)) {
        bounds = bounds.merge(r);
      }

      out.add(
        Sentence(
          index: out.length,
          pageNumber: pageNumber,
          text: text,
          lineRects: List.unmodifiable(rects),
          bounds: bounds,
        ),
      );
    }
  }

  // ---------------------------------------------------------------- normalise

  /// Collapses PDF line-wrapping into flowing text while remembering, for every
  /// output character, which original character it came from.
  static _Normalized _normalize(String raw) {
    final buffer = StringBuffer();
    final sourceIndex = <int>[];
    var pendingSpace = false;
    var emitted = 0;

    void emit(String chunk, int source) {
      if (chunk.isEmpty) return;
      if (pendingSpace && emitted > 0) {
        buffer.write(' ');
        sourceIndex.add(source);
        emitted++;
      }
      pendingSpace = false;
      buffer.write(chunk);
      for (var i = 0; i < chunk.length; i++) {
        sourceIndex.add(source);
      }
      emitted += chunk.length;
    }

    for (var i = 0; i < raw.length; i++) {
      final code = raw.codeUnitAt(i);
      final ch = raw[i];

      if (code == 0x00AD) continue; // soft hyphen

      // Hyphen at a line break: glue the word back together.
      if ((ch == '-' || code == 0x2010) && _startsLineBreak(raw, i + 1)) {
        final next = _firstNonBreak(raw, i + 1);
        if (next != null && _isLower(raw.codeUnitAt(next))) {
          i = next - 1;
          continue;
        }
      }

      if (code <= 0x20) {
        if (emitted > 0) pendingSpace = true;
        continue;
      }

      final ligature = _ligatures[ch];
      emit(ligature ?? ch, i);
    }

    return _Normalized(buffer.toString(), sourceIndex);
  }

  static const _ligatures = <String, String>{
    'ﬀ': 'ff',
    'ﬁ': 'fi',
    'ﬂ': 'fl',
    'ﬃ': 'ffi',
    'ﬄ': 'ffl',
    'ﬅ': 'st',
    'ﬆ': 'st',
    '‘': "'",
    '’': "'",
    '“': '"',
    '”': '"',
    '–': '-',
    '—': '-',
  };

  static bool _startsLineBreak(String s, int from) {
    for (var i = from; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x0A || c == 0x0D) return true;
      if (c == 0x20 || c == 0x09) continue;
      return false;
    }
    return false;
  }

  static int? _firstNonBreak(String s, int from) {
    for (var i = from; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x0A || c == 0x0D || c == 0x20 || c == 0x09) continue;
      return i;
    }
    return null;
  }

  static bool _isLower(int c) => c >= 0x61 && c <= 0x7A;
  static bool _isUpper(int c) => c >= 0x41 && c <= 0x5A;
  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
  static bool _isLetter(int c) => _isLower(c) || _isUpper(c) || c > 0x7F;

  // ------------------------------------------------------------------- split

  List<_Range> _splitIntoSentences(String text) {
    final raw = <_Range>[];
    var start = 0;
    var i = 0;

    while (i < text.length) {
      final c = text[i];
      if (c == '.' || c == '!' || c == '?' || c == '…') {
        // Absorb runs like "?!" and any closing quote or bracket after them.
        var end = i;
        while (end + 1 < text.length && _isTerminator(text[end + 1])) {
          end++;
        }
        var after = end + 1;
        while (after < text.length && _closers.contains(text[after])) {
          after++;
        }

        if (_isSentenceBreak(text, start, i, after)) {
          raw.add(_Range(start, after));
          var next = after;
          while (next < text.length && text[next] == ' ') {
            next++;
          }
          start = next;
          i = next;
          continue;
        }
        i = after;
        continue;
      }
      i++;
    }

    if (start < text.length) raw.add(_Range(start, text.length));

    return _mergeFragments(_capLength(raw, text), text);
  }

  static bool _isTerminator(String c) => c == '.' || c == '!' || c == '?' || c == '…';
  static const _closers = '")]}»›\'';

  bool _isSentenceBreak(String text, int start, int dot, int after) {
    // Must be followed by whitespace (or be the end of the page text).
    if (after < text.length && text[after] != ' ') return false;
    if (after >= text.length) return true;

    // Peek at the next real character: a new sentence opens with a capital, a
    // digit, a quote or a dash.
    var probe = after;
    while (probe < text.length && text[probe] == ' ') {
      probe++;
    }
    if (probe >= text.length) return true;
    final nextCode = text.codeUnitAt(probe);
    final opensSentence =
        _isUpper(nextCode) ||
        _isDigit(nextCode) ||
        nextCode > 0x7F ||
        '"\'([«-'.contains(text[probe]);
    if (!opensSentence) return false;

    // Only single periods can be abbreviations; "?!" and "..." always break.
    if (text[dot] != '.' || (dot + 1 <= after - 1 && text[dot + 1] == '.')) return true;

    final word = _wordBefore(text, dot, start);
    if (word.isEmpty) return false;
    if (word.length == 1 && _isUpper(word.codeUnitAt(0))) return false; // initial
    if (_abbreviations.contains(word.toLowerCase())) return false;

    // A number that is the whole segment so far is a list marker ("1. Load
    // the file"), not the end of a sentence. A number at the end of a real
    // sentence ("...was 1999.") has words in front of it and still breaks.
    if (text.substring(start, dot).trim() == word && _isAllDigits(word)) return false;

    return true;
  }

  static bool _isAllDigits(String value) {
    for (var i = 0; i < value.length; i++) {
      if (!_isDigit(value.codeUnitAt(i))) return false;
    }
    return value.isNotEmpty;
  }

  static String _wordBefore(String text, int dot, int limit) {
    var i = dot - 1;
    while (i >= limit) {
      final c = text.codeUnitAt(i);
      if (_isLetter(c) || _isDigit(c) || c == 0x2E) {
        i--;
      } else {
        break;
      }
    }
    final word = text.substring(i + 1, dot);
    // "e.g" -> "g", so multi-dot abbreviations fall through to the initial rule.
    final lastDot = word.lastIndexOf('.');
    return lastDot == -1 ? word : word.substring(lastDot + 1);
  }

  static const _abbreviations = <String>{
    'mr', 'mrs', 'ms', 'dr', 'prof', 'sr', 'jr', 'st', 'mt', 'rev', 'hon',
    'fig', 'figs', 'eq', 'eqs', 'ref', 'refs', 'no', 'nos', 'vol', 'vols',
    'ch', 'chap', 'sec', 'secs', 'pp', 'p', 'al', 'etc', 'cf', 'vs', 'viz',
    'approx', 'dept', 'univ', 'inc', 'ltd', 'co', 'corp', 'est', 'esp', 'resp',
    'min', 'max', 'avg', 'std', 'ca', 'circa', 'ed', 'eds', 'trans', 'orig',
    'jan', 'feb', 'mar', 'apr', 'jun', 'jul', 'aug', 'sep', 'sept', 'oct',
    'nov', 'dec', 'mon', 'tue', 'tues', 'wed', 'thu', 'thur', 'thurs', 'fri',
    'sat', 'sun',
  };

  /// Cuts sentences that would otherwise be a paragraph-long single clip.
  List<_Range> _capLength(List<_Range> ranges, String text) {
    final out = <_Range>[];
    for (final range in ranges) {
      var start = range.start;
      while (range.end - start > maxSentenceChars) {
        final cut = _softCut(text, start, start + maxSentenceChars);
        if (cut <= start) break;
        out.add(_Range(start, cut));
        start = cut;
        while (start < range.end && text[start] == ' ') {
          start++;
        }
      }
      if (start < range.end) out.add(_Range(start, range.end));
    }
    return out;
  }

  static int _softCut(String text, int start, int limit) {
    for (final sep in const ['; ', ': ', ', ', ' - ', ' ']) {
      final at = text.lastIndexOf(sep, limit);
      if (at > start + 40) return at + sep.length;
    }
    return limit;
  }

  /// Folds headings, list markers and stray numbers into the following sentence
  /// so the narration does not stutter through one-word clips.
  List<_Range> _mergeFragments(List<_Range> ranges, String text) {
    final out = <_Range>[];
    _Range? held;

    for (final range in ranges) {
      final slice = text.substring(range.start, range.end).trim();
      final merged = held == null ? range : _Range(held.start, range.end);

      if (_isStub(slice) && range.end - range.start < 24) {
        held = merged;
        continue;
      }
      out.add(merged);
      held = null;
    }
    if (held != null) out.add(held);
    return out;
  }

  static bool _isStub(String slice) {
    if (slice.isEmpty) return true;
    final words = slice.split(' ').where((w) => w.isNotEmpty).length;
    final ends = slice.endsWith('.') || slice.endsWith('!') || slice.endsWith('?');
    return words < 3 && !ends;
  }

  /// Filters out page numbers, rule lines and other furniture.
  static bool _isWorthSpeaking(String text) {
    if (text.length < 2) return false;
    var letters = 0;
    for (var i = 0; i < text.length; i++) {
      if (_isLetter(text.codeUnitAt(i))) letters++;
    }
    if (letters == 0) return false;
    // "12", "iv", "- 7 -" and friends.
    if (text.length <= 5 && letters <= 2) return false;
    return true;
  }

  // ------------------------------------------------------------------- boxes

  /// Groups the character rectangles of a sentence into one box per visual line.
  static List<PdfRect> _lineBoxes(
    List<PdfRect> charRects,
    List<int> sourceIndex,
    int start,
    int end,
  ) {
    final lines = <PdfRect>[];
    PdfRect? current;
    var lastSource = -1;

    for (var i = start; i < end && i < sourceIndex.length; i++) {
      final src = sourceIndex[i];
      if (src == lastSource) continue; // ligature expansions share a source char
      lastSource = src;
      if (src < 0 || src >= charRects.length) continue;

      final rect = charRects[src];
      if (rect.width <= 0 || rect.height <= 0) continue;

      if (current == null) {
        current = rect;
        continue;
      }

      if (_sameLine(current, rect)) {
        current = current.merge(rect);
      } else {
        lines.add(current);
        current = rect;
      }
    }
    if (current != null) lines.add(current);

    // A touch of padding makes the highlight hug the text instead of clipping it.
    return lines.map((r) => r.inflate(1.0, 1.5)).toList(growable: false);
  }

  /// PDF coordinates put the origin bottom-left, so `top > bottom`.
  static bool _sameLine(PdfRect line, PdfRect glyph) {
    final overlap =
        (line.top < glyph.top ? line.top : glyph.top) -
        (line.bottom > glyph.bottom ? line.bottom : glyph.bottom);
    final reference = line.height < glyph.height ? line.height : glyph.height;
    if (reference <= 0) return false;
    if (overlap < reference * 0.4) return false;
    // Guard against a two-column page whose lines overlap vertically.
    return glyph.left >= line.left - reference * 2;
  }
}

class _Normalized {
  const _Normalized(this.text, this.sourceIndex);
  final String text;
  final List<int> sourceIndex;
}

class _Range {
  const _Range(this.start, this.end);
  final int start;
  final int end;
}
