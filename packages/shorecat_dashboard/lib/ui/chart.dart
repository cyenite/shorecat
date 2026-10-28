// Ashlar UI: Chart. Copied into your app by `ashlar add chart`; it is yours to change.
// ashlar: ignore-file. Charts are drawn left to right in any language, as time and
// number lines are read; ashlar check leaves this file out.
//
// Drawn on the canvas here, with no charting package. A chart is your rows and the parts
// you put in it: a grid, axes, a tooltip, a legend, and the series that read their values
// from each row.
//
// ```dart
// typedef Visit = ({String month, double desktop, double mobile});
//
// BarChart<Visit>(
//   data: visits,
//   x: (r) => r.month,
//   children: [
//     CartesianGrid(),
//     XAxis(),
//     ChartTooltip(),
//     Bar(label: 'Desktop', value: (r) => r.desktop, radius: 4),
//     Bar(label: 'Mobile', value: (r) => r.mobile, radius: 4),
//   ],
// )
// ```
//
// Name the row type on the chart (`BarChart<Visit>`): the parts inside take it from there.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'theme.dart';

// ---------------------------------------------------------------------------------------
// What every chart shares
// ---------------------------------------------------------------------------------------

/// Reads one value from a row: `(r) => r.desktop`. Null leaves a gap.
typedef ChartValue<T> = num? Function(T row);

/// Something put in a chart: a series, an axis, the grid, the tooltip, the legend.
abstract class ChartPart<T> {
  const ChartPart();
}

/// A part that gives [ChartTable] a column: a pie, a radar, a radial bar, or a part of
/// your own.
abstract interface class ChartColumn<T> {
  /// The column's heading.
  String get columnName;

  /// The row's value in it.
  num? columnValue(T row);
}

/// How a line goes from one value to the next.
enum ChartCurve {
  /// A smooth curve that never overshoots a value.
  smooth,

  /// Straight from point to point.
  linear,

  /// Level, then up or down halfway between: for values that hold until they change.
  step,

  /// Level until the next value, then straight up or down to it.
  stepAfter,

  /// Straight up or down first, then level to the next value.
  stepBefore,
}

/// The mark beside each value in a tooltip.
enum ChartIndicator {
  /// A small square of the series' colour.
  dot,

  /// A bar of the colour down the side of the rows.
  line,

  /// The same bar, dashed.
  dashed,

  /// No mark.
  none,
}

/// Where a legend sits.
enum ChartLegendPosition { top, bottom }

/// The shape of a point: a scatter's marks, a line's dots.
enum ChartShape { circle, square, diamond, triangle, cross, star }

/// Where a series writes its labels, relative to each bar or point.
enum ChartLabelPosition {
  /// Above a point, or past the end of a bar.
  top,

  /// Below a point, or before the start of a bar.
  bottom,

  /// Left of a point, or before the start of a lying bar.
  left,

  /// Right of a point, or past the end of a lying bar.
  right,

  /// Inside a bar, at its middle.
  inside,

  /// Inside a bar, at its start: where a lying bar begins.
  insideStart,

  /// Inside a bar, at its end.
  insideEnd,
}

/// Text written on a series: each value by default, or what [text] returns for its row.
///
/// ```dart
/// Bar(
///   label: 'Desktop',
///   value: (r) => r.desktop,
///   labels: [
///     ChartLabels(position: ChartLabelPosition.insideStart, text: (r, _) => r.month),
///     ChartLabels(position: ChartLabelPosition.right),
///   ],
/// )
/// ```
@immutable
class ChartLabels<T> {
  const ChartLabels({
    this.position = ChartLabelPosition.top,
    this.text,
    this.color,
    this.offset = 6,
  });

  /// Where the text sits.
  final ChartLabelPosition position;

  /// The text for a row and its value; null writes the value as the chart formats it.
  /// Returning null writes nothing for that row.
  final String? Function(T row, num value)? text;

  /// Null uses the foreground, or the page's colour inside a bar.
  final Color? color;

  /// The gap between the text and its bar or point.
  final double offset;
}

/// A line's dots, or a radar's: how big, what shape, and a colour per row if they
/// each mean something.
@immutable
class ChartDot<T> {
  const ChartDot({
    this.radius = 3,
    this.shape = ChartShape.circle,
    this.colorOf,
    this.icon,
    this.hollow = false,
  });

  final double radius;
  final ChartShape shape;

  /// A colour for each row's dot; null takes the series'.
  final Color? Function(T row)? colorOf;

  /// An icon in place of the dot, drawn from its font.
  final IconData? icon;

  /// A ring of the colour with the page inside.
  final bool hollow;
}

/// What a tooltip shows for one series at one row.
@immutable
class ChartTooltipItem {
  const ChartTooltipItem({
    required this.label,
    required this.value,
    required this.text,
    required this.color,
    this.icon,
  });

  /// The series' name.
  final String label;

  /// The value, as drawn.
  final num value;

  /// The value, written as the chart writes it.
  final String text;
  final Color color;
  final IconData? icon;
}

/// What a tooltip is showing: the row's label and a line per series.
@immutable
class ChartTooltipData<T> {
  const ChartTooltipData({
    required this.title,
    required this.items,
    this.row,
    this.index,
  });

  /// The row's label: its month, say.
  final String title;
  final List<ChartTooltipItem> items;

  /// The row it is about, when there is one.
  final T? row;
  final int? index;
}

/// The tooltip: shown on hover, on a tap, and as the arrow keys step through the rows.
/// Put it in a chart's children.
class ChartTooltip<T> extends ChartPart<T> {
  const ChartTooltip({
    this.indicator = ChartIndicator.dot,
    this.hideLabel = false,
    this.hideIndicator = false,
    this.labelFormatter,
    this.formatter,
    this.total = false,
    this.cursor = true,
    this.shared = true,
    this.builder,
  });

  /// The mark beside each value: a dot, a line, a dashed line or none.
  final ChartIndicator indicator;

  /// False shows the row's label (the month, say) at the top.
  final bool hideLabel;

  /// Hides the marks beside the values.
  final bool hideIndicator;

  /// Writes the label at the top: 'July 2026' for 'Jul'.
  final String Function(String label, T? row)? labelFormatter;

  /// Writes a series' value: '$2,400'. Null uses the chart's format.
  final String Function(num value, String series, T? row)? formatter;

  /// A last row adding the values up.
  final bool total;

  /// The band or line behind the row under the pointer.
  final bool cursor;

  /// Every series at the row (a trackball); false only the one under the pointer.
  final bool shared;

  /// Your own tooltip in place of the card.
  final Widget Function(BuildContext context, ChartTooltipData<T> data)?
  builder;
}

/// The series' names and colours. Each is a button that hides and shows its series,
/// unless [toggle] is false.
class ChartLegend<T> extends ChartPart<T> {
  const ChartLegend({
    this.position = ChartLegendPosition.bottom,
    this.toggle = true,
    this.builder,
  });

  final ChartLegendPosition position;

  /// Tapping a name hides its series.
  final bool toggle;

  /// Your own legend: the items, and whether each is shown.
  final Widget Function(BuildContext context, List<ChartLegendEntry> entries)?
  builder;
}

/// One name in a legend.
@immutable
class ChartLegendEntry {
  const ChartLegendEntry({
    required this.label,
    required this.color,
    this.icon,
    this.shown = true,
    this.onToggle,
  });

  final String label;
  final Color color;
  final IconData? icon;

  /// False when the series is hidden.
  final bool shown;

  /// Hides or shows the series; null when the legend does not toggle.
  final VoidCallback? onToggle;
}

/// What was tapped or chosen with Enter: the row, and the series when one was under the
/// pointer.
@immutable
class ChartSelection<T> {
  const ChartSelection({required this.index, required this.row, this.series});

  final int index;
  final T row;

  /// The series' label, or null for the whole row.
  final String? series;

  @override
  bool operator ==(Object other) =>
      other is ChartSelection<T> &&
      other.index == index &&
      other.series == series;

  @override
  int get hashCode => Object.hash(index, series);
}

/// A number as charts write it: 186, 1.5, 2.4k, 1.2M.
String chartNumber(num v) {
  final a = v.abs().toDouble();
  String trim(double x) {
    final s = x.toStringAsFixed(x >= 100 ? 0 : (x >= 10 ? 1 : 2));
    return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  }

  if (a >= 1e9) return '${v < 0 ? '-' : ''}${trim(a / 1e9)}B';
  if (a >= 1e6) return '${v < 0 ? '-' : ''}${trim(a / 1e6)}M';
  if (a >= 1e4) return '${v < 0 ? '-' : ''}${trim(a / 1e3)}k';
  if (v == v.roundToDouble()) return v.toInt().toString();
  return trim(a) == '0' ? '0' : '${v < 0 ? '-' : ''}${trim(a)}';
}

/// A whole number with thousands marked: 12,480.
String chartThousands(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// A value as a tooltip writes it: whole numbers with thousands marked, others to two
/// places at most.
String chartPlain(num v) {
  if (v == v.roundToDouble()) return chartThousands(v);
  final s = v.toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

String _percent(num v) => '${(v * 100).round()}%';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// A date as an axis writes it, to the detail [step] calls for: 'Mar', '12 Mar',
/// '14:00', '2026'.
String chartDate(DateTime d, {Duration step = const Duration(days: 1)}) {
  String two(int n) => n.toString().padLeft(2, '0');
  if (step >= const Duration(days: 360)) return '${d.year}';
  if (step >= const Duration(days: 28)) {
    return d.month == 1 ? '${_months[0]} ${d.year}' : _months[d.month - 1];
  }
  if (step >= const Duration(days: 1)) {
    return '${d.day} ${_months[d.month - 1]}';
  }
  if (step >= const Duration(minutes: 1)) {
    return '${two(d.hour)}:${two(d.minute)}';
  }
  return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

/// The colour for series [i] when it brings none: the theme's chart colours in turn.
Color chartColor(BuildContext context, int i) {
  final c = AshlarTheme.of(context).colors.charts;
  return c[i % c.length];
}

/// Round steps for a scale from [lo] to [hi], about [count] of them: 1, 2, 2.5 or 5
/// times a power of ten. Returns the ticks, the first at or below [lo] and the last at or
/// above [hi].
List<double> chartTicks(double lo, double hi, {int count = 5}) {
  if (!lo.isFinite || !hi.isFinite) return [0, 1];
  if (hi < lo) (lo, hi) = (hi, lo);
  if (hi == lo) {
    if (hi == 0) return [0, 1];
    final pad = hi.abs() * .1;
    lo -= pad;
    hi += pad;
  }
  final raw = (hi - lo) / math.max(1, count - 1);
  final p = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  var step = 10 * p;
  for (final m in [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (m * p >= raw) {
      step = m * p;
      break;
    }
  }
  final first = (lo / step).floor() * step;
  final last = (hi / step).ceil() * step;
  return [
    for (var v = first; v <= last + step / 2; v += step)
      // Clean off the float noise: 0.30000000000000004.
      double.parse(v.toStringAsPrecision(12)),
  ];
}

/// The card a chart's tooltip is drawn in. Public so your own charts can use it.
class ChartTooltipCard extends StatelessWidget {
  const ChartTooltipCard({
    super.key,
    this.title,
    required this.items,
    this.indicator = ChartIndicator.dot,
    this.total,
  });

  /// Null leaves the title out.
  final String? title;
  final List<ChartTooltipItem> items;
  final ChartIndicator indicator;

  /// A last row adding the values up.
  final String? total;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    Widget mark(Color color, IconData? icon) => switch (indicator) {
      _ when icon != null => ChartIcon(icon, color: color),
      ChartIndicator.dot => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      ChartIndicator.line => Container(width: 4, height: 16, color: color),
      ChartIndicator.dashed => SizedBox(
        width: 4,
        height: 16,
        child: CustomPaint(painter: _Dash(color)),
      ),
      ChartIndicator.none => const SizedBox.shrink(),
    };
    final value = t.text.xs.copyWith(
      color: c.foreground,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return ExcludeSemantics(
      child: Container(
        constraints: const BoxConstraints(minWidth: 128),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: BorderRadius.circular(t.radiusMd),
          border: Border.all(
            color: c.border.withValues(alpha: c.border.a * .5),
          ),
          boxShadow: t.shadowLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(
                title!,
                style: t.text.xs.copyWith(
                  fontWeight: FontWeight.w500,
                  color: c.foreground,
                ),
              ),
              const SizedBox(height: 4),
            ],
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    mark(item.color, item.icon),
                    if (indicator != ChartIndicator.none || item.icon != null)
                      const SizedBox(width: 8),
                    Text(
                      item.label,
                      style: t.text.xs.copyWith(color: c.mutedForeground),
                    ),
                    const SizedBox(width: 16),
                    Text(item.text, style: value),
                  ],
                ),
              ),
            if (total != null) ...[
              const SizedBox(height: 4),
              Container(height: 1, width: 120, color: c.border),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Total',
                    style: t.text.xs.copyWith(
                      color: c.foreground,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(total!, style: value),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// An icon drawn from its font at the size of a legend's swatch.
class ChartIcon extends StatelessWidget {
  const ChartIcon(this.icon, {super.key, required this.color, this.size = 12});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
    String.fromCharCode(icon.codePoint),
    style: TextStyle(
      fontFamily: icon.fontFamily,
      package: icon.fontPackage,
      fontSize: size,
      height: 1,
      color: color,
    ),
  );
}

class _Dash extends CustomPainter {
  const _Dash(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var y = 0.0; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 2), paint);
    }
  }

  @override
  bool shouldRepaint(_Dash old) => old.color != color;
}

/// A legend: the names and colours, each a button when it can hide its series. Public
/// so your own charts can use it.
class ChartLegendView extends StatelessWidget {
  const ChartLegendView({super.key, required this.entries});

  final List<ChartLegendEntry> entries;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    Widget item(ChartLegendEntry e) {
      final row = Opacity(
        opacity: e.shown ? 1 : .4,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (e.icon != null)
              ChartIcon(e.icon!, color: e.color)
            else
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: e.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            const SizedBox(width: 6),
            Text(
              e.label,
              style: t.text.xs.copyWith(
                color: c.foreground,
                decoration: e.shown ? null : TextDecoration.lineThrough,
              ),
            ),
          ],
        ),
      );
      if (e.onToggle == null) return ExcludeSemantics(child: row);
      // A button: pressed, tapped, or Enter or Space from the keyboard.
      return Semantics(
        button: true,
        toggled: e.shown,
        label: e.label,
        excludeSemantics: true,
        onTap: e.onToggle,
        child: _LegendButton(onPressed: e.onToggle!, child: row),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 4,
      children: [for (final e in entries) item(e)],
    );
  }
}

class _LegendButton extends StatefulWidget {
  const _LegendButton({required this.onPressed, required this.child});

  final VoidCallback onPressed;
  final Widget child;

  @override
  State<_LegendButton> createState() => _LegendButtonState();
}

class _LegendButtonState extends State<_LegendButton> {
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onPressed(),
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.radiusSm),
            border: Border.all(
              color: _focused
                  ? t.colors.ring
                  : t.colors.ring.withValues(alpha: 0),
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Places a tooltip by a point, kept inside [width]: right of it, or left near the edge.
class _Floating extends StatelessWidget {
  const _Floating({required this.at, required this.width, required this.child});

  final Offset at;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final right = at.dx > width * .6;
    return Positioned(
      top: math.max(0, at.dy),
      left: right ? null : at.dx + 12,
      right: right ? width - at.dx + 12 : null,
      child: IgnorePointer(child: child),
    );
  }
}

/// Writes [s] at [at] on a canvas, placed by [align] (topLeft puts its top left corner
/// there). For drawing charts of your own.
void chartText(
  Canvas canvas,
  String s,
  Offset at,
  TextStyle style, [
  Alignment align = Alignment.center,
]) {
  final p = TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  p.paint(
    canvas,
    at - Offset((align.x + 1) / 2 * p.width, (align.y + 1) / 2 * p.height),
  );
}

double _textWidth(String s, TextStyle style) => (TextPainter(
  text: TextSpan(text: s, style: style),
  textDirection: TextDirection.ltr,
)..layout()).width;

