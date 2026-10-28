import 'dart:io';

import 'package:args/args.dart';
import 'package:shorecat_server/shorecat_server.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()..addFlag('help', abbr: 'h', negatable: false);
  addServerOptions(parser);
  try {
    final args = parser.parse(arguments);
    if (args.flag('help')) {
      stdout.writeln('Usage: shorecat_server [options]\n\n${parser.usage}');
      return;
    }
    if (args.rest.isNotEmpty) {
      throw const FormatException('Unexpected positional arguments.');
    }
    exitCode = await runServer(args);
  } on FormatException catch (error) {
    stderr.writeln('error: ${error.message}');
    exitCode = 64;
  }
}
