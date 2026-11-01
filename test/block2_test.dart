import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glamora_movil/main.dart';
import 'package:glamora_movil/session.dart';
import 'package:glamora_movil/util/contact.dart';
import 'package:glamora_movil/util/format.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_api.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  group('Contacto', () {
    test('número local recibe el código de país; el link de WhatsApp lleva el mensaje', () {
      expect(normalizePhone('7000-0000'), '59170000000');
      expect(normalizePhone('+54 9 11 5555 4444'), '5491155554444');
      final uri = whatsappUri('70000000', 'Hola María');
      expect(uri.toString(), 'https://wa.me/59170000000?text=Hola+Mar%C3%ADa');
      expect(callUri('+591 7000 0000').toString(), 'tel:+59170000000');
    });
  });

  final today = DateTime.now();

  FakeApi server() => FakeApi()
    ..on('GET /me', meJson(abilities: {
      'agenda_own': true, 'agenda_all': false, 'appointments_create': true, 'appointments_edit': false,
      'clients_view': true, 'clients_create': true, 'attendance': true, 'commissions_own': true,
    }))
    ..on('GET /auth/companies', [companyJson])
    ..on('GET /agenda', {'appointments': [appointmentJson(start: '${ymd(today)}T10:00:00-04:00')]})
    ..on('GET /agenda/options', {'services': [], 'specialists': [{'id': 14, 'name': 'ANA PÉREZ'}], 'statuses': [{'key': 'pendiente', 'label': 'Pendiente', 'color': '#f59e0b'}]})
    ..on('GET /agenda/availability', {'configured': true, 'off': null, 'special': false, 'blocks': [{'start': '09:00', 'end': '18:00'}], 'busy': []})
    ..on('GET /clients', [{'id': 7, 'name': 'MARÍA LÓPEZ', 'phone': '70000001', 'document': null, 'email': null}])
    ..on('GET /clients/7', {
      'client': {'id': 7, 'name': 'MARÍA LÓPEZ', 'phone': '70000001', 'document': '123456', 'email': null},
      'currency': 'Bs',
      'stats': {'visits': 4, 'last_visit': '2026-10-20 10:00:00', 'purchases': 3, 'spent': 450.5},
      'appointments': [{'id': 1, 'starts_at': '2026-10-20T10:00:00-04:00', 'status_label': 'Completada', 'status_color': '#10b981', 'service': 'CORTE', 'personal': 'ANA'}],
      'sales': [{'id': 9, 'number': 'V-000009', 'date': '2026-10-20T10:30:00-04:00', 'total': 150, 'status': 'completada'}],
      'membership': {'plan': 'MENSUAL', 'ends_on': '30/11/2026', 'discount': 10, 'sessions': [{'service': 'MANICURA', 'remaining': 3, 'included': 4}]},
      'packages': [{'name': '10 DEPILACIONES', 'expiry': 'Vence 01/04/2027', 'items': [{'service': 'DEPILACIÓN', 'remaining': 7, 'included': 10}]}],
      'points': {'balance': 250, 'value': 25},
      'credit': 40,
      'account': {'enabled': true, 'limit': 300, 'debt': 120, 'available': 180, 'overdue': true},
    });

  Future<void> start(WidgetTester tester, FakeApi fake) async {
    final store = MemorySessionStore()..values.addAll({'token': 't', 'company_id': '2'});
    final session = Session(fake.client(), store);
    await tester.pumpWidget(GlamoraApp(session: session));
    await session.restore();
    await tester.pumpAndSettle();
  }

  testWidgets('el detalle de la cita ofrece llamar, WhatsApp, reprogramar y ver ficha', (tester) async {
    await start(tester, server());
    await tester.tap(find.text('MARÍA LÓPEZ'));
    await tester.pumpAndSettle();
    expect(find.text('Llamar'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('Reprogramar'), findsOneWidget);
    expect(find.text('Ver ficha'), findsOneWidget);
  });

  testWidgets('reprogramar fuera de horario: confirma y reenvía forzado', (tester) async {
    var calls = 0;
    final fake = server();
    fake.routes['POST /appointments/12/reschedule'] = (request) {
      calls++;
      if (calls == 1) {
        return FakeApi.json({'message': 'x', 'errors': {'outside_schedule': ['La cita queda fuera del horario de ANA: no trabaja ese día. Si igual quieres agendarla, marca «Agendar de todos modos».']}}, status: 422);
      }
      return FakeApi.json(appointmentJson(start: '${ymd(today)}T16:00:00-04:00'));
    };
    await start(tester, fake);

    await tester.tap(find.text('MARÍA LÓPEZ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reprogramar'));
    await tester.pumpAndSettle();
    expect(find.text('Reprogramar cita'), findsOneWidget);
    // Sin permiso de edición no se puede cambiar de profesional.
    expect(find.text('Profesional'), findsNothing);
    expect(fake.last('GET /agenda/availability').url.queryParameters['ignore'], '12');

    await tester.tap(find.textContaining('Mover a'));
    await tester.pumpAndSettle();
    expect(find.text('Fuera de horario'), findsOneWidget);
    await tester.tap(find.text('Reprogramar de todos modos'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    final sent = fake.body('POST /appointments/12/reschedule');
    expect(sent['force_outside'], isTrue);
    expect(sent['duration_minutes'], 45);
    expect(sent.containsKey('personal_id'), isFalse);
    expect(find.textContaining('Cita reprogramada'), findsOneWidget);
  });

  testWidgets('vista semanal: pide 7 días desde el lunes y tocar un día abre ese día', (tester) async {
    final fake = server();
    await start(tester, fake);

    await tester.tap(find.byTooltip('Ver la semana'));
    await tester.pumpAndSettle();
    final q = fake.last('GET /agenda').url.queryParameters;
    final monday = dateOnly(today).subtract(Duration(days: today.weekday - 1));
    expect(q['days'], '7');
    expect(q['date'], ymd(monday));
    expect(find.byKey(const ValueKey('week-day-0')), findsOneWidget);
    expect(find.text('Esta semana'), findsOneWidget);
    // La cita es de hoy: según el día de la semana puede quedar abajo de la pantalla.
    await tester.scrollUntilVisible(find.text('MARÍA LÓPEZ'), 150, scrollable: find.byType(Scrollable).first);
    expect(find.text('MARÍA LÓPEZ'), findsOneWidget);

    await tester.ensureVisible(find.byKey(ValueKey('week-day-${today.weekday - 1}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('week-day-${today.weekday - 1}')));
    await tester.pumpAndSettle();
    expect(fake.last('GET /agenda').url.queryParameters.containsKey('days'), isFalse);
    expect(find.text('Hoy'), findsWidgets);
  });

  testWidgets('ficha del cliente desde Clientes: deuda, beneficios e historial', (tester) async {
    await start(tester, server());
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Clientes')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MARÍA LÓPEZ').last);
    await tester.pumpAndSettle();

    expect(find.text('Ficha del cliente'), findsOneWidget);
    expect(find.text('Debe Bs 120.00'), findsOneWidget);
    expect(find.text('Tiene cuentas vencidas'), findsOneWidget);
    expect(find.text('Membresía MENSUAL'), findsOneWidget);
    expect(find.text('Paquete 10 DEPILACIONES'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Saldo a favor Bs 40.00'), 200);
    expect(find.text('250 puntos'), findsOneWidget);
    expect(find.text('Saldo a favor Bs 40.00'), findsOneWidget);
    expect(find.text('Bs 450.50'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('V-000009'), 200);
    expect(find.text('V-000009'), findsOneWidget);
  });
}
