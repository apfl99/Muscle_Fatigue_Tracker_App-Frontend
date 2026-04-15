class SupabaseRuntimeState {
  SupabaseRuntimeState._();

  static DateTime? _suspendedUntil;
  static String? _lastReason;

  static bool get isTemporarilySuspended {
    final until = _suspendedUntil;
    if (until == null) {
      return false;
    }
    if (DateTime.now().isAfter(until)) {
      _suspendedUntil = null;
      _lastReason = null;
      return false;
    }
    return true;
  }

  static String? get lastReason => _lastReason;

  static void suspendFor(Duration duration, {String? reason}) {
    _suspendedUntil = DateTime.now().add(duration);
    _lastReason = reason;
  }

  static void clearSuspension() {
    _suspendedUntil = null;
    _lastReason = null;
  }
}
