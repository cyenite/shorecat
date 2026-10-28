import 'dart:io';

abstract final class Log {
  static final bool _isAnsi = stdout.hasTerminal && stdout.supportsAnsiEscapes;

  static String _paint(String code, String text) =>
      _isAnsi ? '\x1B[${code}m$text\x1B[0m' : text;

  static void info(String message) => stdout.writeln(message);

  static void step(String message) => stdout.writeln(_paint('1', '> $message'));

  static void detail(String message) =>
      stdout.writeln(_paint('2', '  $message'));

  static void success(String message) => stdout.writeln(_paint('32', message));

  static void warn(String message) =>
      stderr.writeln(_paint('33', 'warning: $message'));

  static void error(String message) =>
      stderr.writeln(_paint('31', 'error: $message'));
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MiB';
}
