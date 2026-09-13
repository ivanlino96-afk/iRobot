import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiClient {
  ApiClient(String url)
    : dio = Dio(
        BaseOptions(
          baseUrl: url,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ),
      ) {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('La API requiere una URL HTTPS');
    }
  }
  final Dio dio;
  final storage = const FlutterSecureStorage();
  String? token;
  Future<void> restore() async {
    token = await storage.read(key: 'session:${dio.options.baseUrl}');
    if (token != null) dio.options.headers['Authorization'] = 'Bearer $token';
  }

  Future<void> login(
    String email,
    String password, {
    bool register = false,
  }) async {
    final r = await dio.post(
      '/auth/${register ? 'register' : 'login'}',
      data: {'email': email, 'password': password},
    );
    token = r.data['token'];
    dio.options.headers['Authorization'] = 'Bearer $token';
    await storage.write(key: 'session:${dio.options.baseUrl}', value: token);
  }

  Future<void> logout() async {
    await storage.delete(key: 'session:${dio.options.baseUrl}');
    token = null;
    dio.options.headers.remove('Authorization');
  }

  Future<dynamic> get(String path) async => (await dio.get(path)).data;
  Future<dynamic> post(String path, dynamic data) async =>
      (await dio.post(path, data: data)).data;
  Future<void> delete(String path) async {
    await dio.delete(path);
  }
}
