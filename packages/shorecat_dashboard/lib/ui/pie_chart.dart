// Ashlar UI: Pie chart. Copied into your app by `ashlar add pie-chart`; it is yours to change.
// ashlar: ignore-file. Laid out the same in any language, as charts are read.
//
// Slices of a whole, as a pie or a donut, a ring inside a ring if you like: your rows and
// a Pie. The tooltip, legend and labels are chart's.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'chart.dart';
import 'theme.dart';

/// One ring of a pie: a slice per row.
class Pie<T> extends ChartPart<T> implements ChartColumn<T> {
  const Pie({
    required this.value,
    required this.name,
    this.data,
    this.colorOf,
    this.innerRadius,
    this.outerRadius,
    this.paddingAngle = 0,
    this.cornerRadius = 0,
    this.activeIndex,
    this.labels = const [],
    this.labelLine = true,
    this.separators = true,
  });

  final ChartValue<T> value;

  /// Each slice's name, for the legend, the tooltip and a screen reader.
  final String Function(T row) name;

  /// Rows of its own, for a second ring that splits the whole another way.
  final List<T>? data;

  /// A colour per slice; null takes the theme's chart colours in turn.
  final Color? Function(T row)? colorOf;

  /// Where the ring starts and ends, as shares of the radius: 0.6 to 1 is a donut.
  /// Null: a whole pie, or an even share of the radius with other rings.
  final double? innerRadius, outerRadius;

  /// A gap between slices, in degrees.
  final double paddingAngle;

  /// The rounding of each slice's corners.
  final double cornerRadius;

  /// One slice drawn out from the rest: the one being talked about.
  final int? activeIndex;

  /// Text on the slices: [ChartLabelPosition.inside] within them, anything else outside.
  final List<ChartLabels<T>> labels;

  /// A line from each slice to its outside label.
  final bool labelLine;

  /// A thin line of the page between slices.
  final bool separators;

  @override
  String get columnName => 'Value';

  @override
  num? columnValue(T row) => value(row);
}

/// Slices of a whole: put a [Pie] in it, two for a ring inside a ring.
///
/// ```dart
/// PieChart<Browser>(
///   data: browsers,
///   center: Text('1,125'),
///   children: [
///     ChartTooltip(hideLabel: true),
///     Pie(value: (r) => r.visitors, name: (r) => r.browser, innerRadius: .6),
///   ],
/// )
/// ```
class PieChart<T> extends StatefulWidget {
  const PieChart({
    super.key,
    required this.data,
    required this.children,
    this.size = 250,
    this.center,
    this.onSelect,
    this.format,
    this.semanticLabel,
  });

  final List<T> data;
  final List<ChartPart<T>> children;

  /// Its width and height, without the legend.
  final double size;

  /// In the middle of a donut: the figure the chart is about.
  final Widget? center;
  final ValueChanged<ChartSelection<T>?>? onSelect;
  final String Function(num value)? format;
  final String? semanticLabel;

  @override
  State<PieChart<T>> createState() => _PieState<T>();
}

