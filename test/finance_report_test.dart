import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glamora_movil/main.dart';
import 'package:glamora_movil/session.dart';
import 'package:glamora_movil/util/format.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_api.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  Map<String, dynamic> results({double profit = 290}) => {
        'tab': 'resultados', 'from': '2026-11-01', 'to': '2026-11-06',
        'income': {'rows': [{'label': 'Ventas de servicios', 'amount': 250}, {'label': 'Propinas', 'amount': 10}], 'total': 360, 'caja': 360, 'tesoreria': 0, 'otro': 0},
        'expense': {'rows': [{'label': 'LUZ', 'amount': 40}], 'total': 70, 'caja': 30, 'tesoreria': 40, 'otro': 0},
        'profit': profit,
        'capital': {'added': 1200, 'taken': 25},
        'sales_without_cash': {'count': 2, 'amount': 77},
        'note': 'Cuenta el dinero que entró y salió.',
      };

  Map<String, dynamic> movements(String scope, String dir) => {
        'tab': 'movimientos', 'from': '2026-11-01', 'to': '2026-11-06', 'scope': scope, 'direction': dir,
        'summary': {'income': 375, 'expense': 105, 'balance': 270},
        'categories': [{'label': 'Ventas', 'direction': 'in', 'amount': 300, 'share': 1}, {'label': 'INSUMOS', 'direction': 'out', 'amount': 30, 'share': .1}],
        'count': 150, 'limit': 100,
        'items': [
          {'concept': 'Venta V-1', 'category': 'Ventas', 'direction': 'in', 'amount': 300, 'date': '2026-11-02', 'time': '10:15', 'origin': 'CAJA 1', 'method': 'Efectivo', 'cancelled': false},
          {'concept': 'Café', 'category': 'INSUMOS', 'direction': 'out', 'amount': 30, 'date': '2026-11-02', 'time': '11:00', 'origin': 'CAJA 1', 'method': 'Efectivo', 'cancelled': true},
          {'concept': 'Luz', 'category': 'LUZ', 'direction': 'out', 'amount': 40, 'date': '2026-11-01', 'time': null, 'origin': 'BANCO', 'method': null, 'cancelled': false},
        ],
      };

  Map<String, dynamic> closings({bool empty = false}) => {
        'tab': 'cierres', 'from': '2026-11-01', 'to': '2026-11-06', 'count': empty ? 0 : 3, 'limit': 100,
        'sessions': empty
            ? []
            : [
                {'id': 1, 'register': 'CAJA 1', 'branch': 'CENTRO', 'status': 'open', 'opened_by': 'ANA', 'opened_at': '2026-11-06 08:00', 'closed_by': null, 'closed_at': null, 'opening': 100, 'cash_in': 300, 'cash_out': 30, 'others_net': 50, 'others': [{'method': 'QR', 'amount': 50}], 'legacy': false, 'expected': 370, 'counted': null, 'difference': null},
                {'id': 2, 'register': 'CAJA 2', 'branch': null, 'status': 'closed', 'opened_by': 'ANA', 'opened_at': '2026-11-05 08:00', 'closed_by': 'LUIS', 'closed_at': '2026-11-05 20:00', 'opening': 50, 'cash_in': 100, 'cash_out': 0, 'others_net': 0, 'others': [], 'legacy': false, 'expected': 150, 'counted': 145, 'difference': -5, 'count': [{'value': 100, 'kind': 'billete', 'qty': 1}, {'value': 0.5, 'kind': 'moneda', 'qty': 3}]},
                {'id': 3, 'register': 'CAJA 3', 'branch': null, 'status': 'closed', 'opened_by': 'ANA', 'opened_at': '2026-11-04 08:00', 'closed_by': 'LUIS', 'closed_at': '2026-11-04 20:00', 'opening': 50, 'cash_in': 0, 'cash_out': 0, 'others_net': 20, 'others': [{'method': 'QR', 'amount': 20}], 'legacy': true, 'expected': 70, 'counted': 70, 'difference': 0},
              ],
      };

  FakeApi server({double profit = 290, bool noSessions = false, bool hasReport = true}) {
    final fake = FakeApi()
      ..on('GET /me', meJson(abilities: {'dashboard': true, 'reports': true}))
      ..on('GET /auth/companies', [companyJson])
      ..on('GET /dashboard', {'date': '2026-11-06', 'currency': 'Bs', 'sections': <String, bool>{}})
      ..on('GET /reports', {'available': [if (hasReport) {'key': 'finanzas', 'label': 'Finanzas'}, {'key': 'ventas', 'label': 'Ventas'}]});
    fake.routes['GET /reports/finance'] = (req) {
      final q = req.url.queryParameters;
      final Map<String, dynamic> body = switch (q['tab']) {
        'movimientos' => movements(q['scope'] ?? 'caja', q['dir'] ?? 'todos'),
        'cierres' => closings(empty: noSessions),
        _ => results(profit: profit),
      };
      final todo = q['preset'] == 'todo';
      return FakeApi.json({...body, 'from': '2026-10-01', 'to': todo ? ymd(DateTime.now()) : '2026-10-31', 'all_time': todo});
    };
    return fake;
  }

  Future<FakeApi> open(WidgetTester tester, {FakeApi? api}) async {
    tester.view.physicalSize = const Size(420, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = api ?? server();
    final session = Session(fake.client(), MemorySessionStore()..values.addAll({'token': 't', 'company_id': '2'}));
    await tester.pumpWidget(GlamoraApp(session: session));
    await session.restore();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text('Reportes')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finanzas').last);
    await tester.pumpAndSettle();
    return fake;
  }

  Future<void> tabTo(WidgetTester tester, String name) async {
    await tester.tap(find.widgetWithText(Tab, name));
    await tester.pumpAndSettle();
  }

  testWidgets('resultados: ingresos, egresos, utilidad, aportes y aviso', (tester) async {
    final fake = await open(tester);
    expect(fake.last('GET /reports/finance').url.queryParameters['tab'], 'resultados');
    expect(fake.last('GET /reports/finance').url.queryParameters['preset'], 'mes');
    expect(find.widgetWithText(AppBar, 'Finanzas'), findsOneWidget);
    expect(find.text('Ventas de servicios'), findsOneWidget);
    expect(find.text('Total ingresos'), findsOneWidget);
    expect(find.text('Total egresos'), findsOneWidget);
    expect(find.textContaining('Tesorería Bs 40.00'), findsOneWidget);
    expect(find.text('Utilidad'), findsOneWidget);
    expect(find.text('Bs 290.00'), findsOneWidget);
    expect(find.text('Aportes de capital'), findsOneWidget);
    expect(find.text('Retiros'), findsOneWidget);
    expect(find.textContaining('sin caja abierta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pérdida: cambia el título y no rompe', (tester) async {
    await open(tester, api: server(profit: -30));
    expect(find.text('Pérdida'), findsOneWidget);
    expect(find.text('Utilidad'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('períodos: se recarga la pestaña y dice el rango', (tester) async {
    final fake = await open(tester);
    expect(find.text('Desde 01/10/2026 — 31/10/2026'), findsOneWidget);
    await tester.tap(find.text('Hoy'));
    await tester.pumpAndSettle();
    expect(fake.last('GET /reports/finance').url.queryParameters['preset'], 'hoy');
    await tester.dragUntilVisible(find.text('Todo'), find.byType(ListView).first, const Offset(-200, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todo').first);
    await tester.pumpAndSettle();
    expect(fake.last('GET /reports/finance').url.queryParameters['preset'], 'todo');
    expect(find.text('Desde el inicio — hoy'), findsOneWidget);
  });

  testWidgets('movimientos: filtros, categorías y lista por día', (tester) async {
    final fake = await open(tester);
    await tabTo(tester, 'Movimientos');
    final q = fake.last('GET /reports/finance').url.queryParameters;
    expect(q['tab'], 'movimientos');
    expect(q['scope'], 'caja');
    expect(q['preset'], 'mes', reason: 'comparte el período');
    expect(find.textContaining('El cierre cuenta solo el efectivo'), findsOneWidget);
    expect(find.text('Balance'), findsOneWidget);
    expect(find.text('Por categoría'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    expect(find.text('Movimientos (150)'), findsOneWidget);
    expect(find.text('Se muestran los 3 más recientes.'), findsOneWidget);
    expect(find.text('Lunes 2 de noviembre'), findsOneWidget);
    expect(find.text('Domingo 1 de noviembre'), findsOneWidget);
    expect(find.text('Ventas · 10:15 · CAJA 1 · Efectivo'), findsOneWidget);
    expect(find.text('INSUMOS · 11:00 · CAJA 1 · Efectivo · Anulado'), findsOneWidget);
    expect(find.text('LUZ · BANCO'), findsOneWidget, reason: 'sin hora ni medio no quedan separadores sueltos');
    expect(find.text('+ Bs 300.00'), findsOneWidget);
    expect(find.text('− Bs 30.00'), findsOneWidget);

    await tester.tap(find.text('Tesorería'));
    await tester.pumpAndSettle();
    expect(fake.last('GET /reports/finance').url.queryParameters['scope'], 'tesoreria');
    expect(find.textContaining('transferencias'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Egresos'));
    await tester.pumpAndSettle();
    final q2 = fake.last('GET /reports/finance').url.queryParameters;
    expect(q2['dir'], 'egresos');
    expect(q2['scope'], 'tesoreria');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cierres: abierta, faltante y exacto', (tester) async {
    await open(tester);
    await tabTo(tester, 'Cierres');
    expect(find.text('CAJA 1 · CENTRO'), findsOneWidget);
    expect(find.text('Abierta'), findsOneWidget);
    expect(find.text('Cerrada'), findsNWidgets(2));
    expect(find.text('Abrió ANA · 06/11 08:00'), findsOneWidget);
    expect(find.text('Cerró LUIS · 05/11 20:00'), findsOneWidget);
    expect(find.text('Ingresos efectivo'), findsNWidgets(3));
    expect(find.text('Otros medios (no se cuentan): QR Bs 50.00'), findsOneWidget, reason: 'abierta: aparte, sin sumar');
    expect(find.text('Esperado en efectivo'), findsNWidgets(2));
    expect(find.text('Conteo: 1 × 100 · 3 × 0.50'), findsOneWidget);
    // Cerrada antes del cambio: «Otros medios» sigue sumando, como entonces.
    expect(find.text('Esperado en caja'), findsOneWidget);
    expect(find.text('Otros medios'), findsOneWidget);
    expect(find.text('Otros medios: QR Bs 20.00'), findsOneWidget);
    expect(find.text('Faltante Bs 5.00'), findsOneWidget);
    expect(find.text('Exacto'), findsOneWidget);
    expect(find.text('Contado'), findsNWidgets(2), reason: 'la abierta aún no se contó');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cierres sin turnos', (tester) async {
    await open(tester, api: server(noSessions: true));
    await tabTo(tester, 'Cierres');
    expect(find.text('No hay turnos de caja en el período.'), findsOneWidget);
  });

  testWidgets('sin el reporte disponible no aparece la tarjeta', (tester) async {
    tester.view.physicalSize = const Size(420, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = server(hasReport: false);
    final session = Session(fake.client(), MemorySessionStore()..values.addAll({'token': 't', 'company_id': '2'}));
    await tester.pumpWidget(GlamoraApp(session: session));
    await session.restore();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text('Reportes')));
    await tester.pumpAndSettle();
    expect(find.text('Resumen por área'), findsOneWidget);
    expect(find.text('Finanzas'), findsNothing);
  });
}
