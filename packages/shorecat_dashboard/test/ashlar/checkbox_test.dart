// Tests for Checkbox. Copied into your app by `ashlar add checkbox` with the component: they
// check what it promises, so change them as you change it.
import 'dart:ui' show CheckedState;

import 'package:shorecat_dashboard/ui/app.dart';
import 'package:shorecat_dashboard/ui/checkbox.dart';
import 'package:shorecat_dashboard/ui/switch.dart';
import 'package:shorecat_dashboard/ui/theme.dart';
import 'package:flutter/services.dart';
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

/// These tests measure how controls look, so without the room a finger's press area
/// takes on a phone (tap_target_test.dart covers that).
Widget app2(Widget child) => AshlarApp(
  theme: AshlarThemeData.light().copyWith(tapTarget: 0),
  home: Center(child: child),
);

void main() {
  group('Checkbox and Switch', () {
    testWidgets(
      'a checkbox toggles by tap and by Space, and says whether it is checked',
      (tester) async {
        final semantics = tester.ensureSemantics();
        var value = false;
        await tester.pumpWidget(
          app(
            StatefulBuilder(
              builder: (context, set) => Checkbox(
                value: value,
                onChanged: (v) => set(() => value = v),
                semanticLabel: 'Terms',
              ),
            ),
          ),
        );
        await tester.tap(find.byType(Checkbox));
        await tester.pump();
        expect(value, isTrue);
        expect(
          tester.getSemantics(
            find
                .descendant(
                  of: find.byType(Checkbox),
                  matching: find.byType(MergeSemantics),
                )
                .first,
          ),
          matchesSemantics(
            label: 'Terms',
            hasCheckedState: true,
            isChecked: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
            isFocusable: true,
            hasFocusAction: true,
          ),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(value, isFalse);
        semantics.dispose();
      },
    );

    testWidgets('a switch toggles and says whether it is on', (tester) async {
      final semantics = tester.ensureSemantics();
      var value = false;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, set) => Switch(
              value: value,
              onChanged: (v) => set(() => value = v),
              semanticLabel: 'Wi-Fi',
            ),
          ),
        ),
      );
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(value, isTrue);
      expect(
        tester.getSemantics(
          find
              .descendant(
                of: find.byType(Switch),
                matching: find.byType(MergeSemantics),
              )
              .first,
        ),
        matchesSemantics(
          label: 'Wi-Fi',
          hasToggledState: true,
          isToggled: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('disabled, neither changes', (tester) async {
      await tester.pumpWidget(
        app(
          const Column(
            children: [
              Checkbox(value: false, onChanged: null),
              Switch(value: false, onChanged: null),
            ],
          ),
        ),
      );
      await tester.tap(find.byType(Checkbox), warnIfMissed: false);
      await tester.tap(find.byType(Switch), warnIfMissed: false);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('an indeterminate checkbox reads as mixed and ticks on a tap', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    bool? value;
    await tester.pumpWidget(
      app2(
        Checkbox(
          value: false,
          indeterminate: true,
          semanticLabel: 'All',
          onChanged: (v) => value = v,
        ),
      ),
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('All'))
          .getSemanticsData()
          .flagsCollection
          .isChecked,
      CheckedState.mixed,
    );
    await tester.tap(find.byType(Checkbox));
    expect(value, isTrue);
    semantics.dispose();
  });
}
