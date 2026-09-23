import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/env.dart';
import '../i18n/i18n.dart';
import '../storage/prefs.dart';
import 'network_status.dart';

const mediaUploadTimeout = Duration(milliseconds: 180000);
const storyPublishTimeout = Duration(milliseconds: 90000);

/// Background writes that have their own UI state (or none) and must not block the screen.
final _silentPaths = RegExp(
  r'(^|/)(media/upload|livekit/token|notifications/|user-notifications|SiteContent|stories|short-films|banners|auth/'
  r'|user/(avatar|profile-contact|privacy|account))|/read(-all)?$|/view',
  caseSensitive: false,
);

/// Mirrors mobile-app/src/services/api.js.
class Api {
  Api._();

  static final unauthorized = StreamController<void>.broadcast();

  /// stores/apiLoading.js — shown by the global overlay after 300 ms.
  static final loadingOverlay = ValueNotifier<bool>(false);
  static int _pending = 0;
  static Timer? _overlayDelay;

  static bool _tracked(RequestOptions o) {
    if (o.extra['skipGlobalLoader'] == true) return false;
    if (o.method.toUpperCase() == 'GET') return false;
    return !_silentPaths.hasMatch(o.path);
  }

  static void _begin(RequestOptions o) {
    if (!_tracked(o)) return;
    o.extra['_globalLoader'] = true;
    _pending++;
    _overlayDelay ??= Timer(const Duration(milliseconds: 300), () {
      if (_pending > 0) loadingOverlay.value = true;
    });
  }

  static void _end(RequestOptions o) {
    if (o.extra['_globalLoader'] != true) return;
    o.extra.remove('_globalLoader');
    _pending = _pending > 0 ? _pending - 1 : 0;
    if (_pending == 0) {
      _overlayDelay?.cancel();
      _overlayDelay = null;
      loadingOverlay.value = false;
    }
  }

  static final Dio dio = Dio(
    BaseOptions(
      baseUrl: '${Env.apiUrl}/',
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 20),
    ),
  )..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.extra['allowOffline'] != true && !NetworkStatus.online.value) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
                error: 'offline',
                message: I18n.t('noConnection.title'),
              ),
              true,
            );
            return;
          }
          final token = Prefs.instance.token;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          if (RegExp(r'/?media/upload', caseSensitive: false).hasMatch(options.path)) {
            options.sendTimeout = mediaUploadTimeout;
            options.receiveTimeout = mediaUploadTimeout;
          }
          _begin(options);
          handler.next(options);
        },
        onResponse: (res, handler) {
          _end(res.requestOptions);
          NetworkStatus.onTransportSuccess?.call();
          handler.next(res);
        },
        onError: (e, handler) {
          _end(e.requestOptions);
          if (e.error == 'offline') {
            handler.next(e);
            return;
          }
          if (_isTransportError(e)) {
            NetworkStatus.onTransportFailure?.call();
          } else if (e.response != null) {
            NetworkStatus.onTransportSuccess?.call();
          }
          if (e.response?.statusCode == 401 && e.requestOptions.extra['skipUnauthorizedEvent'] != true) {
            unauthorized.add(null);
          }
          handler.next(e);
        },
      ),
    );

  static String _p(String path) => path.startsWith('/') ? path.substring(1) : path;

  static Future<dynamic> get(String path, {Map<String, dynamic>? query, bool skipUnauthorized = false}) async {
    final res = await dio.get(_p(path),
        queryParameters: query, options: Options(extra: {'skipUnauthorizedEvent': skipUnauthorized}));
    return res.data;
  }

  static Future<dynamic> post(String path, [Object? data, Options? options]) async =>
      (await dio.post(_p(path), data: data, options: options)).data;

  static Future<dynamic> put(String path, [Object? data]) async => (await dio.put(_p(path), data: data)).data;

  static Future<dynamic> delete(String path, [Object? data]) async => (await dio.delete(_p(path), data: data)).data;

  static bool _isTransportError(DioException e) =>
      e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.error == 'offline';

  static String errorMessage(Object e, [String fallback = '']) {
    if (e is DioException) {
      if (_isTransportError(e)) {
        return fallback.isNotEmpty ? fallback : I18n.t('noConnection.title');
      }
      final data = e.response?.data;
      if (data is Map && data['message'] is String) return data['message'] as String;
      if (data is Map && data['title'] is String) return data['title'] as String;
    }
    return fallback;
  }

  /// Uploaded files come back as `/uploads/...`; make them absolute against the API host.
  static String? absoluteUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return url;
    return '${Env.apiHost}${url.startsWith('/') ? '' : '/'}$url';
  }
}
