import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';

import '../../ui/badge.dart';
import '../../ui/button.dart';
import '../../ui/card.dart';
import '../../ui/item.dart';
import '../../ui/label.dart';
import '../../ui/slider.dart';
import '../../ui/switch.dart';
import '../../ui/theme.dart';
import '../../ui/toast.dart';
import '../format.dart';
import '../models.dart';
import '../session.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = SessionScope.of(context).app;
    if (app == null) return const LoadingPage();
    return PageBody(
      children: [
        _HealthGateCard(key: ValueKey(app.id), gate: app.healthGate),
        _KeysCard(app: app),
      ],
    );
  }
}

class _HealthGateCard extends StatefulWidget {
  final HealthGate gate;

  const _HealthGateCard({super.key, required this.gate});

  @override
  State<_HealthGateCard> createState() => _HealthGateCardState();
}

class _HealthGateCardState extends State<_HealthGateCard> {
  bool isSaving = false;
  late bool isEnabled = widget.gate.isEnabled;
  late double minLaunches = widget.gate.minLaunches.toDouble();
  late double maxFailureRate = widget.gate.maxFailureRate;

  Future<void> _save() async {
    setState(() => isSaving = true);
    try {
      await SessionScope.of(context).updateApp({
        'health_gate': HealthGate(
          minLaunches: minLaunches.round(),
          isEnabled: isEnabled,
          maxFailureRate: maxFailureRate,
        ).toJson(),
      });
      if (mounted) {
        showToast(context, title: 'Health gate saved', type: ToastType.success);
      }
    } on Object catch (e) {
      if (mounted) {
        showToast(
          context,
          title: 'Could not save',
          description: '$e',
          type: ToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Card(
      children: [
        CardHeader(
          title: const Text('Health gate'),
          description: const Text(
            'Rolls a patch back for every device once too many of its launches crash.',
          ),
          action: Switch(
            value: isEnabled,
            semanticLabel: 'Health gate on',
            onChanged: (v) => setState(() => isEnabled = v),
          ),
        ),
        CardContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Label(
                child: Text(
                  'Roll back above ${percent(maxFailureRate, digits: 0)} boot failures',
                ),
              ),
              const SizedBox(height: 8),
              Slider(
                value: maxFailureRate,
                min: .01,
                max: .5,
                step: .01,
                length: 360,
                semanticLabel: 'Maximum boot failure rate',
                onChanged: isEnabled
                    ? (v) => setState(() => maxFailureRate = v)
                    : null,
              ),
              const SizedBox(height: 20),
              Label(
                child: Text(
                  'Once at least ${minLaunches.round()} launches are reported',
                ),
              ),
              const SizedBox(height: 8),
              Slider(
                value: minLaunches,
                min: 5,
                max: 500,
                step: 5,
                length: 360,
                semanticLabel: 'Minimum launches',
                onChanged: isEnabled
                    ? (v) => setState(() => minLaunches = v)
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                'Devices already roll a crashing patch back on their own. The gate stops '
                'the rest of the litter from installing it.',
                style: t.text.sm.copyWith(color: c.mutedForeground),
              ),
            ],
          ),
        ),
        CardFooter(
          alignment: MainAxisAlignment.end,
          children: [
            Button(
              onPressed: isSaving ? null : _save,
              child: Text(isSaving ? 'Saving...' : 'Save'),
            ),
          ],
        ),
      ],
    );
  }
}

class _KeysCard extends StatelessWidget {
  final AppDetail app;

  const _KeysCard({required this.app});

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Card(
      children: [
        const CardHeader(
          title: Text('Signing keys'),
          description: Text(
            'Ed25519 keys whose signatures the server accepts. Rotate with "shorecat keys rotate".',
          ),
        ),
        CardContent(
          child: Column(
            children: [
              for (final (i, key) in app.publicKeys.indexed)
                Item(
                  leading: const AshlarIcon(AshlarIconsRoundedStroke.keyRound),
                  title: Text(
                    key.length > 36 ? '${key.substring(0, 36)}...' : key,
                    style: t.text.sm.copyWith(fontFamily: 'monospace'),
                  ),
                  description: Text(
                    i == 0 ? 'Registered first' : 'Added by rotation',
                  ),
                  trailing: const Badge(
                    variant: BadgeVariant.outline,
                    leading: AshlarIcon(AshlarIconsRoundedStroke.shieldCheck),
                    child: Text('Trusted'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
