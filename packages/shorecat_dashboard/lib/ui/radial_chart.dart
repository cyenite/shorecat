// Ashlar UI: Radial chart. Copied into your app by `ashlar add radial-chart`; it is yours to change.
// ashlar: ignore-file. Laid out the same in any language, as charts are read.
//
// Values as arcs round a centre: a ring per row, or the series sharing one ring, round
// the whole circle or part of it.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'chart.dart';
import 'theme.dart';

/// Arcs round a centre: a ring per row, or the series sharing one ring when they have
/// a [stackId].
class RadialBar<T> extends ChartPart<T> implements ChartColumn<T> {
  const RadialBar({
    required this.value,
    this.label,
    this.color,
    this.colorOf,
    this.icon,
    this.stackId,
    this.background = true,
    this.round = true,
    this.labels = const [],
  });

  final ChartValue<T> value;

  /// Its name, when there are several series.
  final String? label;
  final Color? color;

  /// A colour per row's ring.
  final Color? Function(T row)? colorOf;
  final IconData? icon;
  final String? stackId;

  /// A faint full ring behind each arc, to show what a full one would be.
  final bool background;

  /// Rounded ends.
  final bool round;

  /// Text on each arc: [ChartLabelPosition.insideStart] writes it at the arc's start.
  final List<ChartLabels<T>> labels;

  @override
  String get columnName => label ?? 'Value';

  @override
  num? columnValue(T row) => value(row);
}

/// Values as arcs round a centre: a ring per row, or the series sharing a ring when
/// stacked; round the whole circle, or part of it.
///
/// ```dart
/// RadialBarChart<Browser>(
///   data: browsers,
///   name: (r) => r.browser,
///   children: [RadialBar(value: (r) => r.visitors, colorOf: (r) => r.color)],
/// )
/// ```
class RadialBarChart<T> extends StatefulWidget {
  const RadialBarChart({
    super.key,
    required this.data,
    required this.children,
    this.name,
    this.size = 250,
    this.startAngle = 0,
    this.endAngle = 360,
    this.innerRadius = .3,
    this.outerRadius = 1,
    this.max,
    this.center,
    this.onSelect,
    this.format,
    this.semanticLabel,
  });

  final List<T> data;
  final List<ChartPart<T>> children;

  /// Each row's name, for the legend, the tooltip and a screen reader.
  final String Function(T row)? name;

  /// Its width; a half ring is about half as tall.
  final double size;

  /// Where the arcs start and the full ring ends, in degrees clockwise from the top:
  /// -90 to 90 is the top half, a gauge.
  final double startAngle, endAngle;

  /// Where the rings start and end, as shares of the radius.
  final double innerRadius, outerRadius;

  /// The value a full ring stands for; the largest, or the largest stack, when not
  /// given.
  final num? max;

  /// In the middle: the figure the chart is about.
  final Widget? center;
  final ValueChanged<ChartSelection<T>?>? onSelect;
  final String Function(num value)? format;
  final String? semanticLabel;

  @override
  State<RadialBarChart<T>> createState() => _RadialState<T>();
}