/// Draws [shape] of radius [r] at [c]: a chart's dot or mark.
void chartMark(
  Canvas canvas,
  ChartShape shape,
  Offset c,
  double r,
  Paint paint,
) {
  switch (shape) {
    case ChartShape.circle:
      canvas.drawCircle(c, r, paint);
    case ChartShape.square:
      canvas.drawRect(Rect.fromCircle(center: c, radius: r * .9), paint);
    case ChartShape.diamond:
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - r * 1.2)
          ..lineTo(c.dx + r * 1.2, c.dy)
          ..lineTo(c.dx, c.dy + r * 1.2)
          ..lineTo(c.dx - r * 1.2, c.dy)
          ..close(),
        paint,
      );
    case ChartShape.triangle:
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - r * 1.2)
          ..lineTo(c.dx + r * 1.1, c.dy + r * .8)
          ..lineTo(c.dx - r * 1.1, c.dy + r * .8)
          ..close(),
        paint,
      );
    case ChartShape.cross:
      final w = r * .45;
      canvas.drawPath(
        Path()
          ..addRect(Rect.fromCenter(center: c, width: r * 2, height: w * 2))
          ..addRect(Rect.fromCenter(center: c, width: w * 2, height: r * 2)),
        paint,
      );
    case ChartShape.star:
      final p = Path();
      for (var i = 0; i < 10; i++) {
        final a = -math.pi / 2 + i * math.pi / 5;
        final d = i.isEven ? r * 1.3 : r * .55;
        final q = c + Offset(math.cos(a), math.sin(a)) * d;
        i == 0 ? p.moveTo(q.dx, q.dy) : p.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(p..close(), paint);
  }
}

/// Draws [icon] centred on [c] at [size], from its font.
void chartGlyph(
  Canvas canvas,
  IconData icon,
  Offset c,
  double size,
  Color color,
) {
  chartText(
    canvas,
    String.fromCharCode(icon.codePoint),
    c,
    TextStyle(
      fontFamily: icon.fontFamily,
      package: icon.fontPackage,
      fontSize: size,
      height: 1,
      color: color,
    ),
  );
}

/// A path through [p]: straight, stepped, or a smooth curve that never overshoots. With
/// [across], the curve is smooth along y (for lying layouts).
Path _through(List<Offset> p, ChartCurve curve, {bool across = false}) {
  final path = Path()..moveTo(p.first.dx, p.first.dy);
  switch (curve) {
    case ChartCurve.step:
      for (var i = 1; i < p.length; i++) {
        if (across) {
          final mid = (p[i - 1].dy + p[i].dy) / 2;
          path
            ..lineTo(p[i - 1].dx, mid)
            ..lineTo(p[i].dx, mid)
            ..lineTo(p[i].dx, p[i].dy);
        } else {
          final mid = (p[i - 1].dx + p[i].dx) / 2;
          path
            ..lineTo(mid, p[i - 1].dy)
            ..lineTo(mid, p[i].dy)
            ..lineTo(p[i].dx, p[i].dy);
        }
      }
      return path;
    case ChartCurve.stepAfter:
      for (var i = 1; i < p.length; i++) {
        across
            ? path.lineTo(p[i - 1].dx, p[i].dy)
            : path.lineTo(p[i].dx, p[i - 1].dy);
        path.lineTo(p[i].dx, p[i].dy);
      }
      return path;
    case ChartCurve.stepBefore:
      for (var i = 1; i < p.length; i++) {
        across
            ? path.lineTo(p[i].dx, p[i - 1].dy)
            : path.lineTo(p[i - 1].dx, p[i].dy);
        path.lineTo(p[i].dx, p[i].dy);
      }
      return path;
    case ChartCurve.linear:
      for (final q in p.skip(1)) {
        path.lineTo(q.dx, q.dy);
      }
      return path;
    case ChartCurve.smooth:
      if (p.length < 3) {
        for (final q in p.skip(1)) {
          path.lineTo(q.dx, q.dy);
        }
        return path;
      }
      // Monotone cubic: tangents from neighbouring slopes, flattened at peaks and
      // troughs, so the curve never overshoots a value.
      double along(Offset o) => across ? o.dy : o.dx;
      double up(Offset o) => across ? o.dx : o.dy;
      final m = <double>[];
      double slope(int a, int b) {
        final d = along(p[b]) - along(p[a]);
        return d == 0 ? 0 : (up(p[b]) - up(p[a])) / d;
      }

      for (var i = 0; i < p.length; i++) {
        if (i == 0) {
          m.add(slope(0, 1));
        } else if (i == p.length - 1) {
          m.add(slope(i - 1, i));
        } else {
          final a = slope(i - 1, i), b = slope(i, i + 1);
          m.add(a * b <= 0 ? 0 : (a + b) / 2);
        }
      }
      for (var i = 0; i < p.length - 1; i++) {
        final d = (along(p[i + 1]) - along(p[i])) / 3;
        if (across) {
          path.cubicTo(
            p[i].dx + m[i] * d,
            p[i].dy + d,
            p[i + 1].dx - m[i + 1] * d,
            p[i + 1].dy - d,
            p[i + 1].dx,
            p[i + 1].dy,
          );
        } else {
          path.cubicTo(
            p[i].dx + d,
            p[i].dy + m[i] * d,
            p[i + 1].dx - d,
            p[i + 1].dy - m[i + 1] * d,
            p[i + 1].dx,
            p[i + 1].dy,
          );
        }
      }
      return path;
  }
}

/// A dashed copy of [source]: [on] pixels drawn, [off] skipped.
Path chartDashed(Path source, {double on = 4, double off = 4}) {
  final out = Path();
  for (final m in source.computeMetrics()) {
    var d = 0.0;
    while (d < m.length) {
      out.addPath(m.extractPath(d, math.min(d + on, m.length)), Offset.zero);
      d += on + off;
    }
  }
  return out;
}

/// Starts a chart's growing in, or shows it whole when motion is reduced: [grown] runs from
/// 0 to 1 as it appears. For charts in other files, and charts of your own.
mixin ChartGrowth<W extends StatefulWidget>
    on State<W>, TickerProviderStateMixin<W> {
  late final grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  bool get still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (still) {
      grow.value = 1;
    } else if (grow.isDismissed) {
      grow.forward();
    }
  }

  @override
  void dispose() {
    grow.dispose();
    super.dispose();
  }

  double get grown => Curves.easeOutCubic.transform(grow.value);
}

// ---------------------------------------------------------------------------------------
// Cartesian charts: rows along one axis, values up the other
// ---------------------------------------------------------------------------------------

/// What an axis's values are.
enum AxisType {
  /// Each row in its own place, evenly spaced: months, names. Dates given as categories
  /// stay evenly spaced too, gaps and all (a trading week without its weekends).
  category,

  /// Numbers, placed by size.
  number,

  /// Dates, placed by when they fall: 1, 2 and 9 March are not evenly spaced.
  time,

  /// Numbers by their powers of ten, for values that run from 1 to a million.
  log,
}

/// Which way a chart lies.
enum ChartLayout {
  /// Rows along the bottom, values up the side: upright bars.
  horizontal,

  /// Rows down the side, values along the bottom: lying bars.
  vertical,
}

/// How stacked series add up.
enum StackOffset {
  /// Each on the one below.
  none,

  /// Each row's stack as shares of its whole, up to 100%.
  expand,
}

/// The axis of the rows: along the bottom, or down the side when the chart lies
/// ([ChartLayout.vertical]). Without one, no labels are drawn.
class XAxis<T> extends ChartPart<T> {
  const XAxis({
    this.type,
    this.hide = false,
    this.tickFormatter,
    this.tickCount,
    this.interval,
    this.tickLine = false,
    this.axisLine = false,
    this.tickMargin = 8,
    this.domain,
    this.last,
    this.top = false,
    this.width,
  });

  /// Null works it out from the values: text is a category, a number a number, a
  /// [DateTime] time.
  final AxisType? type;

  /// Keeps the axis's room and scale but draws nothing.
  final bool hide;

  /// Writes a label: `(v) => (v as String).substring(0, 3)`.
  final String Function(Object value)? tickFormatter;

  /// About how many labels a number or time axis writes; null fits them to the width.
  final int? tickCount;

  /// Every how many categories a label is written: 1 writes each one. Null fits them.
  final int? interval;

  /// A short line at each label.
  final bool tickLine;

  /// A line along the axis.
  final bool axisLine;

  /// The gap between the plot and the labels.
  final double tickMargin;

  /// Where a number or time axis starts and ends; null ends at the data. Give numbers
  /// or [DateTime]s.
  final (Object?, Object?)? domain;

  /// Shows only the last [last] rows, and follows as rows arrive: a live chart scrolls
  /// itself. Pan or zoom (`zoom: true`) to see earlier ones.
  final int? last;

  /// Along the top in place of the bottom.
  final bool top;

  /// The room for labels down the side of a lying chart; null fits the longest, up
  /// to 120.
  final double? width;
}

/// An axis of values: up the side, or along the bottom when the chart lies. Give each
/// one after the first an [id], and series name it in their `yAxisId`.
class YAxis<T> extends ChartPart<T> {
  const YAxis({
    this.id = '',
    this.type = AxisType.number,
    this.right = false,
    this.hide = false,
    this.tickFormatter,
    this.tickCount = 5,
    this.tickLine = false,
    this.axisLine = false,
    this.tickMargin = 8,
    this.domain,
    this.width,
    this.zero,
  });

  /// The name series use to sit on this axis.
  final String id;

  /// [AxisType.number] or [AxisType.log].
  final AxisType type;

  /// On the right of the plot (or at the top of a lying one), for a second scale.
  final bool right;

  /// Keeps the scale but draws nothing.
  final bool hide;

  /// Writes a value: `(v) => '\$${v}k'`.
  final String Function(num value)? tickFormatter;

  /// About how many steps the scale has.
  final int tickCount;
  final bool tickLine;
  final bool axisLine;
  final double tickMargin;

  /// Where the scale starts and ends; null either end to fit the data.
  final (num?, num?)? domain;

  /// The room for the labels; null fits the widest.
  final double? width;

  /// Whether the scale starts at zero. Null: it does for bars and areas, and not for
  /// prices, boxes, scatters and ranges.
  final bool? zero;
}

/// Lines across the plot at the steps of the scale.
class CartesianGrid<T> extends ChartPart<T> {
  const CartesianGrid({
    this.horizontal = true,
    this.vertical = false,
    this.dashed = false,
  });

  /// Lines across the page.
  final bool horizontal;

  /// Lines up the page.
  final bool vertical;
  final bool dashed;
}

/// A run of values read from the rows: a [Bar], [Line], [Area], [Scatter],
/// [Candlestick], [BoxPlot] or [Waterfall].
abstract class CartesianSeries<T> extends ChartPart<T> {
  const CartesianSeries({
    required this.label,
    this.value,
    this.values,
    this.color,
    this.icon,
    this.yAxisId = '',
    this.labels = const [],
    this.hide = false,
  });

  /// The series' name, in the legend, the tooltip and what a screen reader hears.
  final String label;

  /// Reads the value from a row: `(r) => r.desktop`.
  final ChartValue<T>? value;

  /// The values themselves, one per row, in place of [value]: for values worked out
  /// elsewhere, such as an indicator's.
  final List<num?>? values;

  /// Null takes the theme's chart colours in turn.
  final Color? color;

  /// Shown in the legend and the tooltip in place of the swatch.
  final IconData? icon;

  /// The [YAxis] it sits on.
  final String yAxisId;

  /// Text written on each bar or point.
  final List<ChartLabels<T>> labels;

  /// Starts hidden, as if its legend item were tapped.
  final bool hide;
}

/// Bars: side by side, or stacked when they share a [stackId]; floating between [low]
/// and the value when [low] is given (a range).
class Bar<T> extends CartesianSeries<T> {
  const Bar({
    required super.label,
    super.value,
    super.values,
    super.color,
    super.icon,
    super.yAxisId,
    super.labels,
    super.hide,
    this.low,
    this.stackId,
    this.radius = 4,
    this.colorOf,
    this.track = false,
    this.error,
    this.errorBelow,
  });

  /// Where each bar starts, for a range: from low to the value.
  final ChartValue<T>? low;

  /// Bars with the same stack id sit on each other.
  final String? stackId;

  /// The rounding of the bar's far end.
  final double radius;

  /// A colour for each row's bar: bars that each mean something of their own.
  final Color? Function(T row)? colorOf;

  /// A faint full-height bar behind each one.
  final bool track;

  /// An error bar: how far above (and below, unless [errorBelow]) the value it may be.
  final ChartValue<T>? error;
  final ChartValue<T>? errorBelow;
}

/// A line through each row's value.
class Line<T> extends CartesianSeries<T> {
  const Line({
    required super.label,
    super.value,
    super.values,
    super.color,
    super.icon,
    super.yAxisId,
    super.labels,
    super.hide,
    this.curve = ChartCurve.smooth,
    this.dots = false,
    this.dot,
    this.width = 2,
    this.dashed = false,
    this.connectNulls = false,
    this.stackId,
    this.error,
    this.errorBelow,
  });

  final ChartCurve curve;

  /// A dot on each value.
  final bool dots;

  /// The dots' size, shape and colours; giving one draws them.
  final ChartDot<T>? dot;

  /// The line's thickness.
  final double width;
  final bool dashed;

  /// Joins across rows with no value, in place of leaving a gap.
  final bool connectNulls;

  /// Lines with the same stack id sit on each other.
  final String? stackId;
  final ChartValue<T>? error;
  final ChartValue<T>? errorBelow;
}

/// A line with the area under it filled; between [low] and the value when [low] is
/// given (a range); on the area below when they share a [stackId].
class Area<T> extends CartesianSeries<T> {
  const Area({
    required super.label,
    super.value,
    super.values,
    super.color,
    super.icon,
    super.yAxisId,
    super.labels,
    super.hide,
    this.low,
    this.curve = ChartCurve.smooth,
    this.stackId,
    this.gradient = true,
    this.opacity = .4,
    this.dots = false,
    this.dot,
    this.width = 2,
    this.dashed = false,
    this.connectNulls = false,
  });

  final ChartValue<T>? low;
  final ChartCurve curve;
  final String? stackId;

  /// Fades to nothing at the bottom; false fills evenly.
  final bool gradient;

  /// How strong the fill is, at its strongest.
  final double opacity;
  final bool dots;
  final ChartDot<T>? dot;
  final double width;
  final bool dashed;
  final bool connectNulls;
}

/// A mark at each row's x and value; sized by [size], it is a bubble chart.
class Scatter<T> extends CartesianSeries<T> {
  const Scatter({
    required super.label,
    super.value,
    super.values,
    super.color,
    super.icon,
    super.yAxisId,
    super.labels,
    super.hide,
    this.size,
    this.minRadius = 4,
    this.maxRadius = 24,
    this.shape = ChartShape.circle,
    this.colorOf,
    this.opacity = .85,
    this.error,
    this.errorBelow,
  });

  /// A third measure, as each mark's area.
  final ChartValue<T>? size;
  final double minRadius;
  final double maxRadius;
  final ChartShape shape;
  final Color? Function(T row)? colorOf;
  final double opacity;
  final ChartValue<T>? error;
  final ChartValue<T>? errorBelow;
}

/// How prices are drawn.
enum PriceStyle {
  /// A body from open to close, wicks to the high and low. Rising bodies are hollow.
  candle,

  /// A line from low to high, the open ticked left and the close right.
  ohlc,

  /// A line from low to high only.
  hilo,
}

/// Prices by row: open, high, low and close.
class Candlestick<T> extends CartesianSeries<T> {
  const Candlestick({
    required super.label,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    super.color,
    super.icon,
    super.yAxisId,
    super.hide,
    this.style = PriceStyle.candle,
    this.risingColor,
    this.fallingColor,
  }) : super(value: close);

  final ChartValue<T> open;
  final ChartValue<T> high;
  final ChartValue<T> low;
  final ChartValue<T> close;
  final PriceStyle style;

  /// Null: the series' colour, hollow.
  final Color? risingColor;

  /// Null: the series' colour, filled.
  final Color? fallingColor;
}

/// Open, high, low and close as ticks on a line: [Candlestick] drawn the OHLC way.
class Ohlc<T> extends Candlestick<T> {
  const Ohlc({
    required super.label,
    required super.open,
    required super.high,
    required super.low,
    required super.close,
    super.color,
    super.icon,
    super.yAxisId,
    super.hide,
    super.risingColor,
    super.fallingColor,
  }) : super(style: PriceStyle.ohlc);
}

/// High and low as a line: [Candlestick] drawn the HiLo way. Open and close are read
/// for the tooltip.
class HiLo<T> extends Candlestick<T> {
  const HiLo({
    required super.label,
    required super.high,
    required super.low,
    ChartValue<T>? open,
    ChartValue<T>? close,
    super.color,
    super.icon,
    super.yAxisId,
    super.hide,
  }) : super(open: open ?? low, close: close ?? high, style: PriceStyle.hilo);
}

/// A box and whiskers per row, from the row's samples: the middle half in the box, the
/// median across it, whiskers to the furthest samples within one and a half boxes, and
/// the rest as dots.
class BoxPlot<T> extends CartesianSeries<T> {
  const BoxPlot({
    required super.label,
    required this.samples,
    super.color,
    super.icon,
    super.yAxisId,
    super.hide,
    this.mean = true,
    this.outliers = true,
  });

  final List<num> Function(T row) samples;

  /// A cross at the mean.
  final bool mean;

