import 'package:flutter_test/flutter_test.dart';
import 'package:glamora_movil/api/api_client.dart';
import 'package:glamora_movil/models.dart';
import 'package:glamora_movil/session.dart';
import 'package:glamora_movil/util/format.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_api.dart';

void main() {
  group('ApiClient', () {
    test('envía token, salón y JSON; omite parámetros nulos', () async {
      final fake = FakeApi()..on('GET /agenda', {'appointments': []});
      final api = fake.client()
        ..token = 'abc'
        ..companyId = 2;

      await api.get('/agenda', {'date': '2026-10-22', 'personal_id': null});

      final r = fake.last('GET /agenda');
      expect(r.headers['Authorization'], 'Bearer abc');
      expect(r.headers['X-Company-Id'], '2');
      expect(r.headers['Accept'], 'application/json');
      expect(r.url.queryParameters, {'date': '2026-10-22'});
    });

    test('422 de validación: mensaje del primer campo y errores por campo', () async {
      final fake = FakeApi()
        ..on('POST /appointments', {
          'message': 'The given data was invalid.',
          'errors': {
            'starts_at': ['ANA ya tiene una cita de 10:00 a 10:45.'],
          },
        }, status: 422);

      final error = await fake.client().post('/appointments', {}).then<ApiException?>((_) => null, onError: (e) => e as ApiException);

      expect(error!.status, 422);
      expect(error.code, 'validation');
      expect(error.message, 'ANA ya tiene una cita de 10:00 a 10:45.');
      expect(error.field('starts_at'), contains('ya tiene una cita'));
    });

    test('respeta el code de la API y traduce mensajes de Laravel', () async {
      final fake = FakeApi()
        ..on('GET /me', {'code': 'company_required', 'message': 'Elige un salón.'}, status: 409)
        ..on('GET /clients', {'message': 'Too Many Attempts.'}, status: 429);
      final api = fake.client();

      await expectLater(api.get('/me'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'company_required').having((e) => e.message, 'message', 'Elige un salón.')));
      await expectLater(api.get('/clients'), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('Demasiados intentos'))));
    });

    test('sin conexión → ApiException de red', () async {
      final api = ApiClient(baseUrl: 'https://x', httpClient: MockClient((_) async => throw http.ClientException('offline')));

      await expectLater(api.get('/me'), throwsA(isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true)));
    });

    test('401 con token avisa a la sesión', () async {
      final fake = FakeApi()..on('GET /me', {'message': 'Unauthenticated.'}, status: 401);
      var called = false;
      final api = fake.client()
        ..token = 'viejo'
        ..onUnauthorized = () => called = true;

      await expectLater(api.get('/me'), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('sesión expiró'))));
      expect(called, isTrue);
    });
  });

  group('Session', () {
    test('login con un solo salón entra directo y guarda token', () async {
      final fake = FakeApi()
        ..on('POST /auth/login', {'token': '1|tok', 'expires_at': null, 'user': {}, 'companies': [companyJson]})
        ..on('GET /me', meJson());
      final store = MemorySessionStore();
      final session = Session(fake.client(), store);

      await session.login(' ana@test ', 'secreta');

      expect(session.status, SessionStatus.ready);
      expect(session.me!.personal!.fullName, 'ANA PÉREZ');
      expect(store.values, {'token': '1|tok', 'company_id': '2'});
      expect(fake.body('POST /auth/login')['login'], 'ana@test');
      expect(fake.last('GET /me').headers['X-Company-Id'], '2');
    });

    test('login con varios salones pide elegir', () async {
      final fake = FakeApi()
        ..on('POST /auth/login', {
          'token': 't',
          'companies': [companyJson, {'id': 3, 'name': 'OTRO'}],
        });
      final session = Session(fake.client(), MemorySessionStore());

      await session.login('ana', 'x');

      expect(session.status, SessionStatus.choosingCompany);
      expect(session.companies.map((c) => c.name), ['CONTRASTE', 'OTRO']);
    });

    test('restaurar con token vencido vuelve al login con aviso', () async {
      final fake = FakeApi()..on('GET /me', {'message': 'Unauthenticated.'}, status: 401);
      final store = MemorySessionStore()..values.addAll({'token': 'viejo', 'company_id': '2'});
      final session = Session(fake.client(), store);

      await session.restore();
      await Future<void>.delayed(Duration.zero);

      expect(session.status, SessionStatus.loggedOut);
      expect(session.notice, contains('expiró'));
      expect(store.values, isEmpty);
    });

    test('salón bloqueado → selector con el motivo', () async {
      final fake = FakeApi()
        ..on('GET /me', {'code': 'subscription_blocked', 'message': 'La suscripción del salón está suspendida.'}, status: 402)
        ..on('GET /auth/companies', [companyJson]);
      final store = MemorySessionStore()..values.addAll({'token': 't', 'company_id': '2'});
      final session = Session(fake.client(), store);

      await session.restore();

      expect(session.status, SessionStatus.choosingCompany);
      expect(session.error, contains('suspendida'));
      expect(store.values.containsKey('company_id'), isFalse);
    });

    test('logout revoca en el servidor y limpia aunque no haya red', () async {
      final api = ApiClient(baseUrl: 'https://x', httpClient: MockClient((_) async => throw http.ClientException('offline')))..token = 't';
      final store = MemorySessionStore()..values['token'] = 't';
      final session = Session(api, store);

      await session.logout();

      expect(session.status, SessionStatus.loggedOut);
      expect(api.token, isNull);
      expect(store.values, isEmpty);
    });
  });

  group('Modelos y formato', () {
    test('la hora de la cita es la del salón, no la del celular', () {
      final a = Appointment.fromJson(appointmentJson(start: '2026-10-22T10:00:00-04:00'));
      expect(hm(a.startsAt), '10:00');
      expect(a.startsAt.isUtc, isFalse);
      expect(wallIso(a.startsAt), '2026-10-22T10:00:00');
    });

    test('abilities y dinero', () {
      final me = Me.fromJson(meJson(abilities: {'agenda_all': true}));
      expect(me.seesAgenda, isTrue);
      expect(me.can('attendance'), isFalse);
      expect(money(1250.5), 'Bs 1,250.50');
      expect(hexColor('#3b82f6').toARGB32(), 0xFF3B82F6);
    });
  });
}
