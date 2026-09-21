import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../services/narration_script.dart';

/// Paints the narration highlight directly onto the rendered page.
///
/// pdfrx hands us the page rectangle in canvas coordinates; PDF text rectangles
/// use a bottom-left origin, so the y axis is flipped on the way in.
class SentenceHighlighter {
  const SentenceHighlighter({
    required this.current,
    required this.upcoming,
    required this.fill,
    required this.edge,
    required this.showUpcoming,
  });

  final Sentence? current;
  final Sentence? upcoming;
  final Color fill;
  final Color edge;
  final bool showUpcoming;

  void paint(Canvas canvas, Rect pageRect, PdfPage page) {
    if (showUpcoming && upcoming != null && upcoming!.pageNumber == page.pageNumber) {
      _paintSentence(
        canvas,
        pageRect,
        page,
        upcoming!,
        Paint()..color = fill.withValues(alpha: fill.a * 0.28),
        null,
      );
    }

    final sentence = current;
    if (sentence == null || sentence.pageNumber != page.pageNumber) return;

    _paintSentence(
      canvas,
      pageRect,
      page,
      sentence,
      Paint()..color = fill,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
  }

  void _paintSentence(
    Canvas canvas,
    Rect pageRect,
    PdfPage page,
    Sentence sentence,
    Paint fillPaint,
    Paint? strokePaint,
  ) {
    final scaleX = pageRect.width / page.width;
    final scaleY = pageRect.height / page.height;

    for (final box in sentence.lineRects) {
      final rect = Rect.fromLTRB(
        pageRect.left + box.left * scaleX,
        pageRect.top + (page.height - box.top) * scaleY,
        pageRect.left + box.right * scaleX,
        pageRect.top + (page.height - box.bottom) * scaleY,
      );
      if (rect.width <= 0 || rect.height <= 0) continue;

      final rounded = RRect.fromRectAndRadius(rect, Radius.circular(rect.height * 0.22));
      canvas.drawRRect(rounded, fillPaint);
      if (strokePaint != null) canvas.drawRRect(rounded, strokePaint);
    }
  }
}
