import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glamora_movil/main.dart';
import 'package:glamora_movil/session.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_api.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  Map<String, dynamic> report({int warehouses = 2, int noCost = 1, bool below = true, bool clean = false}) => {
        'warehouse_id': null,
        'warehouses': [for (var i = 1; i <= warehouses; i++) {'id': i, 'name': 'ALMACÉN $i'}],
        'summary': {'products': 39, 'units': 802.5, 'cost': 42101, 'sale': 72876.94, 'profit': 30775.94, 'margin': 42.2},
        'categories': [
          {'name': 'TINTES', 'products': 4, 'units': 60, 'cost': 8400, 'sale': 12871, 'share': 1},
          {'name': 'Sin categoría', 'products': 5, 'units': 77, 'cost': 3390, 'sale': 6825.5, 'share': .53},
        ],
        'restock': {
          'out': clean ? 0 : 1, 'low': clean ? 0 : 6, 'cost': clean ? 0 : 500, 'count': clean ? 0 : 7,
          'items': clean
              ? []
              : [
                  {'name': 'SHAMPOO', 'status': 'agotado', 'stock': 0, 'min': 5, 'missing': 5, 'cost': 150},
                  for (var i = 1; i <= 6; i++) {'name': 'BAJO $i', 'status': 'bajo', 'stock': 2, 'min': 3, 'missing': 1, 'cost': 10},
                ],
        },
        'idle': {
          'days': 90, 'value': clean ? 0 : 900, 'count': clean ? 0 : 2,
          'items': clean
              ? []
              : [
                  {'name': 'CREMA', 'units': 10, 'value': 700, 'last_exit': '2026-01-15', 'days': 295},
                  {'name': 'GEL', 'units': 4, 'value': 200, 'last_exit': null, 'days': 120},
                ],
        },
        'below_cost': {'count': below ? 1 : 0, 'items': [if (below) {'name': 'TINTE ROJO', 'cost': 90, 'price': 80, 'units': 3}]},
        'no_cost': noCost,
        'currency': 'Bs',
      };

  FakeApi server(Map<String, dynamic> body) {
    final fake = FakeApi()
      ..on('GET /me', meJson(abilities: {'dashboard': true, 'reports': true}))
      ..on('GET /auth/companies', [companyJson])
      ..on('GET /dashboard', {'date': '2026-11-06', 'currency': 'Bs', 'sections': <String, bool>{}})
      ..on('GET /reports', {'available': [{'key': 'inventario', 'label': 'Inventario'}]})
      ..on('GET /reports/inventory', body);
    return fake;
  }

  Future<FakeApi> open(WidgetTester tester, {Map<String, dynamic>? body}) async {
    tester.view.physicalSize = const Size(420, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = server(body ?? report());
    final session = Session(fake.client(), MemorySessionStore()..values.addAll({'token': 't', 'company_id': '2'}));
    await tester.pumpWidget(GlamoraApp(session: session));
    await session.restore();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text('Reportes')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inventario'));
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('indicadores y categorías, como en la captura', (tester) async {
    await open(tester);
    expect(find.widgetWithText(AppBar, 'Inventario'), findsOneWidget);
    expect(find.text('39'), findsOneWidget);
    expect(find.text('802.5'), findsOneWidget);
    expect(find.text('Bs 42,101.00'), findsOneWidget);
    expect(find.text('Bs 72,876.94'), findsOneWidget);
    expect(find.text('Bs 30,775.94'), findsOneWidget);
    expect(find.text('Margen 42.2%'), findsOneWidget);
    expect(find.text('TINTES'), findsOneWidget);
    expect(find.text('4 productos · 60 unid. · costo Bs 8,400.00'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    expect(find.textContaining('no tienen costo cargado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('para reponer: agotados, bajos, costo y ver todos', (tester) async {
    await open(tester);
    expect(find.text('1 agotado'), findsOneWidget);
    expect(find.text('6 con stock bajo'), findsOneWidget);
    expect(find.text('Llegar al mínimo cuesta Bs 500.00.'), findsOneWidget);
    expect(find.text('SHAMPOO'), findsOneWidget);
    expect(find.text('Faltan 5'), findsOneWidget);
    expect(find.text('BAJO 6'), findsNothing, reason: 'muestra los primeros');
    await tester.tap(find.text('Ver todos (7)'));
    await tester.pumpAndSettle();
    expect(find.text('BAJO 6'), findsOneWidget);
    await tester.tap(find.text('Ver menos'));
    await tester.pumpAndSettle();
    expect(find.text('BAJO 6'), findsNothing);
  });

  testWidgets('sin movimiento y precio bajo el costo', (tester) async {
    await open(tester);
    expect(find.text('Sin salidas en 90 días: Bs 900.00 detenidos en 2 producto(s).'), findsOneWidget);
    expect(find.text('10 unid. · última salida 15/01/2026'), findsOneWidget);
    expect(find.text('4 unid. · nunca ha salido'), findsOneWidget);
    expect(find.text('Precio por debajo del costo'), findsOneWidget);
    expect(find.text('Precio Bs 80.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filtro de almacén', (tester) async {
    final fake = await open(tester);
    expect(fake.last('GET /reports/inventory').url.queryParameters.containsKey('warehouse_id'), isFalse);
    await tester.tap(find.text('ALMACÉN 2'));
    await tester.pumpAndSettle();
    expect(fake.last('GET /reports/inventory').url.queryParameters['warehouse_id'], '2');
    expect(find.textContaining('total de todos los almacenes'), findsOneWidget);
    await tester.tap(find.text('Todos'));
    await tester.pumpAndSettle();
    expect(fake.last('GET /reports/inventory').url.queryParameters.containsKey('warehouse_id'), isFalse);
    expect(find.textContaining('total de todos los almacenes'), findsNothing);
  });

  testWidgets('un solo almacén y nada pendiente: sin filtro ni avisos', (tester) async {
    await open(tester, body: report(warehouses: 1, noCost: 0, below: false, clean: true));
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('Nada por reponer.'), findsOneWidget);
    expect(find.text('Todo se está moviendo.'), findsOneWidget);
    expect(find.text('Precio por debajo del costo'), findsNothing);
    expect(find.textContaining('no tienen costo cargado'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
