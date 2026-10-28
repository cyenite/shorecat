// Ashlar UI: Item. Copied into your app by `ashlar add item`; it is yours to change.

import 'package:flutter/widgets.dart';

import 'pressable.dart';
import 'theme.dart';

enum ItemVariant {
  /// No border or fill.
  plain,

  /// A border round it.
  outline,

  /// A muted fill.
  muted,
}

enum ItemSize {
  /// 16 of padding.
  md,

  /// 12, tighter.
  sm,

  /// 8, for dense lists.
  xs,
}

/// A row in a list: media at the start (an icon, an avatar, an image), a title and a
/// description, and actions at the end. [header] and [footer] run across the whole item,
/// above and below. With [onPressed] the whole row is a button.
///
/// ```dart
/// Item(
///   variant: ItemVariant.outline,
///   leading: ItemMedia.icon(AshlarIcon(AshlarIconsRoundedStroke.shieldCheck)),
///   title: Text('Two-step sign in is on'),
///   description: Text('A code from your phone is asked for at each sign in.'),
///   trailing: Button(size: ButtonSize.sm, variant: ButtonVariant.outline, onPressed: manage, child: Text('Manage')),
/// )
/// ```
class Item extends StatelessWidget {
  const Item({
    super.key,
    required this.title,
    this.description,
    this.leading,
    this.trailing,
    this.header,
    this.footer,
    this.variant = ItemVariant.plain,
    this.size = ItemSize.md,
    this.onPressed,
  });

  /// The item's name.
  final Widget title;

  /// A line under the title.
  final Widget? description;

  /// Usually an [ItemMedia].
  final Widget? leading;

  /// After the label: usually an icon.
  final Widget? trailing;

  /// Across the top and the foot of the item: an image, a row of tags.
  final Widget? header, footer;

  /// How it is set apart: plainly, with a border, or on a muted fill.
  final ItemVariant variant;

  /// Medium, small or extra small: how much room it has.
  final ItemSize size;

  /// Called when it is pressed. Null disables it.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final pad = switch (size) {
      ItemSize.md => 16.0,
      ItemSize.sm => 12.0,
      ItemSize.xs => 8.0,
    };
    final grouped = _ItemGroupScope.of(context);
    Widget body(bool lit) => AnimatedContainer(
      duration: t.duration,
      padding: EdgeInsets.symmetric(
        horizontal: pad,
        vertical: size == ItemSize.xs ? 6 : pad,
      ),
      decoration: BoxDecoration(
        color: lit
            ? c.accent.withValues(alpha: c.accent.a * .5)
            : (variant == ItemVariant.muted
                  ? c.muted.withValues(alpha: c.muted.a * .5)
                  : c.muted.withValues(alpha: 0)),
        borderRadius: grouped ? null : BorderRadius.circular(t.radiusMd),
        border: variant == ItemVariant.outline && !grouped
            ? Border.all(color: c.border)
            : null,
      ),
      child: IconTheme.merge(
        data: IconThemeData(color: c.foreground, size: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header != null) ...[header!, SizedBox(height: pad * .75)],
            Row(
              children: [
                if (leading != null) ...[leading!, SizedBox(width: pad)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DefaultTextStyle.merge(
                        style: t.text.sm.copyWith(
                          color: c.foreground,
                          fontWeight: FontWeight.w500,
                        ),
                        child: title,
                      ),
                      if (description != null) ...[
                        const SizedBox(height: 4),
                        DefaultTextStyle.merge(
                          style: t.text.sm.copyWith(color: c.mutedForeground),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          child: description!,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[SizedBox(width: pad), trailing!],
              ],
            ),
            if (footer != null) ...[SizedBox(height: pad * .75), footer!],
          ],
        ),
      ),
    );
    if (onPressed == null) return body(false);
    return Pressable(
      onPressed: onPressed,
      builder: (context, state) => body(state.hovered || state.focused),
    );
  }
}

/// What sits at the start of an [Item]: an icon on a muted square, an image, or anything.
class ItemMedia extends StatelessWidget {
  const ItemMedia({super.key, required this.child}) : _kind = 0;

  /// An icon on a small muted square.
  const ItemMedia.icon(this.child, {super.key}) : _kind = 1;

  /// A picture, cropped to a rounded square.
  const ItemMedia.image(this.child, {super.key}) : _kind = 2;

  /// The icon, picture or avatar.
  final Widget child;
  final int _kind;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return switch (_kind) {
      1 => Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.colors.muted,
          borderRadius: BorderRadius.circular(t.radiusSm),
          border: Border.all(color: t.colors.border),
        ),
        child: child,
      ),
      2 => ClipRRect(
        borderRadius: BorderRadius.circular(t.radiusSm),
        child: SizedBox.square(dimension: 40, child: child),
      ),
      _ => child,
    };
  }
}

/// Items in one block, as a list: one border round them all, and a line between each.
class ItemGroup extends StatelessWidget {
  const ItemGroup({
    super.key,
    required this.children,
    this.variant = ItemVariant.outline,
    this.separated = true,
  });

  /// What it holds, in order.
  final List<Widget> children;

  /// How its items are set apart.
  final ItemVariant variant;

  /// A line between items.
  final bool separated;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: variant == ItemVariant.muted
              ? c.muted.withValues(alpha: c.muted.a * .5)
              : null,
          borderRadius: BorderRadius.circular(t.radiusMd),
          border: variant == ItemVariant.outline
              ? Border.all(color: c.border)
              : null,
        ),
        child: _ItemGroupScope(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, item) in children.indexed) ...[
                if (i > 0 && separated) const ItemSeparator(),
                item,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemGroupScope extends InheritedWidget {
  const _ItemGroupScope({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ItemGroupScope>() != null;

  @override
  bool updateShouldNotify(_ItemGroupScope old) => false;
}

/// A line between items.
class ItemSeparator extends StatelessWidget {
  const ItemSeparator({super.key});

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: AshlarTheme.of(context).colors.border);
}