  /// Dots for samples beyond the whiskers.
  final bool outliers;
}

/// Changes that add up: each bar starts where the last ended. Rows that [total] picks
/// stand from zero at the running sum.
class Waterfall<T> extends CartesianSeries<T> {
  const Waterfall({
    required super.label,
    required super.value,
    super.color,
    super.icon,
    super.yAxisId,
    super.labels,
    super.hide,
    this.total,
    this.fallingColor,
    this.totalColor,
    this.connectors = true,
    this.radius = 4,
  });

  final bool Function(T row)? total;

  /// Null: the theme's destructive colour.
  final Color? fallingColor;

  /// Null: the foreground, faded.
  final Color? totalColor;

  /// Dashed lines from each bar's end to the next one's start.
  final bool connectors;
  final double radius;
}

/// A series worked out from the rows: an indicator, say. It is given the rows and
/// returns the series to draw.
abstract class DerivedSeries<T> extends ChartPart<T> {
  const DerivedSeries();

  List<CartesianSeries<T>> derive(List<T> data);
}

/// The kinds of trend a [Trendline] fits.
enum TrendKind {
  linear,

  /// Growing by a share each step.
  exponential,
  logarithmic,

  /// A curve of [Trendline.order].
  polynomial,
  power,

  /// The mean of the last [Trendline.period] values.
  movingAverage,
}

/// The trend through a run of values, drawn over the chart and, with [forward], beyond
/// it.
class Trendline<T> extends ChartPart<T> {
  const Trendline({
    required this.value,
    this.kind = TrendKind.linear,
    this.label,
    this.color,
    this.yAxisId = '',
    this.order = 2,
    this.period = 3,
    this.forward = 0,
    this.backward = 0,
    this.dashed = true,
  });

  final ChartValue<T> value;
  final TrendKind kind;

  /// Its name in the legend; null leaves it out.
  final String? label;
  final Color? color;
  final String yAxisId;

  /// The polynomial's degree, 2 to 6.
  final int order;

  /// The moving average's window, in rows.
  final int period;

  /// How far it runs past the last row, in rows for categories and in the axis's units
  /// otherwise (milliseconds for time).
  final num forward;
  final num backward;
  final bool dashed;
}

/// A line across the plot at a value ([y]) or a row ([x]): a target, an average, a
/// day something happened.
class ReferenceLine<T> extends ChartPart<T> {
  const ReferenceLine({
    this.x,
    this.y,
    this.yAxisId = '',
    this.label,
    this.color,
    this.dashed = true,
  }) : assert(x != null || y != null);

  /// A row's x: a category, a number or a [DateTime].
  final Object? x;
  final num? y;
  final String yAxisId;
  final String? label;
  final Color? color;
  final bool dashed;
}

/// A band across the plot: between two values ([y1], [y2]), two rows ([x1], [x2]), or
/// both. Leave an end out to run to the plot's edge.
class ReferenceArea<T> extends ChartPart<T> {
  const ReferenceArea({
    this.x1,
    this.x2,
    this.y1,
    this.y2,
    this.yAxisId = '',
    this.label,
    this.color,
    this.opacity = .12,
  });

  final Object? x1, x2;
  final num? y1, y2;
  final String yAxisId;
  final String? label;
  final Color? color;
  final double opacity;
}

/// A mark at one row's value.
class ReferenceDot<T> extends ChartPart<T> {
  const ReferenceDot({
    required this.x,
    required this.y,
    this.yAxisId = '',
    this.radius = 5,
    this.label,
    this.color,
  });

  final Object x;
  final num y;
  final String yAxisId;
  final double radius;
  final String? label;
  final Color? color;
}

/// A widget placed on the chart at a row ([x]) and a value ([y]): a note, a badge, an
/// icon. [alignment] is the point of the widget that sits there.
class ChartAnnotation<T> extends ChartPart<T> {
  const ChartAnnotation({
    required this.x,
    required this.y,
    required this.child,
    this.yAxisId = '',
    this.alignment = Alignment.bottomCenter,
  });

  final Object x;
  final num y;
  final String yAxisId;
  final Widget child;
  final Alignment alignment;
}

/// A small chart of every row under the plot, with a window to drag and resize: the
/// plot shows what the window covers.
class Brush<T> extends ChartPart<T> {
  const Brush({this.height = 40, this.startIndex, this.endIndex});

  final double height;

  /// The rows the window starts on; null shows them all.
  final int? startIndex, endIndex;
}

/// Lines through the pointer, with the row and the value written on the axes.
class Crosshair<T> extends ChartPart<T> {
  const Crosshair({this.dashed = true});

  final bool dashed;
}

/// A chart of rows along one axis and values up the other: bars, lines, areas, marks,
/// prices, boxes and waterfalls, in any mix. [BarChart], [LineChart], [AreaChart],
/// [ComposedChart] and [ScatterChart] are this, named for what they mostly draw.
///
/// ```dart
/// ComposedChart<Sale>(
///   data: sales,
///   x: (r) => r.month,
///   children: [
///     XAxis(),
///     YAxis(),
///     YAxis(id: 'growth', right: true, tickFormatter: (v) => '$v%'),
///     ChartTooltip(),
///     Bar(label: 'Revenue', value: (r) => r.revenue),
///     Line(label: 'Growth', value: (r) => r.growth, yAxisId: 'growth'),
///   ],
/// )
/// ```
class CartesianChart<T> extends StatefulWidget {
  const CartesianChart({
    super.key,
    required this.data,
    required this.x,
    required this.children,
    this.height = 250,
    this.layout = ChartLayout.horizontal,
    this.stackOffset = StackOffset.none,
    this.barGap = 4,
    this.barCategoryGap = .2,
    this.active,
    this.zoom = false,
    this.onSelect,
    this.onReachStart,
    this.format,
    this.semanticLabel,
  });

  /// The rows, in order along the x axis.
  final List<T> data;

  /// Reads a row's place along the axis: a category (text), a number or a [DateTime].
  final Object Function(T row) x;

  /// The parts: grid, axes, tooltip, legend, series, reference lines and the rest.
  final List<ChartPart<T>> children;

  /// The plot's height with its axes, without the legend.
  final double height;

  /// Upright or lying.
  final ChartLayout layout;

  /// Stacked series on each other, or as shares of their whole.
  final StackOffset stackOffset;

  /// The gap between bars of one row, in pixels.
  final double barGap;

  /// The share of a row's room left between rows' bars.
  final double barCategoryGap;

  /// One row drawn full and the rest faded: the one being talked about.
  final int? active;

  /// Zoom with the wheel or a pinch, pan by dragging; a double tap shows everything
  /// again.
  final bool zoom;

  /// Called when a row (and the series under the pointer, if any) is tapped or chosen
  /// with Enter; null when it is tapped again to let it go. The chosen row stays
  /// drawn full.
  final ValueChanged<ChartSelection<T>?>? onSelect;

  /// Called when the chart is panned to its first row: load earlier rows and put them
  /// at the start of [data]. The view stays where it was.
  final FutureOr<void> Function()? onReachStart;

  /// How a value is written in the tooltip, on the chart and read out: "$2,400".
  /// Shares are written as percentages unless you say.
  final String Function(num value)? format;

  /// What the chart shows, read before its values: 'Visitors by month'.
  final String? semanticLabel;

  @override
  State<CartesianChart<T>> createState() => _CartesianState<T>();
}

/// Bars by row, side by side or stacked.
class BarChart<T> extends CartesianChart<T> {
  const BarChart({
    super.key,
    required super.data,
    required super.x,
    required super.children,
    super.height,
    super.layout,
    super.stackOffset,
    super.barGap,
    super.barCategoryGap,
    super.active,
    super.zoom,
    super.onSelect,
    super.onReachStart,
    super.format,
    super.semanticLabel,
  });
}

/// Lines through each series' values.
class LineChart<T> extends CartesianChart<T> {
  const LineChart({
    super.key,
    required super.data,
    required super.x,
    required super.children,
    super.height,
    super.layout,
    super.stackOffset,
    super.active,
    super.zoom,
    super.onSelect,
    super.onReachStart,
    super.format,
    super.semanticLabel,
  });
}

/// Lines with the area under them filled.
class AreaChart<T> extends CartesianChart<T> {
  const AreaChart({
    super.key,
    required super.data,
    required super.x,
    required super.children,
    super.height,
    super.layout,
    super.stackOffset,
    super.active,
    super.zoom,
    super.onSelect,
    super.onReachStart,
    super.format,
    super.semanticLabel,
  });
}

/// Bars, lines and areas together.
class ComposedChart<T> extends CartesianChart<T> {
  const ComposedChart({
    super.key,
    required super.data,
    required super.x,
    required super.children,
    super.height,
    super.layout,
    super.stackOffset,
    super.barGap,
    super.barCategoryGap,
    super.active,
    super.zoom,
    super.onSelect,
    super.onReachStart,
    super.format,
    super.semanticLabel,
  });
}

/// Marks at each row's x and value: two measures against each other, or three with
/// sized marks (bubbles).
class ScatterChart<T> extends CartesianChart<T> {
  const ScatterChart({
    super.key,
    required super.data,
    required super.x,
    required super.children,
    super.height,
    super.zoom,
    super.onSelect,
    super.format,
    super.semanticLabel,
  });
}

// The engine: rows and parts in, scales and shapes out.

enum _Kind { bar, line, area, scatter, price, box, waterfall }

class _Box {
  _Box(List<num> samples) {
    final s = [for (final v in samples) v.toDouble()]..sort();
    double q(double p) {
      final at = (s.length - 1) * p;
      final lo = at.floor(), hi = at.ceil();
      return s[lo] + (s[hi] - s[lo]) * (at - lo);
    }

    q1 = q(.25);
    median = q(.5);
    q3 = q(.75);
    mean = s.fold<double>(0, (a, v) => a + v) / s.length;
    final reach = (q3 - q1) * 1.5;
    final inside = s.where((v) => v >= q1 - reach && v <= q3 + reach);
    min = inside.isEmpty ? q1 : inside.first;
    max = inside.isEmpty ? q3 : inside.last;
    out = [
      for (final v in s)
        if (v < min || v > max) v,
    ];
  }

  late final double q1, median, q3, mean, min, max;
  late final List<double> out;

  double get low => out.isEmpty ? min : math.min(min, out.first);
  double get high => out.isEmpty ? max : math.max(max, out.last);
}

/// One series, read from the rows for this build.
class _Series {
  _Series(this.kind, this.part, this.index, this.color, int n)
    : top = List.filled(n, null),
      bottom = List.filled(n, null),
      raw = List.filled(n, null);

  final _Kind kind;
  final CartesianSeries<dynamic> part;
  final int index;
  final Color color;

  /// Where each row's bar or point ends, and starts (null: from zero), in axis units.
  final List<double?> top, bottom;

  /// The value itself, for the tooltip and labels.
  final List<double?> raw;
  List<double?>? low;
  List<Color?>? colors;
  List<double?>? radii;
  List<double?>? open, high, lowPrice, close;
  List<_Box?>? boxes;
  List<bool>? totals;
  List<double?>? errHi, errLo;
  final labels = <(ChartLabels<dynamic>, List<String?>)>[];

  /// Bars: which group of a row's room this one takes, of how many.
  int group = 0, groups = 1;

  String get label => part.label;
  String get axis => part.yAxisId;
  bool get barLike =>
      kind == _Kind.bar || kind == _Kind.waterfall || kind == _Kind.box;
}

/// A value axis's scale.
class _YScale {
  _YScale(this.id, this.part);

  final String id;
  final YAxis<dynamic>? part;
  double lo = 0, hi = 1;
  List<double> ticks = const [0, 1];
  double room = 0;

  bool get log => part?.type == AxisType.log;
  bool get right => part?.right ?? false;
  bool get shown => part != null && !part!.hide;

  /// From axis units (powers of ten on a log axis) to 0 at the start and 1 at the end.
  double frac(double v) => hi == lo ? 0 : (v - lo) / (hi - lo);

  /// A value as the axis holds it: its power of ten on a log axis.
  double? hold(num? v) {
    if (v == null) return null;
    if (!log) return v.toDouble();
    return v > 0 ? math.log(v) / math.ln10 : null;
  }

  /// Back from axis units to the value.
  double give(double v) => log ? math.pow(10, v).toDouble() : v;
}

