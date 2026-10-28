// Ashlar UI: Sparkline. Copied into your app by `ashlar add sparkline`; it is yours to
// change.
// ashlar: ignore-file. Drawn left to right in any language, as time is read.
//
// A small chart with no axes, for a stat card or a table row: a line, an area, bars, or
// wins and losses, with its highest, lowest, first and last values marked if you like,
// and the value under the pointer shown.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'chart.dart';
import 'theme.dart';

/// What a sparkline draws.
enum SparkKind {
  line,

  /// A line with the area under it filled.
  area,

  /// A bar per value; below zero they hang down.
  bar,

  /// Each value as a win (up) or a loss (down), the same height: results, not sizes.
  winLoss,
}

/// Which values a sparkline marks with a dot, and writes.
@immutable
class SparkMarkers {
  const SparkMarkers({
    this.all = false,
    this.high = false,
    this.low = false,
    this.first = false,
    this.last = false,
    this.values = false,
  });

  /// Every value.
  final bool all;
  final bool high;
  final bool low;
  final bool first;
  final bool last;

  /// The marked values written beside their dots.
  final bool values;
}

/// A small chart with no axes: the shape of a run of values at a glance.
///
/// ```dart
/// Sparkline(values: [4, 7, 5, 9, 12, 10], markers: SparkMarkers(last: true))
/// ```
class Sparkline extends StatefulWidget {
  const Sparkline({
    super.key,
    required this.values,
    this.kind = SparkKind.line,
    this.width,
    this.height = 32,
    this.color,
    this.negativeColor,
    this.markers = const SparkMarkers(),
    this.band,
    this.curve = ChartCurve.linear,
    this.labels,
    this.trackball = true,
    this.format,
    this.semanticLabel,
  });

  final List<num> values;
  final SparkKind kind;

  /// Null fills the width it is given.
  final double? width;
  final double height;

  /// Null: the theme's first chart colour.
  final Color? color;

  /// Bars below zero and losses; null: the theme's destructive colour.
  final Color? negativeColor;
  final SparkMarkers markers;

  /// A band behind the line between two values: the normal range, a target.
  final (num, num)? band;
  final ChartCurve curve;

  /// A name per value, shown with it under the pointer: the days, say.
  final List<String>? labels;

  /// The value under the pointer, shown above the line.
  final bool trackball;
  final String Function(num value)? format;

  /// What it shows, read before its values: 'Sales this week'.
  final String? semanticLabel;

  @override
  State<Sparkline> createState() => _SparklineState();
}

class _SparklineState extends State<Sparkline> {
  int? _at;

