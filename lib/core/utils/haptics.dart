import 'package:flutter/services.dart';

/// Centralized haptic feedback so taps feel consistent across the app.
class Haptics {
  Haptics._();

  static void light() => HapticFeedback.lightImpact();
  static void medium() => HapticFeedback.mediumImpact();
  static void heavy() => HapticFeedback.heavyImpact();
  static void select() => HapticFeedback.selectionClick();
}
