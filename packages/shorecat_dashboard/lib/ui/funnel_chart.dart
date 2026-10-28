// Ashlar UI: Funnel chart. Copied into your app by `ashlar add funnel-chart`; it is yours
// to change.
// ashlar: ignore-file. Drawn top to bottom in any language.
//
// Steps that narrow, a row each: a funnel (each step as wide as its value, the way
// sign-ups thin out to payments) or a pyramid (each step's height its share of the
// whole).

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'chart.dart';
import 'theme.dart';

/// A funnel's steps: a trapezium per row, as wide as its value, narrowing to the next.
class Funnel<T> extends ChartPart<T> {
  const Funnel({
    required this.value,
    required this.name,
    this.colorOf,
    this.gap = 2,
    this.labels = const [],
    this.conversion = true,
  });

  final ChartValue<T> value;
  final String Function(T row) name;
  final Color? Function(T row)? colorOf;

  /// The gap between steps, in pixels.
  final double gap;

  /// Text on the steps: [ChartLabelPosition.inside] within them, [ChartLabelPosition.right]
  /// or [ChartLabelPosition.left] beside them.
  final List<ChartLabels<T>> labels;

  /// The tooltip says what share of the first step reached each one.
  final bool conversion;
}

/// A pyramid's steps: the first row at the point, each step as tall as its share of the
/// whole.
class Pyramid<T> extends Funnel<T> {
  const Pyramid({
    required super.value,
    required super.name,
    super.colorOf,
    super.gap,
    super.labels,
  }) : super(conversion: false);
}

/// Steps that narrow: put a [Funnel] or a [Pyramid] in it.
///
/// ```dart
/// FunnelChart<Stage>(
///   data: stages,
///   children: [
///     ChartTooltip(),
///     Funnel(
///       value: (r) => r.people,
///       name: (r) => r.stage,
///       labels: [ChartLabels(position: ChartLabelPosition.right, text: (r, _) => r.stage)],
///     ),
///   ],
/// )
/// ```
class FunnelChart<T> extends StatefulWidget {
  const FunnelChart({
    super.key,
    required this.data,
    required this.children,
    this.height = 280,
    this.onSelect,
    this.format,
    this.semanticLabel,
  });

  final List<T> data;
  final List<ChartPart<T>> children;
  final double height;
  final ValueChanged<ChartSelection<T>?>? onSelect;
  final String Function(num value)? format;
  final String? semanticLabel;

  @override
  State<FunnelChart<T>> createState() => _FunnelState<T>();
}

/// A [FunnelChart] holding a [Pyramid], named for what it draws.
class PyramidChart<T> extends FunnelChart<T> {
  const PyramidChart({
    super.key,
    required super.data,
    required super.children,
    super.height,
    super.onSelect,
    super.format,
    super.semanticLabel,
  });
}