class _PieState<T> extends State<PieChart<T>>
    with TickerProviderStateMixin, ChartGrowth<PieChart<T>> {
  int? _at;
  int _ring = 0;
  final _hidden = <int>{};
  ChartSelection<T>? _selected;

  String Function(num) get _format => widget.format ?? chartPlain;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final pies = widget.children.whereType<Pie<T>>().toList();
    final tooltip = widget.children.whereType<ChartTooltip<T>>().firstOrNull;
    final legend = widget.children.whereType<ChartLegend<T>>().firstOrNull;
    final outside = pies.any(
      (p) => p.labels.any((l) => l.position != ChartLabelPosition.inside),
    );
    final margin = outside ? 40.0 : 4.0;
    final r = widget.size / 2 - margin;
    final centre = Offset(widget.size / 2, widget.size / 2);

    // Each ring's slices: rows, values, colours and angles (clockwise from the top).
    final rings = <_Ring<T>>[];
    for (final (k, p) in pies.indexed) {
      final rows = p.data ?? widget.data;
      final values = [
        for (final (i, row) in rows.indexed)
          k == 0 && _hidden.contains(i) ? 0.0 : (p.value(row)?.toDouble() ?? 0),
      ];
      final total = values.fold<double>(0, (a, v) => a + math.max(0, v));
      final inner = p.innerRadius ??
          (pies.length == 1 ? 0.0 : (pies.length - 1 - k) / pies.length * .9);
      final outer = p.outerRadius ??
          (pies.length == 1 ? 1.0 : (pies.length - k) / pies.length);
      rings.add(
        _Ring(
          part: p,
          rows: rows,
          values: values,
          total: total,
          colors: [
            for (final (i, row) in rows.indexed)
              p.colorOf?.call(row) ?? c.charts[i % c.charts.length],
          ],
          inner: inner * r,
          outer: outer * r,
          labels: [
            for (final l in p.labels)
              (
                l,
                [
                  for (final (i, row) in rows.indexed)
                    l.text != null ? l.text!(row, values[i]) : _format(values[i]),
                ],
              ),
          ],
        ),
      );
    }

    (int, int)? sliceAt(Offset p) {
      final d = p - centre;
      var a = math.atan2(d.dy, d.dx) + math.pi / 2;
      if (a < 0) a += 2 * math.pi;
      for (final (k, ring) in rings.indexed) {
        if (d.distance > ring.outer + 8 || d.distance < ring.inner) continue;
        var run = 0.0;
        for (final (i, v) in ring.values.indexed) {
          run += ring.total == 0 ? 0 : math.max(0, v) / ring.total * 2 * math.pi;
          if (a <= run) return (k, i);
        }
      }
      return null;
    }

    final first = rings.firstOrNull;
    final entries = first == null
        ? <ChartLegendEntry>[]
        : [
            for (final (i, row) in first.rows.indexed)
              ChartLegendEntry(
                label: first.part.name(row),
                color: first.colors[i],
                shown: !_hidden.contains(i),
                onToggle: legend?.toggle ?? false
                    ? () => setState(() {
                        if (!_hidden.remove(i) &&
                            _hidden.length < first.rows.length - 1) {
                          _hidden.add(i);
                        }
                      })
                    : null,
              ),
          ];
    final legendView = legend == null
        ? null
        : (legend.builder ?? (context, e) => ChartLegendView(entries: e))(
            context,
            entries,
          );

    Widget? tip;
    if (_at != null && tooltip != null && _ring < rings.length) {
      final ring = rings[_ring];
      final row = ring.rows[_at!];
      final name = ring.part.name(row);
      final v = ring.values[_at!];
      final items = [
        ChartTooltipItem(
          label: name,
          value: v,
          text: tooltip.formatter?.call(v, name, row) ?? _format(v),
          color: ring.colors[_at!],
        ),
      ];
      final data = ChartTooltipData<T>(
        title: tooltip.labelFormatter?.call(name, row) ?? name,
        items: items,
        row: row,
        index: _at,
      );
      tip = tooltip.builder?.call(context, data) ??
          ChartTooltipCard(
            title: tooltip.hideLabel ? null : data.title,
            items: items,
            indicator: tooltip.hideIndicator ? ChartIndicator.none : tooltip.indicator,
          );
    }

    return Semantics(
      container: true,
      label: widget.semanticLabel ?? 'Chart',
      value: [
        for (final ring in rings)
          for (final (i, row) in ring.rows.indexed)
            '${ring.part.name(row)} ${_format(ring.values[i])}',
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
              final hit = sliceAt(e.localPosition);
              _ring = hit?.$1 ?? 0;
              _at = hit?.$2;
            }),
            onExit: (_) => setState(() => _at = null),
            child: GestureDetector(
              onTapDown: (d) => setState(() {
                final hit = sliceAt(d.localPosition);
                _ring = hit?.$1 ?? 0;
                _at = hit?.$2;
              }),
              onTapUp: (d) {
                if (widget.onSelect == null) return;
                final hit = sliceAt(d.localPosition);
                if (hit == null) return;
                final pick = ChartSelection<T>(
                  index: hit.$2,
                  row: rings[hit.$1].rows[hit.$2],
                );
                setState(() => _selected = _selected == pick ? null : pick);
                widget.onSelect!(_selected);
              },
              child: SizedBox.square(
                dimension: widget.size,
                child: AnimatedBuilder(
                  animation: grow,
                  builder: (context, _) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _PiePainter(
                            rings: rings,
                            centre: centre,
                            at: _at,
                            atRing: _ring,
                            selected: _selected?.index,
                            gap: c.background,
                            sweep: grown,
                            labelLine: c.mutedForeground,
                            text: t.text.xs.copyWith(color: c.foreground),
                            inside: t.text.xs.copyWith(
                              color: c.background,
                              fontWeight: FontWeight.w600,
                            ),
                            format: _format,
                          ),
                        ),
                      ),
                      if (widget.center != null)
                        Positioned.fill(
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
                          left: widget.size * .55,
                          child: IgnorePointer(child: tip),
                        ),
                    ],
                  ),
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

class _Ring<T> {
  _Ring({
    required this.part,
    required this.rows,
    required this.values,
    required this.total,
    required this.colors,
    required this.inner,
    required this.outer,
    required this.labels,
  });

  final Pie<T> part;

