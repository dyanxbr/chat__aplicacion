import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'theme.dart';
import 'services/auth_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/chat/chat_list_screen.dart';
import 'services/notification_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'services/biometric_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService.init();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    NotificationService.showNotification(
      message.notification?.title ?? "Mensaje",
      message.notification?.body ?? "",
    );
  });

  runApp(const AFChatApp());
}

class AFChatApp extends StatelessWidget {
  const AFChatApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'A&F Chat',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const _SplashRouter(),
      );
}

class _SplashRouter extends StatefulWidget {
  const _SplashRouter();

  @override
  State<_SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<_SplashRouter> {
  final storage = const FlutterSecureStorage();

  Future<bool> _checkLogin() async {
    final storage = const FlutterSecureStorage();

    /// token biometrico
    String? bioToken = await storage.read(key: "biometric_token");

    /// sesión normal
    bool logged = await AuthService.isLoggedIn();

    /// si existe biometría → pedir huella
    if (bioToken != null) {
      bool ok = await BiometricService.authenticate();

      if (!ok) {
        return false;
      }

      /// restaurar token si no existe
      if (!logged) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("chat_token", bioToken);
      }

      return true;
    }

    return logged;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _checkLogin(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            backgroundColor: kBg,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'A&F Chat',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: kAccent,
                    ),
                  ),
                  SizedBox(height: 24),
                  CircularProgressIndicator(color: kAccent),
                ],
              ),
            ),
          );
        }

        return snap.data! ? const ChatListScreen() : const LoginScreen();
      },
    );
  }
}
