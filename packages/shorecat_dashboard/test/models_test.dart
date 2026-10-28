import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shorecat_dashboard/src/models.dart';

import '../tool/shots/fixture.dart';

void main() {
  test('parses a real app, metrics and events payload', () {
    final app = AppDetail.fromJson(jsonDecode(appJson) as Json);
    final metrics = Metrics.fromJson(jsonDecode(metricsJson) as Json);
    final events = (jsonDecode(eventsJson) as Json)['events']! as List;

    expect(app.releases, isNotEmpty);
    expect(app.patches.map((p) => p.status), contains(PatchStatus.rolledBack));
    expect(metrics.series, hasLength(metrics.windowHours));
    expect(metrics.activeDevices, greaterThan(0));
    expect(
      metrics.adoption.fold<int>(0, (n, a) => n + a.devices),
      metrics.activeDevices,
    );
    expect(DeviceEvent.fromJson(events.first as Json).kind, isNotNull);
  });

  test('unknown statuses and events do not vanish', () {
    expect(PatchStatus.parse('something_new'), PatchStatus.draft);
    expect(EventKind.parse('something_new'), isNull);
  });
}
