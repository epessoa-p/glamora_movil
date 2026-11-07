import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glamora_movil/main.dart';
import 'package:glamora_movil/session.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_api.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  Map<String, dynamic> rank() => {
        'top': [{'name': 'SHAMPOO', 'qty': 3, 'sold': 150, 'profit': 60, 'margin': 40.0}, {'name': 'TINTE', 'qty': 1, 'sold': 100, 'profit': 10, 'margin': 10.0}],
        'low': [{'name': 'TINTE', 'qty': 1, 'sold': 100, 'profit': 10, 'margin': 10.0}, {'name': 'SHAMPOO', 'qty': 3, 'sold': 150, 'profit': 60, 'margin': 40.0}],
      };

  FakeApi server({bool negative = false}) {
    final fake = FakeApi()
      ..on('GET /me', meJson(abilities: {'dashboard': true, 'reports': true}))
      ..on('GET /auth/companies', [companyJson])
      ..on('GET /dashboard', {'date': '2026-11-06', 'currency': 'Bs', 'sections': <String, bool>{}})
      ..on('GET /reports', {'available': [{'key': 'ganancias', 'label': 'Ganancias'}]});
    fake.routes['GET /reports/profit'] = (req) {
      final scope = req.url.queryParameters['scope'] ?? 'ambos';
      return FakeApi.json({
        'scope': scope, 'currency': 'Bs', 'from': '2026-11-01', 'to': '2026-11-06',
        'summary': {'revenue': 450, 'cost': 205, 'profit': negative ? -30 : 245, 'margin': negative ? -6.7 : 54.4},
        'products': {'revenue': 250, 'cost': 180, 'commissions': 5, 'profit': 65, 'margin': 26.0, 'count': 3},
        'services': {'revenue': 200, 'cost': 0, 'commissions': 20, 'profit': 180, 'margin': 90.0, 'count': 1},
        'net': scope == 'ambos' ? {'expenses': 40, 'profit': 205} : null,
        'days': [{'date': '2026-11-06', 'sold': 450, 'profit': 245}],
        'product_rank': scope == 'servicios' ? null : rank(),
        'service_rank': scope == 'productos' ? null : {'top': [{'name': 'CORTE', 'qty': 1, 'sold': 200, 'profit': 180, 'margin': 90.0}], 'low': [{'name': 'CORTE', 'qty': 1, 'sold': 200, 'profit': 180, 'margin': 90.0}]},
        'sales': [{'number': 'V-000001', 'at': '2026-11-06 10:15', 'client': 'MARÍA', 'sold': 300, 'cost': 85, 'profit': 215, 'margin': 71.7}],
        'sales_count': 1,
        'note': 'El costo usa el costo actual de cada producto.',
      });
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
    await tester.tap(find.text('Ganancias'));
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('resumen, productos, servicios, neto, por día y ventas', (tester) async {
    final fake = await open(tester);
    expect(fake.last('GET /reports/profit').url.queryParameters['preset'], 'mes');
    expect(find.widgetWithText(AppBar, 'Ganancias'), findsOneWidget);
    expect(find.text('Margen 54.4%'), findsOneWidget);
    expect(find.text('Costo de productos'), findsOneWidget);
    expect(find.text('Después de gastos'), findsOneWidget);
    expect(find.text('Por día'), findsOneWidget);
    expect(find.text('V-000001'), findsOneWidget);
    expect(find.text('1 registros'), findsOneWidget);
    expect(find.textContaining('10:15 · MARÍA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('períodos y filtro de alcance', (tester) async {
    final fake = await open(tester);
    await tester.tap(find.text('Hoy'));
    await tester.pumpAndSettle();
    expect(fake.last('GET /reports/profit').url.queryParameters['preset'], 'hoy');

    await tester.tap(find.text('Servicios').first);
    await tester.pumpAndSettle();
    final q = fake.last('GET /reports/profit').url.queryParameters;
    expect(q['scope'], 'servicios');
    expect(q['preset'], 'hoy', reason: 'conserva el período');
    expect(find.text('Costo de productos'), findsNothing);
    expect(find.text('Después de gastos'), findsNothing);
    expect(find.text('SHAMPOO'), findsNothing);
    expect(find.text('CORTE'), findsOneWidget);
  });

  testWidgets('más ganancia y margen bajo, por ranking', (tester) async {
    await open(tester);
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(y('SHAMPOO'), lessThan(y('TINTE')));
    await tester.tap(find.text('Margen bajo').first);
    await tester.pumpAndSettle();
    expect(y('TINTE'), lessThan(y('SHAMPOO')));
    expect(find.text('CORTE'), findsOneWidget, reason: 'el de servicios no cambia');
  });

  testWidgets('pérdida: no rompe y se muestra en negativo', (tester) async {
    await open(tester, api: server(negative: true));
    expect(find.text('Margen -6.7%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
