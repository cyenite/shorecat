// Ashlar UI: Checkbox. Copied into your app by `ashlar add checkbox`; it is yours to change.

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';

import 'pressable.dart';
import 'theme.dart';

/// A box that is ticked or not. Give it a [semanticLabel], or put it in a row with a Text.
///
/// ```dart
/// Checkbox(value: agreed, onChanged: (v) => setState(() => agreed = v), semanticLabel: 'Accept terms')
/// ```
class Checkbox extends StatelessWidget {
  const Checkbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    this.indeterminate = false,
    this.error = false,
    this.focusNode,
    this.autofocus = false,
  });

  /// Whether it is ticked.
  final bool value;

  /// Null disables the checkbox.
  final ValueChanged<bool>? onChanged;

  /// What a screen reader calls it when its visible text does not say, as for an icon
  /// alone.
  final String? semanticLabel;

  /// Neither ticked nor not, as over a list where some are: a dash. A tap ticks it.
  final bool indeterminate;

  /// Draws it as invalid.
  final bool error;

  /// Its focus node, to move focus to it or follow it from outside; one is made when not
  /// given.
  final FocusNode? focusNode;

  /// Takes the keyboard's focus when it first appears.
  final bool autofocus;

  // Its own size, at the start, even where its parent stretches what it holds: a
  // stacked Field, a column that fills its width.
  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    widthFactor: 1,
    heightFactor: 1,
    child: _control(context),
  );

  Widget _control(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Pressable(
      onPressed: onChanged == null
          ? null
          : () => onChanged!(indeterminate || !value),
      checked: value,
      mixed: indeterminate,
      semanticLabel: semanticLabel,
      focusNode: focusNode,
      autofocus: autofocus,
      builder: (context, state) => Opacity(
        opacity: state.enabled ? 1 : .5,
        child: AnimatedContainer(
          duration: t.duration,
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            // Opaque, so the shadow beneath does not show through.
            color: value || indeterminate ? c.primary : c.background,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: error
                  ? c.destructive
                  : (value || indeterminate
                        ? c.primary
                        : (state.focused ? c.ring : c.input)),
            ),
            boxShadow: [
              if (state.focused)
                error
                    ? BoxShadow(
                        color: c.destructive.withValues(alpha: .2),
                        spreadRadius: 3,
                      )
                    : t.focusRing.first,
              ...t.shadowXs,
            ],
          ),
          child: indeterminate
              ? AshlarIcon(
                  AshlarIconsRoundedStroke.minus,
                  size: 14,
                  color: c.primaryForeground,
                )
              : value
              ? AshlarIcon(
                  AshlarIconsRoundedStroke.check,
                  size: 14,
                  color: c.primaryForeground,
                )
              : null,
        ),
      ),
    );
  }
}
