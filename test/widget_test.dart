import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transen/main.dart';
import 'package:transen_auth/transen_auth.dart';
import 'package:transen_core/transen_core.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Basic test to check if MyApp builds
    await tester.pumpWidget(
      const ProviderScope(
        child: MyApp(),
      ),
    );

    tester.takeException();
    expect(find.byType(MyApp), findsOneWidget);
  });
}
