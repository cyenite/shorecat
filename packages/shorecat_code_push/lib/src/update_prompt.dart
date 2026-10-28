import 'package:flutter/material.dart';

import '../shorecat_code_push.dart';
import 'update_banner_view.dart';
import 'update_dialog_view.dart';
import 'update_page_view.dart';

enum ShorecatUpdatePresentation {
  banner('Banner'),
  dialog('Dialog'),
  page('Full page');

  final String label;

  const ShorecatUpdatePresentation(this.label);
}

/// Displays a ready patch as a banner, dialog or full page.
/// Place below a MaterialApp's Navigator, such as inside a route's Scaffold.
/// The child stays mounted while a dialog or full page is displayed.
///
/// Pass [builder] to draw your own content in the chosen presentation.
class ShorecatUpdatePrompt extends StatefulWidget {
  final String title;
  final String message;
  final String laterLabel;
  final String restartLabel;
  final String restartingLabel;
  final String restartErrorMessage;
  final Widget? child;
  final Shorecat? shorecat;
  final ShorecatUpdatePresentation presentation;

  /// Replaces the built-in content with your own. The prompt still decides
  /// when it shows and where: inline for a banner, in a dialog route (return a
  /// `Dialog`) or a full-screen route (return a `Scaffold`). Back acts as Later
  /// and is blocked while restarting. The copy fields are then unused.
  final ShorecatUpdateWidgetBuilder? builder;

  /// Save work or ask for confirmation; return false to cancel the restart.
  /// Exceptions show [restartErrorMessage] and let the user try again.
  final Future<bool> Function()? onBeforeRestart;

  const ShorecatUpdatePrompt({
    super.key,
    this.title = 'Update ready',
    this.message = 'Restart to apply the latest version.',
    this.laterLabel = 'Later',
    this.restartLabel = 'Restart',
    this.restartingLabel = 'Restarting…',
    this.restartErrorMessage = 'Could not restart. Please try again.',
    this.child,
    this.shorecat,
    this.presentation = ShorecatUpdatePresentation.banner,
    this.builder,
    this.onBeforeRestart,
  });

  @override
  State<ShorecatUpdatePrompt> createState() => _ShorecatUpdatePromptState();
}

class _ShorecatUpdatePromptState extends State<ShorecatUpdatePrompt> {
  bool _isScheduled = false;
  bool _needsRouteRefresh = false;
  ModalRoute<void>? _route;
  late ShorecatUpdateController _controller;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    _controller = ShorecatUpdateController(
      shorecat: widget.shorecat,
      onBeforeRestart: () async => await widget.onBeforeRestart?.call() ?? true,
    )..addListener(_schedulePresentation);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedulePresentation();
  }

  @override
  void didUpdateWidget(covariant ShorecatUpdatePrompt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shorecat != widget.shorecat) {
      _controller.dispose();
      _attach();
      _needsRouteRefresh = true;
    }
    if (oldWidget.presentation != widget.presentation) {
      _needsRouteRefresh = true;
    }
    _schedulePresentation();
  }

  void _closeRoute() {
    final route = _route;
    _route = null;
    if (route?.isActive == true) route!.navigator?.removeRoute(route);
  }

  void _schedulePresentation() {
    if (_isScheduled) return;
    _isScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isScheduled = false;
      if (!mounted) return;
      if (_needsRouteRefresh) {
        _needsRouteRefresh = false;
        _closeRoute();
      }
      if (!_controller.isVisible ||
          widget.presentation == ShorecatUpdatePresentation.banner) {
        _closeRoute();
        return;
      }
      if (_route != null) return;
      final navigator = Navigator.of(context, rootNavigator: true);
      Widget body(BuildContext context) =>
          _UpdateRouteBody(prompt: widget, controller: _controller);
      final route = widget.presentation == ShorecatUpdatePresentation.dialog
          ? DialogRoute<void>(
              context: context,
              barrierDismissible: false,
              builder: body,
            )
          : MaterialPageRoute<void>(fullscreenDialog: true, builder: body);
      _route = route;
      navigator.push(route).whenComplete(() {
        if (!mounted || !identical(_route, route)) return;
        _route = null;
        _controller.defer();
      });
    });
  }

  @override
  void dispose() {
    final route = _route;
    _route = null;
    _controller.dispose();
    if (route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final hasBanner =
          _controller.isVisible &&
          widget.presentation == ShorecatUpdatePresentation.banner;
      final banner = _BannerEntrance(
        child: _UpdateContent(prompt: widget, controller: _controller),
      );
      if (widget.child == null) {
        return hasBanner ? banner : const SizedBox.shrink();
      }
      return LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            // Capped so large text on a short screen cannot push the screen
            // off. A Flexible would split the height evenly with the child.
            if (hasBanner)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight / 2,
                ),
                child: SingleChildScrollView(child: banner),
              ),
            Expanded(child: widget.child!),
          ],
        ),
      );
    },
  );
}

class _UpdateContent extends StatelessWidget {
  final ShorecatUpdatePrompt prompt;
  final ShorecatUpdateController controller;

  const _UpdateContent({required this.prompt, required this.controller});

  @override
  Widget build(BuildContext context) =>
      prompt.builder?.call(context, controller) ??
      switch (prompt.presentation) {
        ShorecatUpdatePresentation.banner => UpdateBannerView(
          prompt: prompt,
          controller: controller,
        ),
        ShorecatUpdatePresentation.dialog => UpdateDialogView(
          prompt: prompt,
          controller: controller,
        ),
        ShorecatUpdatePresentation.page => UpdatePageView(
          prompt: prompt,
          controller: controller,
        ),
      };
}

class _UpdateRouteBody extends StatelessWidget {
  final ShorecatUpdatePrompt prompt;
  final ShorecatUpdateController controller;

  const _UpdateRouteBody({required this.prompt, required this.controller});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => PopScope(
      canPop: !controller.isRestarting,
      child: _UpdateContent(prompt: prompt, controller: controller),
    ),
  );
}

class _BannerEntrance extends StatelessWidget {
  final Widget child;

  const _BannerEntrance({required this.child});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280),
    curve: Curves.easeOutQuart,
    builder: (context, value, child) => ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: value,
        child: Opacity(opacity: value, child: child),
      ),
    ),
    child: child,
  );
}
