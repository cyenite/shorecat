// Ashlar UI: Heatmap. Copied into your app by `ashlar add heatmap`; it is yours to change.
// ashlar: ignore-file. Drawn left to right in any language, as time is read.
//
// Values as shades in a grid: a cell per row of your data, placed by two of its fields
// (hour by day, say), or a calendar of days the way a year of activity is shown.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'chart.dart';
import 'theme.dart';

/// The shade for [v] between [lo] and [hi]: from [from] to [to] in [steps] steps, or
/// smoothly when [steps] is null.
Color _shade(double v, double lo, double hi, Color from, Color to, int? steps) {
  var f = hi == lo ? 1.0 : ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
  if (steps != null && steps > 1) f = ((f * (steps - 1)).round()) / (steps - 1);
  return Color.lerp(from, to, f)!;
}

/// Values as shades in a grid: each row of [data] a cell, across by [x] and down by
/// [y].
///
/// ```dart
/// Heatmap<Load>(
///   data: load,
///   x: (r) => r.hour,
///   y: (r) => r.day,
///   value: (r) => r.requests,
/// )
/// ```
class Heatmap<T> extends StatefulWidget {
  const Heatmap({
    super.key,
    required this.data,
    required this.x,
    required this.y,
    required this.value,
    this.xLabels,
    this.yLabels,
    this.color,
    this.empty,
    this.steps,
    this.cellHeight = 28,
    this.gap = 2,
    this.radius = 3,
    this.values = false,
    this.scale = true,
    this.format,
    this.onSelect,
    this.semanticLabel,
  });

  final List<T> data;

  /// The column a row falls in.
  final Object Function(T row) x;

  /// The line it falls on.
  final Object Function(T row) y;
  final ChartValue<T> value;

  /// The columns and lines in order; null: in the order they first appear.
  final List<Object>? xLabels, yLabels;

  /// The strongest shade; null: the theme's first chart colour.
  final Color? color;

  /// The faintest; null: the theme's muted colour.
  final Color? empty;

  /// Shades in this many steps rather than smoothly.
  final int? steps;
  final double cellHeight;
  final double gap;
  final double radius;

  /// Each value written in its cell.
  final bool values;

  /// A key from the faintest shade to the strongest under the grid.
  final bool scale;
  final String Function(num value)? format;
  final ValueChanged<ChartSelection<T>?>? onSelect;
  final String? semanticLabel;

  @override
  State<Heatmap<T>> createState() => _HeatmapState<T>();
}

class _HeatmapState<T> extends State<Heatmap<T>> {
  int? _at;

