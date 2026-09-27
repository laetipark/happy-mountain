import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../app/app_controller.dart';
import 'home_screen.dart';

class HappyMountainApp extends StatelessWidget {
  const HappyMountainApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '산등성이',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ko', 'KR'),
    supportedLocales: const [Locale('ko', 'KR')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Environment',
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF397454),
        primary: const Color(0xFF285C41),
        surface: const Color(0xFFFAFCF8),
      ),
      scaffoldBackgroundColor: const Color(0xFFFAFCF8),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFFAFCF8),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE0E8DB)),
        ),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFE0E8DB)),
    ),
    home: HomeScreen(controller: controller),
  );
}
