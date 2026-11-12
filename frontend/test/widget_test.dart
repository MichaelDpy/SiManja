import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/main.dart';

void main() {
  testWidgets('SimanjaApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SimanjaApp());
    expect(find.byType(SimanjaApp), findsOneWidget);
  });
}
