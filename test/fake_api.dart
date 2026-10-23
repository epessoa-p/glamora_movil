import 'dart:convert';

import 'package:glamora_movil/api/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Servidor falso: responde según "MÉTODO /ruta" y registra cada pedido.
class FakeApi {
  final routes = <String, http.Response Function(http.Request)>{};
  final requests = <http.Request>[];

  void on(String route, Object body, {int status = 200}) {
    routes[route] = (_) => json(body, status: status);
  }

  static http.Response json(Object body, {int status = 200}) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  ApiClient client() => ApiClient(
        baseUrl: 'https://test.local/api/v1',
        httpClient: MockClient((request) async {
          requests.add(request);
          final key = '${request.method} ${request.url.path.replaceFirst('/api/v1', '')}';
          final handler = routes[key];
          return handler == null ? json({'message': 'Not Found'}, status: 404) : handler(request);
        }),
      );

  http.Request last(String route) => requests.lastWhere((r) => '${r.method} ${r.url.path.replaceFirst('/api/v1', '')}' == route);

  Map<String, dynamic> body(String route) => jsonDecode(last(route).body) as Map<String, dynamic>;
}

Map<String, dynamic> meJson({Map<String, bool>? abilities, bool personal = true}) => {
      'user': {'id': 4, 'name': 'ana', 'email': 'ana@test', 'is_super_admin': false},
      'company': {'id': 2, 'name': 'CONTRASTE', 'logo_url': null, 'primary_color': '#A85585', 'secondary_color': null, 'currency_symbol': 'Bs'},
      'personal': personal ? {'id': 14, 'full_name': 'ANA PÉREZ', 'cargo': 'Estilista'} : null,
      'abilities': abilities ??
          {
            'agenda_own': true,
            'agenda_all': false,
            'appointments_create': true,
            'appointments_edit': false,
            'clients_view': true,
            'clients_create': true,
            'attendance': true,
            'commissions_own': true,
          },
    };

const companyJson = {'id': 2, 'name': 'CONTRASTE', 'logo_url': null, 'primary_color': '#A85585', 'secondary_color': null};

Map<String, dynamic> appointmentJson({int id = 12, String status = 'pendiente', String start = '2026-10-22T10:00:00-04:00'}) => {
      'id': id,
      'starts_at': start,
      'ends_at': '2026-10-22T10:45:00-04:00',
      'status': status,
      'status_label': status == 'pendiente' ? 'Pendiente' : 'Confirmada',
      'status_color': status == 'pendiente' ? '#f59e0b' : '#3b82f6',
      'price': 100,
      'notes': null,
      'outside_schedule': false,
      'is_mine': true,
      'client': {'id': 7, 'name': 'MARÍA LÓPEZ', 'phone': '70000001'},
      'service': {'id': 21, 'name': 'CORTE'},
      'personal': {'id': 14, 'name': 'ANA PÉREZ'},
    };
