import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:unblocker_gui/src/app.dart';

void main() {
  testWidgets('NukeraApp loads correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const NukeraApp());
    await tester.pump();
    await tester.pump();

    // Main screen: scaffold with app bar title, hero power button and
    // the settings action button.
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('Nukera'), findsOneWidget);
    expect(find.byIcon(Icons.power_settings_new), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });
}
