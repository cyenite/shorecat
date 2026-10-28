import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'config.dart';

typedef Json = Map<String, Object?>;

/// Admin API client for a shorecat server.
class ShorecatClient {
  final String baseUrl;
  final String token;
  final http.Client _http;

  ShorecatClient({
    required this.baseUrl,
    required this.token,
    http.Client? client,
  }) : _http = client ?? http.Client();

  factory ShorecatClient.forProject(ProjectConfig project, UserConfig user) {
    final token = user.tokenFor(project.baseUrl);
    if (token == null) {
      throw CliException(
        'Not logged in to ${project.baseUrl}. Run '
        '"shorecat login --server ${project.baseUrl} --token <admin token>".',
      );
    }
    return ShorecatClient(baseUrl: project.baseUrl, token: token);
  }

  Future<Json> getApp(String appId) => _send('GET', '/api/v1/apps/$appId');

  Future<Json?> findApp(String appId) async {
    try {
      return await getApp(appId);
    } on CliException catch (e) {
      if (e.httpStatus == 404) return null;
      rethrow;
    }
  }

  Future<Json> listApps() => _send('GET', '/api/v1/apps');

  Future<Json> createApp(Json body) => _send('POST', '/api/v1/apps', body);

  Future<Json> updateApp(String appId, Json body) =>
      _send('PATCH', '/api/v1/apps/$appId', body);

  Future<List<Json>> releases(
    String appId, {
    String? version,
    String? platform,
  }) async {
    final query = {'version': ?version, 'platform': ?platform};
    final json = await _send(
      'GET',
      Uri(
        path: '/api/v1/apps/$appId/releases',
        queryParameters: query,
      ).toString(),
    );
    return (json['releases']! as List).cast<Json>();
  }

  Future<Json> createRelease(String appId, Json body) =>
      _send('POST', '/api/v1/apps/$appId/releases', body);

  Future<Json> createPatch(String releaseId, Json body) =>
      _send('POST', '/api/v1/releases/$releaseId/patches', body);

  Future<Json> putPatchArtifact(
    String releaseId,
    int number,
    String arch,
    Json body,
  ) => _send(
    'PUT',
    '/api/v1/releases/$releaseId/patches/$number/artifacts/$arch',
    body,
  );

  Future<Json> publishPatch(String releaseId, int number, Json body) => _send(
    'POST',
    '/api/v1/releases/$releaseId/patches/$number/publish',
    body,
  );

  Future<Json> updatePatch(String releaseId, int number, Json body) =>
      _send('PATCH', '/api/v1/releases/$releaseId/patches/$number', body);

  Future<String> uploadBlob(Uint8List bytes) async {
    final response = await _http.post(
      Uri.parse('$baseUrl/api/v1/blobs'),
      headers: _headers,
      body: bytes,
    );
    return (_decode(response)['sha256'])! as String;
  }

  Future<Uint8List> downloadBlob(String sha256) async {
    final response = await _http.get(
      Uri.parse('$baseUrl/api/v1/blobs/$sha256'),
    );
    if (response.statusCode != 200) {
      throw CliException(
        'Could not download blob $sha256 (${response.statusCode})',
      );
    }
    return response.bodyBytes;
  }

  Future<bool> isReachable() async {
    try {
      final response = await _http
          .get(Uri.parse('$baseUrl/healthz'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } on Object {
      return false;
    }
  }

  Map<String, String> get _headers => {
    'authorization': 'Bearer $token',
    'content-type': 'application/json',
  };

  Future<Json> _send(String method, String path, [Json? body]) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers.addAll(_headers);
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request));
    } on SocketException catch (e) {
      throw CliException('Cannot reach $baseUrl: ${e.message}');
    }
    return _decode(response);
  }

  Json _decode(http.Response response) {
    final Object? json = response.body.isEmpty
        ? <String, Object?>{}
        : jsonDecode(response.body);
    if (response.statusCode >= 300) {
      final error = json is Map ? json['error'] : null;
      throw CliException(
        '${error ?? response.reasonPhrase} (HTTP ${response.statusCode})',
        httpStatus: response.statusCode,
      );
    }
    return json! as Json;
  }

  void close() => _http.close();
}
