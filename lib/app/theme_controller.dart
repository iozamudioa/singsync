import 'package:flutter/material.dart';

class ThemeController extends ChangeNotifier {
  ThemeController() {
    _themeMode = ThemeMode.dark;
  }

  late ThemeMode _themeMode;

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }
}
