/// The shorecat command line.
library;

import 'package:args/command_runner.dart';

import 'src/commands/manage.dart';
import 'src/commands/project.dart';
import 'src/commands/release.dart';
import 'src/commands/simulate.dart';
import 'src/commands/tools.dart';

export 'src/android_build.dart' show AndroidBuild, ArtifactType, ChangeKind;
export 'src/commands/project.dart' show addAsset;
export 'src/config.dart';

CommandRunner<int> shorecatRunner() =>
    CommandRunner<int>('shorecat', 'Code push for Flutter apps.')
      ..addCommand(InitCommand())
      ..addCommand(LoginCommand())
      ..addCommand(DoctorCommand())
      ..addCommand(ReleaseCommand())
      ..addCommand(PatchCommand())
      ..addCommand(ReleasesCommand())
      ..addCommand(PatchesCommand())
      ..addCommand(KeysCommand())
      ..addCommand(DiffCommand())
      ..addCommand(ApplyCommand())
      ..addCommand(InspectCommand())
      ..addCommand(ServerCommand())
      ..addCommand(SimulateCommand());
