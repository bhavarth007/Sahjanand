import 'package:dio/dio.dart';
import 'api_client.dart';
import '../../shared/models/user_model.dart';

class AuthResult {
  final String token;
  final UserModel user;
  const AuthResult({required this.token, required this.user});
}

class AuthService {
  final _client = ApiClient.instance;

  Future<AuthResult> login(String email, String password) async {
    try {
      final response = await _client.dio.post(
        '/api/auth/login',
        data: {'email': email, 'password': password},
      );
      final token = response.data['access_token'] as String;
      final user  = UserModel.fromJson(response.data['user'] as Map<String, dynamic>);
      await _client.saveToken(token);
      return AuthResult(token: token, user: user);
    } on DioException catch (e) {
      final msg = e.response?.data?['detail'] ?? 'Login failed. Please try again.';
      throw Exception(msg);
    }
  }

  Future<void> forgotPassword(String email) async {
    try {
      await _client.dio.post(
        '/api/auth/forgot-password',
        data: {'email': email},
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data?['detail'] ?? 'Request failed.');
    }
  }

  Future<UserModel> getMe() async {
    try {
      final response = await _client.dio.get('/api/auth/me');
      return UserModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(e.response?.data?['detail'] ?? 'Failed to get user.');
    }
  }

  Future<void> logout() async {
    await _client.clearAuth();
  }
}
