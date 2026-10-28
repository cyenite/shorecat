// Ashlar UI: Field. Copied into your app by `ashlar add field`; it is yours to change.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'label.dart';
import 'theme.dart';

/// A control with its label, a description under it and an error when it is wrong. A
/// screen reader hears the label and description as part of the control.
///
/// Vertical puts the label above (inputs, selects); horizontal puts the control first and
/// the label beside it (checkboxes, switches, radios).
///
/// ```dart
/// Field(label: Text('Email'), description: Text('We send receipts here.'), child: Input(placeholder: 'you@example.com'))
/// Field(axis: Axis.horizontal, label: Text('Accept the terms'), child: Checkbox(value: agreed, onChanged: agree))
/// ```
class Field extends StatelessWidget {
  const Field({
    super.key,
    required this.child,
    this.label,
    this.description,
    this.error,
    this.axis = Axis.vertical,
    this.enabled = true,
    this.responsive = false,
    this.card = false,
    this.selected = false,
    this.onPressed,
  });

  /// The control: an Input, a Select, a Checkbox.
  final Widget child;

  /// Names the control: above it, or beside it when across.
  final Widget? label;

  /// Under the control: what it is for.
  final Widget? description;

  /// Shown under the description in the destructive colour, and read out with the field.
  final Widget? error;

  /// Vertical puts the label above; horizontal puts the control first and the label
  /// beside it.
  final Axis axis;

  /// False fades the label and description with the control.
  final bool enabled;

  /// The label beside the control where there is room (480 or more), above it where not.
  final bool responsive;

  /// Drawn as a card to choose: a border round label and control, marked when [selected].
  /// Give it [onPressed] to make the whole card a target, as the control is.
  final bool card;

  /// Marks a card as chosen.
  final bool selected;

  /// Makes the whole card a target, pressing the control, for a field drawn as a card.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final notes = [
      if (description != null)
        Opacity(
          opacity: enabled ? 1 : .5,
          child: DefaultTextStyle.merge(
            style: t.text.sm.copyWith(color: c.mutedForeground),
            child: description!,
          ),
        ),
      if (error != null)
        DefaultTextStyle.merge(
          style: t.text.sm.copyWith(color: c.destructive),
          child: error!,
        ),
    ];
    final label = this.label == null
        ? null
        : Label(enabled: enabled, child: this.label!);
    Widget beside() => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ?label,
              for (final n in notes) ...[const SizedBox(height: 6), n],
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(child: child),
      ],
    );
    Widget body = responsive
        ? LayoutBuilder(
            builder: (context, box) =>
                box.maxWidth >= 480 ? beside() : _stacked(label, notes),
          )
        : axis == Axis.vertical
        ? _stacked(label, notes)
        : _sideBySide(label, notes, t.minTapTarget);
    if (card) {
      body = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onPressed : null,
        child: AnimatedContainer(
          duration: t.duration,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected
                ? c.primary.withValues(alpha: .05)
                : c.primary.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(t.radiusMd),
            border: Border.all(color: selected ? c.primary : c.border),
          ),
          child: body,
        ),
      );
    }
    return MergeSemantics(child: body);
  }

  Widget _stacked(Widget? label, List<Widget> notes) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (label != null) ...[label, const SizedBox(height: 12)],
      child,
      for (final n in notes) ...[const SizedBox(height: 8), n],
    ],
  );

  Widget _sideBySide(Widget? label, List<Widget> notes, double target) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      child,
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Lines the label's first line (20 tall) up with the middle of the control:
            // a 16 tall control, or the larger press area it is centred in for a finger.
            if (label != null)
              Padding(
                padding: EdgeInsets.only(top: math.max(1, (target - 20) / 2)),
                child: label,
              ),
            for (final n in notes) ...[const SizedBox(height: 6), n],
          ],
        ),
      ),
    ],
  );
}

/// Fields that belong together, under a [legend]: an address, a set of notifications.
/// A screen reader hears the legend with them.
class FieldSet extends StatelessWidget {
  const FieldSet({
    super.key,
    required this.children,
    this.legend,
    this.description,
  });

  /// What it holds, in order.
  final List<Widget> children;

  /// Its title, read before its fields.
  final Widget? legend;

  /// A line under the legend.
  final Widget? description;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (legend != null)
            Semantics(
              header: true,
              child: DefaultTextStyle.merge(
                style: t.text.base.copyWith(
                  color: c.foreground,
                  fontWeight: FontWeight.w500,
                ),
                child: legend!,
              ),
            ),
          if (description != null) ...[
            const SizedBox(height: 4),
            DefaultTextStyle.merge(
              style: t.text.sm.copyWith(color: c.mutedForeground),
              child: description!,
            ),
          ],
          if (legend != null || description != null) const SizedBox(height: 16),
          FieldGroup(children: children),
        ],
      ),
    );
  }
}

/// Fields one under the other, evenly spaced.
class FieldGroup extends StatelessWidget {
  const FieldGroup({super.key, required this.children, this.spacing = 24});

  /// What it holds, in order.
  final List<Widget> children;

  /// Space between its fields.
  final double spacing;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, child) in children.indexed) ...[
        if (i > 0) SizedBox(height: spacing),
        child,
      ],
    ],
  );
}

/// A line between fields, with an optional word in its middle: "Or continue with".
class FieldSeparator extends StatelessWidget {
  const FieldSeparator({super.key, this.child});

  /// Words on the line, such as Text('Or'); a plain line when there are none.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final line = Expanded(child: Container(height: 1, color: t.colors.border));
    if (child == null) return Row(children: [line]);
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: DefaultTextStyle.merge(
            style: t.text.sm.copyWith(color: t.colors.mutedForeground),
            child: child!,
          ),
        ),
        line,
      ],
    );
  }
}
