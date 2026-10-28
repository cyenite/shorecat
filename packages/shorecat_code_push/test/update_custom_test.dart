import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shorecat_code_push/shorecat_code_push.dart';

import 'update_banner_test.dart' show FakeShorecat;

void main() {
  for (final presentation in ShorecatUpdatePresentation.values) {
    testWidgets('${presentation.label} renders a custom builder', (
      tester,
    ) async {
      final shorecat = FakeShorecat();
      await tester.pumpWidget(
        CustomPromptApp(shorecat: shorecat, presentation: presentation),
      );
      expect(find.text('Custom patch'), findsNothing);

      shorecat.setPatch(4);
      await tester.pumpAndSettle();
      expect(find.text('Custom patch 4'), findsOneWidget);
      expect(find.text('Update ready'), findsNothing);
      expect(find.text('Screen', skipOffstage: false), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Custom patch 4'), findsNothing);
      expect(shorecat.restartCalls, 0);

      shorecat.setPatch(5);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pump();
      expect(shorecat.restartCalls, 1);
    });
  }

  testWidgets('a custom dialog treats Back as Later', (tester) async {
    final shorecat = FakeShorecat()..setPatch(1);
    await tester.pumpWidget(
      CustomPromptApp(
        shorecat: shorecat,
        presentation: ShorecatUpdatePresentation.dialog,
      ),
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Custom patch 1'), findsNothing);
    expect(find.text('Screen'), findsOneWidget);
    expect(shorecat.restartCalls, 0);
  });

  testWidgets('ShorecatUpdateBuilder exposes state and restarts after Later', (
    tester,
  ) async {
    final shorecat = FakeShorecat();
    final saved = Completer<bool>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShorecatUpdateBuilder(
            shorecat: shorecat,
            onBeforeRestart: () => saved.future,
            builder: (context, update) => Column(
              children: [
                Text('required=${update.isRestartRequired}'),
                Text('visible=${update.isVisible}'),
                Text('deferred=${update.isDeferred}'),
                Text('patch=${update.patchNumber}'),
                Text('restarting=${update.isRestarting}'),
                TextButton(onPressed: update.defer, child: const Text('Defer')),
                TextButton(
                  onPressed: update.restart,
                  child: const Text('Restart now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('required=false'), findsOneWidget);
    expect(find.text('patch=null'), findsOneWidget);

    shorecat.setPatch(2);
    await tester.pump();
    expect(find.text('visible=true'), findsOneWidget);
    expect(find.text('patch=2'), findsOneWidget);

    await tester.tap(find.text('Defer'));
    await tester.pump();
    expect(find.text('visible=false'), findsOneWidget);
    expect(find.text('deferred=true'), findsOneWidget);
    expect(find.text('required=true'), findsOneWidget);

    await tester.tap(find.text('Restart now'));
    await tester.pump();
    expect(find.text('restarting=true'), findsOneWidget);
    expect(shorecat.restartCalls, 0);
    saved.complete(true);
    await tester.pump();
    expect(shorecat.restartCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(shorecat.hasUpdateListeners, isFalse);
  });

  testWidgets('a controller reports restart failures for retry', (
    tester,
  ) async {
    final shorecat = FakeShorecat()
      ..setPatch(3)
      ..restartFailure = StateError('Platform unavailable');
    final update = ShorecatUpdateController(shorecat: shorecat);
    addTearDown(update.dispose);

    await update.restart();
    expect(update.hasRestartFailed, isTrue);
    expect(update.isRestarting, isFalse);

    shorecat.restartFailure = null;
    await update.restart();
    expect(update.hasRestartFailed, isFalse);
    expect(shorecat.restartCalls, 2);
  });

  test('a controller ignores restart when no patch waits', () async {
    final shorecat = FakeShorecat();
    final update = ShorecatUpdateController(shorecat: shorecat);
    addTearDown(update.dispose);

    await update.restart();
    expect(shorecat.restartCalls, 0);
    expect(update.isVisible, isFalse);
  });
}

class CustomPromptApp extends StatelessWidget {
  final FakeShorecat shorecat;
  final ShorecatUpdatePresentation presentation;

  const CustomPromptApp({
    super.key,
    required this.shorecat,
    required this.presentation,
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: ShorecatUpdatePrompt(
        shorecat: shorecat,
        presentation: presentation,
        builder: (context, update) => CustomUpdate(update: update),
        child: const Text('Screen'),
      ),
    ),
  );
}

class CustomUpdate extends StatelessWidget {
  final ShorecatUpdateController update;

  const CustomUpdate({super.key, required this.update});

  @override
  Widget build(BuildContext context) => Material(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Custom patch ${update.patchNumber}'),
        TextButton(onPressed: update.defer, child: const Text('Not now')),
        TextButton(onPressed: update.restart, child: const Text('Apply')),
      ],
    ),
  );
}
