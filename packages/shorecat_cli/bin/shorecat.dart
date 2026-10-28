import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:shorecat_cli/shorecat_cli.dart';

Future<void> main(List<String> arguments) async {
  try {
    exitCode = await shorecatRunner().run(arguments) ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  } on CliException catch (e) {
    stderr.writeln('error: ${e.message}');
    exitCode = e.exitCode;
  }
}
