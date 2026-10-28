import 'package:shorecat_core/shorecat_core.dart';
import 'package:test/test.dart';

void main() {
  final clients = [for (var i = 0; i < 20000; i++) 'client-$i'];

  test('percentage roughly matches the share of clients included', () {
    final included = clients
        .where((c) => Rollout.includes(percentage: 25, clientId: c, salt: 'p1'))
        .length;
    expect(included / clients.length, closeTo(0.25, 0.02));
  });

  test('raising a rollout keeps everyone already included', () {
    for (final c in clients) {
      if (Rollout.includes(percentage: 10, clientId: c, salt: 'p1')) {
        expect(
          Rollout.includes(percentage: 30, clientId: c, salt: 'p1'),
          isTrue,
        );
      }
    }
  });

  test('bounds are exact', () {
    expect(Rollout.includes(percentage: 0, clientId: 'x', salt: 's'), isFalse);
    expect(Rollout.includes(percentage: 100, clientId: 'x', salt: 's'), isTrue);
  });
}
