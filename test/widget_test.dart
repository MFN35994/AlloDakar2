import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transen/main.dart';
import 'package:transen/domain/providers/auth_provider.dart';
import 'package:transen/domain/providers/theme_provider.dart';

class MockAuthNotifier extends StateNotifier<AuthState?> implements AuthNotifier {
  MockAuthNotifier() : super(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => MockAuthNotifier()),
          themeProvider.overrideWith((ref) => ThemeMode.light),
        ],
        child: const MyApp(),
      ),
    );

    // Network images fail in tests by default (returning 400), 
    // we take the exception so it doesn't fail the test.
    tester.takeException();

    expect(find.byType(MyApp), findsOneWidget);
  });
}
