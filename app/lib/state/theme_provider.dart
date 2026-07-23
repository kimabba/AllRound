import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeModeProvider = StateNotifierProvider<ThemeModeController, ThemeMode>(
  (_) => ThemeModeController(),
);

class ThemeModeController extends StateNotifier<ThemeMode> {
  // 기본값은 라이트. 사용자가 설정에서 dark/system 을 선택하면 prefs 에 저장돼 유지됨.
  // (테마 정밀 수정 전까지 임시 — 다크 테마 폴리시는 추후 결정)
  ThemeModeController() : super(ThemeMode.light) {
    _load();
  }

  static const String _key = 'app.themeMode';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_key);
    state = switch (v) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light, // 저장된 설정 없으면 라이트
    };
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, mode.name);
  }
}
