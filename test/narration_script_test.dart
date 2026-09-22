import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:lumen_reader/services/narration_script.dart';

/// These cover the text pipeline that decides what Kokoro is asked to say.
/// The input strings imitate what pdfium hands back: hard line breaks inside
/// paragraphs, hyphenated wraps, ligature glyphs and page furniture.
void main() {
  final builder = ScriptBuilder();

  group('sentence boundaries', () {
    test('splits on terminal punctuation', () {
      expect(
        builder.segment('The engine is warm. It reads aloud! Does it pause? Yes.'),
        ['The engine is warm.', 'It reads aloud!', 'Does it pause?', 'Yes.'],
      );
    });

    test('does not split on common abbreviations', () {
      expect(
        builder.segment('Dr. Chen met Prof. Ada at 9 a.m. in the lab.'),
        ['Dr. Chen met Prof. Ada at 9 a.m. in the lab.'],
      );
    });

    test('does not split on initials', () {
      expect(
        builder.segment('The paper by J. R. Firth is short. It is also famous.'),
        ['The paper by J. R. Firth is short.', 'It is also famous.'],
      );
    });

    test('does not split inside decimals or version numbers', () {
      expect(
        builder.segment('Accuracy reached 98.6 percent. That beat v1.0 easily.'),
        ['Accuracy reached 98.6 percent.', 'That beat v1.0 easily.'],
      );
    });

    test('keeps a trailing quote with its sentence', () {
      expect(
        builder.segment('She said "it works." Then she left.'),
        ['She said "it works."', 'Then she left.'],
      );
    });

    test('splits on an ellipsis followed by a capital', () {
      expect(
        builder.segment('He waited... Then the voice began.'),
        ['He waited...', 'Then the voice began.'],
      );
    });
  });

  group('pdfium text normalisation', () {
    test('joins lines wrapped mid-paragraph', () {
      expect(
        builder.segment('The quick brown fox\njumps over the lazy dog.'),
        ['The quick brown fox jumps over the lazy dog.'],
      );
    });

    test('repairs hyphenated line wraps', () {
      expect(
        builder.segment('The narra-\ntion follows the high-\nlighted text.'),
        ['The narration follows the highlighted text.'],
      );
    });

    test('keeps real hyphens that happen to end a line', () {
      expect(
        builder.segment('It is a well-known\nresult.'),
        ['It is a well-known result.'],
      );
    });

    test('expands ligatures so they are pronounced', () {
      expect(
        builder.segment('The ﬁrst ﬂight was diﬃcult.'),
        ['The first flight was difficult.'],
      );
    });

    test('normalises curly quotes and dashes', () {
      expect(
        builder.segment('“Don’t stop” — she said.'),
        ['"Don\'t stop" - she said.'],
      );
    });

    test('collapses runs of whitespace', () {
      expect(
        builder.segment('Too    many\t\tspaces   here.'),
        ['Too many spaces here.'],
      );
    });
  });

  group('page furniture', () {
    test('drops bare page numbers', () {
      expect(builder.segment('12'), isEmpty);
      expect(builder.segment('- 7 -'), isEmpty);
    });

    test('drops text with no letters at all', () {
      expect(builder.segment('*** 1.2.3 ***'), isEmpty);
    });

    test('folds a short heading into the sentence that follows it', () {
      final result = builder.segment('Results\nThe model converged after twelve epochs.');
      expect(result, hasLength(1));
      expect(result.single, startsWith('Results'));
      expect(result.single, contains('converged'));
    });

    test('keeps a numbered list marker attached to its item', () {
      final result = builder.segment('1. Load the document and wait for the script.');
      expect(result, hasLength(1));
      expect(result.single, startsWith('1.'));
    });
  });

  group('length capping', () {
    test('cuts an overlong sentence on a soft boundary', () {
      final long = 'Alpha beta gamma delta epsilon zeta eta theta; '
          'iota kappa lambda mu nu xi omicron pi, '
          'rho sigma tau upsilon phi chi psi omega and then some more words '
          'to push this comfortably past the limit so it must be divided.';
      final small = ScriptBuilder(maxSentenceChars: 80);
      final parts = small.segment(long);

      expect(parts.length, greaterThan(1));
      for (final part in parts) {
        expect(part.length, lessThanOrEqualTo(80));
      }
      // Nothing may be lost or duplicated by the cut.
      expect(
        parts.join(' ').replaceAll(RegExp(r'\s+'), ' '),
        long.replaceAll(RegExp(r'\s+'), ' '),
      );
    });

    test('leaves normal sentences untouched', () {
      const text = 'A short sentence. Another short one.';
      expect(builder.segment(text), ['A short sentence.', 'Another short one.']);
    });
  });

  group('script indexing', () {
    test('firstIndexOnPage skips pages without text', () {
      final script = NarrationScript([
        for (var i = 0; i < 3; i++)
          Sentence(
            index: i,
            pageNumber: i == 0 ? 1 : 3,
            text: 'sentence $i',
            lineRects: const [],
            bounds: PdfRect.empty,
          ),
      ], 4);

      expect(script.firstIndexOnPage(1), 0);
      // Page 2 has nothing, so it inherits page 3's first sentence.
      expect(script.firstIndexOnPage(2), 1);
      expect(script.firstIndexOnPage(3), 1);
      expect(script.firstIndexOnPage(4), 3);
    });

    test('empty script reports zero', () {
      expect(NarrationScript.empty.firstIndexOnPage(5), 0);
      expect(NarrationScript.empty.isEmpty, isTrue);
    });
  });
}
