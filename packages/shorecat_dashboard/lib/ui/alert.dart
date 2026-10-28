// Ashlar UI: Alert. Copied into your app by `ashlar add alert`; it is yours to change.

import 'package:flutter/widgets.dart';

import 'theme.dart';

enum AlertVariant {
  /// Something to know.
  primary,

  /// Something that went wrong or needs fixing.
  destructive,
}

/// A message in the page that asks for attention: a notice, a warning, an error. A screen
/// reader reads it out when it appears.
///
/// ```dart
/// Alert(icon: AshlarIcon(AshlarIconsRoundedStroke.info), title: Text('Payment received'), description: Text('\$240 from Maya Thompson.'))
/// Alert(variant: AlertVariant.destructive, icon: AshlarIcon(AshlarIconsRoundedStroke.circleAlert), title: Text('The card was declined'))
/// ```
class Alert extends StatelessWidget {
  const Alert({
    super.key,
    this.title,
    this.description,
    this.icon,
    this.variant = AlertVariant.primary,
    this.action,
  });

  /// The alert's title.
  final Widget? title;

  /// A line under the title.
  final Widget? description;

  /// A 16px icon at the top left.
  final Widget? icon;

  /// Plain, or in the destructive colour for something wrong.
  final AlertVariant variant;

  /// A button at the top right.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final destructive = variant == AlertVariant.destructive;
    final fg = destructive ? c.destructive : c.cardForeground;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(t.radiusLg),
          border: Border.all(color: c.border),
        ),
        child: IconTheme.merge(
          data: IconThemeData(color: fg, size: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Padding(padding: const EdgeInsets.only(top: 2), child: icon),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      DefaultTextStyle.merge(
                        style: t.text.sm.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w500,
                        ),
                        child: title!,
                      ),
                    if (title != null && description != null)
                      const SizedBox(height: 4),
                    if (description != null)
                      DefaultTextStyle.merge(
                        style: t.text.sm.copyWith(
                          color: destructive
                              ? c.destructive.withValues(alpha: .9)
                              : c.mutedForeground,
                        ),
                        child: description!,
                      ),
                  ],
                ),
              ),
              if (action != null) ...[const SizedBox(width: 12), action!],
            ],
          ),
        ),
      ),
    );
  }
}
