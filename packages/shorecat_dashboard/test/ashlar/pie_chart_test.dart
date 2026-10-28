// Tests for Pie chart. Copied into your app by `ashlar add pie-chart` with the component:
// they check what it promises, so change them as you change it.
import 'package:shorecat_dashboard/ui/app.dart';
import 'package:shorecat_dashboard/ui/chart.dart';
import 'package:shorecat_dashboard/ui/pie_chart.dart';
import 'package:flutter/gestures.dart';
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

Future<void> mouseAt(WidgetTester tester, Offset at) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(at);
  await tester.pump();
}

String summary(WidgetTester tester, String label) =>
    tester.getSemantics(find.bySemanticsLabel(label)).getSemanticsData().value;

void main() {
  testWidgets('it draws in light and dark', (tester) async {
    for (final mode in AshlarThemeMode.values) {
      await tester.pumpWidget(
        app(
          PieChart<Visit>(
            data: visits,
            center: const Text('801'),
            children: [
              ChartLegend(),
              Pie(
                value: (r) => r.desktop,
                name: (r) => r.month,
                innerRadius: .6,
                paddingAngle: 2,
                cornerRadius: 4,
                labels: [ChartLabels(text: (r, _) => r.month)],
              ),
              Pie(value: (r) => r.mobile, name: (r) => r.month, innerRadius: .3, outerRadius: .55),
            ],
          ),
          mode: mode,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a slice under the pointer shows its name and value', (tester) async {
    await tester.pumpWidget(
      app(
        PieChart<Visit>(
          data: visits.take(2).toList(),
          children: [ChartTooltip(), Pie(value: (r) => r.desktop, name: (r) => r.month)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pie = tester.getRect(find.byType(PieChart<Visit>));
    // 186 of 491, clockwise from the top: the right side is January's.
    await mouseAt(tester, pie.center + Offset(pie.height * .3, 0));
    // The title and the row both name it.
    expect(find.text('Jan'), findsNWidgets(2));
    expect(find.text('186'), findsOneWidget);
  });

  testWidgets('a screen reader hears every slice, and the legend hides one', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      app(
        PieChart<Visit>(
          data: visits,
          semanticLabel: 'Desktop',
          children: [ChartLegend(), Pie(value: (r) => r.desktop, name: (r) => r.month)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(summary(tester, 'Desktop'), 'Jan 186, Feb 305, Mar 237, Apr 73');
    await tester.tap(find.text('Feb'));
    await tester.pumpAndSettle();
    expect(summary(tester, 'Desktop'), contains('Feb 0'));
    semantics.dispose();
  });

  testWidgets('a table shows a pie as a column', (tester) async {
    await tester.pumpWidget(
      app(
        ChartTable<Visit>(
          data: visits,
          x: (r) => r.month,
          children: [Pie(value: (r) => r.desktop, name: (r) => r.month)],
        ),
      ),
    );
    expect(find.text('Value'), findsOneWidget);
    expect(find.text('305'), findsOneWidget);
  });
}
