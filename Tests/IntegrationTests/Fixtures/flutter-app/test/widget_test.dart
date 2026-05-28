import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipit_flutter_test/main.dart';

void main() {
  group('MyApp widget', () {
    testWidgets('renders without crashing', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('shows app bar with title', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      expect(find.text('Flutter Demo Home Page'), findsOneWidget);
    });

    testWidgets('counter starts at zero', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('displays push button message', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      expect(
        find.text('You have pushed the button this many times:'),
        findsOneWidget,
      );
    });

    testWidgets('increment button increments counter', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.tap(find.byKey(const Key('increment_button')));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('increment button multiple taps', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.tap(find.byKey(const Key('increment_button')));
      await tester.tap(find.byKey(const Key('increment_button')));
      await tester.tap(find.byKey(const Key('increment_button')));
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('decrement button decrements counter', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.tap(find.byKey(const Key('increment_button')));
      await tester.tap(find.byKey(const Key('increment_button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('decrement_button')));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('decrement does not go below zero', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.tap(find.byKey(const Key('decrement_button')));
      await tester.pump();
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('reset button resets counter to zero', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.tap(find.byKey(const Key('increment_button')));
      await tester.tap(find.byKey(const Key('increment_button')));
      await tester.tap(find.byKey(const Key('increment_button')));
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reset_button')));
      await tester.pump();
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('shows increment FAB', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      expect(find.byKey(const Key('increment_button')), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('shows decrement FAB', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      expect(find.byKey(const Key('decrement_button')), findsOneWidget);
      expect(find.byIcon(Icons.remove), findsOneWidget);
    });

    testWidgets('shows reset FAB', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      expect(find.byKey(const Key('reset_button')), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('increment then reset then increment shows 1', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.tap(find.byKey(const Key('increment_button')));
      await tester.tap(find.byKey(const Key('increment_button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('reset_button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('increment_button')));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
    });
  });
}
