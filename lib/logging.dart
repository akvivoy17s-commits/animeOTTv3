import 'dart:developer' as developer;

import 'package:logging/logging.dart';

/// Routes package logs through the platform's developer logging facilities.
void configureLogging() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord record) {
    developer.log(
      record.message,
      name: record.loggerName,
      level: record.level.value,
      error: record.error,
      stackTrace: record.stackTrace,
    );
  });
}
