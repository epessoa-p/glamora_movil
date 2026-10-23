// Prueba contra un servidor real (opcional). Se salta si no se define:
//   GLAMORA_LIVE_API=http://127.0.0.1:8000/api/v1
//   GLAMORA_LIVE_USER=correo   GLAMORA_LIVE_PASS=clave
// Crea una cita y un cliente de prueba: usar solo en una base de desarrollo.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glamora_movil/api/api_client.dart';
import 'package:glamora_movil/models.dart';
import 'package:glamora_movil/session.dart';
import 'package:glamora_movil/util/format.dart';

void main() {
  final env = Platform.environment;
  final url = env['GLAMORA_LIVE_API'];
  final skip = url == null ? 'Define GLAMORA_LIVE_API para probar contra un servidor real' : null;

  test('flujo completo contra el servidor', () async {
    final api = ApiClient(baseUrl: url!);
    final session = Session(api, MemorySessionStore());

    await expectLater(session.login(env['GLAMORA_LIVE_USER']!, 'clave-mala'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'invalid_credentials')));

    await session.login(env['GLAMORA_LIVE_USER']!, env['GLAMORA_LIVE_PASS']!, deviceName: 'Prueba Flutter');
    expect(session.status, SessionStatus.ready, reason: session.error);
    final me = session.me!;
    expect(me.personal, isNotNull);

    final options = AgendaOptions.fromJson(await api.get('/agenda/options') as Map<String, dynamic>);
    expect(options.statuses, isNotEmpty);

    final client = ClientInfo.fromJson(await api.post('/clients', {'full_name': 'prueba flutter', 'phone': '70000009'}) as Map<String, dynamic>);
    expect(client.name, 'PRUEBA FLUTTER');
    final found = (await api.get('/clients', {'q': 'prueba flutter'}) as List).map((j) => ClientInfo.fromJson(j as Map<String, dynamic>));
    expect(found.map((c) => c.id), contains(client.id));

    // Mañana 11:00 hora del salón: debe volver exactamente a las 11:00.
    final tomorrow = dateOnly(DateTime.now()).add(const Duration(days: 1));
    final start = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 11);
    final body = {
      'client_id': client.id,
      'service_id': options.services.isEmpty ? null : options.services.first.id,
      'personal_id': me.personal!.id,
      'starts_at': wallIso(start),
    };
    Appointment created;
    try {
      created = Appointment.fromJson(await api.post('/appointments', body) as Map<String, dynamic>);
    } on ApiException catch (e) {
      expect(e.field('outside_schedule'), isNotNull, reason: e.message);
      created = Appointment.fromJson(await api.post('/appointments', {...body, 'force_outside': true}) as Map<String, dynamic>);
    }
    expect(hm(created.startsAt), '11:00');
    expect(created.isMine, isTrue);

    await expectLater(api.post('/appointments', body),
        throwsA(isA<ApiException>().having((e) => e.field('starts_at'), 'choque', contains('ya tiene una cita'))));

    final agenda = await api.get('/agenda', {'date': ymd(tomorrow), 'personal_id': me.personal!.id}) as Map<String, dynamic>;
    expect((agenda['appointments'] as List).map((a) => a['id']), contains(created.id));

    final cancelled = Appointment.fromJson(await api.post('/appointments/${created.id}/status', {'status': 'cancelada'}) as Map<String, dynamic>);
    expect(cancelled.status, 'cancelada');

    final attendance = AttendanceSummary.fromJson(await api.get('/attendance') as Map<String, dynamic>);
    expect(attendance.hoursLabel, isNotEmpty);

    if (me.can('commissions_own')) {
      final report = CommissionReport.fromJson(await api.get('/commissions') as Map<String, dynamic>);
      expect(report.currency, isNotEmpty);
    }

    await session.logout();
    expect(session.status, SessionStatus.loggedOut);
    await expectLater(ApiClient(baseUrl: url).get('/me'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));

    // ignore: avoid_print
    print('OK · cita ${created.id} · cliente ${client.id}');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}
