// Tests for Sparkline. Copied into your app by `ashlar add sparkline` with the
// component: they check what it promises, so change them as you change it.
import 'package:shorecat_dashboard/ui/app.dart';
import 'package:shorecat_dashboard/ui/sparkline.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {AshlarThemeMode mode = AshlarThemeMode.light}) =>
    AshlarApp(
      themeMode: mode,
      home: Center(child: SizedBox(width: 200, child: child)),
    );

void main() {
  testWidgets('every kind draws in light and dark', (tester) async {
    for (final mode in AshlarThemeMode.values) {
      for (final kind in SparkKind.values) {
        await tester.pumpWidget(
          app(
            Sparkline(
              values: const [3, -2, 5, 4, 0, 6],
              kind: kind,
              band: (0, 4),
              markers: const SparkMarkers(
                high: true,
                low: true,
                first: true,
                last: true,
                values: true,
              ),
            ),
            mode: mode,
          ),
        );
        expect(tester.takeException(), isNull, reason: '$kind $mode');
      }
    }
  });

  testWidgets('a screen reader hears its span', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      app(const Sparkline(values: [4, 9, 2, 7], semanticLabel: 'Sales')),
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Sales'))
          .getSemanticsData()
          .value,
      '4 values from 4 to 7, highest 9, lowest 2',
    );
    semantics.dispose();
  });

  testWidgets('the value under the pointer is shown with its label', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const Sparkline(
          values: [4, 9, 2, 7],
          labels: ['Mon', 'Tue', 'Wed', 'Thu'],
        ),
      ),
    );
    final box = tester.getRect(find.byType(Sparkline));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(Offset(box.left + box.width / 3, box.center.dy));
    await tester.pump();
    expect(find.text('Tue  9'), findsOneWidget);
  });

  testWidgets('no values draws nothing and says so', (tester) async {
    await tester.pumpWidget(app(const Sparkline(values: [])));
    expect(tester.takeException(), isNull);
  });

  testWidgets('takes doubles and whole numbers alike', (tester) async {
    final doubles = <double>[18200, 21400, 19850];
    await tester.pumpWidget(
      app(Sparkline(values: doubles, semanticLabel: 'Balance')),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      app(Sparkline(values: <int>[3, 9, 4], kind: SparkKind.area)),
    );
    expect(tester.takeException(), isNull);
  });
}