  /// Each label's text per slice, written while building.
  final List<(ChartLabels<T>, List<String?>)> labels;
  final List<T> rows;
  final List<double> values;
  final double total, inner, outer;
  final List<Color> colors;
}

class _PiePainter extends CustomPainter {
  _PiePainter({
    required this.rings,
    required this.centre,
    required this.at,
    required this.atRing,
    required this.selected,
    required this.gap,
    required this.sweep,
    required this.labelLine,
    required this.text,
    required this.inside,
    required this.format,
  });

  final List<_Ring<dynamic>> rings;
  final Offset centre;
  final int? at, selected;
  final int atRing;
  final Color gap, labelLine;
  final double sweep;
  final TextStyle text, inside;
  final String Function(num) format;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (k, ring) in rings.indexed) {
      if (ring.total <= 0) continue;
      final p = ring.part;
      final pad = p.paddingAngle * math.pi / 180;
      var start = -math.pi / 2;
      final active = p.activeIndex ?? (k == atRing ? at : null) ?? (k == 0 ? selected : null);
      for (final (i, v) in ring.values.indexed) {
        final a = math.max(0, v) / ring.total * 2 * math.pi * sweep;
        if (a <= 0) continue;
        final out = ring.outer + (i == active ? 8 : 0);
        final from = start + pad / 2, to = start + a - pad / 2;
        if (to > from) {
          final path = _slice(centre, ring.inner, out, from, to, p.cornerRadius);
          canvas.drawPath(path, Paint()..color = ring.colors[i]);
          if (p.separators && p.paddingAngle == 0 && ring.values.length > 1) {
            canvas.drawPath(
              path,
              Paint()
                ..color = gap
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5,
            );
          }
        }
        // Labels, once the pie is whole.
        if (sweep == 1) {
          final mid = start + a / 2;
          final dir = Offset(math.cos(mid), math.sin(mid));
          for (final (l, texts) in ring.labels) {
            final s = texts[i];
            if (s == null) continue;
            if (l.position == ChartLabelPosition.inside) {
              final at = centre + dir * ((ring.inner + out) / 2);
              chartText(canvas, s, at, inside.copyWith(color: l.color));
            } else {
              final edge = centre + dir * out;
              final at = centre + dir * (out + 14 + l.offset);
              if (p.labelLine) {
                canvas.drawLine(
                  edge,
                  centre + dir * (out + 10 + l.offset),
                  Paint()
                    ..color = labelLine
                    ..strokeWidth = 1,
                );
              }
              chartText(
                canvas,
                s,
                at,
                text.copyWith(color: l.color),
                Alignment(dir.dx < -.2 ? 1 : (dir.dx > .2 ? -1 : 0), dir.dy < -.2 ? 1 : (dir.dy > .2 ? -1 : 0)),
              );
            }
          }
        }
        start += a;
      }
    }
  }

  @override
  bool shouldRepaint(_PiePainter old) => true;
}

/// A ring's slice between two radii and two angles, its corners rounded by [round].
Path _slice(Offset c, double inner, double outer, double from, double to, double round) {
  final p = Path();
  if (round <= 0 || to - from < .02) {
    p.arcTo(Rect.fromCircle(center: c, radius: outer), from, to - from, true);
    if (inner > 0) {
      p.arcTo(Rect.fromCircle(center: c, radius: inner), to, from - to, false);
    } else {
      p.lineTo(c.dx, c.dy);
    }
    return p..close();
  }
  final r = math.min(round, (outer - inner) / 2);
  final ao = r / outer, ai = inner > 0 ? r / inner : 0.0;
  Offset at(double rad, double a) => c + Offset(math.cos(a), math.sin(a)) * rad;
  p.moveTo(at(outer - r, from).dx, at(outer - r, from).dy);
  p.quadraticBezierTo(at(outer, from).dx, at(outer, from).dy, at(outer, from + ao).dx, at(outer, from + ao).dy);
  p.arcTo(Rect.fromCircle(center: c, radius: outer), from + ao, to - from - 2 * ao, false);
  p.quadraticBezierTo(at(outer, to).dx, at(outer, to).dy, at(outer - r, to).dx, at(outer - r, to).dy);
  if (inner > 0) {
    p.lineTo(at(inner + r, to).dx, at(inner + r, to).dy);
    p.quadraticBezierTo(at(inner, to).dx, at(inner, to).dy, at(inner, to - ai).dx, at(inner, to - ai).dy);
    p.arcTo(Rect.fromCircle(center: c, radius: inner), to - ai, -(to - from - 2 * ai), false);
    p.quadraticBezierTo(at(inner, from).dx, at(inner, from).dy, at(inner + r, from).dx, at(inner + r, from).dy);
  } else {
    p.lineTo(c.dx, c.dy);
  }
  return p..close();
}
