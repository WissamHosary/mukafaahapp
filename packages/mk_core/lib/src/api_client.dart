import 'dart:async';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api_exception.dart';
import 'config.dart';
import 'ids.dart';
import 'secure_store.dart';

/// Single HTTP client for the apps. Adds auth, device, version and language
/// headers; rotates refresh tokens (one refresh in flight at a time); retries
/// safe GETs once on network failure; maps every failure to [ApiException].
class ApiClient {
  ApiClient({
    required this.store,
    required this.app,
    this.onSessionExpired,
    String? baseUrl,
  }) : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl ?? AppConfig.apiUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 20),
            sendTimeout: const Duration(seconds: 20),
            contentType: Headers.jsonContentType,
            responseType: ResponseType.json,
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
  }

  final SecureStore store;

  /// 'CUSTOMER' or 'BUSINESS'.
  final String app;
  final void Function()? onSessionExpired;
  final Dio _dio;

  /// Language sent as Accept-Language (ar/en).
  String language = 'ar';

  /// When set (cashier mode), this token is used instead of the user session.
  String? staffToken;

  /// The shop owner's own counter session: used only for counter (cashier) calls,
  /// while every other call keeps the owner's sign-in.
  String? counterToken;

  static bool _isCounterPath(String path) => path.contains('/v1/business/cashier/');

  String? _appVersion;
  Completer<bool>? _refreshing;
  bool _devServerLoaded = false;

  /// Test builds only: the server address can be changed inside the app, so a
  /// new Wi-Fi address on the PC does not need a rebuild.
  static const devServerKey = 'mk.dev_api_url';

  /// Address requests currently go to.
  Future<String> currentServer() async {
    await _loadDevServer();
    return _dio.options.baseUrl;
  }

  /// Saves a new server address (test builds only) and checks it answers.
  /// Accepts "192.168.1.5", "192.168.1.5:3000" or a full http:// URL.
  Future<bool> setDevServer(String input) async {
    if (!AppConfig.isDev) return false;
    var url = input.trim();
    if (url.isEmpty) {
      await store.write(devServerKey, null);
      _dio.options.baseUrl = AppConfig.apiUrl;
      return ping();
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'http://$url';
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return false;
    if (!uri.hasPort) url = '$url:3000';
    await store.write(devServerKey, url);
    _dio.options.baseUrl = url;
    return ping();
  }

  /// True when the server answers /health.
  Future<bool> ping() async {
    try {
      final r = await _dio.get<dynamic>(
        '/health',
        options: Options(extra: {'auth': false, 'netRetry': true}),
      );
      return r.statusCode == 200;
    } on Object {
      return false;
    }
  }

  Future<void> _loadDevServer() async {
    if (_devServerLoaded) return;
    _devServerLoaded = true;
    if (!AppConfig.isDev) return;
    final saved = await store.read(devServerKey);
    if (saved != null && saved.isNotEmpty) _dio.options.baseUrl = saved;
  }

  Future<void> _onRequest(
    RequestOptions o,
    RequestInterceptorHandler h,
  ) async {
    if (!_devServerLoaded) {
      await _loadDevServer();
      o.baseUrl = _dio.options.baseUrl;
    }
    _appVersion ??= await PackageInfo.fromPlatform()
        .then((p) => '${p.version}+${p.buildNumber}')
        .catchError((_) => 'unknown');
    o.headers['X-App'] = app;
    o.headers['X-App-Version'] = _appVersion;
    o.headers['X-Device-Id'] = await store.deviceId();
    o.headers['Accept-Language'] = language;
    if (o.extra['auth'] != false) {
      final token = staffToken ?? (counterToken != null && _isCounterPath(o.path) ? counterToken : null) ?? await store.accessToken;
      if (token != null) o.headers['Authorization'] = 'Bearer $token';
    }
    h.next(o);
  }

  Future<void> _onError(DioException e, ErrorInterceptorHandler h) async {
    final req = e.requestOptions;
    final status = e.response?.statusCode;
    final isRefreshCall = req.path.endsWith('/v1/auth/refresh');
    if (status == 401 &&
        staffToken == null &&
        !(counterToken != null && _isCounterPath(req.path)) &&
        !isRefreshCall &&
        req.extra['auth'] != false &&
        req.extra['retried'] != true) {
      if (await _refresh()) {
        req.extra['retried'] = true;
        try {
          final res = await _dio.fetch<dynamic>(req);
          return h.resolve(res);
        } on DioException catch (e2) {
          return h.next(e2);
        }
      }
      onSessionExpired?.call();
    }
    // One retry of an idempotent GET after a transient network failure.
    final transient = e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout;
    if (transient && req.method == 'GET' && req.extra['netRetry'] != true) {
      req.extra['netRetry'] = true;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      try {
        return h.resolve(await _dio.fetch<dynamic>(req));
      } on DioException catch (e2) {
        return h.next(e2);
      }
    }
    h.next(e);
  }

  Future<bool> _refresh() async {
    final inflight = _refreshing;
    if (inflight != null) return inflight.future;
    final c = Completer<bool>();
    _refreshing = c;
    try {
      final rt = await store.refreshToken;
      if (rt == null) {
        c.complete(false);
        return false;
      }
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/auth/refresh',
        data: {'refreshToken': rt},
        options: Options(extra: {'auth': false}),
      );
      final d = res.data!;
      await store.saveTokens(
        access: d['accessToken'] as String,
        refresh: d['refreshToken'] as String,
      );
      c.complete(true);
      return true;
    } on Object {
      await store.clearTokens();
      c.complete(false);
      return false;
    } finally {
      _refreshing = null;
    }
  }

  // ---------- public helpers ----------
  Future<T> get<T>(String path, {Map<String, dynamic>? query}) =>
      _wrap(() => _dio.get<T>(path, queryParameters: query));

  Future<T> post<T>(
    String path, {
    Object? data,
    bool auth = true,
    bool idempotent = false,
    String? idempotencyKey,
  }) =>
      _wrap(
        () => _dio.post<T>(
          path,
          data: data ?? <String, dynamic>{},
          options: Options(
            extra: {'auth': auth},
            headers: idempotent
                ? {'Idempotency-Key': idempotencyKey ?? newUuid()}
                : null,
          ),
        ),
      );

  Future<T> put<T>(String path, {Object? data}) =>
      _wrap(() => _dio.put<T>(path, data: data));

  Future<T> patch<T>(String path, {Object? data}) =>
      _wrap(() => _dio.patch<T>(path, data: data));

  Future<T> delete<T>(String path) => _wrap(() => _dio.delete<T>(path));

  /// Address requests go to right now (for building image URLs).
  String get baseUrl => _dio.options.baseUrl;

  /// Turns a server path like `/v1/media/…` into a full URL. Passes full URLs through.
  String? resolve(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return '$base$path';
  }

  Future<T> _wrap<T>(Future<Response<T>> Function() call) async {
    try {
      final r = await call();
      return r.data as T;
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  ApiException _map(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const ApiException(code: 'TIMEOUT', status: 0);
      case DioExceptionType.connectionError:
        return const ApiException(code: 'NETWORK', status: 0);
      case DioExceptionType.cancel:
        return const ApiException(code: 'CANCELLED', status: 0);
      default:
        final data = e.response?.data;
        if (data is Map) {
          return ApiException(
            code: (data['code'] ?? 'HTTP_${e.response?.statusCode}').toString(),
            status: e.response?.statusCode ?? 0,
            message: data['title']?.toString(),
            retryAfterSec: (data['retryAfterSec'] as num?)?.toInt(),
          );
        }
        return ApiException(
          code: e.response == null ? 'NETWORK' : 'HTTP_${e.response?.statusCode}',
          status: e.response?.statusCode ?? 0,
        );
    }
  }
}
