import 'package:flutter_test/flutter_test.dart';

import 'package:lyric_notifier/app/lyric_notifier_app.dart';

void main() {
  testWidgets('Home renders tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const LyricNotifierApp());

    expect(find.text('Now Playing'), findsOneWidget);
    expect(find.text('Buscar letra'), findsOneWidget);
  });
}
