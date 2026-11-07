import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glamora_movil/main.dart';
import 'package:glamora_movil/session.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_api.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets('sin servicios creados: escribir la descripción y pulsar Listo no rompe la pantalla', (tester) async {
    final fake = FakeApi()
      ..on('GET /me', meJson(abilities: {'dashboard': true, 'services_view': true, 'services_create': true, 'services_edit': true}))
      ..on('GET /auth/companies', [companyJson])
      ..on('GET /dashboard', {'date': '2026-11-05', 'currency': 'Bs', 'sections': <String, bool>{}})
      ..on('GET /services', {'services': [], 'categories': [], 'can': {'create': true, 'edit': true, 'create_category': true}});
    final store = MemorySessionStore()..values.addAll({'token': 't', 'company_id': '2'});
    final session = Session(fake.client(), store);
    await tester.pumpWidget(GlamoraApp(session: session));
    await session.restore();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text('Servicios')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuevo'));
    await tester.pumpAndSettle();

    final field = find.widgetWithText(TextField, 'Descripción (opcional)');
    await tester.tap(field);
    await tester.pump();
    // El teclado aparece.
    tester.view.viewInsets = const FakeViewPadding(bottom: 800);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'Comentario de prueba');
    await tester.pump();
    // «Listo» del teclado: se cierra y la pantalla se rearma.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Comentario de prueba'), findsOneWidget);
    tester.view.reset();
  });
}
