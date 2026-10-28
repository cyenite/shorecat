import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';

import '../../ui/badge.dart';
import '../../ui/card.dart';
import '../../ui/chart.dart';
import '../../ui/funnel_chart.dart';
import '../../ui/heatmap.dart';
import '../../ui/item.dart';
import '../../ui/pie_chart.dart';
import '../../ui/theme.dart';
import '../format.dart';
import '../models.dart';
import '../session.dart';
import '../widgets/common.dart';

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final metrics = session.metrics;
    final app = session.app;
    if (session.appId == null) {
      return const NothingYet(
        title: 'No apps yet',
        description:
            'Run "shorecat init" in a Flutter project to register one.',
      );
    }
    if (metrics == null || app == null) return const LoadingPage();
    return PageBody(
      children: [
        _Figures(metrics: metrics, window: session.window),
        _Activity(metrics: metrics, window: session.window),
        ResponsiveGrid(
          minWidth: 360,
          maxColumns: 2,
          children: [
            _Adoption(metrics: metrics),
            _Funnel(app: app, metrics: metrics),
          ],
        ),
        ResponsiveGrid(
          minWidth: 360,
          maxColumns: 2,
          children: [
            _LaunchHeatmap(metrics: metrics),
            _Incidents(app: app),
          ],
        ),
      ],
    );
  }
}

class _Figures extends StatelessWidget {
  final Window window;
  final Metrics metrics;

  const _Figures({required this.window, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final series = metrics.series;
    List<num> trend(EventKind kind) => [for (final b in series) b[kind]];
    final crashFree = metrics.crashFreeRate;
    final failures = metrics[EventKind.bootFailure];
    return ResponsiveGrid(
      children: [
        StatCard(
          label: 'Active devices',
          value: compact(metrics.activeDevices),
          tag: window.label,
          note: '${compact(metrics.knownDevices)} devices seen in all',
          trend: trend(EventKind.check),
        ),
        StatCard(
          label: 'Patches installed',
          value: compact(metrics[EventKind.installSuccess]),
          tag: '${compact(metrics[EventKind.download])} downloads',
          note: '${metrics[EventKind.installFailure]} failed to install',
          trend: trend(EventKind.installSuccess),
        ),
        StatCard(
          label: 'Patched launches',
          value: compact(metrics[EventKind.launchSuccess]),
          tag: '${compact(metrics[EventKind.uninstall])} uninstalls',
          note: 'Launches that reached their first frame',
          trend: trend(EventKind.launchSuccess),
        ),
        StatCard(
          isGood: crashFree == null || crashFree >= .99,
          label: 'Crash-free boots',
          value: percent(crashFree, digits: 2),
          tag: failures == 0 ? 'Purring' : '$failures crashed',
          note: failures == 0
              ? 'No patch has fallen off the sofa'
              : 'Each one rolled itself back',
          trend: trend(EventKind.bootFailure),
        ),
      ],
    );
  }
}

typedef _Point = ({String when, int launches, int installs, int failures});

class _Activity extends StatelessWidget {
  final Window window;
  final Metrics metrics;

  const _Activity({required this.window, required this.metrics});

  /// Hourly buckets for a day, six-hour ones for a week, daily for a month.
  List<_Point> _points() {
    final per = switch (window) {
      Window.day => 1,
      Window.week => 6,
      Window.month => 24,
    };
    final points = <_Point>[];
    final series = metrics.series;
    for (var i = 0; i < series.length; i += per) {
      final chunk = series.sublist(i, (i + per).clamp(0, series.length));
      int sum(EventKind kind) => chunk.fold(0, (n, b) => n + b[kind]);
      final at = chunk.first.hour;
      points.add((
        when: window == Window.day
            ? shortTime(at)
            : window == Window.week
            ? '${weekdays[at.weekday - 1]} ${shortTime(at)}'
            : '${at.day}/${at.month}',
        launches: sum(EventKind.launchSuccess),
        installs: sum(EventKind.installSuccess),
        failures: sum(EventKind.bootFailure),
      ));
    }
    return points;
  }

  @override
  Widget build(BuildContext context) => Card(
    children: [
      CardHeader(
        title: const Text('Activity'),
        description: Text(switch (window) {
          Window.day => 'Launches, installs and crashes by the hour',
          Window.week => 'Every six hours this week',
          Window.month => 'By the day, last 30 days',
        }),
      ),
      CardContent(
        child: AreaChart<_Point>(
          height: 280,
          semanticLabel: 'Launches, installs and boot failures over time',
          data: _points(),
          x: (p) => p.when,
          children: [
            CartesianGrid(),
            XAxis(),
            YAxis(),
            ChartTooltip(indicator: ChartIndicator.dot),
            ChartLegend(),
            Area(label: 'Launches', value: (p) => p.launches),
            Area(label: 'Installs', value: (p) => p.installs),
            Area(
              label: 'Boot failures',
              value: (p) => p.failures,
              color: AshlarTheme.of(context).colors.destructive,
            ),
          ],
        ),
      ),
    ],
  );
}

class _Adoption extends StatelessWidget {
  final Metrics metrics;

