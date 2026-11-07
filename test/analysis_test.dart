import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glamora_movil/main.dart';
import 'package:glamora_movil/session.dart';
import 'package:glamora_movil/widgets/bar_chart.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_api.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  Map<String, dynamic> kpis(num wa, num wc, num pa, num pc) => {
        'week': {'amount': wa, 'count': wc, 'prev_amount': pa, 'prev_count': pc},
        'month': {'amount': wa * 4, 'count': wc * 4, 'prev_amount': 0, 'prev_count': 0},
      };
  Map<String, dynamic> series({bool hours = false}) => {
        'kpis': kpis(100, 2, 200, 4),
        'by_day': [for (final d in ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom']) {'label': d, 'amount': 10, 'count': 1, 'prev_amount': 20, 'prev_count': 2}],
        'weeks': [for (var i = 0; i < 8; i++) {'label': '0$i/11', 'amount': 50 + i, 'count': i}],
        'months': [for (final m in ['jun', 'jul', 'ago', 'sep', 'oct', 'nov']) {'label': m, 'amount': 300, 'count': 3}],
        if (hours) 'hours': [{'label': '10:00', 'amount': 90, 'count': 1}, {'label': '16:00', 'amount': 70, 'count': 5}],
      };

  FakeApi server({bool purchases = true, bool empty = false}) {
    final tabs = [
      {'key': 'servicios', 'label': 'Servicios'},
      {'key': 'ventas', 'label': 'Ventas'},
      if (purchases) {'key': 'compras', 'label': 'Compras'},
      {'key': 'personal', 'label': 'Personal'},
      {'key': 'top', 'label': 'Top'},
    ];
    final fake = FakeApi()
      ..on('GET /me', meJson(abilities: {'dashboard': true, 'reports': true}))
      ..on('GET /auth/companies', [companyJson])
      ..on('GET /dashboard', {'date': '2026-11-05', 'currency': 'Bs', 'sections': <String, bool>{}})
      ..on('GET /reports', {'available': [{'key': 'analisis', 'label': 'Análisis'}]});
    fake.routes['GET /reports/analysis'] = (req) {
      final base = {'currency': 'Bs', 'tabs': tabs};
      final tab = req.url.queryParameters['tab'];
      return FakeApi.json(switch (tab) {
        null => base,
        'servicios' => {...base, 'tab': tab, ...series()},
        'ventas' => {...base, 'tab': tab, ...series(hours: true)},
        'compras' => {...base, 'tab': tab, ...series()},
        'personal' => {
            ...base,
            'tab': tab,
            'kpis': kpis(100, 2, 50, 1),
            'people': empty
                ? <Map<String, dynamic>>[]
                : [
                    {'id': 1, 'name': 'ANA PÉREZ', 'commissions': 45.5, 'week': {'amount': 100, 'count': 2, 'prev_amount': 50, 'prev_count': 1}, 'month': {'amount': 400, 'count': 8, 'prev_amount': 800, 'prev_count': 8}},
                    {'id': 2, 'name': 'LUIS GÓMEZ', 'commissions': null, 'week': {'amount': 0, 'count': 0, 'prev_amount': 0, 'prev_count': 0}, 'month': {'amount': 90, 'count': 1, 'prev_amount': 0, 'prev_count': 0}},
                  ],
          },
        _ => {
            ...base,
            'tab': tab,
            'week': {'services': [{'name': 'SEMANA CORTE', 'amount': 10, 'count': 1}], 'products': [], 'clients': []},
            'month': {
              'services': [{'name': 'CORTE', 'amount': 100, 'count': 2}, {'name': 'TINTE', 'amount': 500, 'count': 1}],
              'products': [],
              'clients': [{'name': 'MARÍA', 'amount': 700, 'count': 3}],
            },
          },
      });
    };
    return fake;
  }

  Future<FakeApi> open(WidgetTester tester, {FakeApi? api}) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = api ?? server();
    final store = MemorySessionStore()..values.addAll({'token': 't', 'company_id': '2'});
    final session = Session(fake.client(), store);
    await tester.pumpWidget(GlamoraApp(session: session));
    await session.restore();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.descendant(of: find.byType(Drawer), matching: find.text('Reportes')), 80, scrollable: find.descendant(of: find.byType(Drawer), matching: find.byType(Scrollable)));
    await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text('Reportes')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Análisis'));
    await tester.pumpAndSettle();
    return fake;
  }

  Future<void> goTab(WidgetTester tester, String label) async {
    final tab = find.descendant(of: find.byType(TabBar), matching: find.text(label));
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();
  }

  testWidgets('pestañas y gráficos comparativos; monto y cantidad', (tester) async {
    await open(tester);
    for (final t in ['Servicios', 'Ventas', 'Compras', 'Personal', 'Top']) {
      expect(find.descendant(of: find.byType(TabBar), matching: find.text(t)), findsOneWidget);
    }
    expect(find.text('Semana anterior vs. actual (por día)'), findsOneWidget);
    expect(find.text('Comparativa semanal (últimas 8)'), findsOneWidget);
    expect(find.text('Comparativa mensual (últimos 6)'), findsOneWidget);
    expect(find.text('Semana anterior'), findsOneWidget);
    expect(find.text('Bs 100.00'), findsOneWidget);
    expect(find.text('-50% vs anterior'), findsOneWidget);
    expect(find.text('Sin dato anterior'), findsOneWidget, reason: 'no inventa un porcentaje sin base');

    await tester.tap(find.text('Cantidad'));
    await tester.pumpAndSettle();
    expect(find.text('Bs 100.00'), findsNothing);
    expect(find.text('2'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ventas: conserva las horas con más ventas y las reordena', (tester) async {
    await open(tester);
    await goTab(tester, 'Ventas');
    await tester.scrollUntilVisible(find.text('Horas con más ventas'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('Bs 90.00'), findsOneWidget);
    expect(tester.getTopLeft(find.text('10:00')).dy, lessThan(tester.getTopLeft(find.text('16:00')).dy));
    await tester.scrollUntilVisible(find.text('N.º de ventas'), -400, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('N.º de ventas'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('16:00'), 200, scrollable: find.byType(Scrollable).last);
    expect(tester.getTopLeft(find.text('16:00')).dy, lessThan(tester.getTopLeft(find.text('10:00')).dy), reason: 'en cantidad manda 16:00');
  });

  testWidgets('compras no aparece si el permiso no lo incluye', (tester) async {
    await open(tester, api: server(purchases: false));
    expect(find.descendant(of: find.byType(TabBar), matching: find.text('Compras')), findsNothing);
  });

  testWidgets('personal: gráficos y detalle por persona, con o sin comisiones', (tester) async {
    await open(tester);
    await goTab(tester, 'Personal');
    expect(find.text('Mes anterior vs. actual'), findsOneWidget);
    expect(find.byType(BarChartCard), findsNWidgets(2));
    await tester.scrollUntilVisible(find.text('ANA PÉREZ'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.textContaining('Comisiones Bs 45.50'), findsOneWidget);
    expect(find.text('-50%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('personal sin datos: mensaje sin errores', (tester) async {
    await open(tester, api: server(empty: true));
    await goTab(tester, 'Personal');
    expect(find.text('Sin ventas del personal en este período.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('top: semana o mes, ordenado por monto o cantidad', (tester) async {
    await open(tester);
    await goTab(tester, 'Top');
    expect(tester.getTopLeft(find.text('TINTE')).dy, lessThan(tester.getTopLeft(find.text('CORTE')).dy));
    await tester.tap(find.text('Cantidad'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('CORTE')).dy, lessThan(tester.getTopLeft(find.text('TINTE')).dy));
    await tester.tap(find.text('Esta semana'));
    await tester.pumpAndSettle();
    expect(find.text('SEMANA CORTE'), findsOneWidget);
  });

  testWidgets('gráfico sin datos no divide entre cero', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BarChartCard(title: 'X', series: const [ChartSeries('', Colors.red)], groups: const [ChartGroup('a', [0]), ChartGroup('b', [-5])], format: (v) => '$v'),
      ),
    ));
    expect(find.text('Sin datos en este período'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('números compactos del eje', () {
    expect(compactNumber(6700), '6.7k');
    expect(compactNumber(21800), '21.8k');
    expect(compactNumber(1500000), '1.5M');
    expect(compactNumber(25), '25');
  });
}
