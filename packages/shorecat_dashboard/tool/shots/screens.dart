// Screens drawn with real server data for the README, without a server:
//   ashlar shot tool/shots/screens.dart:OverviewShot --size 1440x900 --dark
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shorecat_dashboard/src/models.dart';
import 'package:shorecat_dashboard/src/screens/shell.dart';
import 'package:shorecat_dashboard/src/session.dart';

import 'fixture.dart';

Session _session(Place place) => Session()
  ..token = 'shot'
  ..appId = 'shorecat-demo'
  ..appIds = const ['shorecat-demo']
  ..window = Window.week
  ..place = place
  ..refreshedAt = DateTime.now()
  ..app = AppDetail.fromJson(jsonDecode(appJson) as Json)
  ..metrics = Metrics.fromJson(jsonDecode(metricsJson) as Json)
  ..events = [
    for (final e in (jsonDecode(eventsJson) as Json)['events']! as List)
      DeviceEvent.fromJson(e as Json),
  ];

class _Shot extends StatelessWidget {
  final Place place;

  const _Shot({required this.place});

  @override
  Widget build(BuildContext context) =>
      SessionScope(session: _session(place), child: const Shell());
}

class OverviewShot extends StatelessWidget {
  const OverviewShot({super.key});

  @override
  Widget build(BuildContext context) => const _Shot(place: Place.overview);
}

class PatchesShot extends StatelessWidget {
  const PatchesShot({super.key});

  @override
  Widget build(BuildContext context) => const _Shot(place: Place.patches);
}

class DevicesShot extends StatelessWidget {
  const DevicesShot({super.key});

  @override
  Widget build(BuildContext context) => const _Shot(place: Place.devices);
}
