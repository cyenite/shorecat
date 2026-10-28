import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shorecat_code_push/shorecat_code_push.dart';

void main() {
  late FakeShorecat shorecat;

  setUp(() => shorecat = FakeShorecat());

  testWidgets('stays hidden when code push is unavailable', (tester) async {
    await tester.pumpWidget(const BannerApp(banner: ShorecatUpdateBanner()));

    expect(find.text('Update ready'), findsNothing);
  });

  testWidgets('appears when a background update becomes ready', (tester) async {
    await tester.pumpWidget(
      BannerApp(banner: ShorecatUpdateBanner(shorecat: shorecat)),
    );
    expect(find.text('Update ready'), findsNothing);

    shorecat.setPatch(1);
    await tester.pump();

    expect(find.text('Update ready'), findsOneWidget);
    expect(find.text('Restart'), findsOneWidget);
    expect(shorecat.restartCalls, 0);
  });

  testWidgets('shows an already ready patch and hides on rollback', (
    tester,
  ) async {
    shorecat.setPatch(1);
    await tester.pumpWidget(
      BannerApp(banner: ShorecatUpdateBanner(shorecat: shorecat)),
    );
    expect(find.text('Update ready'), findsOneWidget);

    shorecat.setPatch(null);
    await tester.pump();

    expect(find.text('Update ready'), findsNothing);
  });

  testWidgets('does not offer restart without a working boot hook', (
    tester,
  ) async {
    shorecat.hasBootHook = false;
    shorecat.setPatch(1);
    await tester.pumpWidget(
      BannerApp(banner: ShorecatUpdateBanner(shorecat: shorecat)),
    );

    expect(find.text('Update ready'), findsNothing);
  });

  testWidgets('Later hides only the current patch without removing it', (
    tester,
  ) async {
    shorecat.setPatch(1);
    await tester.pumpWidget(
      BannerApp(banner: ShorecatUpdateBanner(shorecat: shorecat)),
    );
    await tester.pumpAndSettle();
    await tester.tap(findLater());
    await tester.pump();

    expect(find.text('Update ready'), findsNothing);
    expect(shorecat.nextPatchNumber, 1);
    expect(shorecat.restartCalls, 0);

    shorecat.setPatch(1);
    await tester.pump();
    expect(find.text('Update ready'), findsNothing);

    shorecat.setPatch(2);
    await tester.pump();
    expect(find.text('Update ready'), findsOneWidget);
  });

  testWidgets('Restart calls the platform once and disables repeated taps', (
    tester,
  ) async {
    final pending = Completer<void>();
    shorecat.restartPending = pending.future;
    shorecat.setPatch(1);
    await tester.pumpWidget(
      BannerApp(banner: ShorecatUpdateBanner(shorecat: shorecat)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restart'));
    await tester.pump();

    expect(shorecat.restartCalls, 1);
    expect(find.text('Restarting…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    pending.complete();
    await tester.pump();
  });

  testWidgets('waits for saving work before restarting', (tester) async {
    final saved = Completer<bool>();
    shorecat.setPatch(1);
    await tester.pumpWidget(
      BannerApp(
        banner: ShorecatUpdateBanner(
          shorecat: shorecat,
          onBeforeRestart: () => saved.future,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restart'));
    await tester.pump();
    expect(shorecat.restartCalls, 0);

    saved.complete(true);
    await tester.pump();
    expect(shorecat.restartCalls, 1);
  });

  testWidgets('can cancel a restart without losing the banner', (tester) async {
    shorecat.setPatch(1);
    await tester.pumpWidget(
      BannerApp(
        banner: ShorecatUpdateBanner(
          shorecat: shorecat,
          onBeforeRestart: () async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restart'));
    await tester.pump();

    expect(shorecat.restartCalls, 0);
    expect(find.text('Restart'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('save failures show retry feedback without restarting', (
    tester,
  ) async {
    shorecat.setPatch(1);
    await tester.pumpWidget(
      BannerApp(
        banner: ShorecatUpdateBanner(
          shorecat: shorecat,
          onBeforeRestart: () async => throw StateError('Save failed'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restart'));
    await tester.pump();

    expect(shorecat.restartCalls, 0);
    expect(find.text('Could not restart. Please try again.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restart failures allow another attempt', (tester) async {
    shorecat.restartFailure = StateError('Platform unavailable');
    shorecat.setPatch(1);
    await tester.pumpWidget(
      BannerApp(banner: ShorecatUpdateBanner(shorecat: shorecat)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restart'));
    await tester.pump();
    expect(find.text('Could not restart. Please try again.'), findsOneWidget);

    shorecat.restartFailure = null;
    await tester.tap(find.text('Restart'));
    await tester.pump();

    expect(shorecat.restartCalls, 2);
    expect(find.text('Could not restart. Please try again.'), findsNothing);
  });

  testWidgets('does not restart a patch rolled back while saving', (
    tester,
  ) async {
    final saved = Completer<bool>();
    shorecat.setPatch(1);
    await tester.pumpWidget(
      BannerApp(
        banner: ShorecatUpdateBanner(
          shorecat: shorecat,
          onBeforeRestart: () => saved.future,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restart'));
    await tester.pump();
    shorecat.setPatch(null);
    saved.complete(true);
    await tester.pump();

    expect(shorecat.restartCalls, 0);
    expect(find.text('Update ready'), findsNothing);
  });

  testWidgets('does not restart after its screen is removed', (tester) async {
    final saved = Completer<bool>();
    shorecat.setPatch(1);
    await tester.pumpWidget(
      BannerApp(
        banner: ShorecatUpdateBanner(
          shorecat: shorecat,
          onBeforeRestart: () => saved.future,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restart'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    saved.complete(true);
    await tester.pump();

    expect(shorecat.restartCalls, 0);
    expect(shorecat.hasUpdateListeners, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a narrow screen with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    shorecat.setPatch(1);
    await tester.pumpWidget(
      BannerApp(textScale: 2, banner: ShorecatUpdateBanner(shorecat: shorecat)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Restart').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class BannerApp extends StatelessWidget {
  final double textScale;
  final ShorecatUpdateBanner banner;

  const BannerApp({super.key, this.textScale = 1, required this.banner});

  @override
  Widget build(BuildContext context) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: Column(
        children: [
          banner,
          const Expanded(child: SizedBox()),
        ],
      ),
    ),
  );
}

class FakeShorecat extends ChangeNotifier implements Shorecat {
  bool hasBootHook = true;
  int restartCalls = 0;
  int? pendingPatchNumber;
  Object? restartFailure;
  Future<void>? restartPending;

  bool get hasUpdateListeners => hasListeners;

  @override
  bool get isHooked => hasBootHook;

  @override
  bool get isRestartRequired => pendingPatchNumber != null;

  @override
  int? get nextPatchNumber => pendingPatchNumber;

  void setPatch(int? number) {
    pendingPatchNumber = number;
    notifyListeners();
  }

  @override
  Future<void> restart() async {
    restartCalls++;
    if (restartFailure case final error?) throw error;
    await restartPending;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The banner offers Later as a close button; dialogs and pages label it.
Finder findLater() => find.text('Later').evaluate().isEmpty
    ? find.byTooltip('Later')
    : find.text('Later');
