import 'package:flutter/material.dart';

import 'update_controller.dart';
import 'update_prompt.dart';
import 'update_prompt_actions.dart';
import 'update_prompt_error.dart';
import 'update_prompt_icon.dart';

class UpdatePageView extends StatelessWidget {
  final ShorecatUpdatePrompt prompt;
  final ShorecatUpdateController controller;

  const UpdatePageView({
    super.key,
    required this.prompt,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const UpdatePromptIcon(size: 72),
                                const SizedBox(height: 28),
                                Semantics(
                                  header: true,
                                  child: Text(
                                    prompt.title,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.4,
                                        ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  prompt.message,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (controller.hasRestartFailed) ...[
                                  const SizedBox(height: 16),
                                  UpdatePromptError(
                                    isCentered: true,
                                    message: prompt.restartErrorMessage,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            UpdateRestartButton(
                              prompt: prompt,
                              controller: controller,
                            ),
                            const SizedBox(height: 4),
                            UpdateLaterButton(
                              prompt: prompt,
                              controller: controller,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
