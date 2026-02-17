import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test runner works', () {
    expect(2 + 2, 4);
  });

  testWidgets('smoke test renders a widget', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('RES-Q'),
          ),
        ),
      ),
    );

    expect(find.text('RES-Q'), findsOneWidget);
  });
}
