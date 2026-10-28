import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shorecat_code_push/shorecat_code_push.dart';

import 'update_banner_test.dart' show FakeShorecat, findLater;

void main() {
  for (final presentation in ShorecatUpdatePresentation.values) {
    testWidgets('${presentation.label} preserves the screen when deferred', (
      tester,
    ) async {
      final shorecat = FakeShorecat();
      await tester.pumpWidget(
        PromptApp(shorecat: shorecat, presentation: presentation),
      );
      await tester.enterText(find.byType(TextField), 'Unsaved work');
      shorecat.setPatch(1);
      await tester.pumpAndSettle();
      expect(find.text('Restart'), findsOneWidget);

      shorecat.setPatch(1);
      await tester.pumpAndSettle();
      expect(find.text('Restart'), findsOneWidget);
      await tester.tap(findLater());
      await tester.pumpAndSettle();

      expect(find.text('Restart'), findsNothing);
      expect(find.text('Unsaved work'), findsOneWidget);
      expect(shorecat.nextPatchNumber, 1);
      expect(shorecat.restartCalls, 0);

      shorecat.setPatch(2);
      await tester.pumpAndSettle();
      expect(find.text('Restart'), findsOneWidget);
    });

    testWidgets('${presentation.label} restarts only on a user action', (
      tester,
    ) async {
      final shorecat = FakeShorecat()..setPatch(1);
      await tester.pumpWidget(
        PromptApp(shorecat: shorecat, presentation: presentation),
      );
      await tester.pumpAndSettle();
      expect(shorecat.restartCalls, 0);
      await tester.tap(find.text('Restart'));
      await pumpWhileRestarting(tester);
      expect(shorecat.restartCalls, 1);
      expect(find.text('Restarting…'), findsOneWidget);
    });

    testWidgets('${presentation.label} disappears when a patch is withdrawn', (
      tester,
    ) async {
      final shorecat = FakeShorecat()..setPatch(1);
      await tester.pumpWidget(
        PromptApp(shorecat: shorecat, presentation: presentation),
      );
      await tester.pumpAndSettle();
      expect(find.text('Restart'), findsOneWidget);
      shorecat.setPatch(null);
      await tester.pumpAndSettle();
      expect(find.text('Restart'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${presentation.label} fits large text on a small screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final shorecat = FakeShorecat()..setPatch(1);
      await tester.pumpWidget(
        PromptApp(shorecat: shorecat, presentation: presentation, textScale: 2),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Restart'));
      expect(find.text('Restart').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the banner leaves the rest of the height to the screen', (
    tester,
  ) async {
    final shorecat = FakeShorecat()..setPatch(1);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShorecatUpdatePrompt(
            shorecat: shorecat,
            child: const SizedBox.expand(key: Key('screen')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final screen = tester.getSize(find.byKey(const Key('screen'))).height;
    final banner = tester.getSize(find.byType(SingleChildScrollView)).height;
    expect(screen + banner, 600);
    expect(banner, lessThan(200));
  });

  for (final presentation in [
    ShorecatUpdatePresentation.dialog,
    ShorecatUpdatePresentation.page,
  ]) {
    testWidgets('${presentation.label} handles Android back as Later', (
      tester,
    ) async {
      final shorecat = FakeShorecat()..setPatch(1);
      await tester.pumpWidget(
        PromptApp(shorecat: shorecat, presentation: presentation),
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Restart'), findsNothing);
      expect(shorecat.nextPatchNumber, 1);
      expect(shorecat.restartCalls, 0);
    });

    testWidgets('${presentation.label} prevents back during preparation', (
      tester,
    ) async {
      final saved = Completer<bool>();
      final shorecat = FakeShorecat()..setPatch(1);
      await tester.pumpWidget(
        PromptApp(
          shorecat: shorecat,
          presentation: presentation,
          onBeforeRestart: () => saved.future,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restart'));
      await pumpWhileRestarting(tester);
      await tester.binding.handlePopRoute();
      await pumpWhileRestarting(tester);
      expect(find.text('Restarting…'), findsOneWidget);
      expect(shorecat.restartCalls, 0);

      saved.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('Restart'), findsOneWidget);
    });
  }

  testWidgets('changing presentation removes only the owned prompt route', (
    tester,
  ) async {
    final shorecat = FakeShorecat()..setPatch(1);
    await tester.pumpWidget(
      PromptApp(
        shorecat: shorecat,
        presentation: ShorecatUpdatePresentation.dialog,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.pumpWidget(
      PromptApp(
        shorecat: shorecat,
        presentation: ShorecatUpdatePresentation.page,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Restart'), findsOneWidget);
    await tester.tap(findLater());
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing the host closes its dialog and detaches listeners', (
    tester,
  ) async {
    final shorecat = FakeShorecat()..setPatch(1);
    final showHost = ValueNotifier(true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: showHost,
            builder: (context, isShown, _) => isShown
                ? ShorecatUpdatePrompt(
                    shorecat: shorecat,
                    presentation: ShorecatUpdatePresentation.dialog,
                  )
                : const Text('Host removed'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    showHost.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(shorecat.hasUpdateListeners, isFalse);
    expect(tester.takeException(), isNull);
    showHost.dispose();
  });

  testWidgets('withdrawal does not pop another screen above the prompt', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final shorecat = FakeShorecat()..setPatch(1);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: ShorecatUpdatePrompt(
            shorecat: shorecat,
            presentation: ShorecatUpdatePresentation.dialog,
            child: const Text('Original screen'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (context) => const Scaffold(body: Text('Other screen')),
      ),
    );
    await tester.pumpAndSettle();
    shorecat.setPatch(null);
    await tester.pumpAndSettle();

    expect(find.text('Other screen'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Original screen'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('replacing the updater detaches the old instance and its route', (
    tester,
  ) async {
    final previous = FakeShorecat()..setPatch(1);
    final current = FakeShorecat();
    await tester.pumpWidget(
      PromptApp(
        shorecat: previous,
        presentation: ShorecatUpdatePresentation.dialog,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.pumpWidget(
      PromptApp(
        shorecat: current,
        presentation: ShorecatUpdatePresentation.dialog,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(previous.hasUpdateListeners, isFalse);

    current.setPatch(2);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// The restart progress indicator never settles, so advance past transitions.
Future<void> pumpWhileRestarting(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

class PromptApp extends StatelessWidget {
  final double textScale;
  final FakeShorecat shorecat;
  final ShorecatUpdatePresentation presentation;
  final Future<bool> Function()? onBeforeRestart;

  const PromptApp({
    super.key,
    this.textScale = 1,
    required this.shorecat,
    required this.presentation,
    this.onBeforeRestart,
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: ShorecatUpdatePrompt(
        shorecat: shorecat,
        presentation: presentation,
        onBeforeRestart: onBeforeRestart,
        child: const SingleChildScrollView(child: TextField()),
      ),
    ),
  );
}
