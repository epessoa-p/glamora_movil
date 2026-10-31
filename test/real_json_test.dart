// Lee respuestas reales del servidor guardadas en un archivo (opcional).
//   GLAMORA_JSON_DIR=carpeta flutter test test/real_json_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glamora_movil/models.dart';

void main() {
  final dir = Platform.environment['GLAMORA_JSON_DIR'];
  final skip = dir == null ? 'Define GLAMORA_JSON_DIR con client_profile.json y agenda_real.json' : null;

  test('ficha del cliente y agenda reales se leen sin errores', () {
    final profile = ClientProfile.fromJson(jsonDecode(File('$dir/client_profile.json').readAsStringSync()) as Map<String, dynamic>);
    expect(profile.client.name, isNotEmpty);
    expect(profile.visits, 1);
    expect(profile.spent, 80);
    expect(profile.appointments, hasLength(3));
    expect(profile.sales, hasLength(1));
    expect(profile.lastVisit, isNotNull);

    final agenda = jsonDecode(File('$dir/agenda_real.json').readAsStringSync()) as Map<String, dynamic>;
    final items = (agenda['appointments'] as List).map((j) => Appointment.fromJson(j as Map<String, dynamic>)).toList();
    expect(items, isNotEmpty);
    expect(items.every((a) => a.endsAt.isAfter(a.startsAt)), isTrue);
  }, skip: skip);
}
