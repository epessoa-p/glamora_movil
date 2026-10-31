import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glamora_movil/api/api_client.dart';
import 'package:glamora_movil/main.dart';
import 'package:glamora_movil/session.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_api.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  test('upload envía multipart con token, salón, archivo y campos', () async {
    late http.BaseRequest seen;
    final api = ApiClient(
      baseUrl: 'https://x/api/v1',
      httpClient: MockClient.streaming((request, body) async {
        seen = request;
        final bytes = await body.toBytes();
        expect(String.fromCharCodes(bytes), contains('name="kind"'));
        expect(String.fromCharCodes(bytes), contains('filename="foto.jpg"'));
        return http.StreamedResponse(Stream.value('{"id":5}'.codeUnits), 201, headers: {'content-type': 'application/json'});
      }),
    )
      ..token = 'tok'
      ..companyId = 2;

    final res = await api.upload('/clients/7/photos', field: 'photo', bytes: [1, 2, 3], filename: 'foto.jpg', fields: {'kind': 'after'});
    expect(res['id'], 5);
    expect(seen.headers['Authorization'], 'Bearer tok');
    expect(seen.headers['X-Company-Id'], '2');
    expect(seen.headers['Content-Type'], startsWith('multipart/form-data'));
  });

  testWidgets('ficha del cliente: galería, visor y eliminar foto', (tester) async {
    final fake = FakeApi()
      ..on('GET /me', meJson(abilities: {'agenda_own': true, 'clients_view': true, 'photos_view': true, 'photos_create': true, 'photos_delete': true}))
      ..on('GET /auth/companies', [companyJson])
      ..on('GET /agenda', {'appointments': []})
      ..on('GET /agenda/options', {'services': [], 'specialists': [], 'statuses': []})
      ..on('GET /clients', [{'id': 7, 'name': 'MARÍA LÓPEZ', 'phone': '70000001', 'document': null, 'email': null}])
      ..on('GET /clients/7', {
        'client': {'id': 7, 'name': 'MARÍA LÓPEZ', 'phone': '70000001'}, 'currency': 'Bs',
        'stats': {'visits': 0, 'last_visit': null, 'purchases': null, 'spent': null},
        'appointments': [], 'sales': null, 'membership': null, 'packages': [], 'points': null, 'credit': null, 'account': null,
      })
      ..on('GET /clients/7/photos', [
        {'id': 1, 'kind': 'before', 'kind_label': 'Antes', 'taken_on': '2026-10-20', 'notes': 'uñas', 'service': 'MANICURA', 'url': 'https://x/p/1', 'thumb_url': 'https://x/p/1/t'},
        {'id': 2, 'kind': 'after', 'kind_label': 'Después', 'taken_on': '2026-10-20', 'notes': null, 'service': null, 'url': 'https://x/p/2', 'thumb_url': 'https://x/p/2/t'},
      ])
      ..on('DELETE /photos/1', {'message': 'Foto eliminada.'});

    final store = MemorySessionStore()..values.addAll({'token': 't', 'company_id': '2'});
    final session = Session(fake.client(), store);
    await tester.pumpWidget(GlamoraApp(session: session));
    await session.restore();
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Clientes')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MARÍA LÓPEZ').last);
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(find.byKey(const ValueKey('photo-2')), find.byType(ListView).last, const Offset(0, -200));
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Fotos antes / después'), findsOneWidget);
    expect(find.text('Agregar'), findsOneWidget);
    expect(find.byKey(const ValueKey('photo-1')), findsOneWidget);
    expect(find.text('Antes'), findsOneWidget);
    expect(find.text('Después'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('photo-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Antes ·'), findsOneWidget);
    expect(find.text('MANICURA · uñas'), findsOneWidget);

    await tester.tap(find.byTooltip('Eliminar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();
    expect(fake.requests.any((r) => r.method == 'DELETE' && r.url.path.endsWith('/photos/1')), isTrue);
    expect(find.text('Foto eliminada.'), findsOneWidget);
  });
}
