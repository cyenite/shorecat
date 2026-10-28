import 'package:flutter/widgets.dart';

import '../../ui/card.dart';
import '../../ui/chart.dart';
import '../../ui/data_table.dart';
import '../../ui/pie_chart.dart';
import '../../ui/progress.dart';
import '../../ui/theme.dart';
import '../format.dart';
import '../models.dart';
import '../session.dart';
import '../widgets/common.dart';

typedef _Share = ({String name, int devices});

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final metrics = session.metrics;
    final app = session.app;
    if (metrics == null || app == null) return const LoadingPage();
    final active = metrics.activeDevices;
    final newest = {
      for (final r in app.releases)
        r.version: r.patches
            .where((p) => p.status == PatchStatus.active)
            .fold<int?>(
              null,
              (n, p) => n == null || p.number > n ? p.number : n,
            ),
    };
    final onNewest = metrics.adoption
        .where((a) => a.patch != null && a.patch == newest[a.release])
        .fold(0, (n, a) => n + a.devices);
    final byRelease = <String, int>{};
    for (final a in metrics.adoption) {
      byRelease[a.release] = (byRelease[a.release] ?? 0) + a.devices;
    }
    return PageBody(
      children: [
        ResponsiveGrid(
          maxColumns: 3,
          children: [
            StatCard(
              label: 'Active devices',
              value: compact(active),
              tag: session.window.label,
              note: 'Checked in or launched in this window',
            ),
            StatCard(
              label: 'On the newest live patch',
              value: active == 0
                  ? 'n/a'
                  : percent(onNewest / active, digits: 0),
              note: '$onNewest of $active active devices',
            ),
            StatCard(
              label: 'Devices ever seen',
              value: compact(metrics.knownDevices),
              note:
                  '${metrics.adoption.length} release and patch combinations live',
            ),
          ],
        ),
        ResponsiveGrid(
          minWidth: 360,
          maxColumns: 2,
          children: [
            _ShareCard(
              title: 'Architectures',
              description: 'Which CPU each device runs',
              shares: [
                for (final e in metrics.archs.entries)
                  (name: e.key, devices: e.value),
              ],
            ),
            _ShareCard(
              title: 'Releases',
              description: 'Store versions still in use',
              shares: [
                for (final e in byRelease.entries)
                  (name: e.key, devices: e.value),
              ],
            ),
          ],
        ),
        _AdoptionTable(metrics: metrics),
      ],
    );
  }
}

class _ShareCard extends StatelessWidget {
  final String title;
  final String description;
  final List<_Share> shares;

  const _ShareCard({
    required this.title,
    required this.description,
    required this.shares,
  });

  @override
  Widget build(BuildContext context) => Card(
    children: [
      CardHeader(title: Text(title), description: Text(description)),
      CardContent(
        child: shares.isEmpty
            ? const SizedBox(height: 200)
            : Center(
                child: PieChart<_Share>(
                  size: 220,
                  semanticLabel: title,
                  data: shares,
                  children: [
                    Pie(
                      value: (s) => s.devices,
                      name: (s) => s.name,
                      paddingAngle: 1,
                    ),
                    ChartTooltip(),
                    ChartLegend(),
                  ],
                ),
              ),
      ),
    ],
  );
}

class _AdoptionTable extends StatelessWidget {
  final Metrics metrics;

  const _AdoptionTable({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final total = metrics.activeDevices == 0 ? 1 : metrics.activeDevices;
    return Card(
      children: [
        const CardHeader(
          title: Text('What is running where'),
          description: Text('Active devices by release and patch'),
        ),
        CardContent(
          child: DataTable(
            columns: const [
              DataColumn(Text('Release')),
              DataColumn(Text('Patch')),
              DataColumn(Text('Devices'), numeric: true),
              DataColumn(Text('Share'), flex: 3),
            ],
            rows: [
              for (final a in metrics.adoption)
                [
                  Text(
                    a.release,
                    style: t.text.sm.copyWith(fontWeight: FontWeight.w500),
                  ),
                  Text(a.patch == null ? 'base release' : '#${a.patch}'),
                  Text(compact(a.devices)),
                  Row(
                    children: [
                      Expanded(child: Progress(value: a.devices / total)),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 48,
                        child: Text(percent(a.devices / total, digits: 0)),
                      ),
                    ],
                  ),
                ],
            ],
          ),
        ),
      ],
    );
  }
}
