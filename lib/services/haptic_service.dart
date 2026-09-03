import 'package:flutter/services.dart';

class HapticService {
  static bool isEnabled = true;

  /// Light vibration for micro-interactions: tab switches, button clicks, sort changes
  static void light() {
    if (!isEnabled) return;
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  /// Medium vibration for player actions: skip track, play/pause, loop/shuffle toggle
  static void medium() {
    if (!isEnabled) return;
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// Heavy / Selection vibration for important milestones: download start/finish, delete
  static void heavy() {
    if (!isEnabled) return;
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// Subtle selection tick (e.g. slider drag, picker)
  static void selection() {
    if (!isEnabled) return;
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
  }
}
