// Tests for Alert Dialog. Copied into your app by `ashlar add alert-dialog` with the component: they
// check what it promises, so change them as you change it.
import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:shorecat_dashboard/ui/alert_dialog.dart';
import 'package:shorecat_dashboard/ui/app.dart';
import 'package:shorecat_dashboard/ui/button.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => AshlarApp(home: Center(child: child));

void main() {
  group('Alert Dialog', () {
    Future<List<bool>> open(WidgetTester tester) async {
      final answers = <bool>[];
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Button(
              onPressed: () async => answers.add(
                await showAlertDialog(
                  context,
                  title: 'Delete?',
                  action: 'Delete',
                  destructive: true,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      return answers;
    }

    testWidgets('a tap outside does nothing; Escape cancels', (tester) async {
      final answers = await open(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('Delete?'), findsOneWidget);
      expect(find.bySemanticsLabel('Close'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Delete?'), findsNothing);
      expect(answers, [false]);
    });

    testWidgets('the action answers true', (tester) async {
      final answers = await open(tester);
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(answers, [true]);
    });
  });

  testWidgets(
    'a small alert dialog is centred, its buttons sharing the width',
    (tester) async {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Button(
              onPressed: () => showAlertDialog(
                context,
                title: 'Leave?',
                small: true,
                media: const AshlarIcon(AshlarIconsRoundedStroke.info),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final cancel = tester.getRect(find.text('Cancel').first),
          go = tester.getRect(find.text('Continue'));
      expect(tester.getCenter(find.text('Leave?')).dx, closeTo(400, 1));
      expect(cancel.center.dy, go.center.dy);
      expect(
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.text('Cancel'),
                    matching: find.byType(Button),
                  )
                  .first,
            )
            .width,
        greaterThan(100),
      );
    },
  );
}
