import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_asistencia_app/features/auth/presentation/screens/signup_screen.dart';

void main() {
  testWidgets('registration rejects empty fields and mismatched passwords', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));
    final submit = find.widgetWithText(FilledButton, 'Crear cuenta');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
    expect(find.text('Ingresa entre 2 y 150 caracteres.'), findsOneWidget);

    final fields = find.byType(TextFormField);
    for (final entry in <int, String>{
      0: 'Ana',
      1: 'Perez',
      2: '123456',
      3: 'clave-segura',
      4: 'otra-clave',
    }.entries) {
      await tester.ensureVisible(fields.at(entry.key));
      await tester.enterText(fields.at(entry.key), entry.value);
    }
    tester.testTextInput.hide();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pump();
    expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
  });

  testWidgets('privacy can be read before creating an account', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));
    final link = find.text('Leer privacidad y condiciones de uso');
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.text('Privacidad y uso de la cuenta'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });
}
