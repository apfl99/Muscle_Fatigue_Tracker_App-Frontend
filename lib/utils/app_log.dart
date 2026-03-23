import 'package:flutter/foundation.dart';

const bool _verboseLogs = bool.fromEnvironment(
  'MUSCLECARE_VERBOSE_LOGS',
  defaultValue: false,
);
const int _configuredLogsPerSecond = int.fromEnvironment(
  'MUSCLECARE_LOGS_PER_SECOND',
  defaultValue: 24,
);
const int _configuredMaxChars = int.fromEnvironment(
  'MUSCLECARE_LOG_MAX_CHARS',
  defaultValue: 380,
);

const int _maxLogsPerSecond =
    _configuredLogsPerSecond <= 0 ? 24 : _configuredLogsPerSecond;
const int _maxLogChars = _configuredMaxChars <= 0 ? 380 : _configuredMaxChars;

int _windowStartedAtMs = 0;
int _printedInWindow = 0;
int _suppressedInWindow = 0;

void appLog(Object? message) {
  if (!kDebugMode) {
    return;
  }

  final nowMs = DateTime.now().millisecondsSinceEpoch;
  _rotateWindowIfNeeded(nowMs);

  final text = _normalizeMessage(message);
  final critical = _isCriticalMessage(text);

  if (!_verboseLogs && !critical && _printedInWindow >= _maxLogsPerSecond) {
    _suppressedInWindow += 1;
    return;
  }

  _printedInWindow += 1;
  debugPrint(text);
}

void appLogLazy(String Function() messageBuilder) {
  if (!kDebugMode) {
    return;
  }
  appLog(messageBuilder());
}

void _rotateWindowIfNeeded(int nowMs) {
  if (_windowStartedAtMs == 0) {
    _windowStartedAtMs = nowMs;
    return;
  }
  if (nowMs - _windowStartedAtMs < 1000) {
    return;
  }

  if (_suppressedInWindow > 0) {
    debugPrint(
      '[appLog] $_suppressedInWindow개 로그를 생략했습니다. '
      '--dart-define=MUSCLECARE_VERBOSE_LOGS=true 로 전체 로그를 볼 수 있습니다.',
    );
  }

  _windowStartedAtMs = nowMs;
  _printedInWindow = 0;
  _suppressedInWindow = 0;
}

String _normalizeMessage(Object? message) {
  final raw = message?.toString() ?? 'null';
  final normalized = raw.replaceAll('\r', '').trimRight();
  if (normalized.length <= _maxLogChars) {
    return normalized;
  }
  return '${normalized.substring(0, _maxLogChars)}…';
}

bool _isCriticalMessage(String text) {
  final lower = text.toLowerCase();
  return text.contains('❌') ||
      text.contains('⚠️') ||
      lower.contains('error') ||
      lower.contains('exception') ||
      lower.contains('fail') ||
      lower.contains('실패') ||
      lower.contains('오류');
}