  String _write(num v) => widget.format?.call(v) ?? chartNumber(v);

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final color = widget.color ?? c.chart1;
    // As doubles: a List<double> or List<int> given as List<num> cannot be reduced with
    // math.max, which is typed for num.
    final values = [for (final v in widget.values) v.toDouble()];
    final summary = values.isEmpty
        ? 'No values'
        : '${values.length} values from ${_write(values.first)} to ${_write(values.last)}, '
              'highest ${_write(values.reduce(math.max))}, lowest ${_write(values.reduce(math.min))}';
    return Semantics(
      container: true,
      label: widget.semanticLabel ?? 'Sparkline',
      value: summary,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth.isFinite ? box.maxWidth : 120.0;
            int? at(Offset p) {
              if (values.isEmpty) return null;
              final f = (p.dx / w).clamp(0.0, .9999);
              return widget.kind == SparkKind.bar ||
                      widget.kind == SparkKind.winLoss
                  ? (f * values.length).floor()
                  : (f * (values.length - 1)).round();
            }

            return MouseRegion(
              onHover: widget.trackball
                  ? (e) => setState(() => _at = at(e.localPosition))
                  : null,
              onExit: (_) => setState(() => _at = null),
              child: GestureDetector(
                onTapDown: widget.trackball
                    ? (d) => setState(() => _at = at(d.localPosition))
                    : null,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _SparkPainter(
                          values: [for (final v in values) v.toDouble()],
                          kind: widget.kind,
                          color: color,
                          negative: widget.negativeColor ?? c.destructive,
                          markers: widget.markers,
                          band: widget.band,
                          bandColor: c.muted,
                          curve: widget.curve,
                          at: _at,
                          page: c.background,
                          text: t.text.xs.copyWith(
                            color: c.foreground,
                            fontSize: 10,
                          ),
                          write: _write,
                        ),
                      ),
                    ),
                    if (_at != null && _at! < values.length)
                      Positioned(
                        left: (_at! + .5) / values.length * w > w * .6
                            ? null
                            : 0,
                        right: (_at! + .5) / values.length * w > w * .6
                            ? 0
                            : null,
                        bottom: widget.height + 4,
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: c.foreground,
                              borderRadius: BorderRadius.circular(t.radiusSm),
                            ),
                            child: Text(
                              [
                                if (widget.labels case final l?
                                    when _at! < l.length)
                                  l[_at!],
                                _write(values[_at!]),
                              ].join('  '),
                              style: t.text.xs.copyWith(color: c.background),
                            ),
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
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({
    required this.values,
    required this.kind,
    required this.color,
    required this.negative,
    required this.markers,
    required this.band,
    required this.bandColor,
    required this.curve,
    required this.at,
    required this.page,
    required this.text,
    required this.write,
  });

  final List<double> values;
  final SparkKind kind;
  final Color color, negative, bandColor, page;
  final SparkMarkers markers;
  final (num, num)? band;
  final ChartCurve curve;
  final int? at;
  final TextStyle text;
  final String Function(num) write;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final n = values.length;
    // Room for the dots at the edges.
    const pad = 3.0;
    var lo = values.reduce(math.min), hi = values.reduce(math.max);
    if (band case (final a, final b)) {
      lo = math.min(lo, a.toDouble());
      hi = math.max(hi, b.toDouble());
    }
    if (kind == SparkKind.bar || kind == SparkKind.winLoss) {
      lo = math.min(lo, 0);
      hi = math.max(hi, 0);
    }
    if (hi == lo) hi = lo + 1;
    double y(double v) => pad + (hi - v) / (hi - lo) * (size.height - pad * 2);
    if (band case (final a, final b)) {
      canvas.drawRect(
        Rect.fromLTRB(0, y(b.toDouble()), size.width, y(a.toDouble())),
        Paint()..color = bandColor,
      );
    }
    if (kind == SparkKind.bar || kind == SparkKind.winLoss) {
      final w = size.width / n;
      final mid = size.height / 2;
      for (var i = 0; i < n; i++) {
        final v = values[i];
        final Rect r;
        if (kind == SparkKind.winLoss) {
          if (v == 0) {
            r = Rect.fromLTWH(i * w + w * .15, mid - 1, w * .7, 2);
          } else {
            r = v > 0
                ? Rect.fromLTRB(i * w + w * .15, pad, i * w + w * .85, mid - 1)
                : Rect.fromLTRB(
                    i * w + w * .15,
                    mid + 1,
                    i * w + w * .85,
                    size.height - pad,
                  );
          }
        } else {
          final z = y(0), top = y(v);
          r = Rect.fromLTRB(
            i * w + w * .15,
            math.min(z, top),
            i * w + w * .85,
            math.max(z, top),
          );
        }
        final c = v < 0 ? negative : color;
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(1.5)),
          Paint()..color = at == null || at == i ? c : c.withValues(alpha: .4),
        );
      }
      return;
    }
    final step = n == 1 ? 0.0 : (size.width - pad * 2) / (n - 1);
    final pts = [
      for (var i = 0; i < n; i++) Offset(pad + i * step, y(values[i])),
    ];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    if (curve == ChartCurve.linear || n < 3) {
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
    } else {
      // A gentle curve through the points.
      for (var i = 1; i < n; i++) {
        final a = pts[i - 1], b = pts[i];
        final mx = (a.dx + b.dx) / 2;
        path.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
      }
    }
    if (kind == SparkKind.area) {
      final fill = Path.from(path)
        ..lineTo(pts.last.dx, size.height)
        ..lineTo(pts.first.dx, size.height)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: .35),
              color.withValues(alpha: .02),
            ],
          ).createShader(Offset.zero & size),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final hiAt = values.indexOf(values.reduce(math.max));
    final loAt = values.indexOf(values.reduce(math.min));
    for (var i = 0; i < n; i++) {
      final marked =
          markers.all ||
          (markers.high && i == hiAt) ||
          (markers.low && i == loAt) ||
          (markers.first && i == 0) ||
          (markers.last && i == n - 1);
      if (!marked && i != at) continue;
      final c = (markers.low && i == loAt) ? negative : color;
      canvas.drawCircle(pts[i], 3.5, Paint()..color = page);
      canvas.drawCircle(pts[i], 2.5, Paint()..color = c);
      if (marked && markers.values) {
        final tp = TextPainter(
          text: TextSpan(text: write(values[i]), style: text),
          textDirection: TextDirection.ltr,
        )..layout();
        final above = pts[i].dy > size.height / 2;
        var x = pts[i].dx - tp.width / 2;
        x = x.clamp(0, math.max(0, size.width - tp.width));
        tp.paint(
          canvas,
          Offset(x, above ? pts[i].dy - tp.height - 3 : pts[i].dy + 3),
        );
      }
    }
    if (at != null && at! < n) {
      canvas.drawLine(
        Offset(pts[at!].dx, 0),
        Offset(pts[at!].dx, size.height),
        Paint()
          ..color = color.withValues(alpha: .35)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) => true;
}
