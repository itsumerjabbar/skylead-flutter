import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'https://skylead.skyos.me/api';

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('userToken');
  }

  static Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userToken', token);
  }

  static Future<void> _saveUserData(Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userData', jsonEncode(userData));
  }

  static Future<Map<String, dynamic>?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('userData');
    if (userDataString != null) {
      return jsonDecode(userDataString);
    }
    return null;
  }

  static Future<void> clearUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userToken');
    await prefs.remove('userData');
  }

  static Future<Map<String, dynamic>> _makeRequest(
    String endpoint,
    String method, {
    Map<String, dynamic>? body,
    Map<String, String>? params,
  }) async {
    final token = await _getToken();
    final url = Uri.parse('$baseUrl$endpoint').replace(queryParameters: params);

    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    http.Response response;
    
    // Add timeout for better iOS compatibility
    const Duration timeout = Duration(seconds: 30);
    
    try {
      if (method == 'GET') {
        response = await http.get(url, headers: headers).timeout(timeout);
      } else if (method == 'POST') {
        response = await http.post(
          url,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        ).timeout(timeout);
      } else if (method == 'PUT') {
        response = await http.put(
          url,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        ).timeout(timeout);
      } else if (method == 'DELETE') {
        response = await http.delete(url, headers: headers).timeout(timeout);
      } else {
        throw Exception('Unsupported HTTP method: $method');
      }
    } catch (e) {
      if (e.toString().contains('timeout')) {
        throw Exception('Request timeout. Please check your internet connection.');
      }
      rethrow;
    }

    if (response.statusCode == 401) {
      // Token expired, clear data
      await clearUserData();
      throw Exception('Session expired. Please login again.');
    }

    if (response.statusCode == 403) {
      // Forbidden access, session ended
      await clearUserData();
      throw Exception('Session has been ended. Please login again.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorData = jsonDecode(response.body);
      throw Exception(errorData['message'] ?? 'Request failed');
    }

    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> get(
    String endpoint, {
    Map<String, String>? params,
  }) async {
    return _makeRequest(endpoint, 'GET', params: params);
  }

  static Future<Map<String, dynamic>> post(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    return _makeRequest(endpoint, 'POST', body: body);
  }

  static Future<Map<String, dynamic>> put(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    return _makeRequest(endpoint, 'PUT', body: body);
  }

  static Future<Map<String, dynamic>> delete(String endpoint) async {
    return _makeRequest(endpoint, 'DELETE');
  }

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorData = jsonDecode(response.body);
      if (response.statusCode == 401) {
        throw Exception('Invalid email or password');
      }
      throw Exception(errorData['message'] ?? 'Login failed');
    }

    final data = jsonDecode(response.body);

    // Extract token and userData with proper validation
    late final String authToken;
    late final Map<String, dynamic> userInfo;

    if (data['data'] != null && data['data']['token'] != null) {
      authToken = data['data']['token'];
      final user = Map<String, dynamic>.from(data['data']);
      user.remove('token');
      userInfo = user;
    } else if (data['token'] != null) {
      authToken = data['token'];
      final user = Map<String, dynamic>.from(data);
      user.remove('token');
      userInfo = user;
    } else {
      throw Exception('Invalid response from server');
    }

    await _saveToken(authToken);
    await _saveUserData(userInfo);

    return userInfo;
  }
}