  String _write(num v) => widget.format?.call(v) ?? chartNumber(v);

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final data = widget.data;
    final xs = widget.xLabels ?? {for (final r in data) widget.x(r)}.toList();
    final ys = widget.yLabels ?? {for (final r in data) widget.y(r)}.toList();
    final values = [for (final r in data) widget.value(r)?.toDouble()];
    final known = values.whereType<double>();
    final lo = known.isEmpty ? 0.0 : known.reduce(math.min);
    final hi = known.isEmpty ? 1.0 : known.reduce(math.max);
    final strong = widget.color ?? c.chart1;
    final faint = widget.empty ?? c.muted;
    final text = t.text.xs.copyWith(color: c.mutedForeground);
    final gutter = ys
            .map((v) => (TextPainter(
                  text: TextSpan(text: '$v', style: text),
                  textDirection: TextDirection.ltr,
                )..layout()).width)
            .fold<double>(0, math.max) +
        8;
    final height = ys.length * (widget.cellHeight + widget.gap) + 24;
    return Semantics(
      container: true,
      label: widget.semanticLabel ?? 'Heatmap',
      value: [
        for (final (i, r) in data.indexed)
          if (values[i] != null) '${widget.y(r)} ${widget.x(r)}: ${_write(values[i]!)}',
      ].take(200).join('; '),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: height,
            child: LayoutBuilder(
              builder: (context, box) {
                final cw = (box.maxWidth - gutter) / math.max(1, xs.length);
                Rect cell(int i) {
                  final r = data[i];
                  final cx = xs.indexOf(widget.x(r)), cy = ys.indexOf(widget.y(r));
                  return Rect.fromLTWH(
                    gutter + cx * cw + widget.gap / 2,
                    cy * (widget.cellHeight + widget.gap),
                    cw - widget.gap,
                    widget.cellHeight,
                  );
                }

                int? hit(Offset p) {
                  for (var i = 0; i < data.length; i++) {
                    if (cell(i).contains(p)) return i;
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
                      if (i != null) {
                        widget.onSelect?.call(ChartSelection<T>(index: i, row: data[i]));
                      }
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _GridPainter(
                              cells: [for (var i = 0; i < data.length; i++) cell(i)],
                              colors: [
                                for (final v in values)
                                  v == null ? faint.withValues(alpha: .4) : _shade(v, lo, hi, faint, strong, widget.steps),
                              ],
                              texts: widget.values
                                  ? [for (final v in values) v == null ? null : _write(v)]
                                  : null,
                              rowLabels: [
                                for (final (k, y) in ys.indexed)
                                  ('$y', k * (widget.cellHeight + widget.gap) + widget.cellHeight / 2),
                              ],
                              colLabels: [
                                for (final (k, x) in xs.indexed)
                                  (x is DateTime ? chartDate(x) : '$x', gutter + (k + .5) * cw),
                              ],
                              gutter: gutter,
                              labelY: ys.length * (widget.cellHeight + widget.gap) + 4,
                              colEvery: math.max(
                                1,
                                ((xs.map((x) => '$x'.length).fold<int>(0, math.max) * 7 + 8) / cw).ceil(),
                              ),
                              radius: widget.radius,
                              at: _at,
                              ring: c.foreground,
                              text: text,
                              onCell: t.text.xs.copyWith(color: c.foreground, fontSize: 10),
                              onStrong: t.text.xs.copyWith(color: c.background, fontSize: 10),
                              strongAt: lo + (hi - lo) * .55,
                              values: values,
                            ),
                          ),
                        ),
                        if (_at != null && values[_at!] != null)
                          Positioned(
                            left: math.min(cell(_at!).right + 6, box.maxWidth - 140),
                            top: cell(_at!).top,
                            child: IgnorePointer(
                              child: ChartTooltipCard(
                                title: '${widget.y(data[_at!])} · ${widget.x(data[_at!])}',
                                items: [
                                  ChartTooltipItem(
                                    label: 'Value',
                                    value: values[_at!]!,
                                    text: _write(values[_at!]!),
                                    color: _shade(values[_at!]!, lo, hi, faint, strong, widget.steps),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (widget.scale && known.isNotEmpty) ...[
            const SizedBox(height: 8),
            _Scale(lo: _write(lo), hi: _write(hi), from: faint, to: strong, steps: widget.steps),
          ],
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.cells,
    required this.colors,
    required this.texts,
    required this.rowLabels,
    required this.colLabels,
    required this.gutter,
    required this.labelY,
    required this.colEvery,
    required this.radius,
    required this.at,
    required this.ring,
    required this.text,
    required this.onCell,
    required this.onStrong,
    required this.strongAt,
    required this.values,
  });

  final List<Rect> cells;
  final List<Color> colors;
  final List<String?>? texts;
  final List<(String, double)> rowLabels, colLabels;
  final double gutter, labelY, radius, strongAt;
  final int colEvery;
  final int? at;
  final Color ring;
  final TextStyle text, onCell, onStrong;
  final List<double?> values;

  void _text(Canvas canvas, String s, Offset at, TextStyle style, Alignment a) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset((a.x + 1) / 2 * tp.width, (a.y + 1) / 2 * tp.height));
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final (i, r) in cells.indexed) {
      final rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
      canvas.drawRRect(rr, Paint()..color = colors[i]);
      if (i == at) {
        canvas.drawRRect(
          rr,
          Paint()
            ..color = ring
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
      if (texts?[i] case final s?) {
        _text(canvas, s, r.center, (values[i] ?? 0) >= strongAt ? onStrong : onCell, Alignment.center);
      }
    }
    for (final (s, y) in rowLabels) {
      _text(canvas, s, Offset(gutter - 8, y), text, Alignment.centerRight);
    }
    for (final (k, (s, x)) in colLabels.indexed) {
      if (k % colEvery == 0) {
        _text(canvas, s, Offset(x, labelY), text, Alignment.topCenter);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => true;
}

/// The key under a heatmap: the faintest shade's value, the shades, the strongest's.
class _Scale extends StatelessWidget {
  const _Scale({
    required this.lo,
    required this.hi,
    required this.from,
    required this.to,
    this.steps,
  });

  final String lo, hi;
  final Color from, to;
  final int? steps;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final style = t.text.xs.copyWith(color: t.colors.mutedForeground);
    final n = steps ?? 5;
    // Wraps rather than overflowing when there is less room than it needs.
    return ExcludeSemantics(
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 3,
        runSpacing: 4,
        children: [
          Padding(padding: const EdgeInsets.only(right: 3), child: Text(lo, style: style)),
          for (var i = 0; i < n; i++)
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Color.lerp(from, to, n == 1 ? 1 : i / (n - 1)),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          Padding(padding: const EdgeInsets.only(left: 3), child: Text(hi, style: style)),
        ],
      ),
    );
  }
}

/// A calendar of days as shades: a column per week, a line per weekday, the way a year
/// of activity is shown.
///
/// ```dart
/// CalendarHeatmap(values: {DateTime(2026, 3, 2): 4, DateTime(2026, 3, 3): 9})
/// ```
class CalendarHeatmap extends StatefulWidget {
  const CalendarHeatmap({
    super.key,
    required this.values,
    this.from,
    this.to,
    this.mondayFirst = true,
    this.color,
    this.empty,
    this.steps = 5,
    this.cell = 12,
    this.gap = 3,
    this.scale = true,
    this.format,
    this.onSelect,
    this.semanticLabel,
  });

  /// A value per day; the time of day is ignored.
  final Map<DateTime, num> values;

  /// The first and last days shown; null: a year to the last day with a value.
  final DateTime? from, to;

  /// Weeks start on Monday; false, on Sunday.
  final bool mondayFirst;
  final Color? color;
  final Color? empty;
  final int? steps;

  /// Each day's size, and the gap between days.
  final double cell, gap;
  final bool scale;
  final String Function(num value)? format;

  /// Called with the day tapped.
  final ValueChanged<DateTime>? onSelect;
  final String? semanticLabel;

  @override
  State<CalendarHeatmap> createState() => _CalendarHeatmapState();
}

class _CalendarHeatmapState extends State<CalendarHeatmap> {
  DateTime? _at;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  String _write(num v) => widget.format?.call(v) ?? chartNumber(v);

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final byDay = <DateTime, double>{};
    widget.values.forEach((d, v) => byDay[_day(d)] = (byDay[_day(d)] ?? 0) + v.toDouble());
    final last = _day(widget.to ??
        (byDay.isEmpty ? DateTime.now() : byDay.keys.reduce((a, b) => a.isAfter(b) ? a : b)));
    final first = _day(widget.from ?? DateTime(last.year - 1, last.month, last.day + 1));
    // Back to the start of the first week.
    final offset = widget.mondayFirst ? first.weekday - 1 : first.weekday % 7;
    final start = DateTime(first.year, first.month, first.day - offset);
    final days = last.difference(start).inDays + 1;
    final weeks = (days / 7).ceil();
    final known = byDay.values;
    final lo = known.isEmpty ? 0.0 : math.min(0.0, known.reduce(math.min));
    final hi = known.isEmpty ? 1.0 : known.reduce(math.max);
    final strong = widget.color ?? c.chart1;
    final faint = widget.empty ?? c.muted;
    final style = t.text.xs.copyWith(color: c.mutedForeground, fontSize: 10);
    const left = 28.0, top = 16.0;
    final step = widget.cell + widget.gap;
    final names = widget.mondayFirst
        ? ['Mon', '', 'Wed', '', 'Fri', '', '']
        : ['', 'Mon', '', 'Wed', '', 'Fri', ''];
    DateTime dayAt(int week, int weekday) =>
        DateTime(start.year, start.month, start.day + week * 7 + weekday);
    DateTime? hit(Offset p) {
      final w = ((p.dx - left) / step).floor(), d = ((p.dy - top) / step).floor();
      if (w < 0 || w >= weeks || d < 0 || d > 6) return null;
      final day = dayAt(w, d);
      return day.isBefore(first) || day.isAfter(last) ? null : day;
    }

    final total = known.fold<double>(0, (a, v) => a + v);
    return Semantics(
      container: true,
      label: widget.semanticLabel ?? 'Calendar',
      value:
          '${chartDate(first)} ${first.year} to ${chartDate(last)} ${last.year}: ${byDay.length} days with values, ${_write(total)} in all',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MouseRegion(
            onHover: (e) => setState(() => _at = hit(e.localPosition)),
            onExit: (_) => setState(() => _at = null),
            child: GestureDetector(
              onTapDown: (d) => setState(() => _at = hit(d.localPosition)),
              onTapUp: (d) {
                final day = hit(d.localPosition);
                if (day != null) widget.onSelect?.call(day);
              },
              child: SizedBox(
                width: left + weeks * step,
                height: top + 7 * step,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _CalendarPainter(
                          weeks: weeks,
                          dayAt: dayAt,
                          first: first,
                          last: last,
                          colorOf: (d) => byDay[d] == null
                              ? faint
                              : _shade(byDay[d]!, lo, hi, faint, strong, widget.steps),
                          cell: widget.cell,
                          step: step,
                          left: left,
                          top: top,
                          names: names,
                          at: _at,
                          ring: c.foreground,
                          style: style,
                        ),
                      ),
                    ),
                    if (_at case final day?)
                      Positioned(
                        left: math.min(
                          left + (day.difference(start).inDays ~/ 7) * step + step,
                          math.max(0, left + weeks * step - 150),
                        ),
                        top: -36,
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: c.foreground,
                              borderRadius: BorderRadius.circular(t.radiusSm),
                            ),
                            child: Text(
                              '${_write(byDay[day] ?? 0)} on ${chartDate(day)} ${day.year}',
                              style: t.text.xs.copyWith(color: c.background),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.scale) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: math.max(left + weeks * step, 160),
              child: _Scale(lo: 'Less', hi: 'More', from: faint, to: strong, steps: widget.steps),
            ),
          ],
        ],
      ),
    );
  }
}

class _CalendarPainter extends CustomPainter {
  _CalendarPainter({
    required this.weeks,
    required this.dayAt,
    required this.first,
    required this.last,
    required this.colorOf,
    required this.cell,
    required this.step,
    required this.left,
    required this.top,
    required this.names,
    required this.at,
    required this.ring,
    required this.style,
  });

  final int weeks;
  final DateTime Function(int week, int weekday) dayAt;
  final DateTime first, last;
  final Color Function(DateTime) colorOf;
  final double cell, step, left, top;
  final List<String> names;
  final DateTime? at;
  final Color ring;
  final TextStyle style;

  void _text(Canvas canvas, String s, Offset o, Alignment a) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, o - Offset((a.x + 1) / 2 * tp.width, (a.y + 1) / 2 * tp.height));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    var lastMonth = -1;
    for (var w = 0; w < weeks; w++) {
      for (var d = 0; d < 7; d++) {
        final day = dayAt(w, d);
        if (day.isBefore(first) || day.isAfter(last)) continue;
        if (day.day <= 7 && d == 0 || (w == 0 && d == 0)) {
          if (day.month != lastMonth && w < weeks - 1) {
            _text(canvas, months[day.month - 1], Offset(left + w * step, top - 4), Alignment.bottomLeft);
            lastMonth = day.month;
          }
        }
        final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(left + w * step, top + d * step, cell, cell),
          const Radius.circular(2),
        );
        canvas.drawRRect(r, Paint()..color = colorOf(day));
        if (day == at) {
          canvas.drawRRect(
            r,
            Paint()
              ..color = ring
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
      }
    }
    for (final (d, s) in names.indexed) {
      if (s.isNotEmpty) {
        _text(canvas, s, Offset(left - 6, top + d * step + cell / 2), Alignment.centerRight);
      }
    }
  }

  @override
  bool shouldRepaint(_CalendarPainter old) => true;
}
