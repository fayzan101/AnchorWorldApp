import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get/get.dart' as g;
import '../utils/custom_snackbar.dart';

import '../config/api_config.dart';
import '../services/socket_service.dart';
class ApiException implements Exception {
  final String? message;
  final int? statusCode;

  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => 'ApiException: ${message ?? 'Unknown error'} (status: $statusCode)';
}

class ApiClient {
  Dio _dio;

  ApiClient()
      : _dio = Dio(BaseOptions(
          baseUrl: ApiConfig.baseUrl,
          connectTimeout: Duration(seconds: ApiConfig.defaultTimeout),
          receiveTimeout: Duration(seconds: ApiConfig.defaultTimeout),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        )) {
    _dio.interceptors.add(InterceptorsWrapper(onError: (DioError err, ErrorInterceptorHandler handler) async {
      try {
        final response = err.response;
        if (response != null && response.statusCode == ApiConfig.unauthorized) {
          final prefs = await SharedPreferences.getInstance();
          final rememberMe = prefs.getBool('remember_me') ?? false;
          final refreshToken = prefs.getString('refresh_token');

          if (!rememberMe) {
            try {
              await SocketService().disconnect();
              await prefs.remove('auth_token');
              await prefs.remove('refresh_token');
              await prefs.remove('remembered_email');
              await prefs.remove('remember_me');
            } catch (_) {}

            final isOnSignin = g.Get.currentRoute == '/signin';
            final isOnReset = g.Get.currentRoute == '/reset-password';
            if (!isOnSignin && !isOnReset && (g.Get.isOverlaysOpen || g.Get.context != null)) {
              g.Get.offAllNamed('/signin');
            }
            handler.next(err);
            return;
          }
          if (refreshToken != null && refreshToken.isNotEmpty) {
            final refreshDio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl, connectTimeout: Duration(seconds: ApiConfig.defaultTimeout)));
            try {
              final refreshResp = await refreshDio.post(ApiConfig.refreshToken, data: {'refresh_token': refreshToken}, options: Options(headers: ApiConfig.jsonHeaders));
              final status = refreshResp.statusCode ?? 0;
              if (status == ApiConfig.success || status == ApiConfig.created) {
                final body = refreshResp.data;
                String? newToken;
                if (body is Map<String, dynamic>) {
                  final inner = (body[ApiConfig.dataKey] is Map<String, dynamic>) ? Map<String, dynamic>.from(body[ApiConfig.dataKey]) : null;
                  newToken = inner?['access_token'] ?? inner?['accessToken'] ?? body['access_token'] ?? body['accessToken'];
                }
                if (newToken != null && newToken.isNotEmpty) {
                  await prefs.setString('auth_token', newToken);
                  _dio.options.headers['Authorization'] = 'Bearer $newToken';
                  final opts = err.requestOptions;
                  opts.headers['Authorization'] = 'Bearer $newToken';
                  final cloneReq = await _dio.fetch(opts);
                  handler.resolve(cloneReq);
                  return;
                }
              }
            } catch (_) {
              try {
                await prefs.remove('auth_token');
                await prefs.remove('refresh_token');
              } catch (_) {}
              if (g.Get.isOverlaysOpen || g.Get.context != null) {
                try {
                  await prefs.remove('remembered_email');
                  await prefs.remove('remember_me');
                } catch (_) {}

                final isOnSignin = g.Get.currentRoute == '/signin';
                final isOnReset = g.Get.currentRoute == '/reset-password';
                if (!isOnSignin && !isOnReset) {
                  g.Get.offAllNamed('/signin');
                }
              }
            }
          }
        }
      } catch (_) {}
      handler.next(err);
    }));
  }

  Future<Response> post(String path, {dynamic data, Options? options}) async {
    try {
      Options? opts = options;
      if (data is FormData) {
        final headers = Map<String, dynamic>.from(options?.headers ?? {});
        headers.remove(Headers.contentTypeHeader);
        headers.remove('Content-Type');
        opts = (options ?? Options()).copyWith(
          headers: headers,
          contentType: null,
        );
      }
      final resp = await _dio.post(path, data: data, options: opts);
      return resp;
    } on DioError catch (e) {
      final typeName = e.type.toString().toLowerCase();
      final isTimeout = typeName.contains('timeout');
      final isSocketIssue = e.error is SocketException || (e.error != null && e.error.toString().toLowerCase().contains('socket'));
      final calledForgot = path.toString().contains(ApiConfig.forgotPassword);
      if ((isTimeout || isSocketIssue) && calledForgot) {
        throw ApiException('Failed to send password reset email');
      }
      if (e.response != null) {
        final respData = e.response?.data;
        String msg;
        try {
          msg = respData is String ? respData : jsonEncode(respData);
        } catch (_) {
          msg = (e.response?.statusMessage ?? e.message).toString();
        }
        throw ApiException(msg, e.response?.statusCode);
      }
      throw ApiException(e.message);
    } catch (e) {
      throw ApiException(e.toString());
    }
  }

  Future<Response> get(String path, {Map<String, dynamic>? queryParameters, Options? options}) async {
    try {
      final resp = await _dio.get(path, queryParameters: queryParameters, options: options);
      return resp;
    } on DioError catch (e) {
      if (e.response != null) {
        final respData = e.response?.data;
        String msg;
        try {
          msg = respData is String ? respData : jsonEncode(respData);
        } catch (_) {
          msg = (e.response?.statusMessage ?? e.message).toString();
        }
        throw ApiException(msg, e.response?.statusCode);
      }
      throw ApiException(e.message);
    } catch (e) {
      throw ApiException(e.toString());
    }
  }

  Future<Response> put(String path, {dynamic data, Options? options}) async {
    try {

      final resp = await _dio.put(path, data: data, options: options);
      return resp;
    } on DioError catch (e) {
      final typeName = e.type.toString().toLowerCase();
      final isTimeout = typeName.contains('timeout');
      final isSocketIssue = e.error is SocketException || (e.error != null && e.error.toString().toLowerCase().contains('socket'));
      final calledForgot = path.toString().contains(ApiConfig.forgotPassword);
      if ((isTimeout || isSocketIssue) && calledForgot) {
        throw ApiException('Failed to send password reset email');
      }

      if (e.response != null) {
        final respData = e.response?.data;
        String msg;
        try {
          msg = respData is String ? respData : jsonEncode(respData);
        } catch (_) {
          msg = (e.response?.statusMessage ?? e.message).toString();
        }
        throw ApiException(msg, e.response?.statusCode);
      }
      throw ApiException(e.message);
    } catch (e) {
      throw ApiException(e.toString());
    }
  }

  Future<Response> patch(String path, {dynamic data, Options? options}) async {
    try {
      final resp = await _dio.patch(path, data: data, options: options);
      return resp;
    } on DioError catch (e) {
      if (e.response != null) {
        final respData = e.response?.data;
        String msg;
        try {
          msg = respData is String ? respData : jsonEncode(respData);
        } catch (_) {
          msg = (e.response?.statusMessage ?? e.message).toString();
        }
        throw ApiException(msg, e.response?.statusCode);
      }
      throw ApiException(e.message);
    } catch (e) {
      throw ApiException(e.toString());
    }
  }

  Future<Response> delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final resp = await _dio.delete(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
      return resp;
    } on DioError catch (e) {
      if (e.response != null) {
        final respData = e.response?.data;
        String msg;
        try {
          msg = respData is String ? respData : jsonEncode(respData);
        } catch (_) {
          msg = (e.response?.statusMessage ?? e.message).toString();
        }
        throw ApiException(msg, e.response?.statusCode);
      }
      throw ApiException(e.message);
    } catch (e) {
      throw ApiException(e.toString());
    }
  }
  Future<void> setAuthToken(String token) async {
    final bearer = 'Bearer $token';
    _dio.options.headers['Authorization'] = bearer;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  void setAuthTokenInMemory(String token) {
    final bearer = 'Bearer $token';
    _dio.options.headers['Authorization'] = bearer;
  }
}
final ApiClient apiClient = ApiClient();
