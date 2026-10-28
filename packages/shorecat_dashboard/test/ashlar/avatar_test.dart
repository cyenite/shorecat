// Tests for Avatar. Copied into your app by `ashlar add avatar` with the component: they
// check what it promises, so change them as you change it.
import 'package:shorecat_dashboard/ui/app.dart';
import 'package:shorecat_dashboard/ui/avatar.dart';
import 'package:shorecat_dashboard/ui/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// These tests measure how controls look, so without the room a finger's press area
/// takes on a phone (tap_target_test.dart covers that).
Widget app(Widget child) => AshlarApp(
  theme: AshlarThemeData.light().copyWith(tapTarget: 0),
  home: Center(child: child),
);

void main() {
  testWidgets('an avatar group overlaps, counts the rest, and is read as one', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      app(
        const AvatarGroup(
          max: 2,
          children: [
            Avatar(fallback: 'MT', semanticLabel: 'Maya'),
            Avatar(fallback: 'KM', semanticLabel: 'Kofi'),
            Avatar(fallback: 'AN', semanticLabel: 'Aiko'),
            Avatar(fallback: 'LH', semanticLabel: 'Luis', badge: AvatarDot()),
          ],
        ),
      ),
    );
    expect(find.text('+2'), findsOneWidget);
    expect(find.text('AN'), findsNothing);
    expect(
      tester.getRect(find.text('KM')).left,
      lessThan(tester.getRect(find.text('MT')).right + 4),
    );
    expect(
      find.bySemanticsLabel('Maya, Kofi, Aiko, Luis'),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
