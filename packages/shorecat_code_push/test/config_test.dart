import 'package:flutter_test/flutter_test.dart';
import 'package:shorecat_code_push/shorecat_code_push.dart';

void main() {
  const key = 'ed25519:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';

  test('parses the file shorecat init writes', () {
    final config = ShorecatConfig.parse('''
app_id: demo
base_url: https://updates.example.com
channel: beta
auto_update: false
max_boot_attempts: 2
public_keys:
  - $key
''');
    expect(config.appId, 'demo');
    expect(config.channel, 'beta');
    expect(config.isAutoUpdate, isFalse);
    expect(config.maxBootAttempts, 2);
    expect(config.publicKeys.single.encode(), key);
  });

  test('refuses a config that could never verify a patch', () {
    expect(
      () => ShorecatConfig.parse('app_id: demo\nbase_url: x\n'),
      throwsFormatException,
    );
  });
}
