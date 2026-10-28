import 'dart:io';

import 'package:args/command_runner.dart';

import '../client.dart';
import '../config.dart';

abstract class ShorecatCommand extends Command<int> {
  Directory get project => Directory.current;

  UserConfig get user => UserConfig.standard();

  ProjectConfig get config => ProjectConfig.load(project);

  ShorecatClient get client => ShorecatClient.forProject(config, user);

  String? option(String name) => argResults!.option(name);

  bool flag(String name) => argResults!.flag(name);

  List<String> get rest => argResults!.rest;

  int intArg(String value, String what) =>
      int.tryParse(value) ??
      (throw UsageException('$what must be a number', usage));

  double percentArg(String value) {
    final n = double.tryParse(value);
    if (n == null || n < 0 || n > 100) {
      throw UsageException('Rollout must be a number from 0 to 100', usage);
    }
    return n;
  }
}
