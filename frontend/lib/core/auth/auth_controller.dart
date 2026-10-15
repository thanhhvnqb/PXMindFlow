import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Account {
  final String id;
  final Dio api;
  Account(this.id, this.api);
}

class AuthController {
  final FlutterSecureStorage storage;
  final String baseUrl;
  AuthController({
    this.storage = const FlutterSecureStorage(
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    ),
    this.baseUrl = const String.fromEnvironment(
      'API_URL',
      defaultValue: 'http://localhost:8000/api/v1',
    ),
  });
  Dio get client => Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );
  Future<Account> login(String email, String password, bool register) async {
    final response = await client.post(
      '/auth/${register ? 'register' : 'login'}',
      data: {'email': email, 'password': password},
    );
    await storage.write(key: 'account', value: jsonEncode(response.data));
    return _account(Map<String, dynamic>.from(response.data));
  }

  Future<Account?> restore() async {
    final value = await storage.read(key: 'account');
    return value == null ? null : _account(jsonDecode(value));
  }

  Account _account(Map<String, dynamic> tokens) {
    final api = client;
    api.options.headers['Authorization'] = 'Bearer ${tokens['access_token']}';
    Future<void>? refreshing;
    api.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) async {
          if (error.response?.statusCode != 401 ||
              error.requestOptions.extra['retried'] == true) {
            handler.next(error);
            return;
          }
          try {
            refreshing ??= (() async {
              final response = await client.post(
                '/auth/refresh',
                data: {'refresh_token': tokens['refresh_token']},
              );
              tokens = Map<String, dynamic>.from(response.data);
              await storage.write(key: 'account', value: jsonEncode(tokens));
              api.options.headers['Authorization'] =
                  'Bearer ${tokens['access_token']}';
            })().whenComplete(() => refreshing = null);
            await refreshing;
            error.requestOptions.headers['Authorization'] =
                api.options.headers['Authorization'];
            error.requestOptions.extra['retried'] = true;
            handler.resolve(await api.fetch(error.requestOptions));
          } catch (_) {
            handler.next(error);
          }
        },
      ),
    );
    return Account(tokens['user_id'], api);
  }

  Future<void> logout() async {
    final value = await storage.read(key: 'account');
    if (value != null) {
      try {
        await client.post(
          '/auth/logout',
          data: {'refresh_token': jsonDecode(value)['refresh_token']},
        );
      } catch (_) {
        /* Local logout still retains domain data. */
      }
    }
    await storage.delete(key: 'account');
  }
}
