// Tests for Slider. Copied into your app by `ashlar add slider` with the component: they
// check what it promises, so change them as you change it.
import 'package:shorecat_dashboard/ui/app.dart';
import 'package:shorecat_dashboard/ui/slider.dart';
import 'package:shorecat_dashboard/ui/theme.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => AshlarApp(home: Center(child: child));

/// These tests measure how controls look, so without the room a finger's press area
/// takes on a phone (tap_target_test.dart covers that).
Widget app2(Widget child) => AshlarApp(
  theme: AshlarThemeData.light().copyWith(tapTarget: 0),
  home: Center(child: child),
);

void main() {
  group('Slider', () {
    Future<List<double>> slider(
      WidgetTester tester, {
      double value = .5,
      double? step,
    }) async {
      final seen = <double>[];
      var v = value;
      await tester.pumpWidget(
        app(
          SizedBox(
            width: 216,
            child: StatefulBuilder(
              builder: (context, set) => Slider(
                value: v,
                step: step,
                semanticLabel: 'Volume',
                onChanged: (x) => set(() {
                  v = x;
                  seen.add(x);
                }),
              ),
            ),
          ),
        ),
      );
      return seen;
    }

    testWidgets('a tap sets the value where it lands', (tester) async {
      final seen = await slider(tester);
      final box = tester.getRect(find.byType(Slider));
      // The thumb's centre runs from 8 to 208 on a 216 wide track.
      await tester.tapAt(Offset(box.left + 8 + 50, box.center.dy));
      expect(seen.last, closeTo(.25, .01));
    });

    testWidgets('the keys step, page and jump to the ends', (tester) async {
      final seen = await slider(tester, step: .1);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(seen.last, closeTo(.6, 1e-9));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(seen.last, closeTo(.4, 1e-9));
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      expect(seen.last, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      expect(seen.last, 0);
    });

    testWidgets(
      'a screen reader hears a slider with its value, and can move it',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final seen = await slider(tester, step: .1);
        final node = tester.getSemantics(find.bySemanticsLabel('Volume'));
        final data = node.getSemanticsData();
        expect(data.flagsCollection.isSlider, isTrue);
        expect(data.label, 'Volume');
        expect(data.value, '50%');
        expect(data.increasedValue, '60%');
        node.owner!.performAction(node.id, SemanticsAction.increase);
        expect(seen.last, closeTo(.6, 1e-9));
        semantics.dispose();
      },
    );
  });

  group('Slider', () {
    testWidgets(
      'a range moves the thumb nearest the tap, and the thumbs never cross',
      (tester) async {
        final semantics = tester.ensureSemantics();
        var range = (.2, .6);
        await tester.pumpWidget(
          app2(
            SizedBox(
              width: 216,
              child: StatefulBuilder(
                builder: (context, set) => Slider.range(
                  values: range,
                  step: .1,
                  semanticLabel: 'Price',
                  onRangeChanged: (r) => set(() => range = r),
                ),
              ),
            ),
          ),
        );
        final box = tester.getRect(find.byType(Slider));
        await tester.tapAt(Offset(box.left + 8 + 180, box.center.dy));
        await tester.pump();
        expect(range.$1, closeTo(.2, 1e-9));
        expect(range.$2, closeTo(.9, 1e-9));
        expect(find.bySemanticsLabel('Price, lowest'), findsOneWidget);
        expect(find.bySemanticsLabel('Price, highest'), findsOneWidget);
        // The low thumb, pushed past the high one, stops at it.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        for (var i = 0; i < 12; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump();
        }
        expect(range.$1, closeTo(.9, 1e-9));
        semantics.dispose();
      },
    );

    testWidgets('upright, the lowest value is at the bottom', (tester) async {
      var v = 0.0;
      await tester.pumpWidget(
        app2(
          StatefulBuilder(
            builder: (context, set) => Slider(
              value: v,
              axis: Axis.vertical,
              length: 216,
              onChanged: (x) => set(() => v = x),
            ),
          ),
        ),
      );
      final box = tester.getRect(find.byType(Slider));
      expect(box.height, 216);
      await tester.tapAt(Offset(box.center.dx, box.top + 8 + 50));
      expect(v, closeTo(.75, .01));
    });
  });
}
