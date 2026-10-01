import 'package:flutter/material.dart';

/// Layout sizes the app adapts to.
///
/// The reader was designed at desktop width, where the transport can spread
/// across one row and every control is a visible icon. A phone has roughly a
/// third of that width and no hover, so the same controls have to fold into
/// fewer rows and move behind a menu.
enum LumenSize {
  /// Phone portrait. One column, stacked transport, controls behind a menu.
  compact,

  /// Large phone landscape, small window, tablet portrait.
  medium,

  /// Desktop and tablet landscape: everything on show.
  expanded,
}

extension LumenLayout on BuildContext {
  LumenSize get size {
    final width = MediaQuery.sizeOf(this).width;
    if (width < 600) return LumenSize.compact;
    if (width < 1000) return LumenSize.medium;
    return LumenSize.expanded;
  }

  bool get isCompact => size == LumenSize.compact;
  bool get isExpanded => size == LumenSize.expanded;

  /// True where pointers are coarse: hover affordances are unavailable and hit
  /// targets need to meet the 48dp guideline.
  bool get _touchPlatform {
    final platform = Theme.of(this).platform;
    return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  }

  /// Horizontal page gutter.
  double get gutter => switch (size) {
    LumenSize.compact => 16,
    LumenSize.medium => 24,
    LumenSize.expanded => 36,
  };

  /// Minimum comfortable hit target for the current input.
  double get tapTarget => isCompact || _touchPlatform ? 48 : 40;
}
