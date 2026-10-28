// Tests for Form. Copied into your app by `ashlar add form` with the component: they
// check what it promises, so change them as you change it.
import 'package:shorecat_dashboard/ui/app.dart';
import 'package:shorecat_dashboard/ui/button.dart';
import 'package:shorecat_dashboard/ui/checkbox.dart';
import 'package:shorecat_dashboard/ui/form.dart';
import 'package:shorecat_dashboard/ui/input.dart';
import 'package:shorecat_dashboard/ui/select.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _SignUp extends StatefulWidget {
  const _SignUp({required this.saved, this.sent});

  final Map<String, Object?> saved;
  final ValueChanged<bool>? sent;

  @override
  State<_SignUp> createState() => _SignUpState();
}

Future<Map<String, Object?>> pumpForm(
  WidgetTester tester, {
  List<bool>? results,
}) async {
  final saved = <String, Object?>{};
  await tester.pumpWidget(
    AshlarApp(
      home: _SignUp(saved: saved, sent: results?.add),
    ),
  );
  return saved;
}

Finder input(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(FormText)),
  matching: find.byType(EditableText),
);

class _SignUpState extends State<_SignUp> {
  final form = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Form(
      key: form,
      child: Column(
        children: [
          FormText(
            label: const Text('Name'),
            validator: Validate.required('Enter your name.'),
            onSaved: (v) => widget.saved['name'] = v,
          ),
          FormText(
            label: const Text('Email'),
            initialValue: 'ama@',
            validator: Validate.all([Validate.required(), Validate.email()]),
            onSaved: (v) => widget.saved['email'] = v,
          ),
          FormItem<String>(
            label: const Text('Team'),
            validator: Validate.required('Pick a team.'),
            onSaved: (v) => widget.saved['team'] = v,
            builder: (field) => Select<String>(
              value: field.value,
              placeholder: 'Choose',
              error: field.hasError,
              options: const [
                SelectOption('design', 'Design'),
                SelectOption('engineering', 'Engineering'),
              ],
              onChanged: field.didChange,
            ),
          ),
          FormItem<bool>(
            initialValue: false,
            axis: Axis.horizontal,
            label: const Text('Accept the terms'),
            validator: Validate.required('Accept the terms to go on.'),
            onSaved: (v) => widget.saved['terms'] = v,
            builder: (field) => Checkbox(
              value: field.value!,
              error: field.hasError,
              onChanged: field.didChange,
            ),
          ),
          Button(
            onPressed: () {
              final ok = form.currentState!.submit();
              widget.sent?.call(ok);
            },
            child: const Text('Create account'),
          ),
          Button(
            onPressed: () => form.currentState!.reset(),
            child: const Text('Reset'),
          ),
        ],
      ),
    ),
  );
}

