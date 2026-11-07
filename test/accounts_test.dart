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
  const all = {
    'dashboard': true, 'cash_view': true, 'accounts_view': true, 'accounts_move': true, 'expenses_view': true, 'expenses_create': true,
    'expense_categories_view': true, 'expense_categories_create': true, 'commissions_view': true,
  };
  const canAll = {'create': true, 'edit': true, 'delete': true, 'move': true, 'expense': true};
  const types = [{'code': 'caja_chica', 'label': 'Caja chica'}, {'code': 'banco', 'label': 'Banco'}, {'code': 'billetera', 'label': 'Billetera digital'}];

  Map<String, dynamic> options({List<Map<String, dynamic>> categories = const [], int? def, List branches = const []}) => {
        'currency': 'Bs',
        'types': types,
        'categories': categories,
        'default_category_id': def,
        'sessions': [{'id': 5, 'name': 'CAJA PRINCIPAL', 'expected': 200}],
        'accounts': [{'id': 1, 'name': 'CAJA CHICA', 'balance': 500}, {'id': 2, 'name': 'BANCO BNB', 'balance': 1000}],
        'can_use_accounts': true,
        'suppliers': [{'id': 9, 'name': 'PROVEEDOR X'}],
        'people': [{'id': 14, 'name': 'ANA PÉREZ'}],
        'branches': branches,
        'can_create_supplier': true,
      };

  FakeApi server(Map<String, bool> abilities, {Map<String, bool> can = canAll, List<Map<String, dynamic>>? owedPeople, List branches = const []}) {
    final fake = FakeApi()
      ..on('GET /me', meJson(abilities: abilities))
      ..on('GET /auth/companies', [companyJson])
      ..on('GET /cash', {'currency': 'Bs', 'registers': [], 'can': {'open': false, 'move': false, 'close': false}})
      ..on('GET /dashboard', {'date': today, 'currency': 'Bs', 'sections': <String, bool>{}})
      ..on('GET /accounts', {
        'currency': 'Bs', 'total': 1500, 'types': types, 'can': can,
        'accounts': [
          {'id': 1, 'name': 'CAJA CHICA', 'type': 'caja_chica', 'type_label': 'Caja chica', 'bank_name': null, 'active': true, 'balance': 500},
          {'id': 2, 'name': 'BANCO BNB', 'type': 'banco', 'type_label': 'Banco', 'bank_name': 'BNB', 'active': true, 'balance': 1000},
        ],
      })
      ..on('POST /accounts', {'message': 'Cuenta creada.', 'id': 3}, status: 201)
      ..on('GET /accounts/1', {
        'id': 1, 'name': 'CAJA CHICA', 'type': 'caja_chica', 'type_label': 'Caja chica', 'bank_name': null, 'account_number': null, 'notes': null, 'active': true, 'balance': 500,
        'movements': [
          {'id': 71, 'type': 'gasto', 'origin': 'Gasto', 'amount': -40, 'concept': 'Pago X', 'date': today, 'reference': null, 'balance_after': 500, 'voided': false, 'can_void': false},
          {'id': 70, 'type': 'manual', 'origin': 'Manual', 'amount': -60, 'concept': 'Retiro', 'date': today, 'reference': null, 'balance_after': 540, 'voided': false, 'can_void': true},
          {'id': 68, 'type': 'manual', 'origin': 'Manual', 'amount': -5, 'concept': 'Anulado X', 'date': today, 'reference': null, 'balance_after': null, 'voided': true, 'can_void': false},
          {'id': 69, 'type': 'apertura', 'origin': 'Saldo inicial', 'amount': 600, 'concept': 'Saldo inicial', 'date': today, 'reference': null, 'balance_after': 600, 'voided': false, 'can_void': false},
        ],
        'has_movements': true,
        'can': can,
      })
      ..on('POST /accounts/1/movements', {'message': 'Movimiento registrado.'}, status: 201)
      ..on('POST /accounts/1/transfer', {'message': 'Transferencia registrada.'}, status: 201)
      ..on('POST /accounts/1/movements/70/void', {'message': 'Movimiento anulado.'})
      ..on('GET /expense-categories', {
        'can': {'create': true, 'edit': true, 'delete': true},
        'categories': [
          {'id': 1, 'name': 'COMIDA', 'type': 'general', 'frequency': null, 'active': true, 'expenses_count': 0, 'can_delete': true},
          {'id': 2, 'name': 'LUZ', 'type': 'basicos', 'frequency': 'mensual', 'active': true, 'expenses_count': 1, 'can_delete': true},
          {'id': 3, 'name': 'HOSTING', 'type': 'basicos', 'frequency': 'anual', 'active': false, 'expenses_count': 0, 'can_delete': true},
          {'id': 4, 'name': 'PAGO A PROVEEDORES', 'type': 'proveedor', 'frequency': null, 'active': true, 'expenses_count': 0, 'can_delete': true},
          {'id': 5, 'name': 'PAGO A PERSONAL', 'type': 'personal', 'frequency': null, 'active': true, 'expenses_count': 1, 'can_delete': true},
        ],
      })
      ..on('POST /expense-categories', {'message': 'Categoría creada.', 'category': {}}, status: 201)
      ..on('GET /finance/basics', {
        'month': today.substring(0, 7), 'label': 'Noviembre 2026', 'previous': '2026-10', 'next': null, 'paid_count': 1, 'pending_count': 1, 'total_paid': 180,
        'services': [
          {'id': 2, 'name': 'LUZ', 'frequency': 'mensual', 'status': 'pagado', 'paid': 180, 'last_amount': 180, 'next_due_on': null},
          {'id': 6, 'name': 'AGUA', 'frequency': 'mensual', 'status': 'pendiente', 'paid': 0, 'last_amount': 65, 'next_due_on': null},
        ],
      })
      ..on('GET /commissions/pending', {
        'people': owedPeople ?? [{'personal_id': 14, 'name': 'ANA PÉREZ', 'count': 2, 'total': 90, 'tips': 10, 'since': '2026-09-01'}],
        'total': 90, 'count': 2, 'can': {'pay': true},
      })
      ..on('POST /commissions/14/settle', {'message': 'Liquidación L-1 pagada.', 'number': 'L-1'}, status: 201)
      ..on('POST /suppliers', {'id': 20, 'name': 'NUEVO'}, status: 201)
      ..on('POST /expenses', {'message': 'Gasto G-000009 registrado.', 'id': 9, 'number': 'G-000009'}, status: 201)
      ..on('POST /expenses/1/cancel', {'message': 'Gasto anulado: el dinero volvió a la cuenta.'});
    fake.routes['GET /finance/options'] = (req) => FakeApi.json(switch (req.url.queryParameters['group']) {
          'general' => options(categories: [{'id': 1, 'name': 'COMIDA', 'type': 'general', 'frequency': null, 'active': true}], branches: branches),
          'proveedor' => options(categories: [{'id': 4, 'name': 'PAGO A PROVEEDORES', 'type': 'proveedor', 'frequency': null, 'active': true}], def: 4),
          'personal' => options(categories: [{'id': 5, 'name': 'PAGO A PERSONAL', 'type': 'personal', 'frequency': null, 'active': true}], def: 5),
          'basicos' => options(categories: [{'id': 2, 'name': 'LUZ', 'type': 'basicos', 'frequency': 'mensual', 'active': true}, {'id': 6, 'name': 'AGUA', 'type': 'basicos', 'frequency': 'mensual', 'active': true}, {'id': 3, 'name': 'HOSTING', 'type': 'basicos', 'frequency': 'anual', 'active': true}]),
          _ => options(),
        });
    fake.routes['GET /expenses'] = (req) => FakeApi.json(switch (req.url.queryParameters['group']) {
          'general' => {
              'currency': 'Bs', 'total': 100, 'can': {'create': true},
              'expenses': [
                {'id': 1, 'number': 'G-000001', 'date': today, 'concept': 'Almuerzo', 'category': 'COMIDA', 'amount': 100, 'reference': null, 'notes': null, 'source': {'type': 'cuenta', 'name': 'CAJA CHICA'}, 'paid_to': null, 'cancelled': false, 'cancel_reason': null, 'can_cancel': true},
                {'id': 2, 'number': 'G-000002', 'date': today, 'concept': 'Café', 'category': 'COMIDA', 'amount': 30, 'reference': null, 'notes': null, 'source': {'type': 'caja', 'name': 'CAJA PRINCIPAL'}, 'paid_to': null, 'cancelled': true, 'cancel_reason': 'Error', 'can_cancel': false},
                {'id': 3, 'number': null, 'date': today, 'concept': 'Viejo', 'category': null, 'amount': 5, 'reference': null, 'notes': null, 'source': null, 'paid_to': null, 'cancelled': false, 'cancel_reason': null, 'can_cancel': false},
              ],
            },
          _ => {'currency': 'Bs', 'total': 0, 'can': {'create': true}, 'expenses': []},
        });
    return fake;
  }

  Future<FakeApi> start(WidgetTester tester, {Map<String, bool> abilities = all, Map<String, bool> can = canAll, FakeApi? api}) async {
    tester.view.physicalSize = const Size(800, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = api ?? server(abilities, can: can);
    final store = MemorySessionStore()..values.addAll({'token': 't', 'company_id': '2'});
    final session = Session(fake.client(), store);
    await tester.pumpWidget(GlamoraApp(session: session));
    await session.restore();
    await tester.pumpAndSettle();
    return fake;
  }

  Future<void> openMenu(WidgetTester tester, String item) async {
    await tester.tap(find.byTooltip('Menú').first);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text(item)));
    await tester.pumpAndSettle();
  }

  Future<void> openAccount(WidgetTester tester) async {
    await openMenu(tester, 'Finanzas');
    await tester.tap(find.text('CAJA CHICA'));
    await tester.pumpAndSettle();
  }

  Future<void> goTab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
    await tester.pumpAndSettle();
  }

  testWidgets('menú: Finanzas y Gastos según permisos', (tester) async {
    await start(tester, abilities: {'dashboard': true});
    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle();
    final drawer = find.byType(Drawer);
    expect(find.descendant(of: drawer, matching: find.text('Finanzas')), findsNothing);
    expect(find.descendant(of: drawer, matching: find.text('Gastos')), findsNothing);
    expect(find.descendant(of: drawer, matching: find.text('Cuentas')), findsNothing);
  });

  testWidgets('Finanzas: encabezado, botón de caja, saldo y barra Cuentas | Categorías', (tester) async {
    await start(tester);
    await openMenu(tester, 'Finanzas');
    expect(find.widgetWithText(AppBar, 'Finanzas'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'CONTRASTE'), findsOneWidget);
    expect(find.byTooltip('Caja cerrada'), findsOneWidget);
    expect(find.text('SALDO DE LAS CUENTAS'), findsOneWidget);
    expect(find.text('Bs 1,500.00'), findsOneWidget);
    expect(find.text('Caja chica'), findsOneWidget);
    expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('Categorías')), findsOneWidget);
    expect(find.text('Nueva cuenta'), findsOneWidget);
  });

  testWidgets('sin permiso de categorías: Finanzas sin barra', (tester) async {
    await start(tester, abilities: {'dashboard': true, 'accounts_view': true});
    await openMenu(tester, 'Finanzas');
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('SALDO DE LAS CUENTAS'), findsOneWidget);
  });

  testWidgets('nueva cuenta: saldo inicial, mayúsculas, banco solo si corresponde', (tester) async {
    final fake = await start(tester);
    await openMenu(tester, 'Finanzas');
    await tester.tap(find.text('Nueva cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Lo que hay hoy en la cuenta. Entra como primer movimiento.'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Banco o billetera (opcional)'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Nombre'), 'caja chica 2');
    await tester.enterText(find.widgetWithText(TextField, 'Saldo inicial'), '600');
    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();
    final body = fake.body('POST /accounts');
    expect(body['name'], 'CAJA CHICA 2');
    expect(body['initial_amount'], 600);
    expect(body.containsKey('source_type'), isFalse);
  });

  testWidgets('nueva cuenta de banco pide banco y número', (tester) async {
    await start(tester);
    await openMenu(tester, 'Finanzas');
    await tester.tap(find.text('Nueva cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Tipo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banco').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Banco o billetera (opcional)'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'N.º de cuenta (opcional)'), findsOneWidget);
  });

  testWidgets('extracto: origen, saldo después y anular solo lo manual', (tester) async {
    final fake = await start(tester);
    await openAccount(tester);
    expect(find.text('Saldo inicial'), findsOneWidget);
    expect(find.text('+Bs 600.00'), findsOneWidget);
    expect(find.text('Saldo Bs 540.00'), findsOneWidget);
    expect(find.textContaining('Anulado', findRichText: true), findsWidgets);
    expect(find.byTooltip('Anular'), findsOneWidget, reason: 'ni el gasto ni el saldo inicial ni lo anulado');
    await tester.tap(find.byTooltip('Anular'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Anular'));
    await tester.pumpAndSettle();
    expect(fake.last('POST /accounts/1/movements/70/void'), isNotNull);
  });

  testWidgets('sin permisos no hay acciones en la cuenta', (tester) async {
    await start(tester, can: const {'create': false, 'edit': false, 'delete': false, 'move': false, 'expense': false});
    await openAccount(tester);
    expect(find.text('Movimiento'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Gasto'), findsNothing);
    expect(find.byTooltip('Anular'), findsNothing);
    expect(find.byTooltip('Editar'), findsNothing);
  });

  testWidgets('hoja de movimiento: ingreso desde la caja', (tester) async {
    final fake = await start(tester);
    await openAccount(tester);
    await tester.tap(find.text('Movimiento'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Importe'), '50');
    await tester.enterText(find.widgetWithText(TextField, 'Concepto'), 'Aporte');
    await tester.tap(find.text('Caja abierta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final body = fake.body('POST /accounts/1/movements');
    expect(body['direction'], 'in');
    expect(body['amount'], 50);
    expect(body['source_type'], 'caja');
    expect(body['cash_session_id'], 5);
    expect(body['movement_date'], today);
    expect(find.text('Movimiento registrado.'), findsOneWidget);
  });

  testWidgets('hoja de movimiento: egreso no pregunta de dónde viene', (tester) async {
    final fake = await start(tester);
    await openAccount(tester);
    await tester.tap(find.text('Movimiento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Egreso'));
    await tester.pumpAndSettle();
    expect(find.text('Viene de'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Importe'), '5');
    await tester.enterText(find.widgetWithText(TextField, 'Concepto'), 'Comisión');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(fake.body('POST /accounts/1/movements').containsKey('source_type'), isFalse);
  });

  testWidgets('transferir: no ofrece la misma cuenta y envía el destino', (tester) async {
    final fake = await start(tester);
    await openAccount(tester);
    await tester.tap(find.text('Movimiento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transferir').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Importe'), '20');
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Hacia'));
    await tester.pumpAndSettle();
    expect(find.text('Cuenta: CAJA CHICA'), findsNothing);
    await tester.tap(find.text('Cuenta: BANCO BNB').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Transferir'));
    await tester.pumpAndSettle();
    expect(fake.body('POST /accounts/1/transfer')['destination'], 'cuenta:2');
  });

  testWidgets('categorías: agrupadas, con periodicidad, cantidad e inactiva', (tester) async {
    await start(tester);
    await openMenu(tester, 'Finanzas');
    await goTab(tester, 'Categorías');
    for (final t in ['GASTOS GENERALES', 'SERVICIOS BÁSICOS', 'PAGOS A PROVEEDORES', 'PAGOS A PERSONAL']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('Mensual'), findsOneWidget);
    expect(find.text('Anual'), findsOneWidget);
    expect(find.text('Inactiva'), findsOneWidget);
    expect(find.text('1 gasto'), findsNWidgets(2));
    expect(find.text('Nueva categoría'), findsOneWidget);
  });

  testWidgets('nueva categoría: servicio básico anual', (tester) async {
    final fake = await start(tester);
    await openMenu(tester, 'Finanzas');
    await goTab(tester, 'Categorías');
    await tester.tap(find.text('Nueva categoría'));
    await tester.pumpAndSettle();
    expect(find.text('Mensual'), findsOneWidget, reason: 'solo la etiqueta de la lista: general no la pide');
    await tester.enterText(find.widgetWithText(TextField, 'Nombre'), 'hosting');
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Tipo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Servicio básico').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Queda pagado si hubo un pago en el mes'), findsOneWidget);
    await tester.tap(find.text('Anual').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Queda pagado por un año'), findsOneWidget);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final body = fake.body('POST /expense-categories');
    expect(body['name'], 'HOSTING');
    expect(body['type'], 'basicos');
    expect(body['frequency'], 'anual');
  });

  testWidgets('gastos: barra de 4 pestañas, número, origen y anulado', (tester) async {
    final fake = await start(tester);
    await openMenu(tester, 'Gastos');
    for (final t in ['Gastos', 'Proveedores', 'Personal', 'Servicios']) {
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(t)), findsOneWidget);
    }
    expect(fake.last('GET /expenses').url.queryParameters['group'], 'general');
    expect(find.text('Bs 100.00 · Almuerzo'), findsOneWidget);
    expect(find.text('G-000001'), findsOneWidget);
    expect(find.text('Anulado'), findsOneWidget);
    expect(find.textContaining('Caja · CAJA PRINCIPAL'), findsOneWidget);
    expect(find.textContaining('Sin origen'), findsOneWidget);
    expect(find.text('Nuevo gasto'), findsOneWidget);
  });

  testWidgets('detalle de un gasto: anular con motivo', (tester) async {
    final fake = await start(tester);
    await openMenu(tester, 'Gastos');
    await tester.tap(find.text('Bs 100.00 · Almuerzo'));
    await tester.pumpAndSettle();
    expect(find.text('Gasto G-000001'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Motivo de la anulación (opcional)'), 'Error');
    await tester.tap(find.text('Anular (vuelve a la cuenta)'));
    await tester.pumpAndSettle();
    expect(fake.body('POST /expenses/1/cancel')['cancel_reason'], 'Error');
    expect(find.text('Gasto anulado: el dinero volvió a la cuenta.'), findsOneWidget);
  });

  testWidgets('un gasto anulado no ofrece anular', (tester) async {
    await start(tester);
    await openMenu(tester, 'Gastos');
    await tester.tap(find.textContaining('Café'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Anular ('), findsNothing);
    expect(find.text('Error'), findsOneWidget);
  });

  testWidgets('alta general: categoría, descripción, propone la cuenta y avisa si no alcanza', (tester) async {
    final fake = await start(tester);
    await openMenu(tester, 'Gastos');
    await tester.tap(find.text('Nuevo gasto'));
    await tester.pumpAndSettle();
    expect(find.text('¿De dónde sale el dinero?'), findsOneWidget);
    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Categoría'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('COMIDA').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Descripción'), 'Almuerzo');
    await tester.enterText(find.widgetWithText(TextField, 'Importe'), '700');
    await tester.pumpAndSettle();
    expect(find.textContaining('no alcanza'), findsOneWidget);
    await tester.tap(find.text('Registrar'));
    await tester.pumpAndSettle();
    final body = fake.body('POST /expenses');
    expect(body['group'], 'general');
    expect(body['expense_category_id'], 1);
    expect(body['source_type'], 'cuenta');
    expect(body['financial_account_id'], 1);
    expect(body['movement_date'], today);
  });

  testWidgets('alta desde caja: dice que sale del cajón', (tester) async {
    final fake = await start(tester);
    await openMenu(tester, 'Gastos');
    await tester.tap(find.text('Nuevo gasto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Caja abierta'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CAJA PRINCIPAL · Bs 200.00'), findsOneWidget);
    expect(find.textContaining('se descuenta en el arqueo'), findsOneWidget);
    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Categoría'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('COMIDA').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrar'));
    await tester.pumpAndSettle();
    expect(fake.body('POST /expenses')['cash_session_id'], 5);
  });

  testWidgets('proveedores: sin elegir categoría, nuevo proveedor rápido', (tester) async {
    final fake = await start(tester);
    await openMenu(tester, 'Gastos');
    await goTab(tester, 'Proveedores');
    await tester.tap(find.text('Pago a proveedor'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(DropdownButtonFormField<int>, 'Categoría'), findsNothing);
    expect(find.widgetWithText(DropdownButtonFormField<int>, 'Concepto'), findsNothing);
    expect(find.text('Pago a … (se completa solo)'), findsOneWidget);
    await tester.tap(find.byTooltip('Nuevo proveedor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'nuevo');
    await tester.tap(find.widgetWithText(FilledButton, 'Crear'));
    await tester.pumpAndSettle();
    expect(fake.body('POST /suppliers')['name'], 'NUEVO');
    await tester.enterText(find.widgetWithText(TextField, 'Importe'), '50');
    await tester.tap(find.text('Registrar'));
    await tester.pumpAndSettle();
    final body = fake.body('POST /expenses');
    expect(body['group'], 'proveedor');
    expect(body['expense_category_id'], 4);
    expect(body['supplier_id'], 20);
  });

  testWidgets('personal: comisiones por pagar y liquidar', (tester) async {
    final fake = await start(tester);
    await openMenu(tester, 'Gastos');
    await goTab(tester, 'Personal');
    expect(find.text('Comisiones por pagar'), findsOneWidget);
    expect(find.textContaining('de cualquier fecha'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Pagar'));
    await tester.pumpAndSettle();
    expect(find.text('Pagar a ANA PÉREZ'), findsOneWidget);
    expect(find.text('Bs 90.00'), findsWidgets);
    await tester.tap(find.textContaining('Incluir propinas'));
    await tester.pumpAndSettle();
    expect(find.text('Bs 100.00'), findsOneWidget);
    await tester.tap(find.text('Pagar liquidación'));
    await tester.pumpAndSettle();
    final body = fake.body('POST /commissions/14/settle');
    expect(body['period_start'], '2026-09-01');
    expect(body['period_end'], today);
    expect(body['include_tips'], true);
    expect(body['financial_account_id'], 1);
    expect(find.text('Liquidación L-1 pagada.'), findsOneWidget);
  });

  testWidgets('personal sin permiso de comisiones: no pide lo pendiente', (tester) async {
    final fake = await start(tester, abilities: {...all}..remove('commissions_view'));
    await openMenu(tester, 'Gastos');
    await goTab(tester, 'Personal');
    expect(find.text('Comisiones por pagar'), findsNothing);
    expect(fake.requests.where((r) => r.url.path.endsWith('/commissions/pending')), isEmpty);
  });

  testWidgets('servicios: control del mes, Registrar con el último importe y meses', (tester) async {
    final fake = await start(tester);
    await openMenu(tester, 'Gastos');
    await goTab(tester, 'Servicios');
    expect(find.text('Noviembre 2026'), findsOneWidget);
    expect(find.textContaining('1 pagado · 1 pendiente'), findsOneWidget);
    expect(find.text('Pendiente · último Bs 65.00'), findsOneWidget);
    expect(find.text('Nuevo servicio'), findsOneWidget);
    await tester.tap(find.byTooltip('Mes anterior'));
    await tester.pumpAndSettle();
    expect(fake.last('GET /finance/basics').url.queryParameters['month'], '2026-10');

    await tester.tap(find.text('Registrar'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Pago de servicio'), findsOneWidget);
    expect(find.text('AGUA'), findsOneWidget);
    expect(find.text('65.00'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Registrar'));
    await tester.pumpAndSettle();
    expect(fake.body('POST /expenses')['expense_category_id'], 6);
    expect(fake.body('POST /expenses')['amount'], 65);
  });

  testWidgets('sucursal: solo se pregunta si hay más de una', (tester) async {
    final fake = server(all, branches: [{'id': 1, 'name': 'CENTRAL'}, {'id': 2, 'name': 'NORTE'}]);
    await start(tester, api: fake);
    await openMenu(tester, 'Gastos');
    await tester.tap(find.text('Nuevo gasto'));
    await tester.pumpAndSettle();
    expect(find.text('Sucursal'), findsOneWidget);
  });
}
