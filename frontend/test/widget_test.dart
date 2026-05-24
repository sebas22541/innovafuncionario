import 'package:flutter_test/flutter_test.dart';

import 'package:qr_asistencia_app/main.dart';

void main() {
  testWidgets('renders responsive auth entry screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const QrWebApp());
    await tester.pump();

    expect(find.text('Ingresar'), findsOneWidget);
    expect(find.text('Ingresar con:'), findsNothing);
  });
}
