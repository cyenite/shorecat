import 'package:shorecat_core/shorecat_core.dart';
import 'package:test/test.dart';

void main() {
  const payload = PatchSignaturePayload(
    patchNumber: 3,
    arch: Arch.arm64,
    appId: 'app-1',
    targetSha256: 'abc',
    releaseVersion: '1.0.0+1',
    platform: AppPlatform.android,
  );

  test('signatures verify against the signing key', () async {
    final pair = await PatchKeyPair.generate();
    final signature = await pair.sign(payload);
    expect(
      await PatchVerifier.verify(
        signature: signature,
        payload: payload,
        trustedKeys: [pair.publicKey],
      ),
      isTrue,
    );
  });

  test('a signature does not transfer to another patch slot', () async {
    final pair = await PatchKeyPair.generate();
    final signature = await pair.sign(payload);
    const replayed = PatchSignaturePayload(
      patchNumber: 4,
      arch: Arch.arm64,
      appId: 'app-1',
      targetSha256: 'abc',
      releaseVersion: '1.0.0+1',
      platform: AppPlatform.android,
    );
    expect(
      await PatchVerifier.verify(
        signature: signature,
        payload: replayed,
        trustedKeys: [pair.publicKey],
      ),
      isFalse,
    );
  });

  test('any trusted key verifies, which allows rotation', () async {
    final oldPair = await PatchKeyPair.generate();
    final newPair = await PatchKeyPair.generate();
    final signature = await newPair.sign(payload);
    expect(
      await PatchVerifier.verify(
        signature: signature,
        payload: payload,
        trustedKeys: [oldPair.publicKey],
      ),
      isFalse,
    );
    expect(
      await PatchVerifier.verify(
        signature: signature,
        payload: payload,
        trustedKeys: [oldPair.publicKey, newPair.publicKey],
      ),
      isTrue,
    );
  });

  test('keys survive PEM and text encoding', () async {
    final pair = await PatchKeyPair.generate();
    final restored = await PatchKeyPair.fromPem(pair.toPem());
    expect(restored.publicKey, pair.publicKey);
    expect(PatchPublicKey.parse(pair.publicKey.encode()), pair.publicKey);
  });

  test('garbage signatures are rejected, not thrown', () async {
    final pair = await PatchKeyPair.generate();
    expect(
      await PatchVerifier.verify(
        signature: '%%%',
        payload: payload,
        trustedKeys: [pair.publicKey],
      ),
      isFalse,
    );
  });
}
