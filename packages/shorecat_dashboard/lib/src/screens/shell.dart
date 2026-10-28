// Adapted from the Ashlar UI shop-dashboard block: the inset sidebar layout,
// its header bar and the account menu at its foot.

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';

import '../../ui/alert.dart';
import '../../ui/avatar.dart';
import '../../ui/badge.dart';
import '../../ui/button.dart';
import '../../ui/dropdown_menu.dart';
import '../../ui/popover.dart';
import '../../ui/separator.dart';
import '../../ui/sidebar.dart';
import '../../ui/spinner.dart';
import '../../ui/theme.dart';
import '../../ui/toggle_group.dart';
import '../format.dart';
import '../models.dart';
import '../session.dart';
import 'devices.dart';
import 'events.dart';
import 'overview.dart';
import 'patches.dart';
import 'settings.dart';

extension PlaceView on Place {
  String get label => switch (this) {
    Place.overview => 'Overview',
    Place.patches => 'Patches',
    Place.devices => 'Devices',
    Place.events => 'Events',
    Place.settings => 'Settings',
  };

  String get blurb => switch (this) {
    Place.overview => 'How your patches are landing',
    Place.patches => 'Rollouts, rollbacks and the kill switch',
    Place.devices => 'Who runs what, where',
    Place.events => 'Every check, install, launch and crash',
    Place.settings => 'Health gate and signing keys',
  };

  IconData get icon => switch (this) {
    Place.overview => AshlarIconsRoundedStroke.layoutDashboard,
    Place.patches => AshlarIconsRoundedStroke.layers,
    Place.devices => AshlarIconsRoundedStroke.smartphone,
    Place.events => AshlarIconsRoundedStroke.activity,
    Place.settings => AshlarIconsRoundedStroke.settings,
  };
}

class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final live =
        session.app?.patches
            .where((p) => p.status == PatchStatus.active)
            .length ??
        0;
    SidebarItem item(Place place, {String? badge}) => SidebarItem(
      place.label,
      icon: place.icon,
      active: session.place == place,
      badge: badge,
      onPressed: () => session.go(place),
    );
    return SidebarLayout(
      variant: SidebarVariant.inset,
      collapse: SidebarCollapse.offcanvas,
      header: const _Brand(),
      groups: [
        SidebarGroup(label: 'Monitor', [
          item(Place.overview),
          item(Place.patches, badge: live == 0 ? null : '$live live'),
          item(Place.devices),
          item(Place.events),
        ]),
        SidebarGroup(label: 'App', [item(Place.settings)]),
        const SidebarGroup.custom(_Tip(), atEnd: true),
      ],
      footer: const _Account(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Header(),
          const Separator(),
          if (session.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Alert(
                variant: AlertVariant.destructive,
                icon: const AshlarIcon(AshlarIconsRoundedStroke.circleAlert),
                title: const Text('The server did not answer'),
                description: Text(session.error!),
              ),
            ),
          Expanded(
            child: switch (session.place) {
              Place.overview => const OverviewScreen(),
              Place.patches => const PatchesScreen(),
              Place.devices => const DevicesScreen(),
              Place.events => const EventsScreen(),
              Place.settings => const SettingsScreen(),
            },
          ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final session = SessionScope.of(context);
    final name = session.app?.name ?? session.appId ?? 'No apps yet';
    return DropdownMenu(
      side: PopoverSide.bottom,
      width: 224,
      builder: (context, menu) => Button(
        variant: ButtonVariant.ghost,
        expand: true,
        semanticLabel: 'App: $name',
        onPressed: session.appIds.length > 1 ? menu.open : null,
        trailing: session.appIds.length > 1
            ? const AshlarIcon(AshlarIconsRoundedStroke.chevronsUpDown)
            : null,
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: c.primary,
                borderRadius: BorderRadius.circular(t.radiusMd),
              ),
              child: AshlarIcon(
                AshlarIconsRoundedStroke.cat,
                size: 18,
                color: c.primaryForeground,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'shorecat',
                    style: t.text.sm.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: t.text.xs.copyWith(color: c.mutedForeground),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      items: [
        for (final id in session.appIds)
          MenuItem(
            leading: AshlarIcon(
              id == session.appId
                  ? AshlarIconsRoundedStroke.check
                  : AshlarIconsRoundedStroke.smartphone,
            ),
            onPressed: () => session.selectApp(id),
            child: Text(id),
          ),
      ],
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip();

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(t.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AshlarIcon(AshlarIconsRoundedStroke.pawPrint, size: 14),
              const SizedBox(width: 6),
              Text(
                'Nine lives',
                style: t.text.sm.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'A patch that crashes before its first frame rolls itself back on the next launch.',
            style: t.text.xs.copyWith(color: c.mutedForeground),
          ),
        ],
      ),
    );
  }
}

class _Account extends StatelessWidget {
  const _Account();

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final session = SessionScope.of(context);
    final host = Uri.tryParse(session.server)?.authority ?? session.server;
    return DropdownMenu(
      side: PopoverSide.top,
      width: 224,
      builder: (context, menu) => Button(
        variant: ButtonVariant.ghost,
        expand: true,
        semanticLabel: 'Server: $host',
        onPressed: menu.open,
        trailing: const AshlarIcon(AshlarIconsRoundedStroke.chevronsUpDown),
        child: Row(
          children: [
            const Avatar(fallback: 'SC'),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Admin',
                    style: t.text.sm.copyWith(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    host,
                    overflow: TextOverflow.ellipsis,
                    style: t.text.xs.copyWith(color: c.mutedForeground),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      items: [
        MenuItem(
          leading: const AshlarIcon(AshlarIconsRoundedStroke.refreshCw),
          onPressed: session.refresh,
          child: const Text('Refresh now'),
        ),
        const MenuSeparator(),
        MenuItem(
          leading: const AshlarIcon(AshlarIconsRoundedStroke.logOut),
          onPressed: session.signOut,
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final session = SessionScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 860;
    final refreshed = session.refreshedAt;
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const SidebarTrigger(),
            const SizedBox(width: 8),
            const SizedBox(height: 16, child: Separator(axis: Axis.vertical)),
            const SizedBox(width: 12),
            Text(
              session.place.label,
              style: t.text.base.copyWith(fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                session.place.blurb,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.text.sm.copyWith(color: c.mutedForeground),
              ),
            ),
            if (wide) ...[
              Badge(
                variant: BadgeVariant.outline,
                leading: session.isLoading
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: Spinner(size: 12),
                      )
                    : const AshlarIcon(AshlarIconsRoundedStroke.radioTower),
                child: Text(
                  refreshed == null
                      ? 'Connecting'
                      : 'Live, ${shortTime(refreshed)}',
                ),
              ),
              const SizedBox(width: 8),
            ],
            ToggleGroup<Window>(
              values: {session.window},
              semanticLabel: 'Time window',
              onChanged: (v) {
                if (v.isNotEmpty) session.setWindow(v.first);
              },
              items: [
                for (final w in Window.values)
                  ToggleGroupItem(w, Text(w.label)),
              ],
            ),
            const SizedBox(width: 8),
            Button(
              variant: ButtonVariant.outline,
              size: ButtonSize.icon,
              semanticLabel: 'Refresh',
              onPressed: session.refresh,
              child: const AshlarIcon(AshlarIconsRoundedStroke.refreshCw),
            ),
          ],
        ),
      ),
    );
  }
}
