// Tests for Heatmap. Copied into your app by `ashlar add heatmap` with the component:
// they check what it promises, so change them as you change it.
import 'package:shorecat_dashboard/ui/app.dart';
import 'package:shorecat_dashboard/ui/heatmap.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {AshlarThemeMode mode = AshlarThemeMode.light}) => AshlarApp(
  themeMode: mode,
  home: Center(child: SizedBox(width: 480, child: child)),
);

typedef Load = ({String day, String hour, double v});

const load = <Load>[
  (day: 'Mon', hour: '9h', v: 10),
  (day: 'Mon', hour: '12h', v: 40),
  (day: 'Tue', hour: '9h', v: 25),
  (day: 'Tue', hour: '12h', v: 5),
];

void main() {
  testWidgets('a grid and a calendar draw in light and dark', (tester) async {
    for (final mode in AshlarThemeMode.values) {
      await tester.pumpWidget(
        app(Heatmap<Load>(data: load, x: (r) => r.hour, y: (r) => r.day, value: (r) => r.v, values: true, steps: 4), mode: mode),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        app(
          CalendarHeatmap(values: {DateTime(2026, 3, 2): 4, DateTime(2026, 3, 9): 9}, to: DateTime(2026, 3, 31)),
          mode: mode,
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the cell under the pointer shows its place and value', (tester) async {
    await tester.pumpWidget(app(Heatmap<Load>(data: load, x: (r) => r.hour, y: (r) => r.day, value: (r) => r.v)));
    final box = tester.getRect(find.byType(Heatmap<Load>));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    // Monday, the second column: past the labels, three quarters along.
    await mouse.moveTo(Offset(box.left + box.width * .8, box.top + 14));
    await tester.pump();
    expect(find.text('Mon · 12h'), findsOneWidget);
    expect(find.text('40'), findsWidgets);
  });

  testWidgets('a tapped day is given to the app', (tester) async {
    DateTime? tapped;
    await tester.pumpWidget(
      app(
        CalendarHeatmap(
          values: {DateTime(2026, 3, 2): 4},
          from: DateTime(2026, 3, 2),
          to: DateTime(2026, 3, 8),
          onSelect: (d) => tapped = d,
        ),
      ),
    );
    // The first week's Monday: past the day names, below the months.
    final box = tester.getRect(find.byType(CalendarHeatmap));
    await tester.tapAt(box.topLeft + const Offset(28 + 6, 16 + 6));
    expect(tapped, DateTime(2026, 3, 2));
  });
}
