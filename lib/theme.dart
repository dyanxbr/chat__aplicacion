import 'package:flutter/material.dart';

const kAccent = Color(0xFF00CEC8);
const kAccentDark = Color(0xFF00a8a3);
const kBg = Color(0xFFd7f4f2);
const kCard = Color(0xFFFFFFFF);
const kText = Color(0xFF0d2b2a);
const kMuted = Color(0xFF5e8f8d);
const kBorder = Color(0xFFb2e8e6);
const kError = Color(0xFFe05b5b);
const kSuccess = Color(0xFF27ae60);
const kChatBg = Color(0xFFf4fbfb);
const kSurface = Color(0xFFeef9f9);
const kChatMuted = Color(0xFF6f9c9a);

const String kApiBase = 'https://chat-production-af8e.up.railway.app';
//const String kApiBase = 'http://192.168.0.11:8000';
const String kGeminiKey = 'AIzaSyCHcPkPOlLFP10zbJOJfbaPc0KBrUI5jKo';
const String kGeminiUrl =
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$kGeminiKey';

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: kBg,
      colorScheme: const ColorScheme.light(
        primary: kAccent,
        onPrimary: Colors.white,
        surface: kCard,
        error: kError,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: kSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kAccent, width: 2)),
        hintStyle: const TextStyle(color: kMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: kAccent,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 50),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: kCard,
        foregroundColor: kText,
        elevation: 0,
        titleTextStyle:
            TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w600),
      ),
    );
