import 'package:flutter/widgets.dart';

import '../shorecat_code_push.dart';

typedef ShorecatUpdateWidgetBuilder =
    Widget Function(BuildContext context, ShorecatUpdateController update);

/// Rebuilds [builder] whenever the restart state changes, for update UI you
/// place yourself: a settings tile, an app bar badge, your own screen.
///
/// It always builds; check [ShorecatUpdateController.isVisible] or
/// [ShorecatUpdateController.isRestartRequired] to decide what to show.
class ShorecatUpdateBuilder extends StatefulWidget {
  final Shorecat? shorecat;
  final ShorecatUpdateWidgetBuilder builder;
  final Future<bool> Function()? onBeforeRestart;

  const ShorecatUpdateBuilder({
    super.key,
    this.shorecat,
    required this.builder,
    this.onBeforeRestart,
  });

  @override
  State<ShorecatUpdateBuilder> createState() => _ShorecatUpdateBuilderState();
}

class _ShorecatUpdateBuilderState extends State<ShorecatUpdateBuilder> {
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
    );
  }

  @override
  void didUpdateWidget(covariant ShorecatUpdateBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shorecat != widget.shorecat) {
      _controller.dispose();
      _attach();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => widget.builder(context, _controller),
  );
}
