import 'package:flutter_test/flutter_test.dart';

import 'package:singsync/app/singsync_app.dart';

void main() {
  testWidgets('Home renders tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const SingSyncApp());

    expect(find.text('Now Playing'), findsOneWidget);
    expect(find.text('Buscar letra'), findsOneWidget);
  });
}
