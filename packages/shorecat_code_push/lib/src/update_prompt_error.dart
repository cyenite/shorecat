import 'package:flutter/material.dart';

class UpdatePromptError extends StatelessWidget {
  final bool isCentered;
  final String message;

  const UpdatePromptError({
    super.key,
    this.isCentered = false,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.error;
    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisSize: isCentered ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline_rounded, size: 18, color: color),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
