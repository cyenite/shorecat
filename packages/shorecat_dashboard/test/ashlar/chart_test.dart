// Tests for Chart. Copied into your app by `ashlar add chart` with the component: they
// check what it promises, so change them as you change it.
import 'package:shorecat_dashboard/ui/app.dart';
import 'package:shorecat_dashboard/ui/chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {AshlarThemeMode mode = AshlarThemeMode.light}) =>
    AshlarApp(
      themeMode: mode,
      home: Center(child: SizedBox(width: 480, child: child)),
    );

typedef Visit = ({String month, double desktop, double mobile});

const visits = <Visit>[
  (month: 'Jan', desktop: 186, mobile: 80),
  (month: 'Feb', desktop: 305, mobile: 200),
  (month: 'Mar', desktop: 237, mobile: 120),
  (month: 'Apr', desktop: 73, mobile: 190),
];

typedef Price = ({
  DateTime day,
  double open,
  double high,
  double low,
  double close,
});

final prices = <Price>[
  for (var i = 0; i < 30; i++)
    (
      day: DateTime(2026, 3, 1 + i),
      open: 100.0 + i,
      high: 104.0 + i,
      low: 98.0 + i,
      close: 102.0 + i,
    ),
];

BarChart<Visit> bars({
  List<ChartPart<Visit>> extra = const [],
  ValueChanged<ChartSelection<Visit>?>? onSelect,
  String? semanticLabel,
}) => BarChart<Visit>(
  data: visits,
  x: (r) => r.month,
  onSelect: onSelect,
  semanticLabel: semanticLabel,
  children: [
    CartesianGrid(),
    XAxis(),
    ChartTooltip(),
    Bar(label: 'Desktop', value: (r) => r.desktop),
    Bar(label: 'Mobile', value: (r) => r.mobile),
    ...extra,
  ],
);

Future<TestGesture> mouseAt(WidgetTester tester, Offset at) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(at);
  await tester.pump();
  return mouse;
}

