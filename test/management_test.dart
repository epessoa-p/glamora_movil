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

  FakeApi server() => FakeApi()
    ..on('GET /me', meJson(abilities: {
      'agenda_own': true, 'agenda_all': true, 'appointments_create': true, 'clients_view': true, 'attendance': true,
      'commissions_own': true, 'dashboard': true, 'receivables': true, 'receivables_collect': true, 'birthdays': true,
    }))
    ..on('GET /auth/companies', [companyJson])
    ..on('GET /agenda', {'appointments': []})
    ..on('GET /agenda/options', {'services': [], 'specialists': [], 'statuses': []})
    ..on('GET /attendance', {'open': null, 'today': null, 'totals': {'worked_days': 0, 'minutes': 0, 'late_days': 0, 'late_min': 0, 'absences': 0, 'hours_label': '0 min'}, 'days': []})
    ..on('GET /clients', [])
    // Misma forma que la respuesta real de /api/v1/dashboard.
    ..on('GET /dashboard', {
      'date': today, 'currency': 'Bs',
      'sections': {'sales': true, 'agenda': true, 'cash': true, 'team': true, 'receivables': true, 'clients': true, 'stock': true},
      'sales': {'today': 450.5, 'today_count': 3, 'tips_today': 20, 'month': 9800,
        'by_method': [{'method': 'Efectivo', 'amount': 300, 'count': 2}, {'method': 'QR', 'amount': 150.5, 'count': 1}],
        'last': [{'number': 'V-000010', 'client': 'MARÍA', 'total': 150.5, 'at': '${today}T10:00:00-04:00'}]},
      'agenda': {'total': 6, 'pending': 4, 'completed': 2, 'canceled': 0, 'next': [appointmentJson(start: '${today}T16:00:00-04:00')]},
      'cash': [{'id': 1, 'name': 'CAJA PRINCIPAL', 'opened_at': '${today}T08:00:00-04:00', 'expected': 520}],
      'team': {'working': 2, 'late': 1, 'absent': 0, 'people': [
        {'name': 'ANA PÉREZ', 'state': 'working', 'label': 'En turno', 'check_in': '08:55'},
        {'name': 'LUIS GÓMEZ', 'state': 'late', 'label': 'Tarde 15 min', 'check_in': '09:15'},
      ]},
      'receivables': {'balance': 300, 'overdue': 120, 'collected_today': 50},
      'clients': {'new_month': 5, 'birthdays_today': 1},
      'stock_low': 2,
    })
    ..on('GET /receivables', {
      'currency': 'Bs', 'total': 300, 'overdue': 120,
      'clients': [{'client': {'id': 7, 'name': 'MARÍA LÓPEZ', 'phone': '70000001', 'document': null, 'email': null}, 'debt': 300, 'accounts': 2, 'oldest_due': '2026-10-20', 'overdue': true}],
    })
    ..on('GET /receivables/7', {
      'client': {'id': 7, 'name': 'MARÍA LÓPEZ', 'phone': '70000001', 'document': null, 'email': null},
      'currency': 'Bs',
      'summary': {'enabled': true, 'limit': 500, 'debt': 300, 'available': 200, 'overdue': true},
      'accounts': [
        {'id': 1, 'sale': 'V-000001', 'amount': 120, 'balance': 120, 'due_date': '2026-10-20', 'overdue': true},
        {'id': 2, 'sale': 'V-000002', 'amount': 180, 'balance': 180, 'due_date': '2026-11-20', 'overdue': false},
      ],
      'receipts': [],
      'payment_methods': [{'code': 'efectivo', 'name': 'Efectivo'}, {'code': 'qr', 'name': 'QR'}],
      'cash_sessions': [{'id': 1, 'name': 'CAJA PRINCIPAL'}],
      'require_cash': false,
    })
    ..on('POST /receivables/7/collect', {'receipt': 'REC-000001', 'amount': 300, 'debt': 0, 'message': 'Cobro registrado: recibo REC-000001.'}, status: 201);

  Future<FakeApi> start(WidgetTester tester) async {
    final fake = server();
    final store = MemorySessionStore()..values.addAll({'token': 't', 'company_id': '2'});
    final session = Session(fake.client(), store);
    await tester.pumpWidget(GlamoraApp(session: session));
    await session.restore();
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('menú lateral: secciones, extras y cierre de sesión', (tester) async {
    await start(tester);
    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle();

    final drawer = find.byType(Drawer);
    for (final item in ['Panel', 'Agenda', 'Asistencia', 'Clientes', 'Mis comisiones', 'Cuentas por cobrar', 'Cumpleaños', 'Cerrar sesión']) {
      await tester.scrollUntilVisible(find.descendant(of: drawer, matching: find.text(item)), 80, scrollable: find.descendant(of: drawer, matching: find.byType(Scrollable)));
      expect(find.descendant(of: drawer, matching: find.text(item)), findsOneWidget, reason: item);
    }
    expect(find.descendant(of: drawer, matching: find.text('Mi perfil')), findsNothing, reason: 'el perfil se abre desde el avatar de arriba');
    await tester.scrollUntilVisible(find.descendant(of: drawer, matching: find.text('Agenda')), -80, scrollable: find.descendant(of: drawer, matching: find.byType(Scrollable)));

    // Una pestaña cambia la vista del inicio y cierra el menú.
    await tester.tap(find.descendant(of: drawer, matching: find.text('Agenda')));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    expect(find.widgetWithText(AppBar, 'Agenda'), findsOneWidget);

    // Un extra se abre encima, con flecha de volver.
    await tester.tap(find.byTooltip('Menú').first);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text('Cuentas por cobrar')));
    await tester.pumpAndSettle();
    expect(find.text('Por cobrar Bs 300.00'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('gerencia: el Panel es la primera pestaña y el perfil se abre arriba a la derecha', (tester) async {
    await start(tester);
    final nav = find.byType(NavigationBar);
    expect(find.descendant(of: nav, matching: find.text('Panel')), findsOneWidget);
    expect(find.descendant(of: nav, matching: find.text('Comisiones')), findsNothing);
    expect(find.descendant(of: nav, matching: find.text('Perfil')), findsNothing);

    expect(find.text('Bs 450.50'), findsOneWidget);
    expect(find.textContaining('3 venta(s)'), findsOneWidget);
    expect(find.text('Efectivo: Bs 300.00'), findsOneWidget);
    expect(find.text('Citas de hoy'), findsOneWidget);
    expect(find.text('CAJA PRINCIPAL · desde 08:00'), findsOneWidget);
    await tester.dragUntilVisible(find.text('Tarde 15 min'), find.byType(ListView).first, const Offset(0, -200));
    expect(find.text('Tarde 15 min'), findsOneWidget);

    await tester.tap(find.byTooltip('Perfil'));
    await tester.pumpAndSettle();
    expect(find.text('Mis comisiones'), findsOneWidget);
    expect(find.text('Cuentas por cobrar'), findsOneWidget);
  });

  testWidgets('cuentas por cobrar: del panel a la cartera y cobro con recibo', (tester) async {
    final fake = await start(tester);
    await tester.dragUntilVisible(find.text('Cuentas por cobrar'), find.byType(ListView).first, const Offset(0, -200));
    await tester.tap(find.text('Cuentas por cobrar'));
    await tester.pumpAndSettle();

    expect(find.text('Por cobrar Bs 300.00'), findsOneWidget);
    expect(find.textContaining('vencida desde'), findsOneWidget);
    await tester.tap(find.text('MARÍA LÓPEZ'));
    await tester.pumpAndSettle();

    expect(find.text('Debe Bs 300.00'), findsOneWidget);
    expect(find.text('Venta V-000001'), findsOneWidget);
    await tester.dragUntilVisible(find.text('Cobrar y emitir recibo'), find.byType(ListView).last, const Offset(0, -200));
    await tester.tap(find.text('Cobrar y emitir recibo'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cobrar'));
    await tester.pumpAndSettle();

    final sent = fake.body('POST /receivables/7/collect');
    expect(sent['amount'], 300);
    expect(sent['payment_method'], 'efectivo');
    expect(sent['cash_session_id'], 1);
    expect(find.textContaining('recibo REC-000001'), findsOneWidget);
  });
}
