import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/main.dart';

void main() {
  testWidgets('renders Curiosity shell actions', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('Curiosity'), findsOneWidget);
    expect(find.byTooltip('Start'), findsOneWidget);
    expect(find.byTooltip('Diary'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
  });
}
