import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glamora_movil/main.dart';
import 'package:glamora_movil/session.dart';
import 'package:glamora_movil/util/format.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_api.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  final today = ymd(DateTime.now());

  FakeApi serverFor({Map<String, bool>? abilities}) => FakeApi()
    ..on('POST /auth/login', {'token': 't', 'companies': [companyJson]})
    ..on('GET /me', meJson(abilities: abilities))
    ..on('GET /auth/companies', [companyJson])
    ..on('GET /agenda', {
      'from': today,
      'to': today,
      'appointments': [appointmentJson()],
    })
    ..on('GET /agenda/options', {
      'services': [
        {'id': 21, 'name': 'CORTE', 'price': 100, 'duration': 45},
      ],
      'specialists': [
        {'id': 14, 'name': 'ANA PÉREZ'},
      ],
      'statuses': [
        {'key': 'pendiente', 'label': 'Pendiente', 'color': '#f59e0b'},
        {'key': 'confirmada', 'label': 'Confirmada', 'color': '#3b82f6'},
      ],
    })
    ..on('GET /agenda/availability', {
      'configured': true,
      'off': null,
      'special': false,
      'blocks': [
        {'start': '09:00', 'end': '19:00'},
      ],
      'busy': [],
    })
    ..on('GET /attendance', {
      'open': null,
      'today': null,
      'totals': {'worked_days': 3, 'minutes': 600, 'late_days': 1, 'late_min': 10, 'absences': 0, 'hours_label': '10 h'},
      'days': [],
    })
    ..on('GET /commissions', {
      'currency': 'Bs',
      'kpis': {'earned': 250, 'pending': 150, 'settled': 100, 'tips': 0},
      'items': [],
    })
    ..on('GET /clients', [
      {'id': 7, 'name': 'MARÍA LÓPEZ', 'phone': '70000001', 'document': null, 'email': null},
    ]);

  Future<Session> start(WidgetTester tester, FakeApi fake, {bool loggedIn = true}) async {
    final store = MemorySessionStore();
    if (loggedIn) store.values.addAll({'token': 't', 'company_id': '2'});
    final session = Session(fake.client(), store);
    await tester.pumpWidget(GlamoraApp(session: session));
    await session.restore();
    await tester.pumpAndSettle();
    return session;
  }

  testWidgets('login: valida campos y muestra el error del servidor', (tester) async {
    final fake = serverFor()..on('POST /auth/login', {'code': 'invalid_credentials', 'message': 'Usuario o contraseña incorrectos.'}, status: 422);
    await start(tester, fake, loggedIn: false);

    await tester.tap(find.text('Ingresar'));
    await tester.pump();
    expect(find.text('Escribe tu correo o usuario.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Correo o usuario'), 'ana');
    await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'mala');
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();

    expect(find.text('Usuario o contraseña incorrectos.'), findsOneWidget);
  });

  testWidgets('login correcto abre la agenda con las pestañas permitidas', (tester) async {
    final fake = serverFor();
    await start(tester, fake, loggedIn: false);

    await tester.enterText(find.widgetWithText(TextFormField, 'Correo o usuario'), 'ana');
    await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'Secreta123');
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();

    expect(find.text('MARÍA LÓPEZ'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
    for (final tab in ['Agenda', 'Asistencia', 'Comisiones', 'Clientes', 'Perfil']) {
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)), findsOneWidget);
    }
    // Sin agenda_all no ve el selector de equipo; la agenda pide solo lo suyo.
    expect(find.text('Todo el equipo'), findsNothing);
    expect(fake.last('GET /agenda').url.queryParameters['personal_id'], '14');
  });

  testWidgets('sin ficha ni permisos solo queda Perfil con la explicación', (tester) async {
    final fake = serverFor()..on('GET /me', meJson(abilities: {}, personal: false));
    await start(tester, fake);

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Sin ficha de personal'), findsOneWidget);
  });

  testWidgets('cambiar el estado de una cita propia', (tester) async {
    final fake = serverFor()..on('POST /appointments/12/status', appointmentJson(status: 'confirmada'));
    await start(tester, fake);

    await tester.tap(find.text('MARÍA LÓPEZ'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Confirmada'));
    await tester.pumpAndSettle();

    expect(fake.body('POST /appointments/12/status'), {'status': 'confirmada'});
    expect(find.text('Estado actualizado: Confirmada.'), findsOneWidget);
  });

  testWidgets('nueva cita fuera de horario: confirma y reenvía forzada', (tester) async {
    var calls = 0;
    final fake = serverFor();
    fake.routes['POST /appointments'] = (request) {
      calls++;
      if (calls == 1) {
        return FakeApi.json({
          'message': 'x',
          'errors': {
            'outside_schedule': ['La cita queda fuera del horario de ANA: no trabaja ese día. Si igual quieres agendarla, marca «Agendar de todos modos».'],
          },
        }, status: 422);
      }
      return FakeApi.json(appointmentJson(id: 99), status: 201);
    };
    await start(tester, fake);

    await tester.tap(find.text('Nueva cita'));
    await tester.pumpAndSettle();

    // Sin cliente no envía.
    await tester.tap(find.textContaining('Agendar '));
    await tester.pumpAndSettle();
    expect(find.text('Elige el cliente.'), findsOneWidget);
    expect(calls, 0);

    await tester.tap(find.text('Elegir cliente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MARÍA LÓPEZ'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Agendar '));
    await tester.pumpAndSettle();
    expect(find.text('Fuera de horario'), findsOneWidget);
    expect(find.textContaining('no trabaja ese día'), findsOneWidget);

    await tester.tap(find.text('Agendar de todos modos'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    final sent = fake.body('POST /appointments');
    expect(sent['force_outside'], isTrue);
    expect(sent['client_id'], 7);
    expect(sent['personal_id'], 14);
    expect(sent['starts_at'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:00$')));
    expect(find.textContaining('Cita agendada'), findsOneWidget);
  });

  testWidgets('asistencia y comisiones muestran sus cifras', (tester) async {
    final fake = serverFor()..on('POST /attendance', {'action': 'in', 'message': 'Entrada registrada a las 09:00.'});
    await start(tester, fake);

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Asistencia')));
    await tester.pumpAndSettle();
    expect(find.text('10 h'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Marcar entrada'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, 'Marcar entrada')));
    await tester.pumpAndSettle();
    expect(fake.body('POST /attendance'), {'action': 'in'});
    expect(find.text('Entrada registrada a las 09:00.'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Comisiones')));
    await tester.pumpAndSettle();
    expect(find.text('Bs 250.00'), findsOneWidget);
    expect(find.text('Bs 150.00'), findsOneWidget);
  });
}
