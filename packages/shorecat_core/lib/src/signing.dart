import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import 'protocol.dart';

class SigningException implements Exception {
  final String message;

  SigningException(this.message);

  @override
  String toString() => 'SigningException: $message';
}

/// What a patch signature covers. Binding the release, platform, arch and
/// patch number (not just the artifact hash) means a validly signed artifact
/// cannot be replayed into a different release or slot.
class PatchSignaturePayload {
  final int patchNumber;
  final Arch arch;
  final String appId;
  final String targetSha256;
  final String releaseVersion;
  final AppPlatform platform;

  const PatchSignaturePayload({
    required this.patchNumber,
    required this.arch,
    required this.appId,
    required this.targetSha256,
    required this.releaseVersion,
    required this.platform,
  });

  List<int> toBytes() => utf8.encode(
    [
      'shorecat-patch-v1',
      appId,
      releaseVersion,
      platform.wireName,
      arch.wireName,
      '$patchNumber',
      targetSha256,
    ].join('\n'),
  );
}

class PatchPublicKey {
  final Uint8List bytes;

  PatchPublicKey(this.bytes) {
    if (bytes.length != 32) {
      throw SigningException('Ed25519 public keys are 32 bytes');
    }
  }

  static const prefix = 'ed25519:';

  factory PatchPublicKey.parse(String encoded) {
    final trimmed = encoded.trim();
    if (!trimmed.startsWith(prefix)) {
      throw SigningException('Public key must start with "$prefix"');
    }
    try {
      return PatchPublicKey(base64.decode(trimmed.substring(prefix.length)));
    } on FormatException {
      throw SigningException('Public key is not valid base64');
    }
  }

  /// Short fingerprint for logs and key rotation bookkeeping.
  String get id => sha256.convert(bytes).toString().substring(0, 12);

  String encode() => '$prefix${base64.encode(bytes)}';

  @override
  bool operator ==(Object other) =>
      other is PatchPublicKey && encode() == other.encode();

  @override
  int get hashCode => encode().hashCode;
}

class PatchKeyPair {
  final Uint8List seed;
  final PatchPublicKey publicKey;

  PatchKeyPair._(this.seed, this.publicKey);

  static const _begin = '-----BEGIN SHORECAT ED25519 PRIVATE KEY-----';
  static const _end = '-----END SHORECAT ED25519 PRIVATE KEY-----';

  static Future<PatchKeyPair> generate() async {
    final pair = await Ed25519().newKeyPair();
    return fromSeed(Uint8List.fromList(await pair.extractPrivateKeyBytes()));
  }

  static Future<PatchKeyPair> fromSeed(Uint8List seed) async {
    if (seed.length != 32) {
      throw SigningException('Ed25519 seeds are 32 bytes');
    }
    final pair = await Ed25519().newKeyPairFromSeed(seed);
    final publicKey = await pair.extractPublicKey();
    return PatchKeyPair._(
      seed,
      PatchPublicKey(Uint8List.fromList(publicKey.bytes)),
    );
  }

  static Future<PatchKeyPair> fromPem(String pem) async {
    final body = pem
        .replaceAll(_begin, '')
        .replaceAll(_end, '')
        .replaceAll(RegExp(r'\s'), '');
    if (!pem.contains(_begin)) {
      throw SigningException('Not a shorecat private key');
    }
    try {
      return await fromSeed(base64.decode(body));
    } on FormatException {
      throw SigningException('Private key body is not valid base64');
    }
  }

  String toPem() => '$_begin\n${base64.encode(seed)}\n$_end\n';

  Future<String> sign(PatchSignaturePayload payload) async {
    final algorithm = Ed25519();
    final pair = await algorithm.newKeyPairFromSeed(seed);
    final signature = await algorithm.sign(payload.toBytes(), keyPair: pair);
    return base64.encode(signature.bytes);
  }
}

abstract final class PatchVerifier {
  /// True when [signature] was made over [payload] by any of [trustedKeys].
  /// Accepting a set is what makes key rotation possible: ship the new key
  /// next to the old one, then start signing with it.
  static Future<bool> verify({
    required String signature,
    required PatchSignaturePayload payload,
    required Iterable<PatchPublicKey> trustedKeys,
  }) async {
    final List<int> signatureBytes;
    try {
      signatureBytes = base64.decode(signature);
    } on FormatException {
      return false;
    }
    final algorithm = Ed25519();
    for (final key in trustedKeys) {
      final isValid = await algorithm.verify(
        payload.toBytes(),
        signature: Signature(
          signatureBytes,
          publicKey: SimplePublicKey(key.bytes, type: KeyPairType.ed25519),
        ),
      );
      if (isValid) return true;
    }
    return false;
  }
}
