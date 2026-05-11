import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'pages/login_page.dart';
import 'pages/Librarian/librarian_page.dart';
import 'pages/Student/home_page.dart';

void main() async {
  // Firebase setup starts here.
  // Flutter must finish binding widgets/plugins before Firebase can initialize.
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Connects the app to the Firebase project configured in Android/iOS/Web.
    // This must run before using FirebaseAuth or FirebaseFirestore anywhere.
    await Firebase.initializeApp();

    runApp(const MyApp());
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'Firebase initialization',
      ),
    );

    runApp(StartupErrorApp(error: error));
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LibraTrack',
      theme: ThemeData(useMaterial3: false),
      home: home ?? const AuthGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFE3E7EB),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF3C13C5)),
            ),
          );
        }

        final user = snapshot.data;
        if (user != null) {
          return RoleGate(user: user);
        }

        return const LoginPage();
      },
    );
  }
}

class RoleGate extends StatelessWidget {
  const RoleGate({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFE3E7EB),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF3C13C5)),
            ),
          );
        }

        final data = snapshot.data?.data();
        final role = (data?['role'] ?? data?['accountType'] ?? 'student')
            .toString()
            .trim()
            .toLowerCase();

        if (role == 'librarian') {
          return const LibrarianPage();
        }

        return const StudentPage();
      },
    );
  }
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LibraTrack',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFE3E7EB),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFD32F2F),
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'LibraTrack could not start',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF4B4B4B),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
