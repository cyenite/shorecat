// Tests for Appearance Picker. Copied into your app by `ashlar add appearance-picker` with
// the component: they check what it promises, so change them as you change it.
import 'dart:ui' show CheckedState;

import 'package:shorecat_dashboard/ui/app.dart';
import 'package:shorecat_dashboard/ui/appearance_picker.dart';
import 'package:shorecat_dashboard/ui/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => AshlarApp(
  home: Center(child: SizedBox(width: 360, child: child)),
);

void main() {
  group('Appearance Picker', () {
    testWidgets('picks System, Light or Dark; the one chosen is checked', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var mode = AshlarThemeMode.system;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, set) => AppearancePicker(
              value: mode,
              onChanged: (m) => set(() => mode = m),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(mode, AshlarThemeMode.dark);
      final dark = tester.getSemantics(find.bySemanticsLabel('Dark'));
      expect(
        dark.getSemanticsData().flagsCollection.isChecked,
        CheckedState.isTrue,
      );
      final light = tester.getSemantics(find.bySemanticsLabel('Light'));
      expect(
        light.getSemanticsData().flagsCollection.isChecked,
        CheckedState.isFalse,
      );
      semantics.dispose();
    });

    testWidgets('each screen is drawn in its own theme\'s colours', (
      tester,
    ) async {
      final light = AshlarThemeData.light();
      final dark = AshlarThemeData.dark();
      await tester.pumpWidget(
        app(
          AppearancePicker(
            value: AshlarThemeMode.light,
            onChanged: (_) {},
            light: light,
            dark: dark,
          ),
        ),
      );
      final backgrounds = {
        for (final box in tester.widgetList<Container>(find.byType(Container)))
          if (box.color != null) box.color,
      };
      expect(
        backgrounds,
        containsAll([light.colors.background, dark.colors.background]),
      );
    });
  });
}
