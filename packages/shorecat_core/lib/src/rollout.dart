import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Deterministic staged rollout bucketing. Every install hashes into one of
/// 10000 buckets per patch, so raising a rollout from 10% to 20% keeps the
/// first 10% and adds new devices, and two patches pick independent cohorts.
abstract final class Rollout {
  static const bucketCount = 10000;

  static int bucketOf({required String clientId, required String salt}) {
    final digest = sha256.convert(utf8.encode('$salt:$clientId')).bytes;
    final value =
        (digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3];
    return value % bucketCount;
  }

  static bool includes({
    required double percentage,
    required String clientId,
    required String salt,
  }) {
    if (percentage >= 100) return true;
    if (percentage <= 0) return false;
    return bucketOf(clientId: clientId, salt: salt) <
        (percentage * bucketCount / 100).round();
  }
}

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();
