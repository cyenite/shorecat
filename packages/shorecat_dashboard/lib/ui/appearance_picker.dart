// Ashlar UI: Appearance Picker. Copied into your app by `ashlar add appearance-picker`; it
// is yours to change.

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';

import 'app.dart';
import 'pressable.dart';
import 'theme.dart';

/// System, light or dark, chosen from three small screens, each drawn in the colours it
/// stands for; System is the light screen and the dark one, cut on a slant. To a screen
/// reader it is three choices, one of them chosen.
///
/// Give it the app's own themes, so the screens show the app's colours.
///
/// ```dart
/// AppearancePicker(
///   value: mode,
///   onChanged: (m) => setState(() => mode = m),
///   light: appTheme,
///   dark: appDarkTheme,
/// )
/// ```
class AppearancePicker extends StatelessWidget {
  const AppearancePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.light,
    this.dark,
    this.systemLabel = 'System',
    this.lightLabel = 'Light',
    this.darkLabel = 'Dark',
  });

  /// The appearance chosen.
  final AshlarThemeMode value;

  /// Told the appearance picked.
  final ValueChanged<AshlarThemeMode> onChanged;

  /// The themes the small screens are drawn in: Ashlar's own when not given.
  final AshlarThemeData? light, dark;

  /// What each is called, under its screen.
  final String systemLabel, lightLabel, darkLabel;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final lightTheme = light ?? AshlarThemeData.light();
    final darkTheme = dark ?? AshlarThemeData.dark();
    Widget screen(AshlarThemeMode mode) => switch (mode) {
      AshlarThemeMode.light => _Screen(lightTheme.colors),
      AshlarThemeMode.dark => _Screen(darkTheme.colors),
      AshlarThemeMode.system => Stack(
        children: [
          _Screen(lightTheme.colors),
          ClipPath(clipper: const _Slant(), child: _Screen(darkTheme.colors)),
        ],
      ),
    };
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Row(
        children: [
          for (final (i, mode) in const [
            AshlarThemeMode.system,
            AshlarThemeMode.light,
            AshlarThemeMode.dark,
          ].indexed) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(
              child: Pressable(
                semanticLabel: switch (mode) {
                  AshlarThemeMode.system => systemLabel,
                  AshlarThemeMode.light => lightLabel,
                  AshlarThemeMode.dark => darkLabel,
                },
                checked: mode == value,
                exclusive: true,
                onPressed: () => onChanged(mode),
                builder: (context, state) {
                  final on = mode == value;
                  return Column(
                    children: [
                      AnimatedContainer(
                        duration: t.duration,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(t.radiusLg + 4),
                          border: Border.all(
                            color: on
                                ? c.foreground
                                : (state.focused
                                      ? c.ring
                                      : (state.hovered ? c.ring : c.border)),
                            width: 2,
                          ),
                        ),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(t.radiusLg),
                              child: screen(mode),
                            ),
                            if (on)
                              PositionedDirectional(
                                end: 6,
                                bottom: 6,
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: c.foreground,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: AshlarIcon(
                                      AshlarIconsRoundedStroke.check,
                                      size: 14,
                                      color: c.background,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        switch (mode) {
                          AshlarThemeMode.system => systemLabel,
                          AshlarThemeMode.light => lightLabel,
                          AshlarThemeMode.dark => darkLabel,
                        },
                        style: t.text.sm.copyWith(
                          color: c.foreground,
                          fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A tiny screen in [colors]: a bar along the top, a card with a picture, and a tab bar.
class _Screen extends StatelessWidget {
  const _Screen(this.colors);

  final AshlarColors colors;

  @override
  Widget build(BuildContext context) => Container(
    height: 110,
    padding: const EdgeInsets.all(8),
    color: colors.background,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 12,
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.border),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.muted,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(7),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(6, 4, 24, 4),
                child: Container(height: 4, color: colors.mutedForeground),
              ),
            ],
          ),
        ),
        const Spacer(),
        Center(
          child: Container(
            width: 48,
            height: 12,
            padding: const EdgeInsets.all(2),
            alignment: AlignmentDirectional.centerStart,
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.border),
            ),
            child: Container(
              width: 16,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The right of a screen, cut on a slant: System's dark side.
class _Slant extends CustomClipper<Path> {
  const _Slant();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width * .62, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(size.width * .38, size.height)
    ..close();

  @override
  bool shouldReclip(_Slant old) => false;
}
