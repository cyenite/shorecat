import 'package:flutter/material.dart';

class UpdatePromptIcon extends StatelessWidget {
  final double size;

  const UpdatePromptIcon({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colors.primary,
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: Icon(
          Icons.auto_awesome_rounded,
          size: size * 0.5,
          color: colors.onPrimary,
        ),
      ),
    );
  }
}
