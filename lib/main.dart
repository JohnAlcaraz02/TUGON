import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/role_selection_screen.dart';
import 'screens/main_navigation.dart';
import 'screens/admin_dashboard.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    print('✅ Firebase initialized successfully');
  } catch (e) {
    print('❌ Firebase initialization error: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TUGON',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        print('🔍 AuthWrapper - Connection state: ${snapshot.connectionState}');

        // Show loading indicator while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading...'),
                ],
              ),
            ),
          );
        }

        // Handle errors
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                ],
              ),
            ),
          );
        }

        // If user is logged in, check their role
        if (snapshot.hasData && snapshot.data != null) {
          return FutureBuilder<UserRole?>(
            future: AuthService().getUserRole(snapshot.data!.uid),
            builder: (context, roleSnapshot) {
              if (roleSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              if (roleSnapshot.hasData) {
                if (roleSnapshot.data == UserRole.admin) {
                  print('✅ Admin user logged in');
                  return const AdminDashboard();
                } else if (roleSnapshot.data == UserRole.user) {
                  print('✅ Regular user logged in');
                  return const MainNavigation();
                }
              }

              // If no role found, show role selection (don't sign out)
              // This allows newly created users to complete their profile
              print('⚠️ No role found for user, showing RoleSelectionScreen');
              return const RoleSelectionScreen();
            },
          );
        }

        // If user is not logged in, show role selection screen
        print('👤 No user logged in, showing RoleSelectionScreen');
        return const RoleSelectionScreen();
      },
    );
  }
}