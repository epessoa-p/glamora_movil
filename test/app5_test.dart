import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glamora_movil/main.dart';
import 'package:glamora_movil/screens/login_screen.dart';
import 'package:glamora_movil/session.dart';
import 'package:glamora_movil/util/format.dart';
import 'package:glamora_movil/widgets/common.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_api.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  final today = ymd(DateTime.now());
  const abilities = {
    'agenda_own': true, 'agenda_all': true, 'clients_view': true, 'attendance': true, 'dashboard': true,
    'cash_view': true, 'cash_open': true, 'cash_move': true, 'cash_close': true,
    'services_view': true, 'services_create': true, 'services_edit': true, 'reports': true,
  };

  Map<String, dynamic> report(String type) => {
        'available': [{'key': 'ventas', 'label': 'Ventas'}, {'key': 'caja', 'label': 'Caja'}, {'key': 'ganancias', 'label': 'Ganancias'}],
        'type': type, 'from': '2026-11-01', 'to': '2026-11-01', 'currency': 'Bs',
        'report': type == 'ganancias'
            ? {'kpis': [{'label': 'Ganancia neta', 'value': '13,800.00', 'color': '#10b981'}], 'tables': [
                {'title': 'Estado de resultados', 'head': ['Concepto', 'Monto'], 'rows': [['Ventas netas', '15,430.00'], ['Ganancia neta', '13,800.00']]},
              ], 'note': 'El costo de productos usa el costo actual.'}
            : type == 'caja'
            ? {'kpis': [{'label': 'Ingresos', 'value': '500.00', 'color': '#10b981'}], 'tables': [
                {'title': 'Arqueos cerrados', 'head': ['Caja', 'Cierre', 'Esperado', 'Contado', 'Diferencia'], 'rows': [['CAJA PRINCIPAL', '01/11/2026 19:20', '1,160.00', '1,160.00', '0.00']]},
              ]}
            : {'kpis': [
                {'label': 'Total vendido', 'value': '1,470.00', 'color': '#14b8a6'},
                {'label': 'N. de ventas', 'value': 9, 'color': '#6366f1'},
              ], 'tables': [
                {'title': 'Por metodo de pago', 'head': ['Metodo', 'Ventas', 'Total'], 'rows': [['Efectivo', 4, '575.00'], ['Qr', 2, '350.00']]},
                {'title': 'Por dia', 'head': ['Dia', 'Ventas', 'Total'], 'rows': []},
              ]},
      };

  FakeApi server() {
    final fake = FakeApi()
      ..on('GET /me', meJson(abilities: abilities))
      ..on('GET /auth/companies', [companyJson])
      ..on('POST /auth/logout', {'message': 'ok'})
      ..on('GET /agenda', {'appointments': []})
      ..on('GET /agenda/options', {'services': [], 'specialists': [], 'statuses': []})
      ..on('GET /attendance', {'open': null, 'today': null, 'totals': {'worked_days': 0, 'minutes': 0, 'late_days': 0, 'late_min': 0, 'absences': 0, 'hours_label': '0 min'}, 'days': []})
      ..on('GET /clients', [])
      ..on('GET /dashboard', {
        'date': today, 'currency': 'Bs',
        'sections': {'sales': true, 'cash': true},
        'sales': {'today': 1470, 'today_count': 9, 'tips_today': 40, 'month': 1470,
          'by_method': [{'method': 'Efectivo', 'amount': 575, 'count': 4}, {'method': 'QR', 'amount': 350, 'count': 2}], 'last': []},
        'cash': [{'id': 1, 'name': 'CAJA PRINCIPAL', 'opened_at': '${today}T08:50:00-04:00', 'expected': 1660}],
      })
      ..on('GET /cash', {'currency': 'Bs', 'registers': [{'id': 1, 'name': 'CAJA PRINCIPAL', 'session': null}], 'can': {'open': true, 'move': true, 'close': true}})
      ..on('GET /services', {
        'services': [
          {'id': 5, 'name': 'CORTE DAMA', 'price': 80, 'duration': 45, 'description': null, 'active': true, 'category': {'id': 2, 'name': 'CABELLO'}},
          {'id': 6, 'name': 'KERATINA', 'price': 300, 'duration': 120, 'description': null, 'active': false, 'category': null},
        ],
        'categories': [{'id': 2, 'name': 'CABELLO'}],
        'can': {'create': true, 'edit': true, 'create_category': true},
      })
      ..on('POST /services', {'message': 'Servicio creado.', 'service': {}}, status: 201)
      ..on('PUT /services/5', {'message': 'Servicio actualizado.', 'service': {}})
      ..on('POST /service-categories', {'id': 9, 'name': 'UÑAS'}, status: 201);
    fake.routes['GET /reports'] = (req) => req.url.queryParameters['meta'] == '1'
        ? FakeApi.json({'available': report('ventas')['available']})
        : FakeApi.json(report(req.url.queryParameters['type'] ?? 'ventas'));
    return fake;
  }

  Future<FakeApi> start(WidgetTester tester) async {
    final fake = server();
    final store = MemorySessionStore()..values.addAll({'token': 't', 'company_id': '2'});
    final session = Session(fake.client(), store);
    await tester.pumpWidget(GlamoraApp(session: session));
    await session.restore();
    await tester.pumpAndSettle();
    return fake;
  }

  Future<void> openFromMenu(WidgetTester tester, String item) async {
    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle();
    final drawer = find.byType(Drawer);
    await tester.scrollUntilVisible(find.descendant(of: drawer, matching: find.text(item)), 80, scrollable: find.descendant(of: drawer, matching: find.byType(Scrollable)));
    await tester.tap(find.descendant(of: drawer, matching: find.text(item)));
    await tester.pumpAndSettle();
  }

  testWidgets('cerrar sesión desde el perfil abierto encima: vuelve al login sin error', (tester) async {
    await start(tester);
    await tester.tap(find.byTooltip('Perfil'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Cerrar sesión'), 120, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Salir'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('panel: formas de pago legibles y acceso rápido a la caja', (tester) async {
    await start(tester);
    expect(find.text('Efectivo: Bs 575.00'), findsOneWidget);
    expect(find.byType(Chip), findsNothing, reason: 'las etiquetas ya no son Chip (salían blanco sobre blanco)');

    await tester.tap(find.byTooltip('Caja cerrada'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Caja'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('CAJA PRINCIPAL · desde 08:50'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Caja'), findsOneWidget);
  });

  testWidgets('servicios: listar, crear con categoría nueva y editar', (tester) async {
    final fake = await start(tester);
    await openFromMenu(tester, 'Servicios');
    expect(find.text('CORTE DAMA'), findsOneWidget);
    expect(find.textContaining('Inactivo'), findsOneWidget);

    await tester.tap(find.text('Nuevo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nombre'), 'Manicure');
    await tester.enterText(find.widgetWithText(TextField, 'Precio'), '60');
    await tester.tap(find.text('45 min'));
    await tester.tap(find.byTooltip('Nueva categoría'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'uñas');
    await tester.tap(find.widgetWithText(FilledButton, 'Crear'));
    await tester.pumpAndSettle();
    expect(find.text('UÑAS'), findsOneWidget);
    await tester.tap(find.text('Crear servicio'));
    await tester.pumpAndSettle();

    final sent = fake.body('POST /services');
    expect(sent['name'], 'Manicure');
    expect(sent['price'], 60);
    expect(sent['duration_minutes'], 45);
    expect(sent['service_category_id'], 9);
    expect(find.text('Servicios'), findsWidgets, reason: 'vuelve al listado');

    await tester.tap(find.text('CORTE DAMA'));
    await tester.pumpAndSettle();
    expect(find.text('Editar servicio'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Precio'), '95');
    await tester.tap(find.text('Activo'));
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    final put = jsonDecode(fake.last('PUT /services/5').body) as Map<String, dynamic>;
    expect(put['price'], 95);
    expect(put['active'], isFalse);
  });

  testWidgets('reportes: indicadores, tablas, cambio de tipo y período', (tester) async {
    final fake = await start(tester);
    await openFromMenu(tester, 'Reportes');
    expect(find.text('Análisis'), findsNothing, reason: 'sin acceso a análisis no se muestra su tarjeta');
    await tester.tap(find.text('Resumen por área'));
    await tester.pumpAndSettle();
    expect(find.text('1,470.00'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Ganancias'), findsNothing, reason: 'Ganancias tiene su propia tarjeta');
    expect(find.text('Por metodo de pago'), findsOneWidget);
    expect(find.text('Efectivo'), findsOneWidget);
    expect(find.text('Sin datos en el período.'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Caja'));
    await tester.pumpAndSettle();
    expect(fake.last('GET /reports').url.queryParameters['type'], 'caja');
    expect(find.text('Arqueos cerrados'), findsOneWidget);
    expect(find.text('1,160.00'), findsWidgets);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Hoy'));
    await tester.pumpAndSettle();
    final q = fake.last('GET /reports').url.queryParameters;
    expect(q['from'], today);
    expect(q['to'], today);
    expect(q['type'], 'caja', reason: 'mantiene el tipo elegido');
  });

  testWidgets('caja abierta: distintivo verde y el botón va directo al turno', (tester) async {
    final fake = server()
      ..on('GET /cash', {'currency': 'Bs', 'registers': [{'id': 1, 'name': 'CAJA PRINCIPAL', 'session': {'id': 5, 'status': 'open', 'opened_at': '${today}T08:50:00-04:00', 'opening': 200, 'expected': 1660}}], 'can': {'open': true, 'move': true, 'close': true}})
      ..on('GET /cash/5', {'id': 5, 'status': 'open', 'opened_at': '${today}T08:50:00-04:00', 'opening': 200, 'expected': 1660, 'register': 'CAJA PRINCIPAL',
        'closed_at': null, 'counted': null, 'difference': null, 'income': 1460, 'expense': 0, 'sales_count': 9, 'by_method': [], 'movements': []});
    final store = MemorySessionStore()..values.addAll({'token': 't', 'company_id': '2'});
    final session = Session(fake.client(), store);
    await tester.pumpWidget(GlamoraApp(session: session));
    await session.restore();
    await tester.pumpAndSettle();

    expect(find.byTooltip('Caja abierta'), findsOneWidget);
    await tester.tap(find.byTooltip('Caja abierta'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'CAJA PRINCIPAL'), findsOneWidget, reason: 'abre el turno, no el listado');
    expect(find.text('Bs 1,660.00'), findsOneWidget);
  });

  testWidgets('menú lateral: logo del salón (o sus iniciales) con el nombre al costado', (tester) async {
    await start(tester);
    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle();
    final logo = find.byType(CompanyLogo);
    expect(logo, findsOneWidget);
    expect(find.descendant(of: logo, matching: find.text('C')), findsOneWidget, reason: 'sin logo: iniciales de CONTRASTE');
    // El nombre queda a la derecha del logo, a la misma altura.
    final logoBox = tester.getRect(logo);
    final nameBox = tester.getRect(find.descendant(of: find.byType(Drawer), matching: find.text('CONTRASTE')));
    expect(nameBox.left, greaterThan(logoBox.right));
    expect(nameBox.top, lessThan(logoBox.bottom));
  });

  testWidgets('logo con URL rota: muestra las iniciales sin error', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CompanyLogo(name: 'Demo Full', url: 'no-es-una-url'))));
    expect(find.text('DF'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
