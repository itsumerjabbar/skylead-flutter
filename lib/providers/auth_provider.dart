import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/fcm_service.dart';

class User {
  final int id;
  final String email;
  final String name;
  final int companyId;
  final int isSuperadmin;
  final String position;
  final String role;
  final List<dynamic> roles;

  User({
    required this.id,
    required this.email,
    required this.name,
    required this.companyId,
    required this.isSuperadmin,
    required this.position,
    required this.role,
    required this.roles,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      email: json['email'],
      name: json['name'],
      companyId: json['company_id'],
      isSuperadmin: json['is_superadmin'],
      position: json['position'],
      role: json['role'],
      roles: json['roles'] ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'company_id': companyId,
      'is_superadmin': isSuperadmin,
      'position': position,
      'role': role,
      'roles': roles,
    };
  }
}

class AuthProvider with ChangeNotifier {
  User? _user;
  bool _isLoading = true;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;

  AuthProvider() {
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    _isLoading = true;
    notifyListeners();

    final userData = await ApiService.getUserData();
    if (userData != null) {
      _user = User.fromJson(userData);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final userData = await ApiService.login(email, password);
      _user = User.fromJson(userData);

      // Clear all existing notifications after successful login
      try {
        await FCMService().clearAllNotifications();
      } catch (e) {
        // Notification clearing failed, but don't fail login
      }

      // Register FCM after successful login
      try {
        await FCMService().registerForPushNotifications();
        // FCM registered successfully
      } catch (e) {
        // FCM registration failed, but don't fail login
        // Error handling can be added here if needed
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> logout() async {
    await ApiService.clearUserData();
    _user = null;
    notifyListeners();
  }

  Future<void> refreshUserData() async {
    final userData = await ApiService.getUserData();
    if (userData != null) {
      _user = User.fromJson(userData);
      notifyListeners();
    }
  }
}