import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'https://skylead.skyos.me/api';

  // Utility method to determine if error is network-related
  static bool isNetworkError(String errorMessage) {
    String lowerMessage = errorMessage.toLowerCase();
    return lowerMessage.contains('no internet connection') ||
           lowerMessage.contains('connection timeout') ||
           lowerMessage.contains('unable to connect') ||
           lowerMessage.contains('network is unreachable') ||
           lowerMessage.contains('no address associated') ||
           lowerMessage.contains('failed to connect') ||
           lowerMessage.contains('connection refused') ||
           lowerMessage.contains('socket') ||
           lowerMessage.contains('timeout') ||
           lowerMessage.contains('check your internet') ||
           lowerMessage.contains('check your network');
  }

  // Utility method to get user-friendly error message
  static String getUserFriendlyErrorMessage(String errorMessage) {
    String cleanMessage = errorMessage.replaceFirst('Exception: ', '');
    
    if (isNetworkError(cleanMessage)) {
      return 'No internet connection. Please check your network and try again.';
    }
    
    // Handle Pusher-related errors from server
    if (cleanMessage.toLowerCase().contains('pusher') || 
        cleanMessage.contains('data content of this event exceeds') ||
        cleanMessage.contains('10240 bytes')) {
      return 'Server is experiencing high load. Your request was processed but real-time updates may be delayed.';
    }
    
    if (cleanMessage.contains('Session expired') || 
        cleanMessage.contains('Session has been ended')) {
      return cleanMessage; // Keep session messages as they are
    }
    
    if (cleanMessage.contains('Invalid email or password')) {
      return cleanMessage; // Keep auth messages as they are
    }
    
    // For generic server errors
    if (cleanMessage.isEmpty || 
        cleanMessage.contains('Request failed') ||
        cleanMessage.contains('Something went wrong')) {
      return 'Unable to connect to server. Please try again later.';
    }
    
    return cleanMessage;
  }

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
      String errorMessage = e.toString().toLowerCase();
      
      // Handle network connectivity issues
      if (errorMessage.contains('timeout') || 
          errorMessage.contains('timed out')) {
        throw Exception('Connection timeout. Please check your internet connection and try again.');
      }
      
      if (errorMessage.contains('socket') || 
          errorMessage.contains('network is unreachable') ||
          errorMessage.contains('no address associated') ||
          errorMessage.contains('failed to connect') ||
          errorMessage.contains('connection refused') ||
          errorMessage.contains('no internet connection') ||
          errorMessage.contains('unable to resolve host')) {
        throw Exception('No internet connection. Please check your network and try again.');
      }
      
      if (errorMessage.contains('handshake') || 
          errorMessage.contains('certificate') ||
          errorMessage.contains('ssl')) {
        throw Exception('Connection security error. Please try again later.');
      }
      
      // For other network errors
      if (errorMessage.contains('clientexception') ||
          errorMessage.contains('formatexception')) {
        throw Exception('Unable to connect to server. Please check your internet connection.');
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
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'email': email, 'password': password}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 401) {
        throw Exception('Invalid email or password. Please check your credentials.');
      }

      if (response.statusCode == 422) {
        // Handle validation errors
        try {
          final errorData = jsonDecode(response.body);
          if (errorData['errors'] != null) {
            final errors = errorData['errors'] as Map<String, dynamic>;
            String errorMessage = '';
            for (final fieldErrors in errors.values) {
              if (fieldErrors is List) {
                errorMessage += '${fieldErrors.join(', ')} ';
              }
            }
            throw Exception(errorMessage.trim().isNotEmpty ? errorMessage.trim() : 'Please check your input and try again.');
          }
        } catch (e) {
          throw Exception('Please check your input and try again.');
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        try {
          final errorData = jsonDecode(response.body);
          String errorMessage = errorData['message'] ?? 'Login failed';
          throw Exception(errorMessage);
        } catch (e) {
          if (response.statusCode >= 500) {
            throw Exception('Server error. Please try again later.');
          } else {
            throw Exception('Login failed. Please check your credentials.');
          }
        }
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
    } catch (e) {
      // Handle network and other errors
      if (e is Exception) {
        rethrow; // Re-throw our custom exceptions
      } else {
        // For other types of errors (network, timeout, etc.)
        String errorMessage = e.toString().toLowerCase();
        
        if (errorMessage.contains('timeout') ||
            errorMessage.contains('timed out')) {
          throw Exception('Connection timeout. Please check your internet connection and try again.');
        }
        
        if (errorMessage.contains('socket') || 
            errorMessage.contains('network is unreachable') ||
            errorMessage.contains('no address associated') ||
            errorMessage.contains('failed to connect') ||
            errorMessage.contains('connection refused') ||
            errorMessage.contains('no internet connection') ||
            errorMessage.contains('unable to resolve host')) {
          throw Exception('No internet connection. Please check your network and try again.');
        }
        
        if (errorMessage.contains('handshake') || 
            errorMessage.contains('certificate') ||
            errorMessage.contains('ssl')) {
          throw Exception('Connection security error. Please try again later.');
        }
        
        // For other network errors
        if (errorMessage.contains('clientexception') ||
            errorMessage.contains('formatexception')) {
          throw Exception('Unable to connect to server. Please check your internet connection.');
        }
        
        throw Exception('Login failed. Please check your internet connection and try again.');
      }
    }
  }

  static Future<void> logout() async {
    try {
      print('📡 Calling logout API...');
      // Call server logout endpoint to invalidate the token
      await post('/logout');
      print('✅ Server logout successful');
    } catch (e) {
      print('⚠️ Server logout failed: $e');
      // Even if server logout fails, we should still clear local data for security
      // Don't throw error here to ensure local logout always works
    } finally {
      // Always clear local data regardless of server response
      print('🧹 Clearing local user data...');
      await clearUserData();
      print('✅ Local data cleared');
    }
  }
}
