import 'package:flutter/material.dart';

import 'update_controller.dart';
import 'update_prompt.dart';

class UpdateRestartButton extends StatelessWidget {
  final bool isCompact;
  final ShorecatUpdatePrompt prompt;
  final ShorecatUpdateController controller;

  const UpdateRestartButton({
    super.key,
    this.isCompact = false,
    required this.prompt,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) => FilledButton(
    style: isCompact
        ? FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.padded,
          )
        : FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    onPressed: controller.isRestarting ? null : controller.restart,
    child: controller.isRestarting
        ? RestartingLabel(label: prompt.restartingLabel)
        : Text(prompt.restartLabel),
  );
}

class UpdateLaterButton extends StatelessWidget {
  final ShorecatUpdatePrompt prompt;
  final ShorecatUpdateController controller;

  const UpdateLaterButton({
    super.key,
    required this.prompt,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    onPressed: controller.isRestarting ? null : controller.defer,
    child: Text(prompt.laterLabel),
  );
}

class RestartingLabel extends StatelessWidget {
  final String label;

  const RestartingLabel({super.key, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox.square(
        dimension: 14,
        // The button's foreground color already reflects its disabled state.
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: DefaultTextStyle.of(context).style.color,
        ),
      ),
      const SizedBox(width: 10),
      Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
    ],
  );
}
