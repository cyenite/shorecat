// Tests for Radial chart. Copied into your app by `ashlar add radial-chart` with the component:
// they check what it promises, so change them as you change it.
import 'package:shorecat_dashboard/ui/app.dart';
import 'package:shorecat_dashboard/ui/chart.dart';
import 'package:shorecat_dashboard/ui/radial_chart.dart';
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
          RadialBarChart<Visit>(
            data: visits,
            name: (r) => r.month,
            startAngle: -90,
            endAngle: 90,
            center: const Text('801'),
            children: [
              PolarGrid(type: PolarGridType.circle),
              ChartLegend(),
              RadialBar(
                value: (r) => r.desktop,
                labels: [ChartLabels(position: ChartLabelPosition.insideStart, text: (r, _) => r.month)],
              ),
            ],
          ),
          mode: mode,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a screen reader hears each value against its whole', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      app(
        RadialBarChart<Visit>(
          data: visits.take(1).toList(),
          name: (r) => r.month,
          max: 2000,
          semanticLabel: 'Visits',
          children: [RadialBar(value: (r) => r.desktop)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(summary(tester, 'Visits'), 'Jan 186 of 2,000');
    semantics.dispose();
  });

  testWidgets('stacked bars share a ring, and the one under the pointer is shown', (tester) async {
    await tester.pumpWidget(
      app(
        RadialBarChart<Visit>(
          data: visits.take(1).toList(),
          children: [
            ChartTooltip(),
            RadialBar(label: 'Desktop', value: (r) => r.desktop, stackId: 'a'),
            RadialBar(label: 'Mobile', value: (r) => r.mobile, stackId: 'a'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final r = tester.getRect(find.byType(RadialBarChart<Visit>));
    // Desktop is 186 of 266, clockwise from the top: the right side is its.
    await mouseAt(tester, r.center + Offset(r.height * .4, 0));
    expect(find.text('Desktop'), findsOneWidget);
    expect(find.text('186'), findsOneWidget);
  });
}
