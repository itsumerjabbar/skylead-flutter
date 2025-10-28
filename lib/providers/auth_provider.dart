import 'dart:async';

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
  bool _showWelcomeAfterLogin = false;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;
  bool get shouldShowWelcome => _showWelcomeAfterLogin;

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
    print('🔑 Starting login process...');
    
    try {
      print('📡 Making API call...');
      final userData = await ApiService.login(email, password);
      print('✅ Login API successful: ${userData['name']}');
          
      _user = User.fromJson(userData);
      _showWelcomeAfterLogin = true;
      
      print('🎉 User set: ${_user!.name}');
      print('🎉 shouldShowWelcome: $_showWelcomeAfterLogin');
      print('🎉 isAuthenticated: $isAuthenticated');
      print('📢 Calling notifyListeners...');
      
      // Force a rebuild of all listening widgets
      notifyListeners();
      
      // Add a slight delay and notify again to ensure UI updates
      Future.delayed(Duration(milliseconds: 100), () {
        print('🔄 Secondary notifyListeners call');
        notifyListeners();
      });
      
      print('✅ notifyListeners completed');
      
      // Background tasks - don't await these
      _performBackgroundTasks();
      
    } catch (e) {
      print('❌ Login failed: $e');
      rethrow;
    }
  }

  Future<void> _performBackgroundTasks() async {
    // Clear all existing notifications after successful login
    try {
      await FCMService().clearAllNotifications();
    } catch (e) {
      print('⚠️ FCM clear failed (non-critical): $e');
    }

    // Register FCM after successful login
    try {
      await FCMService().registerForPushNotifications();
    } catch (e) {
      print('⚠️ FCM registration failed (non-critical): $e');
    }
  }

  void welcomeScreenShown() {
    _showWelcomeAfterLogin = false;
    notifyListeners();
  }

  Future<void> logout() async {
    print('🚪 Starting logout process...');
    
    try {
      // Call API logout which handles both server logout and local data clearing
      await ApiService.logout();
    } catch (e) {
      print('⚠️ Logout process had issues: $e');
      // ApiService.logout() already handles clearing local data in finally block
    }
    
    // Update provider state
    _user = null;
    _showWelcomeAfterLogin = false;
    
    print('🔄 Notifying listeners for UI update...');
    notifyListeners();
    print('✅ Logout completed - should redirect to login screen');
  }

  Future<void> refreshUserData() async {
    final userData = await ApiService.getUserData();
    if (userData != null) {
      _user = User.fromJson(userData);
      notifyListeners();
    }
  }
}