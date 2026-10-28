import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';

import '../../ui/alert_dialog.dart';
import '../../ui/badge.dart';
import '../../ui/button.dart';
import '../../ui/card.dart';
import '../../ui/data_table.dart';
import '../../ui/dialog.dart';
import '../../ui/dropdown_menu.dart';
import '../../ui/chart.dart';
import '../../ui/item.dart';
import '../../ui/progress.dart';
import '../../ui/select.dart';
import '../../ui/sheet.dart';
import '../../ui/slider.dart';
import '../../ui/theme.dart';
import '../../ui/toast.dart';
import '../format.dart';
import '../models.dart';
import '../session.dart';
import '../widgets/common.dart';

class PatchesScreen extends StatelessWidget {
  const PatchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = SessionScope.of(context).app;
    if (app == null) return const LoadingPage();
    if (app.releases.isEmpty) {
      return const NothingYet(
        title: 'No releases yet',
        description: 'Run "shorecat release android" to register one.',
      );
    }
    return PageBody(
      children: [
        for (final release in app.releases.reversed)
          _ReleaseCard(release: release),
      ],
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  final Release release;

  const _ReleaseCard({required this.release});

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final patches = release.patches.reversed.toList();
    return Card(
      children: [
        CardHeader(
          title: Text('Release ${release.version}'),
          description: Text(
            '${release.platform}, ${release.artifactSizes.keys.join(', ')}'
            '${release.flutterVersion == null ? '' : ', Flutter ${release.flutterVersion}'}',
          ),
          action: Badge(
            variant: BadgeVariant.outline,
            child: Text(
              '${patches.length} patch${patches.length == 1 ? '' : 'es'}',
            ),
          ),
        ),
        CardContent(
          child: patches.isEmpty
              ? Text(
                  'No patches yet. Fix some Dart, then "shorecat patch android".',
                  style: t.text.sm.copyWith(color: c.mutedForeground),
                )
              : LayoutBuilder(
                  builder: (context, box) {
                    final isWide = box.maxWidth >= 720;
                    return DataTable(
                      onRowPressed: (i) =>
                          _showPatch(context, release, patches[i]),
                      columns: [
                        const DataColumn(Text('Patch')),
                        const DataColumn(Text('Status'), flex: 2),
                        if (isWide) const DataColumn(Text('Channel')),
                        const DataColumn(Text('Rollout'), flex: 2),
                        const DataColumn(Text('Installs'), numeric: true),
                        if (isWide)
                          const DataColumn(Text('Launches'), numeric: true),
                        const DataColumn(Text('Crashes'), numeric: true),
                        if (isWide)
                          const DataColumn(Text('Size'), numeric: true),
                        const DataColumn(Text('')),
                      ],
                      rows: [
                        for (final patch in patches)
                          [
                            Row(
                              children: [
                                Text(
                                  '#${patch.number}',
                                  style: t.text.sm.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (patch.isCritical) ...[
                                  const SizedBox(width: 6),
                                  const AshlarIcon(
                                    AshlarIconsRoundedStroke.flame,
                                    size: 14,
                                  ),
                                ],
                              ],
                            ),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: StatusBadge(status: patch.status),
                            ),
                            if (isWide) Text(patch.channel),
                            Row(
                              children: [
                                Expanded(
                                  child: Progress(
                                    value: patch.rolloutPercentage / 100,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('${patch.rolloutPercentage.round()}%'),
                              ],
                            ),
                            Text(compact(patch.stat(EventKind.installSuccess))),
                            if (isWide)
                              Text(
                                compact(patch.stat(EventKind.launchSuccess)),
                              ),
                            Text(
                              patch.launches == 0
                                  ? 'n/a'
                                  : percent(patch.failureRate),
                              style: patch.failureRate > .02
                                  ? t.text.sm.copyWith(color: c.destructive)
                                  : null,
                            ),
                            if (isWide) Text(_smallest(patch)),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: _PatchMenu(release: release, patch: patch),
                            ),
                          ],
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  static String _smallest(Patch patch) {
    if (patch.artifacts.isEmpty) return '-';
    final sizes = patch.artifacts.map((a) => a.deltaSize).toList()..sort();
    return bytes(sizes.first);
  }
}

void _showPatch(BuildContext context, Release release, Patch patch) =>
    showSheet<void>(
      context: context,
      builder: (_) => Sheet(
        width: 440,
        title: Text('Patch #${patch.number} for ${release.version}'),
        description: Text(patch.notes ?? 'No release notes'),
        content: _PatchDetail(patch: patch),
      ),
    );

typedef _Step = ({String name, int value});

class _PatchDetail extends StatelessWidget {
  final Patch patch;

  const _PatchDetail({required this.patch});

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final steps = <_Step>[
      (name: 'Downloads', value: patch.stat(EventKind.download)),
      (name: 'Installs', value: patch.stat(EventKind.installSuccess)),
      (name: 'Launches', value: patch.stat(EventKind.launchSuccess)),
      (name: 'Crashes', value: patch.stat(EventKind.bootFailure)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            StatusBadge(status: patch.status),
            const SizedBox(width: 8),
            Badge(variant: BadgeVariant.outline, child: Text(patch.channel)),
            const SizedBox(width: 8),
            Badge(
              variant: BadgeVariant.outline,
              child: Text('${patch.rolloutPercentage.round()}% rollout'),
            ),
          ],
        ),
        if (patch.statusReason != null) ...[
          const SizedBox(height: 12),
          Text(
            patch.statusReason!,
            style: t.text.sm.copyWith(color: c.mutedForeground),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          'Reports',
          style: t.text.sm.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (steps.every((s) => s.value == 0))
          Text(
            'No device has picked it up yet.',
            style: t.text.sm.copyWith(color: c.mutedForeground),
          )
        else
          BarChart<_Step>(
            height: 180,
            semanticLabel: 'Patch events',
            data: steps,
            x: (s) => s.name,
            children: [
              CartesianGrid(),
              XAxis(),
              ChartTooltip(),
              Bar(
                label: 'Reports',
                value: (s) => s.value,
                labels: [ChartLabels(position: ChartLabelPosition.top)],
              ),
            ],
          ),
        const SizedBox(height: 20),
        Text('Health', style: t.text.sm.copyWith(fontWeight: FontWeight.w600)),
        Item(
          leading: const AshlarIcon(AshlarIconsRoundedStroke.heartPulse),
          title: Text('${patch.launches} launches reported'),
          description: Text(
            '${patch.stat(EventKind.bootFailure)} boot failures (${percent(patch.failureRate)}), '
            '${patch.stat(EventKind.installFailure)} install failures',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Artifacts',
          style: t.text.sm.copyWith(fontWeight: FontWeight.w600),
        ),
        for (final a in patch.artifacts)
          Item(
            leading: const AshlarIcon(AshlarIconsRoundedStroke.cpu),
            title: Text('${a.arch}, ${bytes(a.deltaSize)} delta'),
            description: Text(
              'sha256 ${a.hash.substring(0, 16)}...',
              style: t.text.xs,
            ),
          ),
      ],
    );
  }
}

class _PatchMenu extends StatelessWidget {
  final Release release;
  final Patch patch;

  const _PatchMenu({required this.release, required this.patch});

  Future<void> _apply(BuildContext context, Json change, String done) async {
    final session = SessionScope.of(context);
    try {
      await session.updatePatch(release, patch, change);
      if (context.mounted) {
        showToast(context, title: done, type: ToastType.success);
      }
    } on Object catch (e) {
      if (context.mounted) {
        showToast(
          context,
          title: 'Could not update the patch',
          description: '$e',
          type: ToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (patch.status == PatchStatus.draft) return const SizedBox.shrink();
    final isLive = patch.status == PatchStatus.active;
    return DropdownMenu(
      width: 220,
      builder: (context, menu) => Button(
        variant: ButtonVariant.ghost,
        size: ButtonSize.icon,
        semanticLabel: 'Actions for patch ${patch.number}',
        onPressed: menu.open,
        child: const AshlarIcon(AshlarIconsRoundedStroke.ellipsis),
      ),
      items: [
        MenuItem(
          leading: const AshlarIcon(AshlarIconsRoundedStroke.gauge),
          onPressed: () async {
            final value = await showAshlarDialog<double>(
              context: context,
              builder: (_) => _RolloutDialog(patch: patch),
            );
            if (value != null && context.mounted) {
              await _apply(context, {
                'rollout_percentage': value,
              }, 'Rollout set to ${value.round()}%');
            }
          },
          child: const Text('Change rollout'),
        ),
        MenuItem(
          leading: const AshlarIcon(AshlarIconsRoundedStroke.gitBranch),
          onPressed: () async {
            final channel = await showAshlarDialog<String>(
              context: context,
              builder: (_) => _ChannelDialog(patch: patch),
            );
            if (channel != null && context.mounted) {
              await _apply(context, {'channel': channel}, 'Moved to $channel');
            }
          },
          child: const Text('Move to channel'),
        ),
        MenuItem(
          leading: const AshlarIcon(AshlarIconsRoundedStroke.flame),
          onPressed: () => _apply(context, {
            'is_critical': !patch.isCritical,
          }, patch.isCritical ? 'No longer critical' : 'Marked critical'),
          child: Text(patch.isCritical ? 'Unmark critical' : 'Mark critical'),
        ),
        MenuItem(
          leading: AshlarIcon(
            isLive
                ? AshlarIconsRoundedStroke.circlePause
                : AshlarIconsRoundedStroke.circlePlay,
          ),
          onPressed: () => _apply(context, {
            'status': isLive ? 'paused' : 'active',
          }, isLive ? 'Paused: no new installs' : 'Live again'),
          child: Text(isLive ? 'Pause' : 'Resume'),
        ),
        if (patch.status != PatchStatus.rolledBack) ...[
          const MenuSeparator(),
          MenuItem(
            leading: const AshlarIcon(AshlarIconsRoundedStroke.undo2),
            onPressed: () async {
              final isSure = await showAlertDialog(
                context,
                title: 'Roll back patch #${patch.number}?',
                description:
                    'Every device running it uninstalls it at its next check and goes back to '
                    'the newest patch still live, or the release itself.',
                action: 'Roll back',
                destructive: true,
              );
              if (isSure && context.mounted) {
                await _apply(context, {
                  'status': 'rolled_back',
                  'reason': 'Rolled back from the dashboard',
                }, 'Patch rolled back');
              }
            },
            child: const Text('Roll back'),
          ),
        ],
      ],
    );
  }
}

class _RolloutDialog extends StatefulWidget {
  final Patch patch;

  const _RolloutDialog({required this.patch});

  @override
  State<_RolloutDialog> createState() => _RolloutDialogState();
}

class _RolloutDialogState extends State<_RolloutDialog> {
  late double value = widget.patch.rolloutPercentage;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Dialog(
      title: Text('Roll out patch #${widget.patch.number}'),
      description: const Text(
        'Devices keep their place as the share grows: raising it only adds devices.',
      ),
      content: Row(
        children: [
          Expanded(
            child: Slider(
              value: value,
              min: 0,
              max: 100,
              step: 5,
              length: 320,
              semanticLabel: 'Rollout percentage',
              onChanged: (v) => setState(() => value = v),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 48,
            child: Text('${value.round()}%', style: t.text.lg),
          ),
        ],
      ),
      actions: [
        Button(
          variant: ButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        Button(
          onPressed: () => Navigator.of(context).pop(value),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ChannelDialog extends StatefulWidget {
  final Patch patch;

  const _ChannelDialog({required this.patch});

  @override
  State<_ChannelDialog> createState() => _ChannelDialogState();
}

class _ChannelDialogState extends State<_ChannelDialog> {
  late String channel = widget.patch.channel;

  static const channels = ['stable', 'beta', 'staging', 'dev'];

  @override
  Widget build(BuildContext context) => Dialog(
    title: Text('Move patch #${widget.patch.number}'),
    description: const Text(
      'Only devices on the chosen channel will be offered it.',
    ),
    content: Select<String>(
      value: channel,
      semanticLabel: 'Channel',
      options: [
        for (final c in {...channels, widget.patch.channel}) SelectOption(c, c),
      ],
      onChanged: (v) => setState(() => channel = v),
    ),
    actions: [
      Button(
        variant: ButtonVariant.outline,
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      Button(
        onPressed: () => Navigator.of(context).pop(channel),
        child: const Text('Move'),
      ),
    ],
  );
}