class _RadialState<T> extends State<RadialBarChart<T>>
    with TickerProviderStateMixin, ChartGrowth<RadialBarChart<T>> {
  int? _at;
  int? _atBar;

  String Function(num) get _format => widget.format ?? chartPlain;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final data = widget.data;
    final n = data.length;
    final bars = widget.children.whereType<RadialBar<T>>().toList();
    final grid = widget.children.whereType<PolarGrid<T>>().firstOrNull;
    final tooltip = widget.children.whereType<ChartTooltip<T>>().firstOrNull;
    final legend = widget.children.whereType<ChartLegend<T>>().firstOrNull;
    final values = [
      for (final b in bars) [for (final r in data) b.value(r)?.toDouble() ?? 0],
    ];
    // Groups within a ring: one per stack, or per series not stacked.
    final groupOf = <String, int>{};
    for (final (k, b) in bars.indexed) {
      groupOf.putIfAbsent(b.stackId ?? '#$k', () => groupOf.length);
    }
    var max = widget.max?.toDouble() ?? 0;
    if (widget.max == null) {
      for (var i = 0; i < n; i++) {
        final sums = <int, double>{};
        for (final (k, b) in bars.indexed) {
          final g = groupOf[b.stackId ?? '#$k']!;
          sums[g] = (sums[g] ?? 0) + values[k][i];
        }
        for (final s in sums.values) {
          max = math.max(max, s);
        }
      }
    }
    final start = widget.startAngle, end = widget.endAngle;
    final arcDeg = end - start;
    // A half ring needs about half the height.
    final half = arcDeg.abs() <= 180;
    final height = half ? widget.size / 2 + 28 : widget.size;
    final r = widget.size / 2 - 4;
    final centre = Offset(widget.size / 2, half ? widget.size / 2 : widget.size / 2);
    final inner = r * widget.innerRadius, outer = r * widget.outerRadius;
    final ringW = n == 0 ? 0.0 : (outer - inner) / n;
    Color colorOf(int k, int i) =>
        bars[k].colorOf?.call(data[i]) ??
        bars[k].color ??
        (bars.length == 1 ? c.charts[i % c.charts.length] : c.charts[k % c.charts.length]);
    String nameOf(int i) => widget.name?.call(data[i]) ?? '${i + 1}';

    (int, int?)? hit(Offset p) {
      final d = p - centre;
      if (d.distance > outer + 4 || d.distance < inner - 4 || n == 0) {
        return null;
      }
      // Rows from the outside in.
      final ring = ((outer - d.distance) / ringW).floor().clamp(0, n - 1);
      var a = (math.atan2(d.dy, d.dx) + math.pi / 2) * 180 / math.pi;
      while (a < start) {
        a += 360;
      }
      // Which series' arc in the ring the angle falls in.
      final runs = <int, double>{};
      for (final (k, b) in bars.indexed) {
        final g = groupOf[b.stackId ?? '#$k']!;
        final from = runs[g] ?? 0;
        final to = from + values[k][ring] / (max == 0 ? 1 : max) * arcDeg;
        runs[g] = to;
        if (a - start >= from && a - start <= to) return (ring, k);
      }
      return (ring, null);
    }

    final entries = bars.length > 1 && bars.every((b) => b.label != null)
        ? [
            for (final (k, b) in bars.indexed)
              ChartLegendEntry(label: b.label!, color: colorOf(k, 0), icon: b.icon),
          ]
        : [
            for (var i = 0; i < n; i++)
              ChartLegendEntry(label: nameOf(i), color: colorOf(0, i)),
          ];
    final legendView = legend == null
        ? null
        : (legend.builder ?? (context, e) => ChartLegendView(entries: e))(context, entries);

    Widget? tip;
    if (_at != null && tooltip != null && _at! < n && bars.isNotEmpty) {
      final row = data[_at!];
      final items = [
        for (final (k, b) in bars.indexed)
          if (_atBar == null || _atBar == k)
            ChartTooltipItem(
              label: b.label ?? nameOf(_at!),
              value: values[k][_at!],
              text: tooltip.formatter?.call(values[k][_at!], b.label ?? nameOf(_at!), row) ??
                  _format(values[k][_at!]),
              color: colorOf(k, _at!),
              icon: b.icon,
            ),
      ];
      final d = ChartTooltipData<T>(
        title: tooltip.labelFormatter?.call(nameOf(_at!), row) ?? nameOf(_at!),
        items: items,
        row: row,
        index: _at,
      );
      tip = tooltip.builder?.call(context, d) ??
          ChartTooltipCard(
            title: tooltip.hideLabel ? null : d.title,
            items: items,
            indicator: tooltip.hideIndicator ? ChartIndicator.none : tooltip.indicator,
          );
    }

    return Semantics(
      container: true,
      label: widget.semanticLabel ?? 'Chart',
      value: [
        for (var i = 0; i < n; i++)
          for (final (k, b) in bars.indexed)
            '${b.label ?? nameOf(i)} ${_format(values[k][i])} of ${_format(max)}',
      ].join(', '),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (legendView != null && legend!.position == ChartLegendPosition.top) ...[
            legendView,
            const SizedBox(height: 12),
          ],
          MouseRegion(
            onHover: (e) => setState(() {
              final h = hit(e.localPosition);
              _at = h?.$1;
              _atBar = h?.$2;
            }),
            onExit: (_) => setState(() => _at = null),
            child: GestureDetector(
              onTapDown: (d) => setState(() {
                final h = hit(d.localPosition);
                _at = h?.$1;
                _atBar = h?.$2;
              }),
              onTapUp: (d) {
                final h = hit(d.localPosition);
                if (h != null) {
                  widget.onSelect?.call(
                    ChartSelection<T>(
                      index: h.$1,
                      row: data[h.$1],
                      series: h.$2 == null ? null : bars[h.$2!].label,
                    ),
                  );
                }
              },
              child: SizedBox(
                width: widget.size,
                height: height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      width: widget.size,
                      height: widget.size,
                      child: AnimatedBuilder(
                        animation: grow,
                        builder: (context, _) => CustomPaint(
                          painter: _RadialPainter(
                            n: n,
                            bars: bars,
                            values: values,
                            groupOf: groupOf,
                            colorOf: colorOf,
                            names: [for (var i = 0; i < n; i++) nameOf(i)],
                            labelTexts: [
                              for (final b in bars)
                                [
                                  for (final l in b.labels)
                                    [
                                      for (final row in data)
                                        l.text != null
                                            ? l.text!(row, b.value(row) ?? 0)
                                            : _format(b.value(row) ?? 0),
                                    ],
                                ],
                            ],
                            max: max,
                            centre: centre,
                            inner: inner,
                            outer: outer,
                            start: start,
                            arc: arcDeg,
                            grid: grid,
                            at: _at,
                            track: c.muted,
                            line: c.border,
                            page: c.background,
                            fg: c.foreground,
                            text: t.text.xs.copyWith(
                              color: c.background,
                              fontWeight: FontWeight.w600,
                            ),
                            grow: grown,
                          ),
                        ),
                      ),
                    ),
                    if (widget.center != null)
                      Positioned(
                        left: 0,
                        width: widget.size,
                        top: half ? widget.size / 2 - 56 : 0,
                        height: half ? 56 : widget.size,
                        child: IgnorePointer(
                          child: Center(
                            child: DefaultTextStyle.merge(
                              style: t.text.xl.copyWith(
                                fontWeight: FontWeight.w700,
                                color: c.foreground,
                              ),
                              textAlign: TextAlign.center,
                              child: widget.center!,
                            ),
                          ),
                        ),
                      ),
                    if (tip != null)
                      Positioned(
                        top: 0,
                        left: widget.size * .6,
                        child: IgnorePointer(child: tip),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (legendView != null &&
              legend!.position == ChartLegendPosition.bottom) ...[
            const SizedBox(height: 12),
            legendView,
          ],
        ],
      ),
    );
  }
}

