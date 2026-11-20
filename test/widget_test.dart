import 'package:flutter_test/flutter_test.dart';
import 'package:konektor/main.dart';

void main() {
  testWidgets('asks for server settings on first run', (tester) async {
    await tester.pumpWidget(const KonektorApp());
    expect(find.text('Server address'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });
}
