import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Error de la API ya traducido para mostrarlo al usuario.
///
/// La API de Glamora responde los errores con un `code` estable
/// (p. ej. `invalid_credentials`, `company_required`, `no_personal`) y un
/// `message` en español. Los errores de validación (422) traen además
/// `errors` por campo.
class ApiException implements Exception {
  ApiException({
    required this.status,
    required this.code,
    required this.message,
    this.fieldErrors = const {},
    this.body = const {},
  });

  /// Sin conexión, DNS, timeout…: no llegó respuesta del servidor.
  factory ApiException.network(String message) =>
      ApiException(status: 0, code: 'network', message: message);

  factory ApiException.fromResponse(int status, dynamic data) {
    final map = data is Map<String, dynamic> ? data : <String, dynamic>{};

    final errors = <String, List<String>>{};
    final rawErrors = map['errors'];
    if (rawErrors is Map) {
      rawErrors.forEach((key, value) {
        errors['$key'] = value is List ? value.map((e) => '$e').toList() : ['$value'];
      });
    }

    final code = map['code'] is String ? map['code'] as String : _defaultCode(status);

    // Laravel devuelve algunos mensajes en inglés ("Unauthenticated.",
    // "Too Many Attempts.", "Server Error"): se reemplazan.
    String message;
    if (status == 401) {
      message = 'Tu sesión expiró. Vuelve a iniciar sesión.';
    } else if (status == 429) {
      message = 'Demasiados intentos. Espera un minuto y vuelve a probar.';
    } else if (status >= 500) {
      message = 'El servidor tuvo un problema. Intenta de nuevo en unos minutos.';
    } else if (errors.isNotEmpty) {
      message = errors.values.first.first;
    } else if (map['message'] is String && (map['message'] as String).isNotEmpty) {
      message = map['message'] as String;
    } else {
      message = 'No se pudo completar la operación (error $status).';
    }

    return ApiException(status: status, code: code, message: message, fieldErrors: errors, body: map);
  }

  final int status;
  final String code;
  final String message;
  final Map<String, List<String>> fieldErrors;
  final Map<String, dynamic> body;

  bool get isNetwork => status == 0;

  /// Primer mensaje de error de un campo, o null.
  String? field(String name) => fieldErrors[name]?.first;

  static String _defaultCode(int status) => switch (status) {
        401 => 'unauthenticated',
        403 => 'forbidden',
        404 => 'not_found',
        422 => 'validation',
        429 => 'too_many_attempts',
        >= 500 => 'server_error',
        _ => 'http_$status',
      };

  @override
  String toString() => message;
}

/// Cliente HTTP de la API v1. Agrega el token (Bearer) y el salón activo
/// (X-Company-Id) a cada pedido y convierte los errores en [ApiException].
class ApiClient {
  ApiClient({
    required this.baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final Duration timeout;
  final http.Client _http;

  String? token;
  int? companyId;

  /// Se llama cuando el servidor rechaza el token (vencido o revocado).
  void Function()? onUnauthorized;

  Future<dynamic> get(String path, [Map<String, Object?>? query]) => _send('GET', path, query: query);

  Future<dynamic> post(String path, [Map<String, Object?>? body]) => _send('POST', path, body: body ?? const {});

  Future<dynamic> _send(String method, String path, {Map<String, Object?>? query, Map<String, Object?>? body}) async {
    final params = <String, String>{
      for (final e in (query ?? const {}).entries)
        if (e.value != null) e.key: '${e.value}',
    };
    var uri = Uri.parse('$baseUrl$path');
    if (params.isNotEmpty) {
      uri = uri.replace(queryParameters: params);
    }

    final request = http.Request(method, uri)
      ..headers.addAll({
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
        if (companyId != null) 'X-Company-Id': '$companyId',
      });
    if (body != null) {
      request.body = jsonEncode(body);
    }

    http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request).timeout(timeout));
    } on TimeoutException {
      throw ApiException.network('El servidor tardó demasiado en responder. Revisa tu conexión.');
    } catch (_) {
      throw ApiException.network('No se pudo conectar con el servidor. Revisa tu conexión a internet.');
    }

    dynamic data;
    if (response.bodyBytes.isNotEmpty) {
      try {
        data = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        data = null;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    final error = ApiException.fromResponse(response.statusCode, data);
    if (error.status == 401 && token != null) {
      onUnauthorized?.call();
    }
    throw error;
  }
}