class _FunnelState<T> extends State<FunnelChart<T>>
    with SingleTickerProviderStateMixin {
  late final _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  int? _at;
  ChartSelection<T>? _selected;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _grow.value = 1;
    } else if (_grow.isDismissed) {
      _grow.forward();
    }
  }

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  String _write(num v) => widget.format?.call(v) ?? chartThousands(v);

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final part = widget.children.whereType<Funnel<T>>().firstOrNull;
    final tooltip = widget.children.whereType<ChartTooltip<T>>().firstOrNull;
    final legend = widget.children.whereType<ChartLegend<T>>().firstOrNull;
    final data = widget.data;
    if (part == null) return SizedBox(height: widget.height);
    final pyramid = part is Pyramid<T>;
    final values = [for (final r in data) math.max(0.0, part.value(r)?.toDouble() ?? 0)];
    final names = [for (final r in data) part.name(r)];
    final colors = [
      for (final (i, r) in data.indexed) part.colorOf?.call(r) ?? c.charts[i % c.charts.length],
    ];
    final side = part.labels.any((l) => l.position != ChartLabelPosition.inside);
    final texts = [
      for (final l in part.labels)
        (
          l,
          [
            for (final (i, r) in data.indexed)
              l.text != null ? l.text!(r, values[i]) : _write(values[i]),
          ],
        ),
    ];

    List<Path> shapes(Size size) {
      final n = data.length;
      if (n == 0) return const [];
      final left = side ? 0.0 : 0.0;
      final w = size.width - (side ? 120 : 0);
      final cx = left + w / 2;
      final out = <Path>[];
      if (pyramid) {
        final total = values.fold<double>(0, (a, v) => a + v);
        var y = 0.0;
        for (var i = 0; i < n; i++) {
          final h = total == 0 ? size.height / n : values[i] / total * size.height;
          final top = y, bottom = y + h;
          double half(double at) => at / size.height * w / 2;
          out.add(
            Path()
              ..moveTo(cx - half(top), top + (i == 0 ? 0 : part.gap / 2))
              ..lineTo(cx + half(top), top + (i == 0 ? 0 : part.gap / 2))
              ..lineTo(cx + half(bottom), bottom - part.gap / 2)
              ..lineTo(cx - half(bottom), bottom - part.gap / 2)
              ..close(),
          );
          y = bottom;
        }
        return out;
      }
      final big = values.fold<double>(0, math.max);
      final h = (size.height - part.gap * (n - 1)) / n;
      for (var i = 0; i < n; i++) {
        final top = big == 0 ? 0.0 : values[i] / big * w;
        final next = i + 1 < n ? values[i + 1] : values[i] * .7;
        final bottom = big == 0 ? 0.0 : math.max(next / big * w, w * .04);
        final y = i * (h + part.gap);
        out.add(
          Path()
            ..moveTo(cx - top / 2, y)
            ..lineTo(cx + top / 2, y)
            ..lineTo(cx + bottom / 2, y + h)
            ..lineTo(cx - bottom / 2, y + h)
            ..close(),
        );
      }
      return out;
    }

    Widget? tip;
    if (_at != null && tooltip != null && _at! < data.length) {
      final row = data[_at!];
      final first = values.isEmpty ? 0 : values.first;
      final items = [
        ChartTooltipItem(
          label: names[_at!],
          value: values[_at!],
          text: tooltip.formatter?.call(values[_at!], names[_at!], row) ?? _write(values[_at!]),
          color: colors[_at!],
        ),
        if (part.conversion && _at! > 0 && first > 0)
          ChartTooltipItem(
            label: 'Of the first',
            value: values[_at!] / first,
            text: '${(values[_at!] / first * 100).toStringAsFixed(1)}%',
            color: colors[_at!],
          ),
      ];
      final d = ChartTooltipData<T>(title: names[_at!], items: items, row: row, index: _at);
      tip = tooltip.builder?.call(context, d) ??
          ChartTooltipCard(
            title: tooltip.hideLabel ? null : tooltip.labelFormatter?.call(names[_at!], row) ?? names[_at!],
            items: items,
            indicator: tooltip.hideIndicator ? ChartIndicator.none : tooltip.indicator,
          );
    }

    final legendView = legend == null
        ? null
        : (legend.builder ?? (context, e) => ChartLegendView(entries: e))(
            context,
            [for (var i = 0; i < data.length; i++) ChartLegendEntry(label: names[i], color: colors[i])],
          );

    return Semantics(
      container: true,
      label: widget.semanticLabel ?? 'Chart',
      value: [for (var i = 0; i < data.length; i++) '${names[i]} ${_write(values[i])}'].join(', '),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (legendView != null && legend!.position == ChartLegendPosition.top) ...[
            legendView,
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: widget.height,
            child: LayoutBuilder(
              builder: (context, box) {
                final size = Size(box.maxWidth, widget.height);
                final paths = shapes(size);
                int? hit(Offset p) {
                  for (final (i, path) in paths.indexed) {
                    if (path.contains(p)) return i;
                  }
                  return null;
                }

                return MouseRegion(
                  onHover: (e) => setState(() => _at = hit(e.localPosition)),
                  onExit: (_) => setState(() => _at = null),
                  child: GestureDetector(
                    onTapDown: (d) => setState(() => _at = hit(d.localPosition)),
                    onTapUp: (d) {
                      final i = hit(d.localPosition);
                      if (i == null || widget.onSelect == null) return;
                      final pick = ChartSelection<T>(index: i, row: data[i]);
                      setState(() => _selected = _selected == pick ? null : pick);
                      widget.onSelect!(_selected);
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: _grow,
                            builder: (context, _) => CustomPaint(
                              painter: _FunnelPainter(
                                paths: paths,
                                colors: colors,
                                texts: texts,
                                at: _at ?? _selected?.index,
                                grow: Curves.easeOutCubic.transform(_grow.value),
                                inside: t.text.xs.copyWith(
                                  color: c.background,
                                  fontWeight: FontWeight.w600,
                                ),
                                beside: t.text.xs.copyWith(color: c.foreground),
                              ),
                            ),
                          ),
                        ),
                        if (tip != null)
                          Positioned(top: 0, right: 0, child: IgnorePointer(child: tip)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (legendView != null && legend!.position == ChartLegendPosition.bottom) ...[
            const SizedBox(height: 12),
            legendView,
          ],
        ],
      ),
    );
  }
}

class _FunnelPainter extends CustomPainter {
  _FunnelPainter({
    required this.paths,
    required this.colors,
    required this.texts,
    required this.at,
    required this.grow,
    required this.inside,
    required this.beside,
  });

  final List<Path> paths;
  final List<Color> colors;
  final List<(ChartLabels<dynamic>, List<String?>)> texts;
  final int? at;
  final double grow;
  final TextStyle inside, beside;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (i, path) in paths.indexed) {
      final b = path.getBounds();
      canvas.save();
      // Grows open from the middle.
      canvas.translate(b.center.dx, 0);
      canvas.scale(grow, 1);
      canvas.translate(-b.center.dx, 0);
      final c = colors[i];
      canvas.drawPath(
        path,
        Paint()..color = at == null || at == i ? c : c.withValues(alpha: c.a * .45),
      );
      canvas.restore();
      if (grow < 1) continue;
      for (final (l, ts) in texts) {
        final s = ts[i];
        if (s == null) continue;
        final (Offset p, TextStyle style, Alignment a) = switch (l.position) {
          ChartLabelPosition.inside ||
          ChartLabelPosition.insideStart ||
          ChartLabelPosition.insideEnd => (b.center, inside, Alignment.center),
          ChartLabelPosition.left => (Offset(b.left - l.offset, b.center.dy), beside, Alignment.centerRight),
          _ => (
            Offset(math.max(b.right, size.width - 120) + l.offset, b.center.dy),
            beside,
            Alignment.centerLeft,
          ),
        };
        final tp = TextPainter(
          text: TextSpan(text: s, style: style.copyWith(color: l.color)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, p - Offset((a.x + 1) / 2 * tp.width, (a.y + 1) / 2 * tp.height));
      }
    }
  }

  @override
  bool shouldRepaint(_FunnelPainter old) => true;
}
