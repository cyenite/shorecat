import 'package:flutter/material.dart';

import 'update_controller.dart';
import 'update_prompt.dart';
import 'update_prompt_actions.dart';
import 'update_prompt_error.dart';
import 'update_prompt_icon.dart';

class UpdateBannerView extends StatelessWidget {
  final ShorecatUpdatePrompt prompt;
  final ShorecatUpdateController controller;

  const UpdateBannerView({
    super.key,
    required this.prompt,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isDark
                ? colors.surfaceContainerHigh
                : colors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.outlineVariant, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: colors.shadow.withValues(alpha: isDark ? 0.3 : 0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 4, 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                // Large text or a narrow host moves Restart onto its own line.
                final isStacked = constraints.maxWidth / scale < 300;
                final restart = UpdateRestartButton(
                  isCompact: true,
                  prompt: prompt,
                  controller: controller,
                );
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const UpdatePromptIcon(size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                prompt.title,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                prompt.message,
                                maxLines: isStacked ? null : 2,
                                overflow: isStacked
                                    ? null
                                    : TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (!isStacked) restart,
                        IconButton(
                          tooltip: prompt.laterLabel,
                          visualDensity: VisualDensity.compact,
                          color: colors.onSurfaceVariant,
                          onPressed: controller.isRestarting
                              ? null
                              : controller.defer,
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                      ],
                    ),
                    if (controller.hasRestartFailed)
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          48,
                          6,
                          8,
                          0,
                        ),
                        child: UpdatePromptError(
                          message: prompt.restartErrorMessage,
                        ),
                      ),
                    if (isStacked)
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          48,
                          8,
                          8,
                          0,
                        ),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: restart,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
