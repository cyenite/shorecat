// Tests for Item. Copied into your app by `ashlar add item` with the component: they
// check what it promises, so change them as you change it.
import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:shorecat_dashboard/ui/app.dart';
import 'package:shorecat_dashboard/ui/item.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {AshlarThemeMode mode = AshlarThemeMode.light}) =>
    AshlarApp(
      themeMode: mode,
      home: Center(child: child),
    );

Widget app2(Widget child) => AshlarApp(home: Center(child: child));

void main() {
  testWidgets('every variant lays out in light and dark', (tester) async {
    for (final mode in AshlarThemeMode.values) {
      await tester.pumpWidget(
        app(
          SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final v in ItemVariant.values)
                  Item(
                    variant: v,
                    title: const Text('Title'),
                    description: const Text('Description'),
                  ),
              ],
            ),
          ),
          mode: mode,
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('an item with onPressed is a button, by tap and by keyboard', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var n = 0;
    await tester.pumpWidget(
      app(
        SizedBox(
          width: 300,
          child: Item(title: const Text('Open'), onPressed: () => n++),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(n, 2);
    expect(
      tester
          .getSemantics(find.text('Open'))
          .getSemanticsData()
          .flagsCollection
          .isButton,
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('item sizes, media and a group with a line between items', (
    tester,
  ) async {
    await tester.pumpWidget(
      app2(
        const SizedBox(
          width: 360,
          child: ItemGroup(
            children: [
              Item(
                size: ItemSize.sm,
                leading: ItemMedia.icon(
                  AshlarIcon(AshlarIconsRoundedStroke.inbox),
                ),
                title: Text('Inbox'),
              ),
              Item(
                size: ItemSize.xs,
                title: Text('Sent'),
                header: Text('Today'),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(ItemSeparator), findsOneWidget);
    expect(
      tester.getSize(find.byType(Item).last).height,
      lessThan(tester.getSize(find.byType(Item).first).height + 24),
    );
    expect(tester.takeException(), isNull);
  });
}
