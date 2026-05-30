import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qr_asistencia_app/main.dart';

void main() {
  testWidgets('renders responsive auth entry screen', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const QrWebApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Ingresar'), findsOneWidget);
    expect(find.text('Ingresar con:'), findsNothing);
  });
}
