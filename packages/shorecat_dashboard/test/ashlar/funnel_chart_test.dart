// Tests for Funnel chart. Copied into your app by `ashlar add funnel-chart` with the
// component: they check what it promises, so change them as you change it.
import 'package:shorecat_dashboard/ui/app.dart';
import 'package:shorecat_dashboard/ui/chart.dart';
import 'package:shorecat_dashboard/ui/funnel_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {AshlarThemeMode mode = AshlarThemeMode.light}) => AshlarApp(
  themeMode: mode,
  home: Center(child: SizedBox(width: 480, child: child)),
);

typedef Stage = ({String stage, double people});

const stages = <Stage>[
  (stage: 'Visited', people: 1000),
  (stage: 'Signed up', people: 400),
  (stage: 'Paid', people: 100),
];

void main() {
  testWidgets('a funnel and a pyramid draw in light and dark', (tester) async {
    for (final mode in AshlarThemeMode.values) {
      for (final chart in <Widget>[
        FunnelChart<Stage>(
          data: stages,
          children: [
            ChartLegend(),
            Funnel(
              value: (r) => r.people,
              name: (r) => r.stage,
              labels: [
                ChartLabels(position: ChartLabelPosition.inside),
                ChartLabels(position: ChartLabelPosition.right, text: (r, _) => r.stage),
              ],
            ),
          ],
        ),
        PyramidChart<Stage>(data: stages, children: [Pyramid(value: (r) => r.people, name: (r) => r.stage)]),
      ]) {
        await tester.pumpWidget(app(chart, mode: mode));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('a step under the pointer says what share of the first reached it', (tester) async {
    await tester.pumpWidget(
      app(
        FunnelChart<Stage>(
          data: stages,
          height: 300,
          children: [ChartTooltip(), Funnel(value: (r) => r.people, name: (r) => r.stage)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byType(FunnelChart<Stage>));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    // The middle step.
    await mouse.moveTo(box.center);
    await tester.pump();
    expect(find.text('400'), findsOneWidget);
    expect(find.text('40.0%'), findsOneWidget);
  });

  testWidgets('a screen reader hears every step', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      app(
        FunnelChart<Stage>(
          data: stages,
          semanticLabel: 'Sign-ups',
          children: [Funnel(value: (r) => r.people, name: (r) => r.stage)],
        ),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Sign-ups')).getSemanticsData().value,
      'Visited 1,000, Signed up 400, Paid 100',
    );
    semantics.dispose();
  });
}
