import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleNotifier extends Notifier<Locale> {
  late SharedPreferences _prefs;

  @override
  Locale build() {
    // Note: This is a synchronous build. 
    // We expect the prefs to be injected or handled via a provider.
    // For now, we return a default and update when possible.
    return const Locale('fr');
  }

  void init(SharedPreferences prefs) {
    _prefs = prefs;
    final savedCode = _prefs.getString('language_code');
    if (savedCode != null) {
      state = Locale(savedCode);
    }
  }

  Future<void> setLocale(Locale locale) async {
    await _prefs.setString('language_code', locale.languageCode);
    state = locale;
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(() {
  return LocaleNotifier();
});