class _RadialPainter extends CustomPainter {
  _RadialPainter({
    required this.n,
    required this.bars,
    required this.values,
    required this.groupOf,
    required this.colorOf,
    required this.names,
    required this.labelTexts,
    required this.max,
    required this.centre,
    required this.inner,
    required this.outer,
    required this.start,
    required this.arc,
    required this.grid,
    required this.at,
    required this.track,
    required this.line,
    required this.page,
    required this.fg,
    required this.text,
    required this.grow,
  });

  final int n;
  final List<RadialBar<dynamic>> bars;
  final List<List<double>> values;
  final Map<String, int> groupOf;
  final Color Function(int k, int i) colorOf;
  final List<String> names;
  final List<List<List<String?>>> labelTexts;
  final double max, inner, outer, start, arc, grow;
  final Offset centre;
  final PolarGrid<dynamic>? grid;
  final int? at;
  final Color track, line, page, fg;
  final TextStyle text;

  double _rad(double deg) => (deg - 90) * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    if (n == 0 || max <= 0) return;
    final ringW = (outer - inner) / n;
    final groups = groupOf.length;
    final labels = <(String, Offset, ChartLabels<dynamic>)>[];
    if (grid case final g?) {
      // Circles between the rings, and spokes at the ends.
      final p = Paint()
        ..color = line
        ..style = PaintingStyle.stroke;
      for (var i = 0; i <= n; i++) {
        final rad = outer - i * ringW;
        final path = Path()
          ..addArc(Rect.fromCircle(center: centre, radius: rad), _rad(start), arc * math.pi / 180);
        canvas.drawPath(g.dashed ? chartDashed(path) : path, p);
      }
    }
    for (var i = 0; i < n; i++) {
      final ringOuter = outer - i * ringW;
      final band = ringW * .78;
      final each = band / groups;
      final runs = <int, double>{};
      for (final (k, b) in bars.indexed) {
        final g = groupOf[b.stackId ?? '#$k']!;
        final mid = ringOuter - ringW * .11 - each * g - each / 2;
        final rect = Rect.fromCircle(center: centre, radius: mid);
        final w = each * (at == i ? 1.08 : 1);
        if (b.background && (runs[g] ?? 0) == 0) {
          canvas.drawArc(
            rect,
            _rad(start),
            arc * math.pi / 180,
            false,
            Paint()
              ..color = track
              ..style = PaintingStyle.stroke
              ..strokeWidth = each
              ..strokeCap = b.round && b.stackId == null && arc.abs() < 360
                  ? StrokeCap.round
                  : StrokeCap.butt,
          );
        }
        final from = runs[g] ?? 0;
        final sweep = (values[k][i] / max).clamp(0, 1) * arc * grow;
        runs[g] = from + sweep;
        if (sweep.abs() < .01) continue;
        if (grow == 1) {
          for (final (li, l) in b.labels.indexed) {
            if (labelTexts[k][li][i] case final s?) {
              final atDeg = l.position == ChartLabelPosition.insideStart
                  ? start + from + 6
                  : start + from + sweep - 4;
              labels.add((
                s,
                centre + Offset(math.cos(_rad(atDeg)), math.sin(_rad(atDeg))) * mid,
                l,
              ));
            }
          }
        }
        canvas.drawArc(
          rect,
          _rad(start + from),
          sweep * math.pi / 180,
          false,
          Paint()
            ..color = colorOf(k, i)
            ..style = PaintingStyle.stroke
            ..strokeWidth = w
            ..strokeCap = b.round && b.stackId == null ? StrokeCap.round : StrokeCap.butt,
        );
      }
    }
    for (final (s, p, l) in labels) {
      chartText(
        canvas,
        s,
        p,
        text.copyWith(color: l.color),
        l.position == ChartLabelPosition.insideStart
            ? Alignment.centerLeft
            : Alignment.centerRight,
      );
    }
  }

  @override
  bool shouldRepaint(_RadialPainter old) => true;
}
