import 'package:flutter/material.dart';
import 'package:shorecat_code_push/shorecat_code_push.dart';

// Edit these two and run "shorecat patch android" to see code push work.
const buildLabel = 'Release build';
const accent = Color(0xFF0F766E);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Shorecat.initialize();
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'shorecat demo',
    theme: ThemeData(colorSchemeSeed: accent, useMaterial3: true),
    home: const StatusPage(),
  );
}

class StatusPage extends StatefulWidget {
  const StatusPage({super.key});

  @override
  State<StatusPage> createState() => _StatusPageState();
}

class _StatusPageState extends State<StatusPage> {
  bool isBusy = false;
  String? message;

  Shorecat? get shorecat => Shorecat.instance;

  Future<void> checkNow() async {
    final shorecat = this.shorecat;
    if (shorecat == null) return;
    setState(() => isBusy = true);
    final result = await shorecat.update();
    setState(() {
      isBusy = false;
      message = '$result';
    });
  }

  @override
  Widget build(BuildContext context) {
    final shorecat = this.shorecat;
    return Scaffold(
      appBar: AppBar(title: const Text('shorecat demo')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          BuildBanner(label: buildLabel, color: accent),
          const SizedBox(height: 24),
          if (shorecat == null)
            const Text('Code push is off (debug build or not Android).')
          else ...[
            StatusRow(
              name: 'Running patch',
              value: '${shorecat.currentPatchNumber ?? 'base release'}',
            ),
            StatusRow(
              name: 'Next launch',
              value: '${shorecat.nextPatchNumber ?? 'base release'}',
            ),
            StatusRow(
              name: 'Boot hook',
              value: shorecat.isHooked ? 'active' : 'missing',
            ),
            if (shorecat.crashedPatchNumber != null)
              StatusRow(
                name: 'Rolled back',
                value: 'patch ${shorecat.crashedPatchNumber} crashed',
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: isBusy ? null : checkNow,
              child: Text(isBusy ? 'Checking...' : 'Check for update'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: shorecat.isRestartRequired ? shorecat.restart : null,
              child: const Text('Restart to apply'),
            ),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(message!, key: const Key('message')),
            ],
          ],
        ],
      ),
    );
  }
}

class BuildBanner extends StatelessWidget {
  final String label;
  final Color color;

  const BuildBanner({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      label,
      key: const Key('build-label'),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class StatusRow extends StatelessWidget {
  final String name;
  final String value;

  const StatusRow({super.key, required this.name, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(child: Text(name)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}
