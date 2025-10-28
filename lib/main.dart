import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Initialize FCM
  final fcmService = FCMService();
  await fcmService.initialize(
    onNotificationReceived: (data) {
      // Handle notification data here if needed
    },
  );
  
  // Clear all notifications when app starts fresh
  await fcmService.clearAllNotifications();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AuthProvider())],
      child: MaterialApp(
        title: 'SkyLead',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        initialRoute: '/',
        routes: {
          '/': (context) => AuthWrapper(),
          '/login': (context) => LoginScreen(),
          '/welcome': (context) => WelcomeScreen(),
          '/main': (context) => MainScreen(),
          '/home': (context) => MainScreen(),
        },
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        print('🔄 AuthWrapper rebuild - isLoading: ${auth.isLoading}, isAuthenticated: ${auth.isAuthenticated}, shouldShowWelcome: ${auth.shouldShowWelcome}');
        
        // Show loading screen during initial load
        if (auth.isLoading) {
          print('⏳ Showing loading screen');
          return const Scaffold(
            backgroundColor: Color(0xFF1B5E5A),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2ECC71)),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Loading...',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          );
        }

        // Handle authenticated states
        if (auth.isAuthenticated) {
          if (auth.shouldShowWelcome) {
            print('👋 Showing welcome screen');
            return WelcomeScreen();
          } else {
            print('🏠 Showing main screen');
            return MainScreen();
          }
        }

        // Show login screen for unauthenticated users
        print('🔐 Showing login screen');
        return LoginScreen();
      },
    );
  }
}
