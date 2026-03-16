import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme.dart';
import 'services/auth_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/chat/chat_list_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
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

class _SplashRouter extends StatelessWidget {
  const _SplashRouter();
  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: AuthService.isLoggedIn(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Scaffold(
              backgroundColor: kBg,
              body: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('A&F Chat',
                      style: TextStyle(fontSize: 32,
                          fontWeight: FontWeight.w700, color: kAccent)),
                  SizedBox(height: 24),
                  CircularProgressIndicator(color: kAccent),
                ]),
              ),
            );
          }
          return snap.data! ? const ChatListScreen() : const LoginScreen();
        },
      );
}