void main() {
  group('Validate', () {
    test('required turns down nothing, blanks, empty lists and false', () {
      final check = Validate.required<Object?>('No');
      expect(check(null), 'No');
      expect(check('  '), 'No');
      expect(check(const <int>[]), 'No');
      expect(check(false), 'No');
      expect(check('a'), isNull);
      expect(check(true), isNull);
      expect(check(0), isNull);
    });

    test('lengths, email, numbers, and the first message of several wins', () {
      expect(Validate.minLength(3)('ab'), 'At least 3 characters.');
      expect(Validate.minLength(3)('abc'), isNull);
      expect(Validate.maxLength(1)('ab'), 'At most 1 character.');
      expect(Validate.email()('ama@example.com'), isNull);
      expect(Validate.email()('ama@'), 'Enter an email address.');
      expect(Validate.email()(''), isNull);
      expect(Validate.min(18)(17), 'At least 18.');
      expect(Validate.max(99)(100), 'At most 99.');
      final both = Validate.all<String>([
        Validate.required('First'),
        Validate.minLength(5, 'Second'),
      ]);
      expect(both(''), 'First');
      expect(both('abc'), 'Second');
      expect(both('abcdef'), isNull);
    });
  });

  testWidgets('no errors show before the form is sent, even while typing', (
    tester,
  ) async {
    await pumpForm(tester);
    await tester.enterText(input('Name'), 'A');
    await tester.enterText(input('Name'), '');
    await tester.pump();
    expect(find.text('Enter your name.'), findsNothing);
  });

  testWidgets(
    'sending shows each error under its field and focuses the first wrong one',
    (tester) async {
      final results = <bool>[];
      final saved = await pumpForm(tester, results: results);
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(results, [false]);
      expect(saved, isEmpty);
      expect(find.text('Enter your name.'), findsOneWidget);
      expect(find.text('Enter an email address.'), findsOneWidget);
      expect(find.text('Pick a team.'), findsOneWidget);
      expect(find.text('Accept the terms to go on.'), findsOneWidget);
      // Focus is in the Name input, the first on screen.
      final focused = FocusManager.instance.primaryFocus!;
      expect(
        tester.widget<EditableText>(input('Name')).focusNode,
        same(focused),
      );
      // The controls are marked too.
      expect(
        tester
            .widget<Input>(
              find.descendant(
                of: find.ancestor(
                  of: find.text('Name'),
                  matching: find.byType(FormText),
                ),
                matching: find.byType(Input),
              ),
            )
            .error,
        isTrue,
      );
    },
  );

  testWidgets('after sending, each error clears as it is put right', (
    tester,
  ) async {
    await pumpForm(tester);
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.enterText(input('Name'), 'Ama');
    await tester.pump();
    expect(find.text('Enter your name.'), findsNothing);
    expect(find.text('Enter an email address.'), findsOneWidget);
    await tester.enterText(input('Email'), 'ama@example.com');
    await tester.pump();
    expect(find.text('Enter an email address.'), findsNothing);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(find.text('Accept the terms to go on.'), findsNothing);
    // Still wrong: the team. Focus goes there now.
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a team.'), findsOneWidget);
    final team = find.ancestor(
      of: find.text('Team'),
      matching: find.byType(FormItem<String>),
    );
    expect(
      find
          .descendant(of: team, matching: find.byType(Focus))
          .evaluate()
          .map((e) => (e.widget as Focus).focusNode)
          .contains(FocusManager.instance.primaryFocus),
      isTrue,
    );
  });

  testWidgets('a right form saves every value and says so', (tester) async {
    final results = <bool>[];
    final saved = await pumpForm(tester, results: results);
    await tester.enterText(input('Name'), 'Ama');
    await tester.enterText(input('Email'), 'ama@example.com');
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Design').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Create account'));
    await tester.pump();
    expect(results, [true]);
    expect(saved, {
      'name': 'Ama',
      'email': 'ama@example.com',
      'team': 'design',
      'terms': true,
    });
  });

  testWidgets('reset puts the first values back, text included', (
    tester,
  ) async {
    await pumpForm(tester);
    await tester.enterText(input('Email'), 'ama@example.com');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(tester.widget<EditableText>(input('Email')).controller.text, 'ama@');
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    expect(find.text('Enter your name.'), findsNothing);
  });

  testWidgets('a screen reader hears the error with the field', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpForm(tester);
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    final data = tester.getSemantics(input('Name')).getSemanticsData();
    expect('${data.label} ${data.hint}', contains('Enter your name.'));
    semantics.dispose();
  });

  testWidgets('text set on its controller becomes the value', (tester) async {
    final controller = TextEditingController();
    String? saved;
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(
      AshlarApp(
        home: Form(
          key: form,
          child: FormText(
            controller: controller,
            label: const Text('Code'),
            validator: Validate.minLength(4),
            onSaved: (v) => saved = v,
          ),
        ),
      ),
    );
    controller.text = 'KE-1234';
    await tester.pump();
    expect(form.currentState!.submit(), isTrue);
    expect(saved, 'KE-1234');
    controller.dispose();
  });
}
