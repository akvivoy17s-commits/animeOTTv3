import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'pages/home.dart';
import 'pages/login.dart';
import 'firebase_options.dart';
import 'logging.dart';
import 'services/admin_service.dart';
import 'ui/neo.dart';
import 'ui/splash_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  configureLogging();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await GoogleSignIn.instance.initialize(
    clientId: kIsWeb ? 'YOUR_WEB_CLIENT_ID' : null,
  );

  AdminService.init();

  runApp(const MainApp());
}

// ============================================================
// MAIN APP
// ============================================================

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: Neo.appName,
      theme: Neo.theme(),
      builder: (context, child) {
        // keeps layouts safe when users set very large system fonts
        return MediaQuery.withClampedTextScaling(
          minScaleFactor: 0.85,
          maxScaleFactor: 1.15,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const _Root(),
    );
  }
}

// ============================================================
// ROOT: splash first, then auth gate
// ============================================================

class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: _splashDone
          ? const AuthGate(key: ValueKey('gate'))
          : SplashPage(
              key: const ValueKey('splash'),
              onDone: () {
                if (mounted) setState(() => _splashDone = true);
              },
            ),
    );
  }
}

// ============================================================
// AUTH GATE
// ============================================================

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Neo.bg,
            body: Center(child: CircularProgressIndicator(color: Neo.cyan)),
          );
        }

        if (snapshot.hasData) {
          return const HomePage();
        }

        return const LoginPage();
      },
    );
  }
}
