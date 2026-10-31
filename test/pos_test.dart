import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glamora_movil/main.dart';
import 'package:glamora_movil/session.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_api.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  const abilities = {
    'agenda_own': true, 'agenda_all': true, 'appointments_create': true, 'clients_view': true, 'clients_create': true,
    'sales_create': true, 'sales_view': true, 'cash_view': true, 'cash_open': true, 'cash_move': true, 'cash_close': true,
  };

  Map<String, dynamic> sessionJson({String status = 'open', double expected = 100, double expense = 0, double? counted, double? difference}) => {
        'id': 5, 'status': status, 'opened_at': '2026-10-29T08:00:00-04:00', 'opening': 100, 'expected': expected,
        'register': 'CAJA PRINCIPAL', 'closed_at': status == 'open' ? null : '2026-10-29T20:00:00-04:00',
        'counted': counted, 'difference': difference, 'income': 0, 'expense': expense, 'sales_count': 0,
        'by_method': [], 'movements': [
          if (expense > 0) {'id': 1, 'type': 'egreso', 'amount': expense, 'concept': 'CAFÉ', 'method': 'Efectivo', 'at': '2026-10-29T09:00:00-04:00'},
        ],
      };

  final saleJson = {
    'id': 90, 'number': 'V-000090', 'client': 'MARÍA LÓPEZ', 'total': 100, 'tip': 10, 'method': 'Efectivo', 'status': 'completada',
    'at': '2026-10-29T10:30:00-04:00', 'subtotal': 100, 'discounts': 0, 'tax': 0, 'credit_applied': 0, 'coupon': null,
    'points_redeemed': 0, 'cash': 'CAJA PRINCIPAL', 'notes': null, 'currency': 'Bs',
    'items': [
      {'description': 'CORTE', 'quantity': 1, 'unit_price': 100, 'total': 100, 'specialist': 'ANA PÉREZ', 'session': false},
    ],
  };

  FakeApi server() {
    final fake = FakeApi()
      ..on('GET /me', meJson(abilities: abilities))
      ..on('GET /auth/companies', [companyJson])
      ..on('GET /agenda', {'appointments': [appointmentJson()]})
      ..on('GET /agenda/options', {'services': [], 'specialists': [], 'statuses': []})
      ..on('GET /clients', [])
      ..on('GET /pos/options', {
        'currency': 'Bs',
        'catalog': [
          {'kind': 'service', 'id': 21, 'name': 'CORTE', 'price': 100, 'duration': 45, 'category_id': null},
          {'kind': 'product', 'id': 31, 'name': 'SHAMPOO', 'price': 40, 'stock': 0},
          {'kind': 'product', 'id': 32, 'name': 'CERA', 'price': 25, 'stock': 6},
        ],
        'categories': [],
        'specialists': [{'id': 14, 'name': 'ANA PÉREZ'}],
        'default_principal': 14,
        'payment_methods': [
          {'code': 'efectivo', 'name': 'Efectivo', 'icon': 'bi-cash', 'cash': true, 'default': true},
          {'code': 'qr', 'name': 'QR', 'icon': 'bi-qr-code', 'cash': false, 'default': false},
        ],
        'cash_sessions': [{'id': 5, 'name': 'CAJA PRINCIPAL'}],
        'require_cash': false,
        'features': {'coupons': true, 'loyalty': false, 'clients_create': true},
      })
      ..on('GET /pos/clients', [
        {'id': 7, 'name': 'MARÍA LÓPEZ', 'phone': '70000001', 'document': null},
      ])
      ..on('POST /sales', {'message': 'Venta registrada: V-000090', 'sale': saleJson}, status: 201)
      ..on('GET /sales', {
        'date': '2026-10-29', 'currency': 'Bs', 'scope': 'all', 'can_all': true,
        'totals': {'count': 1, 'total': 100, 'tips': 10, 'by_method': [{'method': 'Efectivo', 'amount': 100, 'count': 1}]},
        'sales': [saleJson],
      })
      ..on('GET /sales/90', saleJson)
      ..on('GET /cash', {
        'currency': 'Bs',
        'registers': [{'id': 1, 'name': 'CAJA PRINCIPAL', 'session': null}],
        'can': {'open': true, 'move': true, 'close': true},
      })
      ..on('POST /cash/open', {'message': 'Caja abierta.', 'session': sessionJson()}, status: 201)
      ..on('GET /cash/5', sessionJson())
      ..on('POST /cash/5/movements', {'message': 'Gasto registrado.', 'session': sessionJson(expected: 80, expense: 20)}, status: 201)
      ..on('POST /cash/5/close', {'message': 'Caja cerrada: faltan 5.00.', 'session': sessionJson(status: 'closed', expected: 80, expense: 20, counted: 75, difference: -5)});

    // La cotización suma lo que trae el carrito (como el servidor).
    fake.routes['POST /pos/quote'] = (req) {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final items = (body['items'] as List).cast<Map<String, dynamic>>();
      final lines = [
        for (final i in items)
          {'gross': (i['quantity'] as num) * (i['unit_price'] as num), 'total': (i['quantity'] as num) * (i['unit_price'] as num), 'badge': null, 'uses_session': false, 'package_discount': 0},
      ];
      final total = lines.fold<num>(0, (s, l) => s + (l['total'] as num));
      final tip = (body['tip'] as num?) ?? 0;
      final coupon = body['coupon_code'];
      return FakeApi.json({
        'lines': lines, 'subtotal': total, 'line_discounts': 0, 'global_discount': 0, 'membership_discount': 0, 'package_discount': 0,
        'promotion_discount': 0, 'coupon_discount': 0, 'coupon': null, 'redeem_points': 0, 'loyalty_discount': 0, 'gravado': total,
        'tax': 0, 'total': total, 'tip': tip, 'credit_applied': 0, 'charge': total + tip, 'charge_now': total + tip,
        'on_credit': false, 'points_to_earn': 0,
        'client': body['client_id'] == null ? null : {'id': 7, 'name': 'MARÍA LÓPEZ', 'membership': null, 'packages': [], 'points': {'enabled': false}, 'credit': 0},
        'errors': [if (coupon != null) 'El cupón $coupon no existe.'],
        'warnings': [],
      });
    };
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

  Finder chargeButton() => find.descendant(of: find.byType(FilledButton), matching: find.textContaining('Cobrar'));

  testWidgets('cobrar: catálogo, clienta, propina, cupón inválido y venta registrada', (tester) async {
    final fake = await start(tester);
    await openFromMenu(tester, 'Cobrar');

    expect(find.text('Cliente ocasional'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.ancestor(of: chargeButton(), matching: find.byType(FilledButton))).onPressed, isNull,
        reason: 'sin líneas no se puede cobrar');

    // Catálogo: sin stock no se puede elegir; CERA se agrega dos veces → cantidad 2.
    await tester.tap(find.text('Agregar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sin stock'), findsOneWidget);
    await tester.tap(find.text('CORTE'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Agregar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'cera');
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('CERA')));
      await tester.pumpAndSettle();
    }
    expect(fake.body('POST /pos/quote')['items'], [
      {'service_id': 21, 'quantity': 1, 'unit_price': 100},
      {'product_id': 32, 'quantity': 2, 'unit_price': 25},
    ]);
    expect(find.text('Cobrar Bs 150.00'), findsOneWidget);

    // Clienta desde el buscador.
    await tester.tap(find.text('Cliente ocasional'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MARÍA LÓPEZ'));
    await tester.pumpAndSettle();
    expect(fake.body('POST /pos/quote')['client_id'], 7);
    expect(fake.body('POST /pos/quote')['personal_id'], 14, reason: 'profesional por defecto: la ficha del usuario');

    // Propina y vuelto en efectivo.
    await tester.enterText(find.widgetWithText(TextField, 'Propina'), '10');
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('Cobrar Bs 160.00'), findsOneWidget);
    await tester.scrollUntilVisible(find.widgetWithText(TextField, 'Recibido'), 120, scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.widgetWithText(TextField, 'Recibido'), '200');
    await tester.pump();
    expect(find.text('Vuelto Bs 40.00'), findsOneWidget);

    // Un cupón inválido bloquea el cobro con el mensaje del servidor.
    await tester.scrollUntilVisible(find.widgetWithText(TextField, 'Cupón'), -120, scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.widgetWithText(TextField, 'Cupón'), 'nope');
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('El cupón NOPE no existe.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.ancestor(of: chargeButton(), matching: find.byType(FilledButton))).onPressed, isNull);
    await tester.enterText(find.widgetWithText(TextField, 'Cupón'), '');
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    await tester.tap(chargeButton());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cobrar').last);
    await tester.pumpAndSettle();

    final sent = fake.body('POST /sales');
    expect(sent['client_id'], 7);
    expect(sent['payment_method'], 'efectivo');
    expect(sent['cash_session_id'], 5, reason: 'con una sola caja abierta se elige sola');
    expect(sent['tip'], 10);
    expect(sent.containsKey('coupon_code'), isFalse);
    expect(find.text('¡Venta cobrada!'), findsOneWidget);
    expect(find.text('Nueva venta'), findsOneWidget);
  });

  testWidgets('cobrar desde una cita: precarga clienta, servicio y profesional', (tester) async {
    final fake = await start(tester);
    await tester.tap(find.text('MARÍA LÓPEZ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cobrar Bs 100.00'));
    await tester.pumpAndSettle();

    final q = fake.body('POST /pos/quote');
    expect(q['client_id'], 7);
    expect(q['personal_id'], 14);
    expect(q['items'], [{'service_id': 21, 'quantity': 1, 'unit_price': 100}]);
    expect(find.text('Cobrar Bs 100.00'), findsOneWidget);
  });

  testWidgets('ventas del día: totales y detalle', (tester) async {
    await start(tester);
    await openFromMenu(tester, 'Ventas');
    expect(find.text('Bs 100.00'), findsWidgets);
    expect(find.text('1 venta(s) · propinas Bs 10.00'), findsOneWidget);
    await tester.tap(find.text('MARÍA LÓPEZ'));
    await tester.pumpAndSettle();
    expect(find.text('Venta V-000090'), findsOneWidget);
    expect(find.textContaining('ANA PÉREZ'), findsOneWidget);
  });

  testWidgets('caja: abrir, registrar un gasto y cerrar con arqueo', (tester) async {
    final fake = await start(tester);
    await openFromMenu(tester, 'Caja');
    expect(find.text('Cerrada'), findsOneWidget);

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '100');
    await tester.tap(find.text('Abrir caja'));
    await tester.pumpAndSettle();
    expect(fake.body('POST /cash/open'), {'cash_register_id': 1, 'opening_amount': 100});
    expect(find.text('Bs 100.00'), findsWidgets);

    // Gasto: sin concepto no se envía.
    await tester.tap(find.text('Gasto'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Monto'), '20');
    await tester.tap(find.text('Registrar'));
    await tester.pumpAndSettle();
    expect(find.text('Indica el concepto.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Concepto'), 'Café');
    await tester.tap(find.text('Registrar'));
    await tester.pumpAndSettle();
    expect(fake.body('POST /cash/5/movements'), {'type': 'egreso', 'amount': 20, 'concept': 'Café'});
    expect(find.text('Bs 80.00'), findsOneWidget);
    expect(find.text('CAFÉ'), findsOneWidget);

    // Cierre: el diálogo muestra cuánto falta antes de confirmar.
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '75');
    await tester.pump();
    expect(find.text('Faltan Bs 5.00'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Cerrar caja'));
    await tester.pumpAndSettle();
    expect(fake.body('POST /cash/5/close'), {'closing_amount': 75});
    expect(find.text('Faltante'), findsOneWidget);
    expect(find.text('Gasto'), findsNothing, reason: 'cerrada: sin acciones');
  });
}
