import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:shorecat_core/shorecat_core.dart';
import 'package:yaml/yaml.dart';

import 'config.dart';

enum ArtifactType {
  aab('aab', 'appbundle'),
  apk('apk', 'apk');

  final String wireName;
  final String buildCommand;

  const ArtifactType(this.wireName, this.buildCommand);

  static ArtifactType parse(String value) => values.firstWhere(
    (t) => t.wireName == value,
    orElse: () => throw CliException('Unknown artifact type "$value"'),
  );
}

/// What changed outside `libapp.so` between a release and a patch build.
/// Declaration order is severity order for reporting.
enum ChangeKind {
  android('Java/Kotlin code, resources or AndroidManifest'),
  native('Native libraries'),
  assets('Flutter assets'),
  other('Other packaged files');

  final String label;

  const ChangeKind(this.label);

  static ChangeKind of(String path) {
    if (path.startsWith('assets/flutter_assets/')) return assets;
    if (path.startsWith('lib/')) return native;
    if (path.endsWith('.dex') ||
        path.startsWith('dex/') ||
        path.startsWith('res/') ||
        path.startsWith('manifest/') ||
        path == 'AndroidManifest.xml' ||
        path == 'resources.arsc' ||
        path == 'resources.pb') {
      return android;
    }
    return other;
  }
}

class FlutterVersion {
  final String engine;
  final String framework;
  final String version;

  const FlutterVersion({
    required this.engine,
    required this.framework,
    required this.version,
  });

  static Future<FlutterVersion> detect() async {
    final result = await Process.run('flutter', [
      '--version',
      '--machine',
    ], runInShell: true);
    if (result.exitCode != 0) {
      throw CliException('Could not run "flutter --version": ${result.stderr}');
    }
    final text = '${result.stdout}';
    final json = jsonDecode(text.substring(text.indexOf('{'))) as Map;
    return FlutterVersion(
      engine: json['engineRevision'] as String,
      framework: json['frameworkRevision'] as String,
      version: json['frameworkVersion'] as String,
    );
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'framework_revision': framework,
    'engine_revision': engine,
  };

  @override
  String toString() => '$version (engine ${engine.substring(0, 10)})';
}

class AndroidBuild {
  final File archive;
  final ArtifactType type;
  final Map<Arch, Uint8List> libraries;
  final Map<String, int> fingerprint;

  const AndroidBuild({
    required this.archive,
    required this.type,
    required this.libraries,
    required this.fingerprint,
  });

  static Future<AndroidBuild> run({
    required Directory project,
    required ArtifactType type,
    String? flavor,
    String? target,
    List<String> extraArgs = const [],
  }) async {
    final args = [
      'build',
      type.buildCommand,
      '--release',
      if (flavor != null) ...['--flavor', flavor],
      if (target != null) ...['--target', target],
      ...extraArgs,
    ];
    stdout.writeln('\$ flutter ${args.join(' ')}');
    final process = await Process.start(
      'flutter',
      args,
      workingDirectory: project.path,
      runInShell: true,
      mode: ProcessStartMode.inheritStdio,
    );
    if (await process.exitCode != 0) {
      throw CliException('flutter build ${type.buildCommand} failed');
    }
    return read(_output(project, type, flavor), type);
  }

  static AndroidBuild read(File archive, ArtifactType type) {
    final input = InputFileStream(archive.path);
    try {
      final zip = ZipDecoder().decodeStream(input);
      final libraries = <Arch, Uint8List>{};
      final fingerprint = <String, int>{};
      for (final file in zip) {
        if (!file.isFile) continue;
        final path = type == ArtifactType.aab && file.name.startsWith('base/')
            ? file.name.substring(5)
            : file.name;
        final library = RegExp(r'^lib/([^/]+)/libapp\.so$').firstMatch(path);
        if (library != null) {
          final arch = Arch.fromAndroidAbi(library.group(1)!);
          if (arch != null) libraries[arch] = Uint8List.fromList(file.content);
          continue;
        }
        if (_isBuildNoise(path)) continue;
        fingerprint[path] = file.crc32 ?? sha256Hex(file.content).hashCode;
      }
      if (libraries.isEmpty) {
        throw CliException('No libapp.so found in ${archive.path}');
      }
      return AndroidBuild(
        archive: archive,
        type: type,
        libraries: libraries,
        fingerprint: fingerprint,
      );
    } finally {
      input.closeSync();
    }
  }

  /// Files that differ between byte-identical builds and say nothing about
  /// whether the patch is safe.
  static bool _isBuildNoise(String path) =>
      path.startsWith('META-INF/') ||
      path.startsWith('BUNDLE-METADATA/') ||
      path == 'BundleConfig.pb' ||
      path == 'stamp-cert-sha256';

  static Map<ChangeKind, List<String>> compare(
    Map<String, int> release,
    Map<String, int> patch,
  ) {
    final changes = <ChangeKind, List<String>>{};
    void add(String path, String what) =>
        (changes[ChangeKind.of(path)] ??= []).add('$what $path');
    for (final e in patch.entries) {
      final old = release[e.key];
      if (old == null) {
        add(e.key, 'added');
      } else if (old != e.value) {
        add(e.key, 'changed');
      }
    }
    for (final path in release.keys) {
      if (!patch.containsKey(path)) add(path, 'removed');
    }
    return changes;
  }

  static File _output(Directory project, ArtifactType type, String? flavor) {
    final outputs = p.join(project.path, 'build', 'app', 'outputs');
    final path = switch (type) {
      ArtifactType.aab => p.join(
        outputs,
        'bundle',
        flavor == null ? 'release' : '${flavor}Release',
        'app${flavor == null ? '' : '-$flavor'}-release.aab',
      ),
      ArtifactType.apk => p.join(
        outputs,
        'flutter-apk',
        'app${flavor == null ? '' : '-$flavor'}-release.apk',
      ),
    };
    final file = File(path);
    if (!file.existsSync()) throw CliException('Build output missing: $path');
    return file;
  }
}

/// `version` from pubspec.yaml in the `name+code` form the device reports
/// (`versionName+versionCode`). Flutter defaults the code to 1.
String pubspecReleaseVersion(Directory project) {
  final file = File(p.join(project.path, 'pubspec.yaml'));
  if (!file.existsSync()) {
    throw CliException('No pubspec.yaml in ${project.path}');
  }
  final yaml = loadYaml(file.readAsStringSync()) as YamlMap;
  final version = yaml['version'] as String?;
  if (version == null) throw CliException('pubspec.yaml has no version');
  return version.contains('+') ? version : '$version+1';
}
