// Tests for Card. Copied into your app by `ashlar add card` with the component: they
// check what it promises, so change them as you change it.
import 'package:shorecat_dashboard/ui/app.dart';
import 'package:shorecat_dashboard/ui/badge.dart';
import 'package:shorecat_dashboard/ui/button.dart';
import 'package:shorecat_dashboard/ui/card.dart';
import 'package:shorecat_dashboard/ui/separator.dart';
import 'package:shorecat_dashboard/ui/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// These tests measure how controls look, so without the room a finger's press area
/// takes on a phone (tap_target_test.dart covers that).
Widget app(Widget child, {AshlarThemeMode mode = AshlarThemeMode.light}) =>
    AshlarApp(
      theme: AshlarThemeData.light().copyWith(tapTarget: 0),
      darkTheme: AshlarThemeData.dark().copyWith(tapTarget: 0),
      themeMode: mode,
      home: Center(child: child),
    );

Widget app2(Widget child) => AshlarApp(home: Center(child: child));

void main() {
  group('Card, Badge and Separator', () {
    testWidgets('lay out in light and dark without overflow', (tester) async {
      for (final mode in [AshlarThemeMode.light, AshlarThemeMode.dark]) {
        await tester.pumpWidget(
          app(
            SizedBox(
              width: 360,
              child: Card(
                children: [
                  const CardHeader(
                    title: Text('Title'),
                    description: Text('Description'),
                    action: Badge(child: Text('New')),
                  ),
                  const CardContent(child: Separator()),
                  CardFooter(
                    children: [
                      Button(onPressed: () {}, child: const Text('OK')),
                    ],
                  ),
                ],
              ),
            ),
            mode: mode,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('New'), findsOneWidget);
      }
    });
  });

  testWidgets(
    'a small card pads by 16; an image runs to its edges; a header can be lined',
    (tester) async {
      await tester.pumpWidget(
        app2(
          SizedBox(
            width: 300,
            child: Card(
              size: CardSize.sm,
              children: [
                const CardImage(
                  height: 100,
                  child: ColoredBox(color: Color(0xFF888888)),
                ),
                const CardHeader(title: Text('Title'), border: true),
                CardFooter(
                  children: [Button(onPressed: () {}, child: const Text('Go'))],
                ),
              ],
            ),
          ),
        ),
      );
      final card = tester.getRect(find.byType(Card)),
          image = tester.getRect(find.byType(CardImage));
      expect(image.top, card.top + 1);
      expect(image.width, card.width - 2);
      expect(tester.getRect(find.text('Title')).left, card.left + 1 + 16);
      expect(tester.takeException(), isNull);
    },
  );
}