class _CartesianState<T> extends State<CartesianChart<T>>
    with TickerProviderStateMixin, ChartGrowth<CartesianChart<T>> {
  late final _morph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..value = 1;
  Map<String, (List<double?>, List<double?>)> _from = const {};
  Map<String, (List<double?>, List<double?>)> _drawn = const {};

  final _hidden = <String>{};
  int? _at;
  String? _atSeries;
  Offset? _pointer;
  bool _focused = false;
  ChartSelection<T>? _selected;

  /// What the plot shows along x, in axis units; null for everything (or [XAxis.last]).
  (double, double)? _window;
  bool _loading = false;
  double _pinchWidth = 0;

  @override
  void initState() {
    super.initState();
    _morph.addListener(() => setState(() {}));
    for (final p in widget.children) {
      if (p is CartesianSeries<T> && p.hide) _hidden.add(p.label);
    }
  }

  @override
  void didUpdateWidget(CartesianChart<T> old) {
    super.didUpdateWidget(old);
    if (!identical(old.data, widget.data)) {
      // Rows put in front (loaded by onReachStart) keep the view where it was.
      final w = _window;
      if (w != null && old.data.isNotEmpty && widget.data.isNotEmpty) {
        final first = old.x(old.data.first);
        if (first is String) {
          final k = widget.data.indexWhere((r) => widget.x(r) == first);
          if (k > 0) _window = (w.$1 + k, w.$2 + k);
        }
      }
      if (!still && _drawn.isNotEmpty) {
        _from = _drawn;
        _morph.forward(from: 0);
      }
      _at = null;
    }
  }

  @override
  void dispose() {
    _morph.dispose();
    super.dispose();
  }

  String Function(num) get _format =>
      widget.format ??
      (widget.stackOffset == StackOffset.expand ? _percent : chartPlain);

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final data = widget.data;
    final n = data.length;
    final across = widget.layout == ChartLayout.vertical;

    // The parts, sorted.
    XAxis<T>? xAxis;
    final yAxes = <String, YAxis<T>>{};
    CartesianGrid<T>? grid;
    ChartTooltip<T>? tooltip;
    ChartLegend<T>? legend;
    Brush<T>? brush;
    Crosshair<T>? crosshair;
    final parts = <CartesianSeries<T>>[];
    final trends = <Trendline<T>>[];
    final refs = <ChartPart<T>>[];
    final notes = <ChartAnnotation<T>>[];
    for (final p in widget.children) {
      switch (p) {
        case XAxis<T>():
          xAxis ??= p;
        case YAxis<T>():
          yAxes.putIfAbsent(p.id, () => p);
        case CartesianGrid<T>():
          grid = p;
        case ChartTooltip<T>():
          tooltip = p;
        case ChartLegend<T>():
          legend = p;
        case Brush<T>():
          brush = p;
        case Crosshair<T>():
          crosshair = p;
        case CartesianSeries<T>():
          parts.add(p);
        case DerivedSeries<T>():
          parts.addAll(p.derive(data));
        case Trendline<T>():
          trends.add(p);
        case ReferenceLine<T>() || ReferenceArea<T>() || ReferenceDot<T>():
          refs.add(p);
        case ChartAnnotation<T>():
          notes.add(p);
        default:
          break;
      }
    }

    // Along x: each row's place, in axis units.
    final xs = [for (final r in data) widget.x(r)];
    final first = xs.isEmpty ? null : xs.first;
    final type =
        xAxis?.type ??
        switch (first) {
          DateTime() => AxisType.time,
          num() => AxisType.number,
          _ => AxisType.category,
        };
    final band = type == AxisType.category;
    double? place(Object? v, [int? i]) => switch (type) {
      AxisType.category =>
        i != null ? i + .5 : (xs.contains(v) ? xs.indexOf(v!) + .5 : null),
      AxisType.time =>
        v is DateTime ? v.millisecondsSinceEpoch.toDouble() : null,
      AxisType.log => v is num && v > 0 ? math.log(v) / math.ln10 : null,
      AxisType.number => v is num ? v.toDouble() : null,
    };
    final us = [for (var i = 0; i < n; i++) place(xs[i], i) ?? 0.0];
    // A row's room along x: one for categories, the closest gap between rows otherwise.
    var room = 1.0;
    if (!band && n > 1) {
      room = double.infinity;
      for (var i = 1; i < n; i++) {
        final d = (us[i] - us[i - 1]).abs();
        if (d > 0) room = math.min(room, d);
      }
      if (!room.isFinite) room = 1;
    }
    final hasBars = parts.any(
      (p) => p is Bar || p is Waterfall || p is BoxPlot || p is Candlestick,
    );
    var fullLo = band ? 0.0 : (n == 0 ? 0.0 : us.reduce(math.min));
    var fullHi = band ? n.toDouble() : (n == 0 ? 1.0 : us.reduce(math.max));
    if (!band) {
      if (hasBars || n == 1) {
        fullLo -= room / 2;
        fullHi += room / 2;
      } else if (type == AxisType.number && n > 1) {
        // A number axis ends on round numbers, as a value axis does.
        final ticks = chartTicks(fullLo, fullHi, count: xAxis?.tickCount ?? 6);
        fullLo = ticks.first;
        fullHi = ticks.last;
      }
      final d = xAxis?.domain;
      if (d != null) {
        if (place(d.$1) case final lo?) fullLo = lo;
        if (place(d.$2) case final hi?) fullHi = hi;
      }
      if (fullHi == fullLo) fullHi = fullLo + 1;
    }
    // The window: chosen by zooming, panning or the brush; else the last rows; else all.
    var (lo, hi) = (fullLo, fullHi);
    if (_window case final w?) {
      (lo, hi) = w;
    } else if (brush != null &&
        (brush.startIndex != null || brush.endIndex != null) &&
        n > 0) {
      final a = (brush.startIndex ?? 0).clamp(0, n - 1);
      final b = (brush.endIndex ?? n - 1).clamp(a, n - 1);
      lo = band ? a.toDouble() : us[a] - (hasBars ? room / 2 : 0);
      hi = band ? b + 1.0 : us[b] + (hasBars ? room / 2 : 0);
    } else if (xAxis?.last case final last? when n > last) {
      lo = band
          ? (n - last).toDouble()
          : us[n - last] - (hasBars ? room / 2 : 0);
    }
    if (hi <= lo) hi = lo + room;
    bool inView(int i) => us[i] >= lo - room && us[i] <= hi + room;

    // Each series' values, stacked and on their axis's terms.
    final scales = <String, _YScale>{
      for (final p in parts) p.yAxisId: _YScale(p.yAxisId, yAxes[p.yAxisId]),
      for (final y in yAxes.values) y.id: _YScale(y.id, y),
    };
    if (scales.isEmpty) scales[''] = _YScale('', null);
    final expand = widget.stackOffset == StackOffset.expand;
    final series = <_Series>[];
    final stacks = <String, (List<double>, List<double>)>{};
    final totals = <String, List<double>>{};
    if (expand) {
      for (final p in parts) {
        final key = switch (p) {
          Bar(:final stackId?) ||
          Line(:final stackId?) ||
          Area(:final stackId?) => '${p.yAxisId}/$stackId',
          _ => null,
        };
        if (key == null || _hidden.contains(p.label)) continue;
        final sum = totals.putIfAbsent(key, () => List.filled(n, 0));
        for (var i = 0; i < n; i++) {
          sum[i] += (_read(p, i) ?? 0).abs();
        }
      }
    }
    for (final (k, p) in parts.indexed) {
      final kind = switch (p) {
        Bar() => _Kind.bar,
        Line() => _Kind.line,
        Area() => _Kind.area,
        Scatter() => _Kind.scatter,
        Candlestick() => _Kind.price,
        BoxPlot() => _Kind.box,
        Waterfall() => _Kind.waterfall,
        _ => _Kind.line,
      };
      final s = _Series(
        kind,
        p,
        k,
        p.color ?? c.charts[k % c.charts.length],
        n,
      );
      final y = scales[p.yAxisId]!;
      final stackId = switch (p) {
        Bar(:final stackId) ||
        Line(:final stackId) ||
        Area(:final stackId) => stackId,
        _ => null,
      };
      final key = stackId == null ? null : '${p.yAxisId}/$stackId';
      final hidden = _hidden.contains(p.label);
      var running = 0.0;
      for (var i = 0; i < n; i++) {
        final row = data[i];
        var v = _read(p, i)?.toDouble();
        s.raw[i] = v;
        switch (p) {
          case Bar(:final low?) || Area(:final low?):
            s.top[i] = y.hold(v);
            s.bottom[i] = y.hold(low(row));
            (s.low ??= List.filled(n, null))[i] = low(row)?.toDouble();
          case Candlestick():
            s.open = (s.open ?? List.filled(n, null))
              ..[i] = p.open(row)?.toDouble();
            s.high = (s.high ?? List.filled(n, null))
              ..[i] = p.high(row)?.toDouble();
            s.lowPrice = (s.lowPrice ?? List.filled(n, null))
              ..[i] = p.low(row)?.toDouble();
            s.close = (s.close ?? List.filled(n, null))
              ..[i] = p.close(row)?.toDouble();
            s.top[i] = y.hold(s.high![i]);
            s.bottom[i] = y.hold(s.lowPrice![i]);
          case BoxPlot():
            final samples = p.samples(row);
            final b = samples.isEmpty ? null : _Box(samples);
            (s.boxes ??= List.filled(n, null))[i] = b;
            s.raw[i] = b?.median;
            s.top[i] = y.hold(b?.high);
            s.bottom[i] = y.hold(b?.low);
          case Waterfall():
            final total = p.total?.call(row) ?? false;
            (s.totals ??= List.filled(n, false))[i] = total;
            if (total) {
              s.raw[i] = running;
              s.bottom[i] = y.hold(0);
              s.top[i] = y.hold(running);
            } else if (v != null) {
              s.bottom[i] = y.hold(running);
              running += v;
              s.top[i] = y.hold(running);
            }
          default:
            if (v != null && key != null && !hidden) {
              if (expand) {
                final whole = totals[key]![i];
                v = whole == 0 ? 0 : v / whole;
              }
              final (pos, neg) = stacks.putIfAbsent(
                key,
                () => (List.filled(n, 0), List.filled(n, 0)),
              );
              final base = v >= 0 ? pos[i] : neg[i];
              s.bottom[i] = base;
              s.top[i] = base + v;
              if (v >= 0) {
                pos[i] += v;
              } else {
                neg[i] += v;
              }
            } else {
              s.top[i] = y.hold(v);
            }
        }
        // Error bars, as values on the axis.
        final (err, below) = switch (p) {
          Bar(:final error, :final errorBelow) ||
          Line(:final error, :final errorBelow) ||
          Scatter(:final error, :final errorBelow) => (error, errorBelow),
          _ => (null, null),
        };
        if (err != null && s.raw[i] != null) {
          final up = err(row)?.toDouble(),
              down = (below ?? err)(row)?.toDouble();
          final at = y.give(s.top[i] ?? 0);
          (s.errHi ??= List.filled(n, null))[i] = up == null
              ? null
              : y.hold(at + up);
          (s.errLo ??= List.filled(n, null))[i] = down == null
              ? null
              : y.hold(at - down);
        }
        switch (p) {
          case Bar(:final colorOf?) || Scatter(:final colorOf?):
            (s.colors ??= List.filled(n, null))[i] = colorOf(row);
          case Line(dot: ChartDot(:final colorOf?)) ||
              Area(dot: ChartDot(:final colorOf?)):
            (s.colors ??= List.filled(n, null))[i] = colorOf(row);
          default:
            break;
        }
        if (p case Scatter(:final size?)) {
          (s.radii ??= List.filled(n, null))[i] = size(row)?.toDouble();
        }
      }
      // A bubble's area grows with its size.
      if (s.radii case final r?) {
        final known = r.whereType<double>();
        final big = known.isEmpty
            ? 1.0
            : known.map((v) => v.abs()).reduce(math.max);
        final sc = p as Scatter;
        for (var i = 0; i < n; i++) {
          if (r[i] case final v?) {
            r[i] =
                sc.minRadius +
                (sc.maxRadius - sc.minRadius) *
                    math.sqrt(v.abs() / (big == 0 ? 1 : big));
          }
        }
      }
      for (final l in p.labels) {
        s.labels.add((
          l,
          [
            for (var i = 0; i < n; i++)
              s.raw[i] == null
                  ? null
                  : (l.text != null
                        ? l.text!(data[i], s.raw[i]!)
                        : _format(
                            expand && s.top[i] != null && s.bottom[i] != null
                                ? s.top[i]! - s.bottom[i]!
                                : s.raw[i]!,
                          )),
          ],
        ));
      }
      if (!hidden) series.add(s);
    }

    // Bars share each row's room: one group per stack, or per bar not stacked.
    final groupOf = <String, int>{};
    for (final s in series.where((s) => s.kind == _Kind.bar)) {
      final b = s.part as Bar;
      groupOf.putIfAbsent(b.stackId ?? '#${s.index}', () => groupOf.length);
    }
    for (final s in series.where((s) => s.kind == _Kind.bar)) {
      final b = s.part as Bar;
      s.group = groupOf[b.stackId ?? '#${s.index}']!;
      s.groups = groupOf.length;
    }

    // Each value axis's scale, from what is in view.
    for (final y in scales.values) {
      final on = series.where((s) => s.axis == y.id).toList();
      var a = double.infinity, b = double.negativeInfinity;
      void take(double? v) {
        if (v == null || !v.isFinite) return;
        a = math.min(a, v);
        b = math.max(b, v);
      }

      for (final s in on) {
        for (var i = 0; i < n; i++) {
          if (!inView(i)) continue;
          take(s.top[i]);
          take(s.bottom[i]);
          take(s.errHi?[i]);
          take(s.errLo?[i]);
        }
      }
      for (final tr in trends.where((tr) => tr.yAxisId == y.id)) {
        for (var i = 0; i < n; i++) {
          if (inView(i)) take(y.hold(tr.value(data[i])));
        }
      }
      if (!a.isFinite) (a, b) = (0, 1);
      // Bars and areas stand on zero; lines do too, unless they ride on prices, boxes or
      // marks, whose scale fits their own range.
      final ranged = on.any(
        (s) =>
            s.kind == _Kind.price ||
            s.kind == _Kind.box ||
            s.kind == _Kind.scatter,
      );
      final zero =
          y.part?.zero ??
          on.any(
            (s) =>
                (s.kind == _Kind.bar ||
                    s.kind == _Kind.area ||
                    s.kind == _Kind.waterfall ||
                    (s.kind == _Kind.line && !ranged)) &&
                s.low == null,
          );
      if (zero && !y.log) {
        a = math.min(a, 0);
        b = math.max(b, 0);
      }
      if (expand && on.any((s) => s.bottom.any((v) => v != null))) {
        y.lo = 0;
        y.hi = 1;
        y.ticks = const [0, .25, .5, .75, 1];
        continue;
      }
      final d = y.part?.domain;
      if (d?.$1 != null) a = y.hold(d!.$1) ?? a;
      if (d?.$2 != null) b = y.hold(d!.$2) ?? b;
      if (y.log) {
        y.lo = a.floorToDouble();
        y.hi = math.max(b.ceilToDouble(), y.lo + 1);
        y.ticks = [for (var v = y.lo; v <= y.hi; v++) v];
      } else {
        final ticks = chartTicks(a, b, count: y.part?.tickCount ?? 5);
        y.lo = d?.$1 != null ? a : ticks.first;
        y.hi = d?.$2 != null ? b : ticks.last;
        y.ticks = [
          for (final v in ticks)
            if (v >= y.lo - 1e-9 && v <= y.hi + 1e-9) v,
        ];
      }
    }

    // The room round the plot: the axes' labels, the brush.
    final text = t.text.xs.copyWith(color: c.mutedForeground);
    final line = math.max(20.0, MediaQuery.textScalerOf(context).scale(16) + 4);
    String yText(_YScale y, double v) {
      final value = y.give(v);
      return y.part?.tickFormatter?.call(value) ??
          (expand && y.hi == 1 && y.lo == 0
              ? _percent(value)
              : chartNumber(value));
    }

    for (final y in scales.values) {
      if (!y.shown) continue;
      y.room = across
          ? line + y.part!.tickMargin
          : (y.part!.width ??
                y.ticks
                        .map((v) => _textWidth(yText(y, v), text))
                        .fold<double>(0, math.max) +
                    y.part!.tickMargin);
    }
    String xText(Object v) {
      if (xAxis?.tickFormatter case final f?) return f(v);
      return switch (v) {
        DateTime() => chartDate(v),
        num() => chartNumber(type == AxisType.log ? v : v),
        _ => '$v',
      };
    }

    final xa = xAxis;
    final showX = xa != null && !xa.hide;
    final xRoom = !showX
        ? 0.0
        : across
        ? (xa.width ??
              math.min(
                120.0,
                xs
                        .map((v) => _textWidth(xText(v), text))
                        .fold<double>(0, math.max) +
                    xa.tickMargin,
              ))
        : line + xa.tickMargin;
    final topLabels = series.any(
      (s) => s.labels.any((l) => l.$1.position == ChartLabelPosition.top),
    );
    final leftAxes = scales.values.where((y) => y.shown && !y.right);
    final rightAxes = scales.values.where((y) => y.shown && y.right);
    final brushRoom = brush == null ? 0.0 : brush.height + 12;
    final inset = EdgeInsets.fromLTRB(
      across ? xRoom : leftAxes.fold<double>(0, (a, y) => a + y.room),
      across
          ? rightAxes.fold<double>(0, (a, y) => a + y.room) + 4
          : (topLabels ? 20 : 6) + (xAxis?.top == true ? xRoom : 0),
      across
          ? (rightAxes.isEmpty ? 16 : 8) + (topLabels ? 24 : 0)
          : math.max(rightAxes.fold<double>(0, (a, y) => a + y.room), 4),
      (across
              ? leftAxes.fold<double>(0, (a, y) => a + y.room)
              : (xAxis?.top == true ? 0 : xRoom)) +
          brushRoom,
    );

    final colors = [
      for (final (k, p) in parts.indexed)
        p.color ?? c.charts[k % c.charts.length],
    ];
    final legendView = legend == null
        ? null
        : (legend.builder ??
              (context, entries) =>
                  ChartLegendView(entries: entries))(context, [
            for (final (k, p) in parts.indexed)
              ChartLegendEntry(
                label: p.label,
                color: colors[k],
                icon: p.icon,
                shown: !_hidden.contains(p.label),
                onToggle: legend.toggle && parts.length > 1
                    ? () => setState(() {
                        if (_hidden.contains(p.label)) {
                          _hidden.remove(p.label);
                        } else if (_hidden.length < parts.length - 1) {
                          // One series always stays.
                          _hidden.add(p.label);
                        }
                      })
                    : null,
              ),
            for (final tr in trends)
              if (tr.label != null)
                ChartLegendEntry(
                  label: tr.label!,
                  color: tr.color ?? c.mutedForeground,
                ),
          ]);

    return Semantics(
      container: true,
      label: widget.semanticLabel ?? 'Chart',
      value: _summary(xs, series, xText),
      child: Focus(
        onFocusChange: (f) => setState(() {
          _focused =
              f &&
              FocusManager.instance.highlightMode ==
                  FocusHighlightMode.traditional;
          if (!f) _at = null;
        }),
        onKeyEvent: (node, e) => _key(e, n, across),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (legendView != null &&
                legend!.position == ChartLegendPosition.top) ...[
              legendView,
              const SizedBox(height: 12),
            ],
            SizedBox(
              height: widget.height,
              child: LayoutBuilder(
                builder: (context, box) {
                  final plot = Rect.fromLTRB(
                    inset.left,
                    inset.top,
                    box.maxWidth - inset.right,
                    widget.height - inset.bottom,
                  );
                  final alongLen = across ? plot.height : plot.width;
                  double alongPx(double u) =>
                      (across ? plot.top : plot.left) +
                      (u - lo) / (hi - lo) * alongLen;
                  double uAt(Offset p) =>
                      lo +
                      ((across ? p.dy - plot.top : p.dx - plot.left) /
                              alongLen) *
                          (hi - lo);
                  final bandPx = room / (hi - lo) * alongLen;
                  Offset at(double u, double v, _YScale y) {
                    final a = alongPx(u);
                    final f = y.frac(v);
                    return across
                        ? Offset(plot.left + f * plot.width, a)
                        : Offset(a, plot.bottom - f * plot.height);
                  }

                  // The x labels: every category that fits, or round steps.
                  final xTicks = <(double, String)>[];
                  if (showX && n > 0) {
                    if (band) {
                      final widest = across
                          ? line
                          : xs
                                    .map((v) => _textWidth(xText(v), text))
                                    .fold<double>(0, math.max) +
                                8;
                      final every =
                          xa.interval ?? math.max(1, (widest / bandPx).ceil());
                      for (var i = 0; i < n; i++) {
                        if (i % every == 0 && us[i] >= lo && us[i] <= hi) {
                          xTicks.add((us[i], xText(xs[i])));
                        }
                      }
                    } else if (type == AxisType.time) {
                      xTicks.addAll(
                        _timeTicks(
                          lo,
                          hi,
                          xa.tickCount ?? math.max(2, (alongLen / 64).floor()),
                          xa.tickFormatter,
                        ),
                      );
                    } else if (type == AxisType.log) {
                      for (var v = lo.ceilToDouble(); v <= hi; v++) {
                        final value = math.pow(10, v);
                        xTicks.add((
                          v,
                          xa.tickFormatter?.call(value) ?? chartNumber(value),
                        ));
                      }
                    } else {
                      for (final v in chartTicks(
                        lo,
                        hi,
                        count:
                            xa.tickCount ??
                            math.max(2, (alongLen / 70).floor()),
                      )) {
                        if (v >= lo && v <= hi) xTicks.add((v, xText(v)));
                      }
                    }
                  }

                  int? rowAt(Offset p) {
                    if (n == 0) return null;
                    final u = uAt(p);
                    if (u < lo || u > hi) return null;
                    if (band) return u.floor().clamp(0, n - 1);
                    var best = 0;
                    for (var i = 1; i < n; i++) {
                      if ((us[i] - u).abs() < (us[best] - u).abs()) best = i;
                    }
                    return best;
                  }

                  // The series under the pointer: a bar it is over, or the closest point.
                  String? seriesAt(Offset p, int i) {
                    String? best;
                    var bestD = 24.0;
                    for (final s in series) {
                      final y = scales[s.axis]!;
                      if (s.top[i] == null) continue;
                      if (s.barLike) {
                        final zero = y.log ? y.lo : 0.0.clamp(y.lo, y.hi);
                        final r = _barRect(
                          s,
                          us[i],
                          s.top[i]!,
                          s.bottom[i] ?? zero,
                          y,
                          at,
                          bandPx,
                          across,
                          barGap: widget.barGap,
                          catGap: widget.barCategoryGap,
                        );
                        if (r.inflate(2).contains(p)) return s.label;
                        continue;
                      }
                      final q = at(
                        us[i],
                        s.kind == _Kind.price
                            ? (s.top[i]! + s.bottom[i]!) / 2
                            : s.top[i]!,
                        y,
                      );
                      final d = (q - p).distance;
                      if (d < bestD) {
                        bestD = d;
                        best = s.label;
                      }
                    }
                    return best;
                  }

                  final scatterOnly =
                      series.isNotEmpty &&
                      series.every((s) => s.kind == _Kind.scatter);
                  void hover(Offset p) {
                    var i = rowAt(p);
                    String? s;
                    if (i != null &&
                        (scatterOnly || tooltip?.shared == false)) {
                      // The closest mark to the pointer, of any row.
                      var bestD = 24.0;
                      int? bestI;
                      for (final sr in series) {
                        final y = scales[sr.axis]!;
                        for (var k = 0; k < n; k++) {
                          if (sr.top[k] == null || !inView(k)) continue;
                          final d = (at(us[k], sr.top[k]!, y) - p).distance;
                          if (d < bestD) {
                            bestD = d;
                            bestI = k;
                            s = sr.label;
                          }
                        }
                      }
                      if (!scatterOnly) s = seriesAt(p, i);
                      i = scatterOnly ? bestI : (s == null ? null : i);
                    } else if (i != null) {
                      s = seriesAt(p, i);
                    }
                    setState(() {
                      _at = i;
                      _atSeries = s;
                      _pointer = plot.contains(p) ? p : null;
                    });
                  }

                  void select(Offset p) {
                    if (widget.onSelect == null) return;
                    final i = scatterOnly ? _at : rowAt(p);
                    if (i == null) return;
                    final pick = ChartSelection<T>(
                      index: i,
                      row: data[i],
                      series: scatterOnly ? _atSeries : seriesAt(p, i),
                    );
                    setState(() => _selected = _selected == pick ? null : pick);
                    widget.onSelect!(_selected);
                  }

                  // Zooming and panning move the window, kept inside the rows.
                  final canMove =
                      widget.zoom || xAxis?.last != null || brush != null;
                  void moveTo(double a, double b) {
                    final width = (b - a).clamp(
                      math.min(room * 2, fullHi - fullLo),
                      fullHi - fullLo,
                    );
                    var s = a.clamp(fullLo, fullHi - width);
                    setState(() => _window = (s, s + width));
                    if (s <= fullLo + 1e-9 &&
                        widget.onReachStart != null &&
                        !_loading) {
                      _loading = true;
                      Future.sync(widget.onReachStart!).whenComplete(() {
                        if (mounted) _loading = false;
                      });
                    }
                  }

                  void zoomAt(Offset p, double factor) {
                    final u = uAt(p).clamp(lo, hi);
                    final width = (hi - lo) * factor;
                    final f = (u - lo) / (hi - lo);
                    moveTo(u - f * width, u - f * width + width);
                  }

                  final showTip =
                      tooltip != null &&
                      _at != null &&
                      _at! < n &&
                      series.isNotEmpty;
                  final tipAt = !showTip
                      ? Offset.zero
                      : scatterOnly
                      ? at(
                          us[_at!],
                          series
                                  .firstWhere(
                                    (s) => s.label == _atSeries,
                                    orElse: () => series.first,
                                  )
                                  .top[_at!] ??
                              0,
                          scales[series.first.axis]!,
                        )
                      : across
                      ? Offset(plot.left + plot.width * .55, alongPx(us[_at!]))
                      : Offset(alongPx(us[_at!]), _pointer?.dy ?? plot.top);

                  // What is drawn now: the values, part way from the last ones while
                  // they change.
                  final m = Curves.easeInOutCubic.transform(_morph.value);
                  final drawn = <String, (List<double?>, List<double?>)>{};
                  for (final s in series) {
                    final was = _from[s.label];
                    if (was != null && m < 1) {
                      double? lerp(
                        List<double?> from,
                        List<double?> to,
                        int i,
                      ) {
                        final b = to[i];
                        final a = i < from.length ? from[i] : null;
                        return a == null || b == null ? b : a + (b - a) * m;
                      }

                      s.top.setAll(0, [
                        for (var i = 0; i < n; i++) lerp(was.$1, s.top, i),
                      ]);
                      s.bottom.setAll(0, [
                        for (var i = 0; i < n; i++) lerp(was.$2, s.bottom, i),
                      ]);
                    }
                    drawn[s.label] = (List.of(s.top), List.of(s.bottom));
                  }
                  _drawn = drawn;

                  final chart = AnimatedBuilder(
                    animation: Listenable.merge([grow, _morph]),
                    builder: (context, _) => CustomPaint(
                      size: Size(box.maxWidth, widget.height),
                      painter: _CartesianPainter(
                        series: series,
                        scales: scales,
                        us: us,
                        lo: lo,
                        hi: hi,
                        plot: plot,
                        across: across,
                        band: band,
                        bandPx: bandPx,
                        at: at,
                        alongPx: alongPx,
                        barGap: widget.barGap,
                        catGap: widget.barCategoryGap,
                        grid: grid,
                        xTicks: xTicks,
                        xAxis: xAxis,
                        showX: showX,
                        yText: yText,
                        refs: [for (final r in refs) r],
                        place: place,
                        trends: [
                          for (final tr in trends)
                            (
                              tr,
                              _fit(
                                tr,
                                data,
                                us,
                                scales[tr.yAxisId] ?? scales.values.first,
                              ),
                            ),
                        ],
                        hovered: _at,
                        focus: _selected?.index ?? widget.active,
                        cursor: tooltip?.cursor ?? false,
                        crosshair: crosshair,
                        pointer: _pointer,
                        pointerText: _pointer == null
                            ? null
                            : (
                                xText(_giveX(uAt(_pointer!), type, xs)),
                                yText(
                                  scales.values.first,
                                  scales.values.first.lo +
                                      (across
                                              ? (_pointer!.dx - plot.left) /
                                                    plot.width
                                              : (plot.bottom - _pointer!.dy) /
                                                    plot.height) *
                                          (scales.values.first.hi -
                                              scales.values.first.lo),
                                ),
                              ),
                        grow: grown,
                        clip: lo > fullLo + 1e-9 || hi < fullHi - 1e-9,
                        text: text,
                        strong: t.text.xs.copyWith(
                          color: c.foreground,
                          fontWeight: FontWeight.w500,
                        ),
                        page: c.background,
                        line: c.border,
                        muted: c.muted,
                        fg: c.foreground,
                        mutedFg: c.mutedForeground,
                        falling: c.destructive,
                        ring: _focused ? c.ring : null,
                      ),
                    ),
                  );

                  return Listener(
                    onPointerSignal: widget.zoom
                        ? (e) {
                            if (e is PointerScrollEvent &&
                                plot.contains(e.localPosition)) {
                              GestureBinding.instance.pointerSignalResolver
                                  .register(e, (e) {
                                    final d =
                                        (e as PointerScrollEvent).scrollDelta;
                                    zoomAt(
                                      e.localPosition,
                                      math.exp((d.dy + d.dx) * .0015),
                                    );
                                  });
                            }
                          }
                        : null,
                    child: MouseRegion(
                      onHover: (e) => hover(e.localPosition),
                      onExit: (_) => setState(() {
                        _at = null;
                        _pointer = null;
                      }),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) => hover(d.localPosition),
                        onTapUp: (d) => select(d.localPosition),
                        onDoubleTap: widget.zoom
                            ? () => setState(() => _window = null)
                            : null,
                        onScaleStart: canMove
                            ? (d) => _pinchWidth = hi - lo
                            : null,
                        onScaleUpdate: canMove
                            ? (d) {
                                if (d.pointerCount > 1 && widget.zoom) {
                                  final width =
                                      _pinchWidth /
                                      d.horizontalScale.clamp(.05, 50);
                                  final u = uAt(d.localFocalPoint);
                                  final f = (u - lo) / (hi - lo);
                                  moveTo(u - f * width, u - f * width + width);
                                } else {
                                  final du =
                                      -(across
                                          ? d.focalPointDelta.dy
                                          : d.focalPointDelta.dx) /
                                      alongLen *
                                      (hi - lo);
                                  moveTo(lo + du, hi + du);
                                }
                              }
                            : null,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(child: chart),
                            for (final note in notes)
                              if (place(note.x) case final u?
                                  when u >= lo && u <= hi)
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  child: Transform.translate(
                                    offset: at(
                                      u,
                                      (scales[note.yAxisId] ??
                                                  scales.values.first)
                                              .hold(note.y) ??
                                          0,
                                      scales[note.yAxisId] ??
                                          scales.values.first,
                                    ),
                                    child: FractionalTranslation(
                                      translation: Offset(
                                        -(note.alignment.x + 1) / 2,
                                        -(note.alignment.y + 1) / 2,
                                      ),
                                      child: note.child,
                                    ),
                                  ),
                                ),
                            if (brush != null)
                              Positioned(
                                left: plot.left,
                                width: plot.width,
                                bottom: 0,
                                height: brush.height,
                                child: _BrushView(
                                  rows: [
                                    for (var i = 0; i < n; i++)
                                      series.isEmpty
                                          ? null
                                          : series.first.top[i],
                                  ],
                                  us: us,
                                  fullLo: fullLo,
                                  fullHi: fullHi,
                                  lo: lo,
                                  hi: hi,
                                  onChanged: moveTo,
                                ),
                              ),
                            if (showTip)
                              _Floating(
                                at: tipAt,
                                width: box.maxWidth,
                                child: _tooltipFor(
                                  context,
                                  tooltip,
                                  _at!,
                                  series,
                                  scales,
                                  xText(xs[_at!]),
                                  scatterOnly || !tooltip.shared
                                      ? _atSeries
                                      : null,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (legendView != null &&
                legend!.position == ChartLegendPosition.bottom) ...[
              const SizedBox(height: 12),
              legendView,
            ],
          ],
        ),
      ),
    );
  }

  num? _read(CartesianSeries<T> p, int i) {
    if (p.values case final v?) return i < v.length ? v[i] : null;
    return p.value?.call(widget.data[i]);
  }

  static Object _giveX(double u, AxisType type, List<Object> xs) =>
      switch (type) {
        AxisType.category =>
          xs.isEmpty ? '' : xs[u.floor().clamp(0, xs.length - 1)],
        AxisType.time => DateTime.fromMillisecondsSinceEpoch(u.round()),
        AxisType.log => math.pow(10, u),
        AxisType.number => u,
      };

  KeyEventResult _key(KeyEvent e, int n, bool across) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final next = across
        ? LogicalKeyboardKey.arrowDown
        : LogicalKeyboardKey.arrowRight;
    final back = across
        ? LogicalKeyboardKey.arrowUp
        : LogicalKeyboardKey.arrowLeft;
    if (n == 0) return KeyEventResult.ignored;
    int? to;
    if (e.logicalKey == next) to = ((_at ?? -1) + 1).clamp(0, n - 1);
    if (e.logicalKey == back) to = ((_at ?? n) - 1).clamp(0, n - 1);
    if (e.logicalKey == LogicalKeyboardKey.home) to = 0;
    if (e.logicalKey == LogicalKeyboardKey.end) to = n - 1;
    if (to != null) {
      setState(() {
        _at = to;
        _atSeries = null;
        _pointer = null;
      });
      return KeyEventResult.handled;
    }
    if ((e.logicalKey == LogicalKeyboardKey.enter ||
            e.logicalKey == LogicalKeyboardKey.space) &&
        _at != null &&
        widget.onSelect != null) {
      final pick = ChartSelection<T>(index: _at!, row: widget.data[_at!]);
      setState(() => _selected = _selected == pick ? null : pick);
      widget.onSelect!(_selected);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// What a screen reader hears: every row while there are few, else each series' span.
  String _summary(
    List<Object> xs,
    List<_Series> series,
    String Function(Object) xText,
  ) {
    if (xs.length <= 60) {
      return [
        for (var i = 0; i < xs.length; i++)
          '${xText(xs[i])}: ${[for (final s in series)
            if (s.raw[i] != null) '${s.label} ${_format(s.raw[i]!)}'].join(', ')}',
      ].join('; ');
    }
    return [
      '${xs.length} rows from ${xText(xs.first)} to ${xText(xs.last)}',
      for (final s in series)
        if (s.raw.whereType<double>().isNotEmpty)
          '${s.label} from ${_format(s.raw.whereType<double>().reduce(math.min))} '
              'to ${_format(s.raw.whereType<double>().reduce(math.max))}',
    ].join('; ');
  }

  Widget _tooltipFor(
    BuildContext context,
    ChartTooltip<T> tip,
    int i,
    List<_Series> series,
    Map<String, _YScale> scales,
    String label,
    String? only,
  ) {
    final row = widget.data[i];
    String write(num v, String name) =>
        tip.formatter?.call(v, name, row) ?? _format(v);
    final items = <ChartTooltipItem>[];
    for (final s in series) {
      if (only != null && s.label != only) continue;
      final color = s.colors?[i] ?? s.color;
      void add(String name, num? v, [String? text]) {
        if (v == null) return;
        items.add(
          ChartTooltipItem(
            label: name,
            value: v,
            text: text ?? write(v, name),
            color: color,
            icon: s.part.icon,
          ),
        );
      }

      switch (s.kind) {
        case _Kind.price:
          final p = s.part as Candlestick;
          if (p.style != PriceStyle.hilo) add('Open', s.open![i]);
          add('High', s.high![i]);
          add('Low', s.lowPrice![i]);
          if (p.style != PriceStyle.hilo) add('Close', s.close![i]);
        case _Kind.box:
          final b = s.boxes![i];
          if (b == null) continue;
          add('Max', b.max);
          add('Q3', b.q3);
          add('Median', b.median);
          add('Q1', b.q1);
          add('Min', b.min);
          if ((s.part as BoxPlot).mean) add('Mean', b.mean);
        default:
          final v = s.raw[i];
          if (v == null) continue;
          if (s.low?[i] case final l?) {
            add(s.label, v, '${write(l, s.label)} to ${write(v, s.label)}');
          } else if (widget.stackOffset == StackOffset.expand &&
              s.bottom[i] != null &&
              s.top[i] != null) {
            add(s.label, s.top[i]! - s.bottom[i]!);
          } else {
            add(s.label, v);
          }
      }
    }
    final data = ChartTooltipData<T>(
      title: tip.labelFormatter?.call(label, row) ?? label,
      items: items,
      row: row,
      index: i,
    );
    if (tip.builder case final b?) return b(context, data);
    return ChartTooltipCard(
      title: tip.hideLabel ? null : data.title,
      items: items,
      indicator: tip.hideIndicator ? ChartIndicator.none : tip.indicator,
      total: tip.total
          ? write(items.fold<num>(0, (a, it) => a + it.value), 'Total')
          : null,
    );
  }
}

/// Round steps along a time axis between [lo] and [hi] (milliseconds): seconds to
/// years, about [count] of them, on whole minutes, days, months and years.
List<(double, String)> _timeTicks(
  double lo,
  double hi,
  int count,
  String Function(Object)? format,
) {
  const s = Duration(seconds: 1),
      m = Duration(minutes: 1),
      h = Duration(hours: 1);
  const d = Duration(days: 1);
  final steps = [
    s, s * 5, s * 15, s * 30, m, m * 5, m * 15, m * 30, //
    h, h * 3, h * 6, h * 12, d, d * 2, d * 7, d * 14,
  ];
  final span = hi - lo;
  final want = span / math.max(1, count);
  String text(DateTime t, Duration step) =>
      format?.call(t) ?? chartDate(t, step: step);
  final out = <(double, String)>[];
  for (final step in steps) {
    if (step.inMilliseconds >= want) {
      final ms = step.inMilliseconds;
      // Steps of a day or more fall on local midnights.
      var t = DateTime.fromMillisecondsSinceEpoch(lo.ceil());
      t = step >= d
          ? DateTime(
              t.year,
              t.month,
              t.day + (t.hour > 0 || t.minute > 0 ? 1 : 0),
            )
          : DateTime.fromMillisecondsSinceEpoch((lo / ms).ceil() * ms);
      while (t.millisecondsSinceEpoch <= hi) {
        out.add((t.millisecondsSinceEpoch.toDouble(), text(t, step)));
        t = step >= d
            ? DateTime(t.year, t.month, t.day + step.inDays)
            : t.add(step);
      }
      return out;
    }
  }
  // Months and years.
  final months = want / (d.inMilliseconds * 30.4);
  final every = [
    1,
    2,
    3,
    6,
    12,
    24,
    60,
    120,
  ].firstWhere((k) => k >= months, orElse: () => 120);
  final start = DateTime.fromMillisecondsSinceEpoch(lo.floor());
  var t = DateTime(
    start.year,
    ((start.month - 1) ~/ every.clamp(1, 12)) * every.clamp(1, 12) + 1,
  );
  if (every >= 12) t = DateTime((start.year ~/ (every ~/ 12)) * (every ~/ 12));
  while (t.millisecondsSinceEpoch <= hi) {
    if (t.millisecondsSinceEpoch >= lo) {
      out.add((
        t.millisecondsSinceEpoch.toDouble(),
        text(
          t,
          every >= 12 ? const Duration(days: 365) : const Duration(days: 30),
        ),
      ));
    }
    t = DateTime(t.year, t.month + every);
  }
  return out;
}

/// The points a trendline passes through, in axis units: fitted to the rows and run
/// [Trendline.backward] before and [Trendline.forward] after them.
List<Offset> _fit<T>(
  Trendline<T> tr,
  List<T> data,
  List<double> us,
  _YScale y,
) {
  final pts = <(double, double)>[];
  for (var i = 0; i < data.length; i++) {
    final v = tr.value(data[i]);
    if (v != null) pts.add((us[i], v.toDouble()));
  }
  if (pts.length < 2) return const [];
  if (tr.kind == TrendKind.movingAverage) {
    final k = tr.period.clamp(1, pts.length);
    return [
      for (var i = k - 1; i < pts.length; i++)
        if (y.hold(
              pts
                      .sublist(i - k + 1, i + 1)
                      .fold<double>(0, (a, p) => a + p.$2) /
                  k,
            )
            case final v?)
          Offset(pts[i].$1, v),
    ];
  }
  final xs = [for (final p in pts) p.$1];
  final from = xs.reduce(math.min) - tr.backward;
  final to = xs.reduce(math.max) + tr.forward;
  // Least squares on transformed values: ln y for growth, ln x for logarithms.
  double? Function(double) f;
  switch (tr.kind) {
    case TrendKind.linear || TrendKind.polynomial:
      final order = tr.kind == TrendKind.linear ? 1 : tr.order.clamp(2, 6);
      final c = _polyfit(
        [for (final p in pts) p.$1],
        [for (final p in pts) p.$2],
        order,
      );
      if (c == null) return const [];
      f = (x) {
        var v = 0.0;
        for (var k = c.length - 1; k >= 0; k--) {
          v = v * x + c[k];
        }
        return v;
      };
    case TrendKind.exponential:
      final ok = pts.where((p) => p.$2 > 0).toList();
      final c = _polyfit(
        [for (final p in ok) p.$1],
        [for (final p in ok) math.log(p.$2)],
        1,
      );
      if (c == null) return const [];
      f = (x) => math.exp(c[0] + c[1] * x);
    case TrendKind.logarithmic:
      final ok = pts.where((p) => p.$1 > 0).toList();
      final c = _polyfit(
        [for (final p in ok) math.log(p.$1)],
        [for (final p in ok) p.$2],
        1,
      );
      if (c == null) return const [];
      f = (x) => x > 0 ? c[0] + c[1] * math.log(x) : null;
    case TrendKind.power:
      final ok = pts.where((p) => p.$1 > 0 && p.$2 > 0).toList();
      final c = _polyfit(
        [for (final p in ok) math.log(p.$1)],
        [for (final p in ok) math.log(p.$2)],
        1,
      );
      if (c == null) return const [];
      f = (x) => x > 0 ? math.exp(c[0]) * math.pow(x, c[1]) : null;
    case TrendKind.movingAverage:
      return const [];
  }
  return [
    for (var k = 0; k <= 80; k++)
      if (f(from + (to - from) * k / 80) case final v? when v.isFinite)
        if (y.hold(v) case final h?) Offset(from + (to - from) * k / 80, h),
  ];
}

/// The coefficients (constant first) of the polynomial of [order] closest to the points,
/// by least squares; null when they do not settle it.
List<double>? _polyfit(List<double> x, List<double> y, int order) {
  final m = order + 1;
  if (x.length < m) return null;
  // The normal equations, solved by elimination.
  final a = List.generate(m, (_) => List<double>.filled(m + 1, 0));
  for (var i = 0; i < x.length; i++) {
    final p = List<double>.generate(2 * m, (k) => math.pow(x[i], k).toDouble());
    for (var r = 0; r < m; r++) {
      for (var c = 0; c < m; c++) {
        a[r][c] += p[r + c];
      }
      a[r][m] += p[r] * y[i];
    }
  }
  for (var col = 0; col < m; col++) {
    var pivot = col;
    for (var r = col + 1; r < m; r++) {
      if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
    }
    if (a[pivot][col].abs() < 1e-12) return null;
    final swap = a[col];
    a[col] = a[pivot];
    a[pivot] = swap;
    for (var r = 0; r < m; r++) {
      if (r == col) continue;
      final k = a[r][col] / a[col][col];
      for (var c = col; c <= m; c++) {
        a[r][c] -= k * a[col][c];
      }
    }
  }
  return [for (var r = 0; r < m; r++) a[r][m] / a[r][r]];
}

/// A bar's rectangle on screen, from [bottom] to [top] at [u], in its share of the
/// row's room.
Rect _barRect(
  _Series s,
  double u,
  double top,
  double bottom,
  _YScale y,
  Offset Function(double, double, _YScale) at,
  double bandPx,
  bool across, {
  double barGap = 4,
  double catGap = .2,
}) {
  final inner = bandPx * (1 - catGap);
  final double thick, offset;
  if (s.kind == _Kind.bar) {
    thick = math.max(1, (inner - barGap * (s.groups - 1)) / s.groups);
    offset = -inner / 2 + s.group * (thick + barGap);
  } else {
    thick = math.max(1, inner * (s.kind == _Kind.box ? .5 : 1));
    offset = -thick / 2;
  }
  final a = at(u, bottom, y), b = at(u, top, y);
  return across
      ? Rect.fromLTRB(
          math.min(a.dx, b.dx),
          a.dy + offset,
          math.max(a.dx, b.dx),
          a.dy + offset + thick,
        )
      : Rect.fromLTRB(
          a.dx + offset,
          math.min(a.dy, b.dy),
          a.dx + offset + thick,
          math.max(a.dy, b.dy),
        );
}

class _CartesianPainter extends CustomPainter {
  _CartesianPainter({
    required this.series,
    required this.scales,
    required this.us,
    required this.lo,
    required this.hi,
    required this.plot,
    required this.across,
    required this.band,
    required this.bandPx,
    required this.at,
    required this.alongPx,
    required this.barGap,
    required this.catGap,
    required this.grid,
    required this.xTicks,
    required this.xAxis,
    required this.showX,
    required this.yText,
    required this.refs,
    required this.place,
    required this.trends,
    required this.hovered,
    required this.focus,
    required this.cursor,
    required this.crosshair,
    required this.pointer,
    required this.pointerText,
    required this.grow,
    required this.clip,
    required this.text,
    required this.strong,
    required this.page,
    required this.line,
    required this.muted,
    required this.fg,
    required this.mutedFg,
    required this.falling,
    required this.ring,
  });

  final List<_Series> series;
  final Map<String, _YScale> scales;
  final List<double> us;
  final double lo, hi, bandPx, barGap, catGap, grow;
  final Rect plot;
  final bool across, band, showX, cursor, clip;
  final Offset Function(double u, double v, _YScale y) at;
  final double Function(double u) alongPx;
  final CartesianGrid<dynamic>? grid;
  final List<(double, String)> xTicks;
  final XAxis<dynamic>? xAxis;
  final String Function(_YScale y, double v) yText;
  final List<ChartPart<dynamic>> refs;
  final double? Function(Object? v, [int? i]) place;
  final List<(Trendline<dynamic>, List<Offset>)> trends;
  final int? hovered, focus;
  final Crosshair<dynamic>? crosshair;
  final Offset? pointer;
  final (String, String)? pointerText;
  final TextStyle text, strong;
  final Color page, line, muted, fg, mutedFg, falling;
  final Color? ring;

  _YScale get _main => scales[''] ?? scales.values.first;
  _YScale _y(String id) => scales[id] ?? _main;
  double _zero(_YScale y) => y.log ? y.lo : 0.0.clamp(y.lo, y.hi);

  /// A value part way up from the zero line, as the chart grows in.
  double _g(_YScale y, double v) {
    final z = _zero(y);
    return z + (v - z) * grow;
  }

  bool _inView(int i) {
    final half = band ? .5 : (hi - lo);
    return us[i] >= lo - half - 1 && us[i] <= hi + half + 1;
  }

  Color _dim(Color c, int i) =>
      focus == null || focus == i ? c : c.withValues(alpha: c.a * .35);

  Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  void _dashLine(Canvas canvas, Offset a, Offset b, Paint p, bool dashed) {
    if (!dashed) {
      canvas.drawLine(a, b, p);
      return;
    }
    canvas.drawPath(
      chartDashed(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy),
      ),
      Paint()
        ..color = p.color
        ..strokeWidth = p.strokeWidth
        ..style = PaintingStyle.stroke,
    );
  }

  /// A line across the plot at a value (or up it, lying).
  (Offset, Offset) _across(double v, _YScale y) {
    final f = y.frac(v);
    return across
        ? (
            Offset(plot.left + f * plot.width, plot.top),
            Offset(plot.left + f * plot.width, plot.bottom),
          )
        : (
            Offset(plot.left, plot.bottom - f * plot.height),
            Offset(plot.right, plot.bottom - f * plot.height),
          );
  }

  /// A line across the plot at a place along x.
  (Offset, Offset) _along(double u) {
    final a = alongPx(u);
    return across
        ? (Offset(plot.left, a), Offset(plot.right, a))
        : (Offset(a, plot.top), Offset(a, plot.bottom));
  }

  Rect? _bar(_Series s, int i) {
    final y = _y(s.axis);
    final top = s.top[i];
    if (top == null) return null;
    return _barRect(
      s,
      us[i],
      _g(y, top),
      _g(y, s.bottom[i] ?? _zero(y)),
      y,
      at,
      bandPx,
      across,
      barGap: barGap,
      catGap: catGap,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = line
      ..strokeWidth = 1;

    // The grid, at the scale's steps and the rows' labels.
    if (grid case final g?) {
      final valueLines = across ? g.vertical : g.horizontal;
      final rowLines = across ? g.horizontal : g.vertical;
      if (valueLines) {
        for (final v in _main.ticks) {
          final (a, b) = _across(v, _main);
          _dashLine(canvas, _px(a), _px(b), gridPaint, g.dashed);
        }
      }
      if (rowLines) {
        for (final (u, _) in xTicks) {
          final (a, b) = _along(u);
          _dashLine(canvas, _px(a), _px(b), gridPaint, g.dashed);
        }
      }
    }
    // The zero line, when values go below it.
    for (final y in scales.values) {
      if (!y.log && y.lo < 0 && y.hi > 0) {
        final (a, b) = _across(0, y);
        canvas.drawLine(_px(a), _px(b), gridPaint);
      }
    }

    canvas.save();
    if (clip) {
      canvas.clipRect(
        across
            ? Rect.fromLTRB(-1e4, plot.top, 1e4, plot.bottom)
            : Rect.fromLTRB(plot.left, -1e4, plot.right, 1e4),
      );
    }

    // Bands behind everything.
    for (final r in refs.whereType<ReferenceArea<dynamic>>()) {
      final y = _y(r.yAxisId);
      double edge(Object? x, bool end) {
        final u = place(x);
        if (u == null) return end ? hi : lo;
        return band ? u + (end ? .5 : -.5) : u;
      }

      final u1 = r.x1 == null ? lo : edge(r.x1, false);
      final u2 = r.x2 == null ? hi : edge(r.x2, true);
      final v1 = r.y1 == null ? y.lo : (y.hold(r.y1) ?? y.lo);
      final v2 = r.y2 == null ? y.hi : (y.hold(r.y2) ?? y.hi);
      final rect = Rect.fromPoints(
        at(u1, v1, y),
        at(u2, v2, y),
      ).intersect(plot);
      final color = r.color ?? mutedFg;
      canvas.drawRect(
        rect,
        Paint()..color = color.withValues(alpha: r.opacity),
      );
      if (r.label != null) {
        chartText(
          canvas,
          r.label!,
          rect.topLeft + const Offset(6, 4),
          text,
          Alignment.topLeft,
        );
      }
    }

    // The row under the pointer: a band behind bars, a line through points.
    final bars = series.any((s) => s.barLike || s.kind == _Kind.price);
    if (cursor && hovered != null && bars) {
      final c = alongPx(us[hovered!]);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          across
              ? Rect.fromLTRB(
                  plot.left,
                  c - bandPx / 2 + 2,
                  plot.right,
                  c + bandPx / 2 - 2,
                )
              : Rect.fromLTRB(
                  c - bandPx / 2 + 2,
                  plot.top,
                  c + bandPx / 2 - 2,
                  plot.bottom,
                ),
          const Radius.circular(6),
        ),
        Paint()..color = muted,
      );
    }

    for (final s in series) {
      switch (s.kind) {
        case _Kind.bar:
          _bars(canvas, s);
        case _Kind.line || _Kind.area:
          _lines(canvas, s);
        case _Kind.scatter:
          _scatter(canvas, s);
        case _Kind.price:
          _prices(canvas, s);
        case _Kind.box:
          _boxes(canvas, s);
        case _Kind.waterfall:
          _waterfall(canvas, s);
      }
      _errors(canvas, s);
    }

    for (final (tr, pts) in trends) {
      if (pts.length < 2) continue;
      final y = _y(tr.yAxisId);
      final path = _through([
        for (final p in pts) at(p.dx, _g(y, p.dy), y),
      ], ChartCurve.linear);
      final p = _stroke(tr.color ?? mutedFg, 1.5);
      canvas.drawPath(tr.dashed ? chartDashed(path, on: 6, off: 4) : path, p);
    }

    for (final r in refs) {
      switch (r) {
        case ReferenceLine<dynamic>():
          final y = _y(r.yAxisId);
          final color = r.color ?? mutedFg;
          final p = Paint()
            ..color = color
            ..strokeWidth = 1;
          Offset? end;
          if (r.y != null && y.hold(r.y) != null) {
            final (a, b) = _across(y.hold(r.y)!, y);
            _dashLine(canvas, a, b, p, r.dashed);
            end = across ? a : b;
          } else if (place(r.x) case final u?) {
            final (a, b) = _along(u);
            _dashLine(canvas, a, b, p, r.dashed);
            end = across ? b : a;
          }
          if (r.label != null && end != null) {
            chartText(
              canvas,
              r.label!,
              end + (across ? const Offset(-4, 4) : const Offset(-4, -4)),
              text.copyWith(color: color),
              across ? Alignment.topRight : Alignment.bottomRight,
            );
          }
        case ReferenceDot<dynamic>():
          final y = _y(r.yAxisId);
          final u = place(r.x);
          final v = y.hold(r.y);
          if (u == null || v == null) continue;
          final q = at(u, v, y);
          canvas.drawCircle(q, r.radius + 2, Paint()..color = page);
          canvas.drawCircle(q, r.radius, Paint()..color = r.color ?? fg);
          if (r.label != null) {
            chartText(
              canvas,
              r.label!,
              q - Offset(0, r.radius + 6),
              strong,
              Alignment.bottomCenter,
            );
          }
        default:
          break;
      }
    }

    for (final s in series) {
      _labels(canvas, s);
    }

    if (cursor && hovered != null && !bars && series.isNotEmpty) {
      final (a, b) = _along(us[hovered!]);
      canvas.drawLine(a, b, Paint()..color = line);
      // The trackball: a dot on every series at the row.
      for (final s in series) {
        if (s.kind != _Kind.line && s.kind != _Kind.area) continue;
        final v = s.top[hovered!];
        if (v == null) continue;
        final y = _y(s.axis);
        final q = at(us[hovered!], _g(y, v), y);
        canvas.drawCircle(q, 5, Paint()..color = page);
        canvas.drawCircle(
          q,
          4,
          Paint()..color = s.colors?[hovered!] ?? s.color,
        );
      }
    }
    canvas.restore();

    _axes(canvas);

    if (crosshair != null && pointer != null && pointerText != null) {
      final p = Paint()
        ..color = mutedFg
        ..strokeWidth = 1;
      _dashLine(
        canvas,
        Offset(pointer!.dx, plot.top),
        Offset(pointer!.dx, plot.bottom),
        p,
        crosshair!.dashed,
      );
      _dashLine(
        canvas,
        Offset(plot.left, pointer!.dy),
        Offset(plot.right, pointer!.dy),
        p,
        crosshair!.dashed,
      );
      void tag(String s, Offset o, Alignment a) {
        final tp = TextPainter(
          text: TextSpan(
            text: s,
            style: strong.copyWith(color: page),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final box = Rect.fromLTWH(
          o.dx - (a.x + 1) / 2 * (tp.width + 8),
          o.dy - (a.y + 1) / 2 * (tp.height + 4),
          tp.width + 8,
          tp.height + 4,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(4)),
          Paint()..color = fg,
        );
        tp.paint(canvas, box.topLeft + const Offset(4, 2));
      }

      final (xs, ys) = pointerText!;
      if (across) {
        tag(xs, Offset(plot.left, pointer!.dy), Alignment.centerRight);
        tag(ys, Offset(pointer!.dx, plot.bottom), Alignment.topCenter);
      } else {
        tag(xs, Offset(pointer!.dx, plot.bottom), Alignment.topCenter);
        tag(ys, Offset(plot.left, pointer!.dy), Alignment.centerRight);
      }
    }

    if (ring != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(plot.inflate(4), const Radius.circular(8)),
        _stroke(ring!, 2),
      );
    }
  }

  /// Snaps a hairline to the pixel grid.
  Offset _px(Offset o) =>
      Offset(o.dx.roundToDouble() + .5, o.dy.roundToDouble() + .5);

  void _bars(Canvas canvas, _Series s) {
    final b = s.part as Bar;
    final y = _y(s.axis);
    for (var i = 0; i < us.length; i++) {
      if (!_inView(i)) continue;
      final rect = _bar(s, i);
      if (rect == null) continue;
      if (b.track) {
        final full = _barRect(
          s,
          us[i],
          y.hi,
          y.lo,
          y,
          at,
          bandPx,
          across,
          barGap: barGap,
          catGap: catGap,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(full, Radius.circular(b.radius)),
          Paint()..color = muted,
        );
      }
      final up = (s.top[i] ?? 0) >= (s.bottom[i] ?? _zero(y));
      // Only a bar's far end rounds; in a stack, only the outermost one's.
      var round = true;
      if (b.stackId != null) {
        for (final o in series) {
          if (o.index <= s.index || o.kind != _Kind.bar) continue;
          final ob = o.part as Bar;
          if (ob.stackId != b.stackId || o.axis != s.axis) continue;
          final ot = o.top[i], obm = o.bottom[i];
          if (ot != null && obm != null && ot != obm && (ot >= obm) == up) {
            round = false;
          }
        }
      }
      final r = Radius.circular(
        round ? math.min(b.radius, (across ? rect.height : rect.width) / 2) : 0,
      );
      final shape = across
          ? RRect.fromRectAndCorners(
              rect,
              topRight: up ? r : Radius.zero,
              bottomRight: up ? r : Radius.zero,
              topLeft: up ? Radius.zero : r,
              bottomLeft: up ? Radius.zero : r,
            )
          : RRect.fromRectAndCorners(
              rect,
              topLeft: up ? r : Radius.zero,
              topRight: up ? r : Radius.zero,
              bottomLeft: up ? Radius.zero : r,
              bottomRight: up ? Radius.zero : r,
            );
      canvas.drawRRect(
        shape,
        Paint()..color = _dim(s.colors?[i] ?? s.color, i),
      );
    }
  }

  /// The visible points of a series in runs between gaps, thinned to about two a
  /// pixel when there are many more.
  List<List<(int, Offset)>> _runs(
    _Series s,
    List<double?> values, {
    bool keepGaps = true,
  }) {
    final y = _y(s.axis);
    final runs = <List<(int, Offset)>>[[]];
    final connect = switch (s.part) {
      Line(:final connectNulls) || Area(:final connectNulls) => connectNulls,
      _ => false,
    };
    var first = 0, last = us.length - 1;
    while (first < last && us[first + 1] < lo) {
      first++;
    }
    while (last > first && us[last - 1] > hi) {
      last--;
    }
    for (var i = first; i <= last; i++) {
      final v = values[i];
      if (v == null) {
        if (!connect && keepGaps && runs.last.isNotEmpty) runs.add([]);
        continue;
      }
      runs.last.add((i, at(us[i], _g(y, v), y)));
    }
    final px = across ? plot.height : plot.width;
    return [
      for (final r in runs)
        if (r.isNotEmpty) r.length > px * 2 ? _thin(r, px.ceil()) : r,
    ];
  }

  /// Keeps the first, lowest, highest and last point of each pixel column.
  List<(int, Offset)> _thin(List<(int, Offset)> run, int columns) {
    double along(Offset o) => across ? o.dy : o.dx;
    double up(Offset o) => across ? o.dx : o.dy;
    final out = <(int, Offset)>[];
    final start = along(run.first.$2), end = along(run.last.$2);
    final w = (end - start) / columns;
    var k = 0;
    while (k < run.length) {
      final col = w == 0 ? 0 : ((along(run[k].$2) - start) / w).floor();
      final group = <(int, Offset)>[];
      while (k < run.length &&
          (w == 0 ? 0 : ((along(run[k].$2) - start) / w).floor()) == col) {
        group.add(run[k++]);
      }
      var mn = group.first, mx = group.first;
      for (final p in group) {
        if (up(p.$2) < up(mn.$2)) mn = p;
        if (up(p.$2) > up(mx.$2)) mx = p;
      }
      final keep = {group.first, mn, mx, group.last}.toList()
        ..sort((a, b) => a.$1.compareTo(b.$1));
      out.addAll(keep);
    }
    return out;
  }

  void _lines(Canvas canvas, _Series s) {
    final y = _y(s.axis);
    final (curve, width, dashed, dots, dot) = switch (s.part) {
      Line(
        :final curve,
        :final width,
        :final dashed,
        :final dots,
        :final dot,
      ) =>
        (curve, width, dashed, dots, dot),
      Area(
        :final curve,
        :final width,
        :final dashed,
        :final dots,
        :final dot,
      ) =>
        (curve, width, dashed, dots, dot),
      _ => (ChartCurve.linear, 2.0, false, false, null),
    };
    final tops = _runs(s, s.top);
    if (s.kind == _Kind.area) {
      final a = s.part as Area;
      final zero = _zero(y);
      for (final run in tops) {
        if (run.length < 2 && s.bottom.every((b) => b == null)) continue;
        final top = _through(
          [for (final p in run) p.$2],
          curve,
          across: across,
        );
        final under = [
          for (final (i, _) in run.reversed)
            at(us[i], _g(y, s.bottom[i] ?? zero), y),
        ];
        final fill = Path.from(top)
          ..lineTo(under.first.dx, under.first.dy)
          ..extendWithPath(_through(under, curve, across: across), Offset.zero)
          ..close();
        final c = s.color;
        canvas.drawPath(
          fill,
          Paint()
            ..shader = LinearGradient(
              begin: across ? Alignment.centerRight : Alignment.topCenter,
              end: across ? Alignment.centerLeft : Alignment.bottomCenter,
              colors: a.gradient
                  ? [c.withValues(alpha: a.opacity), c.withValues(alpha: .05)]
                  : [
                      c.withValues(alpha: a.opacity * .75),
                      c.withValues(alpha: a.opacity * .75),
                    ],
            ).createShader(plot),
        );
        if (s.low != null) {
          canvas.drawPath(
            _through(under.reversed.toList(), curve, across: across),
            _stroke(c, width * .75),
          );
        }
      }
    }
    for (final run in tops) {
      if (run.length < 2) continue;
      final path = _through([for (final p in run) p.$2], curve, across: across);
      canvas.drawPath(
        dashed ? chartDashed(path, on: 6, off: 4) : path,
        _stroke(s.color, width),
      );
    }
    if (dots || dot != null) {
      final d = dot ?? const ChartDot<dynamic>();
      for (final run in tops) {
        for (final (i, p) in run) {
          final color = _dim(s.colors?[i] ?? s.color, i);
          if (d.icon != null) {
            canvas.drawCircle(p, d.radius + 4, Paint()..color = page);
            chartGlyph(canvas, d.icon!, p, d.radius * 3, color);
          } else if (d.hollow) {
            chartMark(canvas, d.shape, p, d.radius, Paint()..color = page);
            chartMark(canvas, d.shape, p, d.radius, _stroke(color, 2));
          } else {
            chartMark(canvas, d.shape, p, d.radius, Paint()..color = color);
          }
        }
      }
    }
  }

  void _scatter(Canvas canvas, _Series s) {
    final p = s.part as Scatter;
    final y = _y(s.axis);
    final many =
        s.radii == null &&
        p.shape == ChartShape.circle &&
        s.colors == null &&
        us.length > 3000;
    if (many) {
      final pts = <Offset>[
        for (var i = 0; i < us.length; i++)
          if (s.top[i] != null && _inView(i)) at(us[i], _g(y, s.top[i]!), y),
      ];
      canvas.drawPoints(
        ui.PointMode.points,
        pts,
        Paint()
          ..color = s.color.withValues(alpha: p.opacity)
          ..strokeWidth = p.minRadius * 2
          ..strokeCap = StrokeCap.round,
      );
      return;
    }
    for (var i = 0; i < us.length; i++) {
      final v = s.top[i];
      if (v == null || !_inView(i)) continue;
      final q = at(us[i], _g(y, v), y);
      final r = (s.radii?[i] ?? p.minRadius + .5) * (i == hovered ? 1.25 : 1);
      final color = _dim(s.colors?[i] ?? s.color, i);
      chartMark(
        canvas,
        p.shape,
        q,
        r,
        Paint()..color = color.withValues(alpha: color.a * p.opacity),
      );
      if (s.radii != null) chartMark(canvas, p.shape, q, r, _stroke(color, 1));
    }
  }

  void _prices(Canvas canvas, _Series s) {
    final p = s.part as Candlestick;
    final y = _y(s.axis);
    final w = math.max(1.0, bandPx * (1 - catGap) * .7);
    for (var i = 0; i < us.length; i++) {
      if (!_inView(i)) continue;
      final o = y.hold(s.open![i]), h = y.hold(s.high![i]);
      final l = y.hold(s.lowPrice![i]), c = y.hold(s.close![i]);
      if (h == null || l == null) continue;
      final rising = (s.close![i] ?? 0) >= (s.open![i] ?? 0);
      final color = _dim(
        (rising ? p.risingColor : p.fallingColor) ?? s.color,
        i,
      );
      final top = at(us[i], _g(y, h), y), bottom = at(us[i], _g(y, l), y);
      final paint = _stroke(color, 1.5)..strokeCap = StrokeCap.butt;
      canvas.drawLine(top, bottom, paint);
      if (o == null || c == null || p.style == PriceStyle.hilo) continue;
      final po = at(us[i], _g(y, o), y), pc = at(us[i], _g(y, c), y);
      if (p.style == PriceStyle.ohlc) {
        final tick = across ? Offset(0, w / 2) : Offset(w / 2, 0);
        canvas.drawLine(po - tick, po, paint);
        canvas.drawLine(pc, pc + tick, paint);
        continue;
      }
      final half = across ? Offset(0, w / 2) : Offset(w / 2, 0);
      var body = Rect.fromPoints(po - half, pc + half);
      if (body.height < 1 && !across) {
        body = Rect.fromCenter(
          center: body.center,
          width: body.width,
          height: 1,
        );
      }
      if (rising && p.risingColor == null) {
        canvas.drawRect(body, Paint()..color = page);
        canvas.drawRect(
          body,
          _stroke(color, 1.5)..strokeJoin = StrokeJoin.miter,
        );
      } else {
        canvas.drawRect(body, Paint()..color = color);
      }
    }
  }

  void _boxes(Canvas canvas, _Series s) {
    final p = s.part as BoxPlot;
    final y = _y(s.axis);
    final w = math.max(2.0, bandPx * (1 - catGap) * .5);
    for (var i = 0; i < us.length; i++) {
      final b = s.boxes![i];
      if (b == null || !_inView(i)) continue;
      final color = _dim(s.color, i);
      Offset q(double v) => at(us[i], _g(y, y.hold(v) ?? y.lo), y);
      final half = across ? Offset(0, w / 2) : Offset(w / 2, 0);
      final box = Rect.fromPoints(q(b.q1) - half, q(b.q3) + half);
      canvas.drawRect(box, Paint()..color = color.withValues(alpha: .2));
      canvas.drawRect(box, _stroke(color, 1.5)..strokeJoin = StrokeJoin.miter);
      final edge = _stroke(color, 1.5)..strokeCap = StrokeCap.butt;
      canvas.drawLine(
        q(b.median) - half,
        q(b.median) + half,
        _stroke(color, 2.5)..strokeCap = StrokeCap.butt,
      );
      canvas.drawLine(q(b.q3), q(b.max), edge);
      canvas.drawLine(q(b.q1), q(b.min), edge);
      canvas.drawLine(q(b.max) - half * .6, q(b.max) + half * .6, edge);
      canvas.drawLine(q(b.min) - half * .6, q(b.min) + half * .6, edge);
      if (p.mean) {
        chartMark(
          canvas,
          ChartShape.cross,
          q(b.mean),
          3.5,
          Paint()..color = fg,
        );
      }
      if (p.outliers) {
        for (final v in b.out) {
          canvas.drawCircle(q(v), 3, _stroke(color, 1.5));
        }
      }
    }
  }

  void _waterfall(Canvas canvas, _Series s) {
    final p = s.part as Waterfall;
    final y = _y(s.axis);
    Rect? last;
    for (var i = 0; i < us.length; i++) {
      final rect = _bar(s, i);
      if (rect == null) continue;
      final total = s.totals![i];
      final down = !total && (s.raw[i] ?? 0) < 0;
      final color = _dim(
        total
            ? (p.totalColor ?? fg.withValues(alpha: .75))
            : down
            ? (p.fallingColor ?? falling)
            : s.color,
        i,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect,
          Radius.circular(
            math.min(p.radius, (across ? rect.height : rect.width) / 2),
          ),
        ),
        Paint()..color = color,
      );
      if (p.connectors && last != null && grow == 1) {
        final v = s.bottom[i] ?? 0;
        final at0 = at(us[i], total ? (s.top[i] ?? 0) : v, y);
        final paint = Paint()
          ..color = mutedFg
          ..strokeWidth = 1;
        _dashLine(
          canvas,
          across ? Offset(at0.dx, last.bottom) : Offset(last.right, at0.dy),
          across ? Offset(at0.dx, rect.top) : Offset(rect.left, at0.dy),
          paint,
          true,
        );
      }
      last = rect;
    }
  }

  void _errors(Canvas canvas, _Series s) {
    final hiE = s.errHi, loE = s.errLo;
    if (hiE == null && loE == null) return;
    final y = _y(s.axis);
    for (var i = 0; i < us.length; i++) {
      final top = s.top[i];
      if (top == null || !_inView(i)) continue;
      var centre = at(us[i], _g(y, top), y);
      if (s.kind == _Kind.bar) {
        final r = _bar(s, i);
        if (r == null) continue;
        centre = across
            ? Offset(r.right, r.center.dy)
            : Offset(r.center.dx, r.top);
      }
      final a = hiE?[i] == null ? centre : at(us[i], _g(y, hiE![i]!), y);
      final b = loE?[i] == null ? centre : at(us[i], _g(y, loE![i]!), y);
      final aAligned = across
          ? Offset(a.dx, centre.dy)
          : Offset(centre.dx, a.dy);
      final bAligned = across
          ? Offset(b.dx, centre.dy)
          : Offset(centre.dx, b.dy);
      final p = _stroke(fg.withValues(alpha: .7), 1.25)
        ..strokeCap = StrokeCap.butt;
      canvas.drawLine(aAligned, bAligned, p);
      final cap = across ? const Offset(0, 4) : const Offset(4, 0);
      canvas.drawLine(aAligned - cap, aAligned + cap, p);
      canvas.drawLine(bAligned - cap, bAligned + cap, p);
    }
  }

  void _labels(Canvas canvas, _Series s) {
    if (s.labels.isEmpty || grow < .98) return;
    final y = _y(s.axis);
    for (final (l, texts) in s.labels) {
      for (var i = 0; i < us.length; i++) {
        final str = texts[i];
        if (str == null || !_inView(i) || s.top[i] == null) continue;
        final rect = s.barLike
            ? _bar(s, i)
            : Rect.fromCenter(
                center: at(us[i], s.top[i]!, y),
                width: 0,
                height: 0,
              );
        if (rect == null) continue;
        final up = (s.top[i] ?? 0) >= (s.bottom[i] ?? _zero(y));
        final o = l.offset;
        final inside =
            l.position == ChartLabelPosition.inside ||
            l.position == ChartLabelPosition.insideStart ||
            l.position == ChartLabelPosition.insideEnd;
        final style =
            (inside && s.barLike ? strong.copyWith(color: page) : strong)
                .copyWith(color: l.color);
        final (Offset p, Alignment a) = switch (l.position) {
          ChartLabelPosition.top when across =>
            up
                ? (rect.centerRight + Offset(o, 0), Alignment.centerLeft)
                : (rect.centerLeft - Offset(o, 0), Alignment.centerRight),
          ChartLabelPosition.top =>
            up
                ? (rect.topCenter - Offset(0, o), Alignment.bottomCenter)
                : (rect.bottomCenter + Offset(0, o), Alignment.topCenter),
          ChartLabelPosition.bottom when across => (
            rect.centerLeft - Offset(o, 0),
            Alignment.centerRight,
          ),
          ChartLabelPosition.bottom => (
            rect.bottomCenter + Offset(0, o),
            Alignment.topCenter,
          ),
          ChartLabelPosition.left => (
            rect.centerLeft - Offset(o, 0),
            Alignment.centerRight,
          ),
          ChartLabelPosition.right => (
            rect.centerRight + Offset(o, 0),
            Alignment.centerLeft,
          ),
          ChartLabelPosition.inside => (rect.center, Alignment.center),
          ChartLabelPosition.insideStart when across => (
            rect.centerLeft + Offset(o, 0),
            Alignment.centerLeft,
          ),
          ChartLabelPosition.insideStart => (
            rect.bottomCenter - Offset(0, o),
            Alignment.bottomCenter,
          ),
          ChartLabelPosition.insideEnd when across => (
            rect.centerRight - Offset(o, 0),
            Alignment.centerRight,
          ),
          ChartLabelPosition.insideEnd => (
            rect.topCenter + Offset(0, o),
            Alignment.topCenter,
          ),
        };
        chartText(canvas, str, p, style, a);
      }
    }
  }

  void _axes(Canvas canvas) {
    final axisPaint = Paint()
      ..color = line
      ..strokeWidth = 1;
    if (showX && xAxis != null) {
      final x = xAxis!;
      final m = x.tickMargin;
      if (x.axisLine) {
        final a = across
            ? plot.topLeft
            : (x.top ? plot.topLeft : plot.bottomLeft);
        final b = across
            ? plot.bottomLeft
            : (x.top ? plot.topRight : plot.bottomRight);
        canvas.drawLine(_px(a), _px(b), axisPaint);
      }
      for (final (u, s) in xTicks) {
        final a = alongPx(u);
        if (across) {
          chartText(
            canvas,
            s,
            Offset(plot.left - m, a),
            text,
            Alignment.centerRight,
          );
          if (x.tickLine) {
            canvas.drawLine(
              Offset(plot.left - 6, a),
              Offset(plot.left, a),
              axisPaint,
            );
          }
        } else if (x.top) {
          chartText(
            canvas,
            s,
            Offset(a, plot.top - m),
            text,
            Alignment.bottomCenter,
          );
          if (x.tickLine) {
            canvas.drawLine(
              Offset(a, plot.top - 6),
              Offset(a, plot.top),
              axisPaint,
            );
          }
        } else {
          chartText(
            canvas,
            s,
            Offset(a, plot.bottom + m),
            text,
            Alignment.topCenter,
          );
          if (x.tickLine) {
            canvas.drawLine(
              Offset(a, plot.bottom),
              Offset(a, plot.bottom + 6),
              axisPaint,
            );
          }
        }
      }
    }
    // Value axes from the plot outwards: the first on each side nearest.
    var left = across ? plot.bottom : plot.left;
    var right = across ? plot.top : plot.right;
    for (final y in scales.values) {
      if (!y.shown) continue;
      final p = y.part!;
      final edge = y.right ? right : left;
      final m = p.tickMargin;
      if (p.axisLine) {
        if (across) {
          canvas.drawLine(
            Offset(plot.left, edge),
            Offset(plot.right, edge),
            axisPaint,
          );
        } else {
          canvas.drawLine(
            Offset(edge, plot.top),
            Offset(edge, plot.bottom),
            axisPaint,
          );
        }
      }
      for (final v in y.ticks) {
        final f = y.frac(v);
        final s = yText(y, v);
        if (across) {
          final x = plot.left + f * plot.width;
          chartText(
            canvas,
            s,
            Offset(x, y.right ? edge - m : edge + m),
            text,
            y.right ? Alignment.bottomCenter : Alignment.topCenter,
          );
        } else {
          final py = plot.bottom - f * plot.height;
          chartText(
            canvas,
            s,
            Offset(y.right ? edge + m : edge - m, py),
            text,
            y.right ? Alignment.centerLeft : Alignment.centerRight,
          );
          if (p.tickLine) {
            canvas.drawLine(
              Offset(edge, py),
              Offset(y.right ? edge + 6 : edge - 6, py),
              axisPaint,
            );
          }
        }
      }
      if (y.right) {
        right += across ? -y.room : y.room;
      } else {
        left += across ? y.room : -y.room;
      }
    }
  }

  @override
  bool shouldRepaint(_CartesianPainter old) => true;
}

