// Tests for Field. Copied into your app by `ashlar add field` with the component: they
// check what it promises, so change them as you change it.
import 'package:shorecat_dashboard/ui/app.dart';
import 'package:shorecat_dashboard/ui/checkbox.dart';
import 'package:shorecat_dashboard/ui/field.dart';
import 'package:shorecat_dashboard/ui/input.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {AshlarThemeMode mode = AshlarThemeMode.light}) =>
    AshlarApp(
      themeMode: mode,
      home: Center(child: child),
    );

Widget app2(Widget child) => AshlarApp(home: Center(child: child));

void main() {
  group('Field', () {
    testWidgets('a screen reader hears the label with the checkbox', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        app(
          SizedBox(
            width: 300,
            child: Field(
              axis: Axis.horizontal,
              label: const Text('Accept the terms'),
              description: const Text('You can leave at any time.'),
              child: Checkbox(value: false, onChanged: (_) {}),
            ),
          ),
        ),
      );
      final node = tester
          .getSemantics(find.byType(Checkbox))
          .getSemanticsData();
      expect(node.label, contains('Accept the terms'));
      expect(node.label, contains('You can leave at any time.'));
      semantics.dispose();
    });

    testWidgets('an input in a field is named by its label', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        app(
          const SizedBox(
            width: 300,
            child: Field(
              label: Text('Email'),
              error: Text('Enter an email'),
              child: Input(placeholder: 'you@example.com'),
            ),
          ),
        ),
      );
      // What a screen reader gets: the field with everything merged into it.
      final node = tester
          .getSemantics(find.byType(EditableText))
          .getSemanticsData();
      expect(node.label, contains('Email'));
      expect(node.label, contains('Enter an email'));
      expect(node.flagsCollection.isTextField, isTrue);
      semantics.dispose();
    });
  });

  group('Field', () {
    testWidgets(
      'a field set reads its legend; a choice card picks on a tap anywhere',
      (tester) async {
        final semantics = tester.ensureSemantics();
        var picked = false;
        await tester.pumpWidget(
          app2(
            SizedBox(
              width: 360,
              child: StatefulBuilder(
                builder: (context, set) => FieldSet(
                  legend: const Text('Plan'),
                  children: [
                    Field(
                      card: true,
                      selected: picked,
                      axis: Axis.horizontal,
                      onPressed: () => set(() => picked = !picked),
                      label: const Text('Pro'),
                      description: const Text('For teams.'),
                      child: Checkbox(
                        value: picked,
                        onChanged: (v) => set(() => picked = v),
                      ),
                    ),
                    const FieldSeparator(child: Text('or')),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(
          tester
              .getSemantics(find.text('Plan'))
              .getSemanticsData()
              .flagsCollection
              .isHeader,
          isTrue,
        );
        await tester.tap(find.text('For teams.'));
        await tester.pump();
        expect(picked, isTrue);
        expect(find.text('or'), findsOneWidget);
        semantics.dispose();
      },
    );

    testWidgets(
      'responsive: the label beside the field when wide, above it when narrow',
      (tester) async {
        for (final (width, beside) in [(600.0, true), (320.0, false)]) {
          await tester.pumpWidget(
            app2(
              SizedBox(
                width: width,
                child: const Field(
                  responsive: true,
                  label: Text('Name'),
                  child: Input(placeholder: 'Maya'),
                ),
              ),
            ),
          );
          final label = tester.getRect(find.text('Name')),
              input = tester.getRect(find.byType(Input));
          expect(input.left > label.right, beside, reason: '$width');
        }
      },
    );
  });
}
