import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

class ApiError implements Exception {
  final int status;
  final String message;

  const ApiError(this.status, this.message);

  @override
  String toString() => message;
}

/// Time windows the dashboard can show, in the order they are offered.
enum Window {
  day(24, '24h'),
  week(168, '7d'),
  month(720, '30d');

  final int hours;
  final String label;

  const Window(this.hours, this.label);
}

/// Places in the dashboard, in sidebar order.
enum Place { overview, patches, devices, events, settings }

/// Everything the dashboard shows, refreshed on a timer while signed in.
class Session extends ChangeNotifier {
  final http.Client _http = http.Client();
  Timer? _poll;
  bool isLoading = false;
  String? token;
  String? error;
  String server = Uri.base.scheme.startsWith('http')
      ? Uri.base.origin
      : 'http://localhost:8787';
  String? appId;
  Window window = Window.day;
  Place place = Place.overview;
  DateTime? refreshedAt;
  Metrics? metrics;
  AppDetail? app;
  List<String> appIds = const [];
  List<DeviceEvent> events = const [];

  static const pollEvery = Duration(seconds: 10);

  bool get isSignedIn => token != null;

  Future<void> signIn(String server, String token) async {
    this.server = server.replaceAll(RegExp(r'/+$'), '');
    this.token = token;
    try {
      final json = await _get('/api/v1/apps');
      appIds = [
        for (final a in json['apps']! as List) (a as Json)['id']! as String,
      ];
      appId = appIds.isEmpty ? null : appIds.first;
      error = null;
    } on Object {
      this.token = null;
      rethrow;
    }
    notifyListeners();
    await refresh();
    _poll?.cancel();
    _poll = Timer.periodic(pollEvery, (_) => refresh());
  }

  void signOut() {
    _poll?.cancel();
    token = null;
    app = null;
    metrics = null;
    events = const [];
    notifyListeners();
  }

  void go(Place place) {
    this.place = place;
    notifyListeners();
  }

  Future<void> selectApp(String id) async {
    appId = id;
    app = null;
    metrics = null;
    notifyListeners();
    await refresh();
  }

  Future<void> setWindow(Window window) async {
    this.window = window;
    notifyListeners();
    await refresh();
  }

  Future<void> refresh() async {
    final id = appId;
    if (token == null || id == null || isLoading) return;
    isLoading = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        _get('/api/v1/apps/$id'),
        _get('/api/v1/apps/$id/metrics?hours=${window.hours}'),
        _get('/api/v1/events?app_id=$id'),
      ]);
      app = AppDetail.fromJson(results[0]);
      metrics = Metrics.fromJson(results[1]);
      events = [
        for (final e in results[2]['events']! as List)
          DeviceEvent.fromJson(e as Json),
      ];
      refreshedAt = DateTime.now();
      error = null;
    } on Object catch (e) {
      error = '$e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updatePatch(Release release, Patch patch, Json change) async {
    await _send(
      'PATCH',
      '/api/v1/releases/${release.id}/patches/${patch.number}',
      change,
    );
    await refresh();
  }

  Future<void> updateApp(Json change) async {
    await _send('PATCH', '/api/v1/apps/$appId', change);
    await refresh();
  }

  Future<Json> _get(String path) => _send('GET', path, null);

  Future<Json> _send(String method, String path, Json? body) async {
    final request = http.Request(method, Uri.parse('$server$path'))
      ..headers['authorization'] = 'Bearer $token'
      ..headers['content-type'] = 'application/json';
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(await _http.send(request));
    final json = response.body.isEmpty
        ? <String, Object?>{}
        : jsonDecode(response.body);
    if (response.statusCode >= 300) {
      throw ApiError(
        response.statusCode,
        json is Map
            ? '${json['error'] ?? response.reasonPhrase}'
            : '${response.reasonPhrase}',
      );
    }
    return json as Json;
  }

  @override
  void dispose() {
    _poll?.cancel();
    _http.close();
    super.dispose();
  }
}

/// Hands the session down the tree and rebuilds dependents when it changes.
class SessionScope extends InheritedNotifier<Session> {
  const SessionScope({
    super.key,
    required Session session,
    required super.child,
  }) : super(notifier: session);

  static Session of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>()!.notifier!;
}
