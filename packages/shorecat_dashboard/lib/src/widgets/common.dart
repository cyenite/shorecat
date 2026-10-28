import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';

import '../../ui/badge.dart';
import '../../ui/card.dart';
import '../../ui/empty.dart';
import '../../ui/skeleton.dart';
import '../../ui/sparkline.dart';
import '../../ui/theme.dart';
import '../models.dart';

/// Lays children out in equal columns, as many as fit, the way the
/// shop-dashboard block lays out its figures.
class ResponsiveGrid extends StatelessWidget {
  final double minWidth;
  final int maxColumns;
  final List<Widget> children;

  const ResponsiveGrid({
    super.key,
    this.minWidth = 240,
    this.maxColumns = 4,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      const gap = 16.0;
      final fit = ((box.maxWidth + gap) / (minWidth + gap)).floor().clamp(
        1,
        maxColumns,
      );
      final width = (box.maxWidth - gap * (fit - 1)) / fit;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

/// Scrolling page body with the dashboard's padding.
class PageBody extends StatelessWidget {
  final List<Widget> children;

  const PageBody({super.key, required this.children});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const SizedBox(height: 24),
          child,
        ],
      ],
    ),
  );
}

/// One figure with its trend, as a card.
class StatCard extends StatelessWidget {
  final bool isGood;
  final String label;
  final String value;
  final String note;
  final String? tag;
  final List<num> trend;

  const StatCard({
    super.key,
    this.isGood = true,
    required this.label,
    required this.value,
    required this.note,
    this.tag,
    this.trend = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Card(
      children: [
        CardHeader(
          description: Text(label),
          title: Text(value, style: t.text.xxl),
          action: tag == null
              ? null
              : Badge(
                  variant: isGood
                      ? BadgeVariant.outline
                      : BadgeVariant.destructive,
                  child: Text(tag!),
                ),
        ),
        CardFooter(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (trend.length > 1)
                    Sparkline(
                      values: trend,
                      kind: SparkKind.area,
                      height: 36,
                      color: isGood ? c.primary : c.destructive,
                      semanticLabel: '$label trend',
                    ),
                  const SizedBox(height: 8),
                  Text(
                    note,
                    style: t.text.sm.copyWith(color: c.mutedForeground),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class StatusBadge extends StatelessWidget {
  final PatchStatus status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) => Badge(
    variant: switch (status) {
      PatchStatus.active => BadgeVariant.primary,
      PatchStatus.rolledBack => BadgeVariant.destructive,
      PatchStatus.paused || PatchStatus.draft => BadgeVariant.secondary,
    },
    leading: AshlarIcon(switch (status) {
      PatchStatus.active => AshlarIconsRoundedStroke.radioTower,
      PatchStatus.paused => AshlarIconsRoundedStroke.circlePause,
      PatchStatus.rolledBack => AshlarIconsRoundedStroke.undo2,
      PatchStatus.draft => AshlarIconsRoundedStroke.fileClock,
    }),
    child: Text(status.label),
  );
}

class EventBadge extends StatelessWidget {
  final EventKind? kind;

  const EventBadge({super.key, required this.kind});

  @override
  Widget build(BuildContext context) {
    final kind = this.kind;
    return Badge(
      variant: kind == null
          ? BadgeVariant.ghost
          : kind.isFailure
          ? BadgeVariant.destructive
          : kind == EventKind.launchSuccess
          ? BadgeVariant.primary
          : BadgeVariant.outline,
      leading: AshlarIcon(switch (kind) {
        EventKind.check => AshlarIconsRoundedStroke.search,
        EventKind.download => AshlarIconsRoundedStroke.download,
        EventKind.installSuccess => AshlarIconsRoundedStroke.package,
        EventKind.launchSuccess => AshlarIconsRoundedStroke.rocket,
        EventKind.uninstall => AshlarIconsRoundedStroke.undo2,
        EventKind.installFailure ||
        EventKind.bootFailure => AshlarIconsRoundedStroke.siren,
        null => AshlarIconsRoundedStroke.circleAlert,
      }),
      child: Text(kind?.label ?? 'Unknown'),
    );
  }
}

/// Placeholder cards while the first load is on its way.
class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key});

  @override
  Widget build(BuildContext context) => PageBody(
    children: [
      ResponsiveGrid(
        children: [for (var i = 0; i < 4; i++) const Skeleton(height: 132)],
      ),
      const Skeleton(height: 320),
    ],
  );
}

class NothingYet extends StatelessWidget {
  final String title;
  final String description;

  const NothingYet({super.key, required this.title, required this.description});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Empty(
      icon: const AshlarIcon(AshlarIconsRoundedStroke.cat),
      title: Text(title),
      description: Text(description),
      border: true,
    ),
  );
}
