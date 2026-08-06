import 'package:flutter/material.dart';

/// Clearance so scroll content sits above the floating notched nav (no solid filler).
class LayoutInsets {
  LayoutInsets._();

  /// Nav bar (~64) + modest FAB overhang — keep tight so pages don’t end in a huge blank band.
  static double navClearance(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return 76 + bottom;
  }
}
