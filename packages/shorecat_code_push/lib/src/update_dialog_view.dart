import 'package:flutter/material.dart';

import 'update_controller.dart';
import 'update_prompt.dart';
import 'update_prompt_actions.dart';
import 'update_prompt_error.dart';
import 'update_prompt_icon.dart';

class UpdateDialogView extends StatelessWidget {
  final ShorecatUpdatePrompt prompt;
  final ShorecatUpdateController controller;

  const UpdateDialogView({
    super.key,
    required this.prompt,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Dialog(
      backgroundColor: theme.brightness == Brightness.dark
          ? colors.surfaceContainerHigh
          : colors.surfaceContainerLowest,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const UpdatePromptIcon(size: 44),
              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: Text(
                  prompt.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                prompt.message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (controller.hasRestartFailed) ...[
                const SizedBox(height: 12),
                UpdatePromptError(message: prompt.restartErrorMessage),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: UpdateLaterButton(
                      prompt: prompt,
                      controller: controller,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: UpdateRestartButton(
                      prompt: prompt,
                      controller: controller,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