/// The brush: every row in small, and the window the plot shows, to drag and resize.
class _BrushView extends StatefulWidget {
  const _BrushView({
    required this.rows,
    required this.us,
    required this.fullLo,
    required this.fullHi,
    required this.lo,
    required this.hi,
    required this.onChanged,
  });

  final List<double?> rows;
  final List<double> us;
  final double fullLo, fullHi, lo, hi;
  final void Function(double lo, double hi) onChanged;

  @override
  State<_BrushView> createState() => _BrushViewState();
}

class _BrushViewState extends State<_BrushView> {
  int _grip = 0; // -1 the start, 1 the end, 0 the whole window

  @override
  Widget build(BuildContext context) {
    final c = AshlarTheme.of(context).colors;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final span = widget.fullHi - widget.fullLo;
        double px(double u) => (u - widget.fullLo) / span * w;
        double u(double x) => widget.fullLo + x / w * span;
        final a = px(widget.lo), b = px(widget.hi);
        return Semantics(
          slider: true,
          label: 'Rows shown',
          value:
              '${((widget.lo - widget.fullLo) / span * 100).round()}% to ${((widget.hi - widget.fullLo) / span * 100).round()}%',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) {
              final x = d.localPosition.dx;
              _grip = (x - a).abs() < 10 ? -1 : ((x - b).abs() < 10 ? 1 : 0);
              if (_grip == 0 && (x < a || x > b)) {
                final half = (widget.hi - widget.lo) / 2;
                widget.onChanged(u(x) - half, u(x) + half);
              }
            },
            onHorizontalDragUpdate: (d) {
              final du = d.delta.dx / w * span;
              switch (_grip) {
                case -1:
                  widget.onChanged(
                    math.min(widget.lo + du, widget.hi - span / 50),
                    widget.hi,
                  );
                case 1:
                  widget.onChanged(
                    widget.lo,
                    math.max(widget.hi + du, widget.lo + span / 50),
                  );
                default:
                  widget.onChanged(widget.lo + du, widget.hi + du);
              }
            },
            child: CustomPaint(
              size: Size(w, box.maxHeight),
              painter: _BrushPainter(
                rows: widget.rows,
                us: widget.us,
                px: px,
                a: a,
                b: b,
                line: c.mutedForeground,
                border: c.border,
                window: c.muted,
                handle: c.foreground,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BrushPainter extends CustomPainter {
  _BrushPainter({
    required this.rows,
    required this.us,
    required this.px,
    required this.a,
    required this.b,
    required this.line,
    required this.border,
    required this.window,
    required this.handle,
  });

  final List<double?> rows;
  final List<double> us;
  final double Function(double) px;
  final double a, b;
  final Color line, border, window, handle;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, const Radius.circular(6)),
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke,
    );
    final known = rows.whereType<double>();
    if (known.length > 1) {
      final mn = known.reduce(math.min), mx = known.reduce(math.max);
      final path = Path();
      var started = false;
      for (var i = 0; i < rows.length; i++) {
        final v = rows[i];
        if (v == null) continue;
        final q = Offset(
          px(us[i]),
          size.height -
              4 -
              (mx == mn ? .5 : (v - mn) / (mx - mn)) * (size.height - 8),
        );
        started ? path.lineTo(q.dx, q.dy) : path.moveTo(q.dx, q.dy);
        started = true;
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = line.withValues(alpha: .6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    final sel = Rect.fromLTRB(a, 0, b, size.height);
    canvas.drawRect(sel, Paint()..color = window.withValues(alpha: .6));
    for (final x in [a, b]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x, size.height / 2),
            width: 6,
            height: size.height * .6,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = handle,
      );
    }
  }

  @override
  bool shouldRepaint(_BrushPainter old) => true;
}

// ---------------------------------------------------------------------------------------
// The grid behind polar charts (radar-chart, radial-chart)
// ---------------------------------------------------------------------------------------

/// The lines a radar or radial chart is drawn over.
enum PolarGridType {
  /// Polygons through the axes (a radar's default).
  polygon,

  /// Circles round the centre.
  circle,
}

/// The rings and spokes behind a radar or radial chart.
class PolarGrid<T> extends ChartPart<T> {
  const PolarGrid({
    this.type = PolarGridType.polygon,
    this.rings = 4,
    this.radii,
    this.radialLines = true,
    this.fill = false,
    this.dashed = false,
  });

  final PolarGridType type;

  /// How many rings, evenly out to the edge.
  final int rings;

  /// The rings' places as shares of the radius, in place of [rings]: `[1]` draws the
  /// outer ring alone.
  final List<double>? radii;

  /// Spokes from the centre to each axis.
  final bool radialLines;

  /// Every other band filled.
  final bool fill;
  final bool dashed;
}

// ---------------------------------------------------------------------------------------
// The values as a table
// ---------------------------------------------------------------------------------------

/// A chart's values as a table: a row per data row, a column per series. Give it the
/// same rows and parts as the chart, to show beside it or in its place for those who
/// would rather read the numbers.
///
/// ```dart
/// ChartTable<Visit>(data: visits, x: (r) => r.month, children: parts)
/// ```
class ChartTable<T> extends StatelessWidget {
  const ChartTable({
    super.key,
    required this.data,
    required this.x,
    required this.children,
    this.heading = '',
    this.format,
  });

  final List<T> data;

  /// Each row's label, the first column.
  final Object Function(T row) x;

  /// The chart's parts: each series becomes a column, as does any [ChartColumn] (a pie,
  /// a radar, a radial bar).
  final List<ChartPart<T>> children;

  /// The first column's heading.
  final String heading;
  final String Function(num value)? format;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final write = format ?? chartPlain;
    final columns = <(String, num? Function(int))>[];
    for (final p in children) {
      switch (p) {
        case DerivedSeries<T>():
          for (final s in p.derive(data)) {
            columns.add((
              s.label,
              (i) => s.values?[i] ?? s.value?.call(data[i]),
            ));
          }
        case Candlestick<T>():
          columns
            ..add(('${p.label} open', (i) => p.open(data[i])))
            ..add(('${p.label} high', (i) => p.high(data[i])))
            ..add(('${p.label} low', (i) => p.low(data[i])))
            ..add(('${p.label} close', (i) => p.close(data[i])));
        case BoxPlot<T>():
          columns.add((
            '${p.label} median',
            (i) {
              final s = p.samples(data[i]);
              return s.isEmpty ? null : _Box(s).median;
            },
          ));
        case CartesianSeries<T>():
          columns.add((p.label, (i) => p.values?[i] ?? p.value?.call(data[i])));
        case final ChartColumn<T> c:
          columns.add((c.columnName, (i) => c.columnValue(data[i])));
        default:
          break;
      }
    }
    String label(Object v) => v is DateTime ? chartDate(v) : '$v';
    final head = t.text.xs.copyWith(
      color: c.mutedForeground,
      fontWeight: FontWeight.w500,
    );
    final body = t.text.xs.copyWith(
      color: c.foreground,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget cell(String s, TextStyle style, {bool end = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        s,
        style: style,
        textAlign: end ? TextAlign.end : TextAlign.start,
      ),
    );
    return Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      border: TableBorder(horizontalInside: BorderSide(color: c.border)),
      children: [
        TableRow(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          children: [
            cell(heading, head),
            for (final (name, _) in columns) cell(name, head, end: true),
          ],
        ),
        for (var i = 0; i < data.length; i++)
          TableRow(
            children: [
              cell(label(x(data[i])), body),
              for (final (_, read) in columns)
                cell(read(i) == null ? '' : write(read(i)!), body, end: true),
            ],
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------
// Histograms
// ---------------------------------------------------------------------------------------

/// One bar of a histogram: the values from [from] up to [to], and how many there were.
typedef ChartBin = ({double from, double to, int count});

/// Splits [values] into [bins] bins of equal width over their span: Sturges' rule
/// (1 + log2 n) when not given.
List<ChartBin> chartBins(List<num> values, {int? bins}) {
  if (values.isEmpty) return const [];
  final ds = [for (final v in values) v.toDouble()];
  final lo = ds.reduce(math.min), hi = ds.reduce(math.max);
  final n = bins ?? (1 + (math.log(values.length) / math.ln2).ceil());
  final width = hi == lo ? 1.0 : (hi - lo) / n;
  final counts = List.filled(n, 0);
  for (final v in values) {
    counts[((v - lo) / width).floor().clamp(0, n - 1)]++;
  }
  return [
    for (var i = 0; i < n; i++)
      (from: lo + i * width, to: lo + (i + 1) * width, count: counts[i]),
  ];
}

/// How often values fall in each span: bars side by side over a number line, and the
/// normal curve with the same mean and spread over them if you like.
///
/// ```dart
/// HistogramChart(values: deliveryMinutes, label: 'Orders', normalCurve: true)
/// ```
class HistogramChart extends StatelessWidget {
  const HistogramChart({
    super.key,
    required this.values,
    this.bins,
    this.label = 'Count',
    this.color,
    this.height = 250,
    this.normalCurve = false,
    this.grid = true,
    this.tickFormatter,
    this.semanticLabel,
  });

  final List<num> values;

  /// How many bars; Sturges' rule when null.
  final int? bins;

  /// The bars' name in the tooltip.
  final String label;
  final Color? color;
  final double height;

  /// The bell curve a normal spread with these values' mean and deviation would make.
  final bool normalCurve;
  final bool grid;

  /// Writes a value on the number line.
  final String Function(num value)? tickFormatter;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final b = chartBins(values, bins: bins);
    final n = values.length;
    final mean = n == 0 ? 0.0 : values.fold<double>(0, (a, v) => a + v) / n;
    final sd = n == 0
        ? 0.0
        : math.sqrt(
            values.fold<double>(0, (a, v) => a + (v - mean) * (v - mean)) / n,
          );
    final width = b.isEmpty ? 1.0 : b.first.to - b.first.from;
    String write(num v) => tickFormatter?.call(v) ?? chartNumber(v);
    return BarChart<ChartBin>(
      data: b,
      x: (r) => (r.from + r.to) / 2,
      height: height,
      barCategoryGap: .04,
      semanticLabel: semanticLabel,
      children: [
        if (grid) CartesianGrid(),
        XAxis(tickFormatter: (v) => write(v as num)),
        YAxis(),
        ChartTooltip(
          labelFormatter: (_, r) =>
              r == null ? '' : '${write(r.from)} to ${write(r.to)}',
        ),
        Bar(label: label, value: (r) => r.count, color: color, radius: 2),
        if (normalCurve && sd > 0)
          Line(
            label: 'Normal',
            values: [
              for (final r in b)
                n *
                    width /
                    (sd * math.sqrt(2 * math.pi)) *
                    math.exp(
                      -math.pow((r.from + r.to) / 2 - mean, 2) / (2 * sd * sd),
                    ),
            ],
            dashed: true,
            width: 1.5,
          ),
      ],
    );
  }
}
