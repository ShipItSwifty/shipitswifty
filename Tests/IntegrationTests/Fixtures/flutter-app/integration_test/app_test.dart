import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shipit_flutter_test/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App integration tests', () {
    testWidgets('app launches and shows initial state', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      expect(find.text('Flutter Demo Home Page'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('You have pushed the button this many times:'), findsOneWidget);
    });

    testWidgets('increment button increases counter', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('increment_button')));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('counter increments three times correctly', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      for (int i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('increment_button')));
        await tester.pumpAndSettle();
      }

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('decrement button decreases counter', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('increment_button')));
      await tester.tap(find.byKey(const Key('increment_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('decrement_button')));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('reset button resets counter to zero', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('increment_button')));
      await tester.tap(find.byKey(const Key('increment_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reset_button')));
      await tester.pumpAndSettle();

      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('all three buttons are visible', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('increment_button')), findsOneWidget);
      expect(find.byKey(const Key('decrement_button')), findsOneWidget);
      expect(find.byKey(const Key('reset_button')), findsOneWidget);
    });
  });
}
