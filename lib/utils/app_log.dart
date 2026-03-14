import 'package:flutter/foundation.dart';

void appLog(Object? message) {
  if (!kDebugMode) {
    return;
  }
  debugPrint(message?.toString());
}