  const _Adoption({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final rows = metrics.adoption.take(6).toList();
    return Card(
      children: [
        const CardHeader(
          title: Text('Patch adoption'),
          description: Text('What active devices are running'),
        ),
        CardContent(
          child: rows.isEmpty
              ? const _Quiet(text: 'No device has checked in yet.')
              : Center(
                  child: PieChart<Adoption>(
                    size: 240,
                    semanticLabel: 'Devices by patch',
                    data: rows,
                    center: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(compact(metrics.activeDevices), style: t.text.xxl),
                        Text(
                          'devices',
                          style: t.text.xs.copyWith(color: c.mutedForeground),
                        ),
                      ],
                    ),
                    children: [
                      Pie(
                        value: (a) => a.devices,
                        name: (a) => a.label,
                        innerRadius: .62,
                        paddingAngle: 2,
                        cornerRadius: 4,
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
}

typedef _Step = ({String name, int value});

/// Devices, not events: each step is a subset of the one before, which is
/// what makes it a funnel. Event counts are not (one install, many launches).
class _Funnel extends StatelessWidget {
  final AppDetail app;
  final Metrics metrics;

  const _Funnel({required this.app, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final newest = {
      for (final r in app.releases)
        r.version: r.patches
            .where((p) => p.status == PatchStatus.active)
            .fold<int?>(
              null,
              (n, p) => n == null || p.number > n ? p.number : n,
            ),
    };
    int sum(bool Function(Adoption a) test) =>
        metrics.adoption.where(test).fold(0, (n, a) => n + a.devices);
    final steps = <_Step>[
      (name: 'Active devices', value: metrics.activeDevices),
      (name: 'Running a patch', value: sum((a) => a.patch != null)),
      (
        name: 'On the newest live patch',
        value: sum((a) => a.patch != null && a.patch == newest[a.release]),
      ),
    ];
    return Card(
      children: [
        const CardHeader(
          title: Text('Update coverage'),
          description: Text('How much of the litter runs your latest fix'),
        ),
        CardContent(
          child: metrics.activeDevices == 0
              ? const _Quiet(text: 'No device has checked in in this window.')
              : FunnelChart<_Step>(
                  height: 260,
                  semanticLabel: 'Update coverage',
                  data: steps,
                  children: [
                    Funnel(
                      value: (s) => s.value,
                      name: (s) => s.name,
                      labels: [
                        ChartLabels(
                          position: ChartLabelPosition.inside,
                          text: (s, v) => '${s.name}: ${compact(v)}',
                        ),
                      ],
                    ),
                    ChartTooltip(),
                  ],
                ),
        ),
      ],
    );
  }
}

typedef _Cell = ({String day, int hour, int launches});

class _LaunchHeatmap extends StatelessWidget {
  final Metrics metrics;

  const _LaunchHeatmap({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final cells = <String, _Cell>{};
    for (final b in metrics.series) {
      final day = weekdays[b.hour.weekday - 1];
      final key = '$day ${b.hour.hour}';
      final old = cells[key];
      cells[key] = (
        day: day,
        hour: b.hour.hour,
        launches: (old?.launches ?? 0) + b[EventKind.launchSuccess],
      );
    }
    return Card(
      children: [
        const CardHeader(
          title: Text('When cats wake up'),
          description: Text('Patched launches by weekday and hour'),
        ),
        CardContent(
          child: Heatmap<_Cell>(
            semanticLabel: 'Launches by weekday and hour',
            data: cells.values.toList(),
            x: (c) => c.hour,
            y: (c) => c.day,
            value: (c) => c.launches,
            xLabels: [for (var h = 0; h < 24; h++) h],
            yLabels: weekdays,
            cellHeight: 18,
          ),
        ),
      ],
    );
  }
}

class _Incidents extends StatelessWidget {
  final AppDetail app;

  const _Incidents({required this.app});

  @override
  Widget build(BuildContext context) {
    final troubled = [
      for (final r in app.releases)
        for (final p in r.patches)
          if (p.status == PatchStatus.rolledBack ||
              p.status == PatchStatus.paused ||
              p.stat(EventKind.bootFailure) > 0)
            (release: r, patch: p),
    ].reversed.take(5).toList();
    return Card(
      children: [
        const CardHeader(
          title: Text('Hairballs'),
          description: Text('Patches that crashed, paused or were rolled back'),
        ),
        CardContent(
          child: troubled.isEmpty
              ? const _Quiet(
                  text: 'Nothing to cough up. Every patch landed on its feet.',
                )
              : Column(
                  children: [
                    for (final (:release, :patch) in troubled)
                      Item(
                        leading: AshlarIcon(
                          patch.status == PatchStatus.rolledBack
                              ? AshlarIconsRoundedStroke.undo2
                              : AshlarIconsRoundedStroke.triangleAlert,
                        ),
                        title: Text(
                          '${release.version} patch #${patch.number}',
                        ),
                        description: Text(
                          [
                            if (patch.stat(EventKind.bootFailure) > 0)
                              '${patch.stat(EventKind.bootFailure)} boot failures '
                                  '(${percent(patch.failureRate)} of launches)',
                            ?patch.statusReason,
                          ].join('. '),
                        ),
                        trailing: StatusBadge(status: patch.status),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Quiet extends StatelessWidget {
  final String text;

  const _Quiet({required this.text});

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return SizedBox(
      height: 160,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Badge(
              variant: BadgeVariant.ghost,
              child: AshlarIcon(AshlarIconsRoundedStroke.cat),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                style: t.text.sm.copyWith(color: t.colors.mutedForeground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
