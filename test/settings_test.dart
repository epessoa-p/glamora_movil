import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glamora_movil/main.dart';
import 'package:glamora_movil/session.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_api.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  const all = {
    'dashboard': true, 'reports': true, 'clients_view': true,
    'company_view': true, 'company_edit': true,
    'branches_view': true, 'branches_create': true, 'branches_edit': true,
    'schedules_view': true, 'schedules_edit': true,
    'payment_methods_view': true, 'payment_methods_create': true, 'payment_methods_edit': true,
  };

  FakeApi server(Map<String, bool> abilities) => FakeApi()
    ..on('GET /me', meJson(abilities: abilities))
    ..on('GET /auth/companies', [companyJson])
    ..on('GET /clients', [])
    ..on('GET /dashboard', {'date': '2026-11-02', 'currency': 'Bs', 'sections': <String, bool>{}})
    ..on('GET /company', {
      'name': 'CONTRASTE', 'ruc': null, 'address': 'Av. Siempre Viva', 'phone': '7000', 'email': null, 'description': null,
      'primary_color': '#A85585', 'secondary_color': null, 'logo_url': null, 'can': {'edit': true},
    })
    ..on('PUT /company', {'message': 'Datos de la empresa actualizados.', 'name': 'CONTRASTE SPA', 'logo_url': null})
    ..on('GET /branches', {
      'branches': [
        {'id': 1, 'name': 'CENTRAL', 'code': null, 'phone': '7000', 'email': null, 'address': 'Av. 1', 'manager_name': null, 'active': true, 'warehouse': {'id': 1, 'name': 'ALMACÉN CENTRAL'}},
      ],
      'warehouses': [{'id': 1, 'name': 'ALMACÉN CENTRAL'}],
      'can': {'create': true, 'edit': true, 'plan_room': true},
    })
    ..on('POST /branches', {'message': 'Sucursal creada.', 'branch': {}}, status: 201)
    ..on('GET /schedules', {
      'people': [
        {'id': 14, 'name': 'ANA PÉREZ', 'cargo': 'Estilista', 'configured': true, 'weekdays': [1, 2, 3], 'today': {'off': null, 'blocks': [{'start': '09:00', 'end': '18:00'}]}},
      ],
      'can': {'edit': true},
    })
    ..on('GET /schedules/14', {
      'id': 14, 'name': 'ANA PÉREZ',
      'days': [
        for (final (i, l) in ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'].indexed)
          {'weekday': i + 1, 'label': l, 'on': i < 3, 'blocks': i < 3 ? [{'start': '09:00', 'end': '18:00'}] : []},
      ],
      'exceptions': [{'type': 'No trabaja', 'from': '2026-11-10', 'to': '2026-11-12', 'start': null, 'end': null, 'reason': 'Vacaciones'}],
      'can': {'edit': true},
    })
    ..on('PUT /schedules/14', {'message': 'Horario guardado.', 'days': [], 'exceptions': []})
    ..on('GET /payment-methods', {
      'methods': [
        {'id': 6, 'name': 'Efectivo', 'code': 'efectivo', 'is_system': true, 'icon': 'bi-cash-coin', 'affects_cash': true, 'is_default': true, 'active': true, 'sort_order': 10},
        {'id': 9, 'name': 'QR', 'code': 'qr', 'icon': 'bi-qr-code', 'affects_cash': false, 'is_default': false, 'active': false, 'sort_order': 40},
      ],
      'can': {'create': true, 'edit': true, 'close_settings': true},
      'close': {'mode': 'monto', 'modes': [], 'bills': [200, 100, 50, 20, 10], 'coins': [5, 2, 1, 0.5, 0.2, 0.1]},
    })
    ..on('PUT /cash-close-settings', {'message': 'Cierre de caja guardado.', 'mode': 'denominaciones', 'bills': [100], 'coins': [0.5]})
    ..on('POST /payment-methods', {'message': 'Método de pago creado.', 'method': {}}, status: 201)
    ..on('PUT /payment-methods/9', {'message': 'Método de pago actualizado.', 'method': {}});

  Future<FakeApi> start(WidgetTester tester, [Map<String, bool> abilities = all]) async {
    final fake = server(abilities);
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
    final drawer = find.byType(Drawer);
    final target = find.descendant(of: drawer, matching: find.text(item));
    await tester.scrollUntilVisible(target, 80, scrollable: find.descendant(of: drawer, matching: find.byType(Scrollable)));
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// Desplaza la lista de la pantalla de arriba hasta que se ve el widget.
  Future<void> reveal(WidgetTester tester, Finder target) async {
    final list = find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(target, 120, scrollable: list);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  testWidgets('cabecera con el nombre del personal; Reportes y Configuración junto a Cerrar sesión, sin Mi perfil', (tester) async {
    await start(tester);
    expect(find.widgetWithText(AppBar, 'ANA PÉREZ'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'CONTRASTE'), findsNothing);

    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle();
    final drawer = find.byType(Drawer);
    final scrollable = find.descendant(of: drawer, matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(find.descendant(of: drawer, matching: find.text('Cerrar sesión')), 80, scrollable: scrollable);
    expect(find.descendant(of: drawer, matching: find.text('Mi perfil')), findsNothing);
    final y = {for (final t in ['Reportes', 'Configuración', 'Cerrar sesión']) t: tester.getTopLeft(find.descendant(of: drawer, matching: find.text(t))).dy};
    expect(y['Reportes']!, lessThan(y['Configuración']!));
    expect(y['Configuración']!, lessThan(y['Cerrar sesión']!));
    // Los tres van juntos, después del último divisor.
    final dividers = find.descendant(of: drawer, matching: find.byType(Divider));
    expect(tester.getTopLeft(dividers.last).dy, lessThan(y['Reportes']!));
  });

  testWidgets('configuración: cuadros según permisos', (tester) async {
    await start(tester, {'dashboard': true, 'branches_view': true, 'schedules_view': true});
    await openMenu(tester, 'Configuración');
    expect(find.text('Sucursales'), findsOneWidget);
    expect(find.text('Horarios'), findsOneWidget);
    expect(find.text('Mi empresa'), findsNothing);
    expect(find.text('Formas de pago'), findsNothing);
  });

  testWidgets('sin ningún permiso de configuración no aparece en el menú', (tester) async {
    await start(tester, {'dashboard': true, 'clients_view': true});
    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(Drawer), matching: find.text('Configuración')), findsNothing);
    expect(find.descendant(of: find.byType(Drawer), matching: find.text('Reportes')), findsNothing);
  });

  testWidgets('mi empresa: editar y guardar', (tester) async {
    final fake = await start(tester);
    await openMenu(tester, 'Configuración');
    await tester.tap(find.text('Mi empresa'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nombre del salón'), 'CONTRASTE SPA');
    await reveal(tester, find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    final body = fake.body('PUT /company');
    expect(body['name'], 'CONTRASTE SPA');
    expect(body['primary_color'], '#A85585');
    expect(body['address'], 'Av. Siempre Viva');
    expect(find.text('Datos de la empresa actualizados.'), findsOneWidget);
  });

  testWidgets('sucursales: lista y nueva sucursal con almacén propio', (tester) async {
    final fake = await start(tester);
    await openMenu(tester, 'Configuración');
    await tester.tap(find.text('Sucursales'));
    await tester.pumpAndSettle();
    expect(find.text('CENTRAL'), findsOneWidget);
    expect(find.textContaining('Almacén: ALMACÉN CENTRAL'), findsOneWidget);
    await tester.tap(find.text('Nueva'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nombre'), 'NORTE');
    await tester.tap(find.text('Crear sucursal'));
    await tester.pumpAndSettle();
    expect(fake.body('POST /branches')['name'], 'NORTE');
    expect(fake.body('POST /branches')['warehouse_id'], isNull, reason: 'sin elegir: se crea un almacén para la sucursal');
    expect(find.widgetWithText(AppBar, 'Sucursales'), findsOneWidget);
  });

  testWidgets('horarios: activar un día copia el horario y se guarda la semana', (tester) async {
    final fake = await start(tester);
    await openMenu(tester, 'Configuración');
    await tester.tap(find.text('Horarios'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hoy: 09:00–18:00'), findsOneWidget);
    await tester.tap(find.text('ANA PÉREZ').last);
    await tester.pumpAndSettle();

    // Jueves se activa con el horario de los otros días.
    await reveal(tester, find.text('Jueves'));
    await tester.tap(find.descendant(of: find.ancestor(of: find.text('Jueves'), matching: find.byType(Card)), matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    await reveal(tester, find.textContaining('Vacaciones'));
    expect(find.textContaining('Vacaciones'), findsOneWidget);
    await tester.tap(find.text('Guardar horario'));
    await tester.pumpAndSettle();
    final days = fake.body('PUT /schedules/14')['days'] as Map<String, dynamic>;
    expect(days['4'], {'on': true, 'blocks': [{'start': '09:00', 'end': '18:00'}]});
    expect((days['5'] as Map)['on'], false);
    expect(find.widgetWithText(AppBar, 'Horarios'), findsOneWidget);
  });

  testWidgets('formas de pago: insignias, crear y reactivar conservando el código', (tester) async {
    final fake = await start(tester);
    await openMenu(tester, 'Configuración');
    await tester.tap(find.text('Formas de pago'));
    await tester.pumpAndSettle();
    expect(find.text('Predeterminada'), findsOneWidget);
    expect(find.text('Siempre habilitado'), findsOneWidget);
    expect(find.text('Inactivo'), findsOneWidget);

    await tester.tap(find.text('Nuevo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nombre'), 'Tigo Money');
    await reveal(tester, find.text('Pago por celular'));
    await tester.tap(find.text('Pago por celular'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Crear forma de pago'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear forma de pago'));
    await tester.pumpAndSettle();
    final created = fake.body('POST /payment-methods');
    expect(created['name'], 'Tigo Money');
    expect(created['icon'], 'bi-phone');
    expect(created.containsKey('code'), isFalse, reason: 'el servidor arma el código desde el nombre');

    // El aviso de «creado» tapa la parte de abajo.
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.tap(find.text('QR'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Activa'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    final updated = fake.body('PUT /payment-methods/9');
    expect(updated['active'], true);
    expect(updated['code'], 'qr');
  });
testWidgets('formas de pago: el efectivo no se desactiva ni deja de contar', (tester) async {
    final fake = await start(tester);
    await openMenu(tester, 'Configuración');
    await tester.tap(find.text('Formas de pago'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Efectivo'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Editar forma de pago'), findsOneWidget);
    final cash = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Cuenta como efectivo'));
    final active = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Activa'));
    expect(cash.onChanged, isNull);
    expect(active.onChanged, isNull);
    expect(cash.value && active.value, isTrue);
    expect(find.text('El efectivo está siempre habilitado y siempre se cuenta'), findsOneWidget);
    await reveal(tester, find.text('Guardar cambios'));
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    final sent = fake.body('PUT /payment-methods/6');
    expect(sent['active'], true);
    expect(sent['affects_cash'], true);
  });

  testWidgets('cierre de caja: elegir billetes y monedas y su lista', (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = await start(tester);
    await openMenu(tester, 'Configuración');
    await tester.tap(find.text('Formas de pago'));
    await tester.pumpAndSettle();
    expect(find.text('Cierre de caja'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Billetes'), findsNothing, reason: 'un solo monto: sin lista');
    await tester.tap(find.text('Billetes y monedas'));
    await tester.pumpAndSettle();
    expect(find.text('200, 100, 50, 20, 10'), findsOneWidget);
    expect(find.text('5, 2, 1, 0.50, 0.20, 0.10'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Billetes'), '100');
    await tester.enterText(find.widgetWithText(TextField, 'Monedas'), '0.50');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(fake.body('PUT /cash-close-settings'), {'mode': 'denominaciones', 'bills': ['100'], 'coins': ['0.50']});
    expect(find.text('Cierre de caja guardado.'), findsOneWidget);
  });

  testWidgets('cierre de caja: sin permiso de preferencias solo se ve', (tester) async {
    final fake = await start(tester);
    fake.on('GET /payment-methods', {
      'methods': [{'id': 6, 'name': 'Efectivo', 'code': 'efectivo', 'is_system': true, 'icon': 'bi-cash-coin', 'affects_cash': true, 'is_default': true, 'active': true, 'sort_order': 0}],
      'can': {'create': false, 'edit': false, 'close_settings': false},
      'close': {'mode': 'denominaciones', 'bills': [100], 'coins': [1]},
    });
    await openMenu(tester, 'Configuración');
    await tester.tap(find.text('Formas de pago'));
    await tester.pumpAndSettle();
    expect(find.text('Guardar'), findsNothing);
    expect(find.text('Solo quien edita las preferencias puede cambiarlo.'), findsOneWidget);
  });
}
