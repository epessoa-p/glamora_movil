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

  final opened = <Uri>[];
  setUp(() {
    opened.clear();
    urlOpener = (uri) async {
      opened.add(uri);
      return true;
    };
  });

  final tomorrow = dateOnly(DateTime.now()).add(const Duration(days: 1));
  final monday = dateOnly(DateTime.now()).subtract(Duration(days: DateTime.now().weekday - 1));

  FakeApi server() => FakeApi()
    ..on('GET /me', meJson(abilities: {
      'agenda_own': true, 'appointments_create': true, 'appointments_edit': true, 'clients_view': true, 'clients_create': true,
      'clients_edit': true, 'reminders': true, 'birthdays': true, 'schedule': true, 'attendance': true, 'commissions_own': true,
    }))
    ..on('GET /auth/companies', [companyJson])
    ..on('GET /agenda', {'appointments': []})
    ..on('GET /agenda/options', {'services': [], 'specialists': [], 'statuses': []})
    ..on('GET /reminders', {
      'date': ymd(tomorrow),
      'templates': [{'id': 3, 'name': 'Recordatorio', 'is_default': true}],
      'appointments': [appointmentJson(start: '${ymd(tomorrow)}T09:00:00-04:00') ..addAll({'reminded_at': null, 'reminded_by': null})],
    })
    ..on('POST /messages/whatsapp', {'text': 'Hola María', 'url': 'https://wa.me/59170000001?text=Hola%20Mar%C3%ADa'})
    ..on('POST /appointments/12/status', appointmentJson(status: 'confirmada', start: '${ymd(tomorrow)}T09:00:00-04:00'))
    ..on('GET /clients', [{'id': 7, 'name': 'MARÍA LÓPEZ', 'phone': '70000001', 'document': null, 'email': null}])
    ..on('GET /birthdays', {
      'range': 'today', 'templates': [{'id': 4, 'name': 'Cumple', 'is_default': true}],
      'coupons': [{'id': 9, 'code': 'CUMPLE15', 'value': '15 %'}],
      'clients': [{'id': 7, 'name': 'MARÍA LÓPEZ', 'phone': '70000001', 'birthday': ymd(DateTime.now()), 'age': 30, 'is_today': true, 'greeted_at': null}],
    })
    ..on('GET /schedule', {
      'from': ymd(monday), 'to': ymd(monday.add(const Duration(days: 6))), 'configured': true,
      'days': [
        for (var i = 0; i < 7; i++)
          {
            'date': ymd(monday.add(Duration(days: i))),
            'off': i == 2 ? 'Vacaciones' : null,
            'special': false,
            'blocks': i == 0 ? [{'start': '09:00', 'end': '13:00'}, {'start': '14:00', 'end': '18:00'}] : [],
            'minutes': i == 0 ? 480 : 0,
          },
      ],
    })
    ..on('GET /attendance', {'open': null, 'today': null, 'totals': {'worked_days': 0, 'minutes': 0, 'late_days': 0, 'late_min': 0, 'absences': 0, 'hours_label': '0 min'}, 'days': []})
    ..on('GET /clients/7', {
      'client': {'id': 7, 'name': 'MARÍA LÓPEZ', 'phone': '70000001', 'document': null, 'email': null, 'birthdate': '1996-05-10', 'notes': 'Alergia al látex'},
      'currency': 'Bs', 'stats': {'visits': 0, 'last_visit': null, 'purchases': null, 'spent': null},
      'appointments': [], 'sales': null, 'membership': null, 'packages': [], 'points': null, 'credit': null, 'account': null,
    })
    ..on('PUT /clients/7', {'id': 7, 'name': 'MARÍA LÓPEZ', 'phone': '72222222'});

  Future<FakeApi> start(WidgetTester tester) async {
    final fake = server();
    final store = MemorySessionStore()..values.addAll({'token': 't', 'company_id': '2'});
    final session = Session(fake.client(), store);
    await tester.pumpWidget(GlamoraApp(session: session));
    await session.restore();
    await tester.pumpAndSettle();
    return fake;
  }

  Future<void> tab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
    await tester.pumpAndSettle();
  }

  testWidgets('recordatorios: avisar por WhatsApp y marcar «Confirmó»', (tester) async {
    final fake = await start(tester);
    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text('Recordatorios')));
    await tester.pumpAndSettle();

    expect(fake.last('GET /reminders').url.queryParameters['date'], ymd(tomorrow));
    expect(find.text('Sin avisar'), findsWidgets);
    await tester.tap(find.text('Avisar'));
    await tester.pumpAndSettle();
    expect(fake.body('POST /messages/whatsapp'), {'client_id': 7, 'type': 'reminder', 'appointment_id': 12, 'template_id': 3});
    expect(opened.single.host, 'wa.me');
    expect(find.textContaining('Avisada'), findsOneWidget);
    expect(find.text('Reenviar'), findsOneWidget);

    await tester.tap(find.text('Confirmó'));
    await tester.pumpAndSettle();
    expect(fake.body('POST /appointments/12/status'), {'status': 'confirmada'});
    expect(find.text('Confirmó'), findsNothing);
  });

  testWidgets('cumpleaños: saludar con cupón de regalo', (tester) async {
    final fake = await start(tester);
    await tab(tester, 'Clientes');
    await tester.tap(find.byTooltip('Cumpleaños'));
    await tester.pumpAndSettle();

    expect(find.textContaining('¡Hoy!'), findsOneWidget);
    await tester.tap(find.text('Sin cupón'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CUMPLE15 · 15 %').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saludar'));
    await tester.pumpAndSettle();
    expect(fake.body('POST /messages/whatsapp'), {'client_id': 7, 'type': 'birthday', 'template_id': 4, 'coupon_id': 9});
    expect(find.textContaining('Ya saludado'), findsOneWidget);
  });

  testWidgets('mi horario: turnos de la semana, libre y total', (tester) async {
    await start(tester);
    await tab(tester, 'Asistencia');
    await tester.tap(find.text('Mi horario'));
    await tester.pumpAndSettle();

    expect(find.text('09:00–13:00  ·  14:00–18:00'), findsOneWidget);
    expect(find.text('Libre · Vacaciones'), findsOneWidget);
    expect(find.text('8 h en la semana'), findsOneWidget);
  });

  testWidgets('editar cliente desde su ficha', (tester) async {
    final fake = await start(tester);
    await tab(tester, 'Clientes');
    await tester.tap(find.text('MARÍA LÓPEZ').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Editar'));
    await tester.pumpAndSettle();

    expect(find.text('Alergia al látex'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Teléfono'), '72222222');
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    final sent = fake.body('PUT /clients/7');
    expect(sent['phone'], '72222222');
    expect(sent['birthdate'], '1996-05-10');
    expect(sent['notes'], 'Alergia al látex');
    expect(find.text('Cliente actualizado.'), findsOneWidget);
  });
}
