import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { admin, user }

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserRole?> getUserRole(String uid) async {
    try {
      final adminDoc = await _firestore.collection('admins').doc(uid).get();
      if (adminDoc.exists) {
        return UserRole.admin;
      }

      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (userDoc.exists) {
        return UserRole.user;
      }

      return null;
    } catch (e) {
      print('Error getting user role: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> signUpWithEmail({
    required String email,
    required String password,
    required UserRole role,
    String? displayName,
  }) async {
    try {
      print('🔐 Starting signup for: $email with role: $role');

      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      print('✅ Firebase Auth user created: ${userCredential.user?.uid}');
      print('📝 Creating Firestore document...');

      await _createUserDocument(userCredential.user!, role, displayName: displayName);
      await Future.delayed(const Duration(milliseconds: 500));

      print('✅ Signup complete!');

      return {
        'success': true,
        'user': userCredential.user,
        'role': role,
      };
    } on FirebaseAuthException catch (e) {
      print('❌ FirebaseAuthException: ${e.code} - ${e.message}');
      return {
        'success': false,
        'message': _getErrorMessage(e.code),
      };
    } catch (e) {
      print('❌ Unexpected error during signup: $e');
      return {
        'success': false,
        'message': 'An unexpected error occurred. Please try again.',
      };
    }
  }

  Future<Map<String, dynamic>> signInWithEmail({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final actualRole = await getUserRole(userCredential.user!.uid);

      if (actualRole == null) {
        await _auth.signOut();
        return {
          'success': false,
          'message': 'Account not found. Please sign up first.',
        };
      }

      if (actualRole != role) {
        await _auth.signOut();
        return {
          'success': false,
          'message': role == UserRole.admin
              ? 'This account is not an admin account.'
              : 'This account is not a user account.',
        };
      }

      await _updateLastLogin(userCredential.user!.uid, actualRole);

      return {
        'success': true,
        'user': userCredential.user,
        'role': actualRole,
      };
    } on FirebaseAuthException catch (e) {
      return {
        'success': false,
        'message': _getErrorMessage(e.code),
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'An unexpected error occurred. Please try again.',
      };
    }
  }

  Future<Map<String, dynamic>> signInWithGoogle({required UserRole role}) async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        return {
          'success': false,
          'message': 'Google sign-in cancelled',
        };
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential = await _auth.signInWithCredential(credential);
      final existingRole = await getUserRole(userCredential.user!.uid);

      if (existingRole == null) {
        await _createUserDocument(userCredential.user!, role);
      } else if (existingRole != role) {
        await _auth.signOut();
        await _googleSignIn.signOut();
        return {
          'success': false,
          'message': role == UserRole.admin
              ? 'This Google account is registered as a user, not an admin.'
              : 'This Google account is registered as an admin, not a user.',
        };
      } else {
        await _updateLastLogin(userCredential.user!.uid, existingRole);
      }

      return {
        'success': true,
        'user': userCredential.user,
        'role': role,
      };
    } catch (e) {
      print('❌ Google Sign-In error: $e');
      return {
        'success': false,
        'message': 'Failed to sign in with Google. Please try again.',
      };
    }
  }

  Future<void> _createUserDocument(User user, UserRole role, {String? displayName}) async {
    try {
      final collection = role == UserRole.admin ? 'admins' : 'users';
      final userDoc = _firestore.collection(collection).doc(user.uid);

      print('📝 Attempting to create document in collection: $collection');
      print('📝 User ID: ${user.uid}');
      print('📝 Email: ${user.email}');

      await userDoc.set({
        'userId': user.uid,
        'email': user.email,
        'displayName': displayName ?? '',
        'photoURL': user.photoURL ?? '',
        'role': role.toString(),
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
      });

      print('✅ Successfully created user document in Firestore!');
    } catch (e) {
      print('❌ Error creating user document: $e');
      rethrow;
    }
  }

  Future<void> _updateLastLogin(String uid, UserRole role) async {
    final collection = role == UserRole.admin ? 'admins' : 'users';
    await _firestore.collection(collection).doc(uid).update({
      'lastLogin': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      final role = await getUserRole(uid);
      if (role == null) return null;

      final collection = role == UserRole.admin ? 'admins' : 'users';
      final doc = await _firestore.collection(collection).doc(uid).get();

      if (doc.exists) {
        return {
          ...doc.data()!,
          'role': role,
        };
      }
      return null;
    } catch (e) {
      print('Error getting user data: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }

  Future<Map<String, dynamic>> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return {
        'success': true,
        'message': 'Password reset email sent. Check your inbox.',
      };
    } on FirebaseAuthException catch (e) {
      return {
        'success': false,
        'message': _getErrorMessage(e.code),
      };
    }
  }

  String _getErrorMessage(String code) {
    switch (code) {
      case 'weak-password':
        return 'The password provided is too weak. Use at least 6 characters.';
      case 'email-already-in-use':
        return 'An account already exists for this email.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      default:
        return 'An error occurred. Please try again.';
    }
  }
}