void main() {
  testWidgets('every kind draws in light and dark', (tester) async {
    for (final mode in AshlarThemeMode.values) {
      for (final chart in <Widget>[
        bars(),
        BarChart<Visit>(
          data: visits,
          x: (r) => r.month,
          layout: ChartLayout.vertical,
          children: [
            XAxis(),
            YAxis(),
            Bar(
              label: 'Desktop',
              value: (r) => r.desktop,
              stackId: 'a',
              labels: [
                ChartLabels(
                  position: ChartLabelPosition.insideStart,
                  text: (r, _) => r.month,
                ),
              ],
            ),
            Bar(label: 'Mobile', value: (r) => r.mobile, stackId: 'a'),
          ],
        ),
        LineChart<Visit>(
          data: visits,
          x: (r) => r.month,
          children: [
            XAxis(),
            YAxis(),
            Line(label: 'Desktop', value: (r) => r.desktop, dots: true),
            Line(
              label: 'Mobile',
              value: (r) => r.mobile,
              curve: ChartCurve.step,
            ),
          ],
        ),
        AreaChart<Visit>(
          data: visits,
          x: (r) => r.month,
          stackOffset: StackOffset.expand,
          children: [
            Area(label: 'Desktop', value: (r) => r.desktop, stackId: 'a'),
            Area(label: 'Mobile', value: (r) => r.mobile, stackId: 'a'),
          ],
        ),
        ScatterChart<Visit>(
          data: visits,
          x: (r) => r.desktop,
          children: [
            XAxis(),
            YAxis(),
            Scatter(
              label: 'Visits',
              value: (r) => r.mobile,
              size: (r) => r.desktop,
            ),
            Trendline(value: (r) => r.mobile),
          ],
        ),
        ComposedChart<Price>(
          data: prices,
          x: (r) => r.day,
          children: [
            XAxis(),
            YAxis(),
            YAxis(id: 'b', right: true, type: AxisType.log),
            Candlestick(
              label: 'USD',
              open: (r) => r.open,
              high: (r) => r.high,
              low: (r) => r.low,
              close: (r) => r.close,
            ),
            Ohlc(
              label: 'O',
              open: (r) => r.open,
              high: (r) => r.high,
              low: (r) => r.low,
              close: (r) => r.close,
              yAxisId: 'b',
            ),
            ReferenceArea(y1: 110, y2: 115),
            ReferenceLine(x: prices[10].day),
            Brush(),
            Crosshair(),
          ],
        ),
        ComposedChart<Visit>(
          data: visits,
          x: (r) => r.month,
          children: [
            XAxis(),
            BoxPlot(
              label: 'Spread',
              samples: (r) => [r.mobile, r.desktop, (r.mobile + r.desktop) / 2],
            ),
            Waterfall(
              label: 'Change',
              value: (r) => r.desktop - r.mobile,
              total: (r) => r.month == 'Apr',
            ),
            Line(label: 'Mean', value: (r) => r.mobile, error: (r) => 10),
          ],
        ),
      ]) {
        await tester.pumpWidget(app(chart, mode: mode));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$chart $mode');
      }
    }
  });

  testWidgets('a screen reader hears what it shows and every value', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(app(bars(semanticLabel: 'Visitors by month')));
    await tester.pumpAndSettle();
    final node = tester
        .getSemantics(find.bySemanticsLabel('Visitors by month'))
        .getSemanticsData();
    expect(node.value, contains('Jan: Desktop 186, Mobile 80'));
    expect(node.value, contains('Apr: Desktop 73, Mobile 190'));
    semantics.dispose();
  });

  testWidgets('hovering a row shows its values; leaving hides them', (
    tester,
  ) async {
    await tester.pumpWidget(app(bars()));
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byType(BarChart<Visit>));
    // The second of four rows.
    final mouse = await mouseAt(
      tester,
      Offset(box.left + box.width * .375, box.top + 100),
    );
    expect(find.text('305'), findsOneWidget);
    expect(find.text('200'), findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(find.text('305'), findsNothing);
  });

  testWidgets('the tooltip writes its values and title your way', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        BarChart<Visit>(
          data: visits,
          x: (r) => r.month,
          children: [
            ChartTooltip(
              labelFormatter: (label, r) => '$label 2026',
              formatter: (v, series, r) => '\$$v',
              total: true,
            ),
            Bar(label: 'Desktop', value: (r) => r.desktop),
            Bar(label: 'Mobile', value: (r) => r.mobile),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byType(BarChart<Visit>));
    await mouseAt(tester, Offset(box.left + box.width * .125, box.top + 100));
    expect(find.text('Jan 2026'), findsOneWidget);
    expect(find.text('\$186.0'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    // The total is written the way each value is.
    expect(find.text('\$266.0'), findsOneWidget);
  });

  testWidgets('the arrow keys step through the rows, and Enter chooses one', (
    tester,
  ) async {
    ChartSelection<Visit>? chosen;
    await tester.pumpWidget(app(bars(onSelect: (s) => chosen = s)));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('186'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('305'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(chosen?.index, 1);
    expect(chosen?.row.month, 'Feb');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(chosen, isNull);
  });

  testWidgets('a tap tells the app the row and the bar under it', (
    tester,
  ) async {
    ChartSelection<Visit>? chosen;
    await tester.pumpWidget(app(bars(onSelect: (s) => chosen = s)));
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byType(BarChart<Visit>));
    // March's first bar, Desktop, low down where both bars stand.
    await tester.tapAt(Offset(box.left + box.width * .58, box.bottom - 50));
    await tester.pump();
    expect(chosen?.row.month, 'Mar');
    expect(chosen?.series, 'Desktop');
  });

  testWidgets('the legend hides and shows a series, and one always stays', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      app(bars(extra: [ChartLegend()], semanticLabel: 'Visits')),
    );
    await tester.pumpAndSettle();
    String summary() => tester
        .getSemantics(find.bySemanticsLabel('Visits'))
        .getSemanticsData()
        .value;
    expect(summary(), contains('Mobile 80'));
    await tester.tap(find.text('Mobile'));
    await tester.pumpAndSettle();
    expect(summary(), isNot(contains('Mobile 80')));
    await tester.tap(find.text('Desktop'));
    await tester.pumpAndSettle();
    expect(summary(), contains('Desktop 186'));
    await tester.tap(find.text('Mobile'));
    await tester.pumpAndSettle();
    expect(summary(), contains('Mobile 80'));
    semantics.dispose();
  });

  testWidgets('stacked series add up, and expanded ones make 100%', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        AreaChart<Visit>(
          data: visits,
          x: (r) => r.month,
          stackOffset: StackOffset.expand,
          children: [
            ChartTooltip(),
            Area(label: 'Desktop', value: (r) => r.desktop, stackId: 'a'),
            Area(label: 'Mobile', value: (r) => r.mobile, stackId: 'a'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byType(AreaChart<Visit>));
    await mouseAt(tester, Offset(box.left + box.width * .125, box.top + 100));
    // 186 of 266, and 80 of 266.
    expect(find.text('70%'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);
  });

  testWidgets('a time axis places rows by when they fall', (tester) async {
    final semantics = tester.ensureSemantics();
    final days = <Price>[prices[0], prices[1], prices[8]];
    await tester.pumpWidget(
      app(
        LineChart<Price>(
          data: days,
          x: (r) => r.day,
          semanticLabel: 'Close',
          children: [
            XAxis(),
            ChartTooltip(),
            Line(label: 'Close', value: (r) => r.close),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byType(LineChart<Price>));
    // A third of the way along is the 3rd or 4th of March: closest to the 2nd, not the
    // 9th, though the 9th is the next row.
    await mouseAt(tester, Offset(box.left + box.width * .3, box.top + 100));
    expect(find.text('103'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Close'))
          .getSemanticsData()
          .value,
      contains('1 Mar'),
    );
    semantics.dispose();
  });

  testWidgets('zooming with the wheel and panning by drag move the window', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var reached = 0;
    final many = <Price>[for (var i = 0; i < 30; i++) prices[i]];
    await tester.pumpWidget(
      app(
        LineChart<Price>(
          data: many,
          x: (r) => r.day,
          zoom: true,
          onReachStart: () => reached++,
          children: [
            XAxis(last: 10),
            Line(label: 'Close', value: (r) => r.close),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byType(LineChart<Price>));
    // Dragging right shows earlier rows, and reaching the first asks for more.
    await tester.dragFrom(box.center, Offset(box.width * 3, 0));
    await tester.pumpAndSettle();
    expect(reached, greaterThan(0));
    // The wheel zooms in about the pointer.
    final mouse = await mouseAt(tester, box.center);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: box.center,
        scrollDelta: const Offset(0, -300),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
    semantics.dispose();
  });

  testWidgets('new rows move from the old values rather than jumping', (
    tester,
  ) async {
    Widget chart(List<Visit> data) => app(
      BarChart<Visit>(
        data: data,
        x: (r) => r.month,
        children: [Bar(label: 'Desktop', value: (r) => r.desktop)],
      ),
    );
    await tester.pumpWidget(chart(visits));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      chart([
        for (final v in visits)
          (month: v.month, desktop: v.desktop * 2, mobile: v.mobile),
      ]),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('with less motion asked for, it draws at once', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: app(bars()),
      ),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a table shows every row and series', (tester) async {
    await tester.pumpWidget(
      app(
        ChartTable<Visit>(
          data: visits,
          x: (r) => r.month,
          heading: 'Month',
          children: [
            Bar(label: 'Desktop', value: (r) => r.desktop),
            Bar(label: 'Mobile', value: (r) => r.mobile),
          ],
        ),
      ),
    );
    expect(find.text('Month'), findsOneWidget);
    expect(find.text('305'), findsOneWidget);
    expect(find.text('190'), findsOneWidget);
  });

  test('values fall into bins of equal width', () {
    final b = chartBins([1, 2, 2, 3, 9, 10], bins: 3);
    expect([for (final x in b) x.count], [4, 0, 2]);
    expect(b.first.from, 1);
    expect(b.last.to, 10);
    // Sturges: 1 + log2(8) bins for eight values.
    expect(chartBins([for (var i = 0; i < 8; i++) i]).length, 4);
    // A list of doubles, as most data is, and one of whole numbers.
    expect(chartBins(<double>[1.5, 2.5, 9]).length, 3);
    expect(chartBins(<int>[1, 2, 9]).length, 3);
  });

  testWidgets('a histogram draws its bins and the normal curve', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      app(
        HistogramChart(
          values: const [12, 15, 15, 18, 19, 21, 22, 22, 23, 25, 28, 31, 40],
          bins: 4,
          normalCurve: true,
          semanticLabel: 'Minutes',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Minutes'))
          .getSemanticsData()
          .value,
      contains('Count 6'),
    );
    semantics.dispose();
  });

  test('round scales: 1, 2, 2.5 or 5 times a power of ten', () {
    expect(chartTicks(0, 305), [0, 100, 200, 300, 400]);
    expect(chartTicks(0, 1), [0, .25, .5, .75, 1]);
    expect(chartNumber(12480), '12.5k');
    expect(chartThousands(12480), '12,480');
  });
}
