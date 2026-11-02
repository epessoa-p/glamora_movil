import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api/api_client.dart';
import 'models.dart';

/// Dónde se guarda el token entre aperturas de la app.
abstract class SessionStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

/// Almacenamiento cifrado del sistema (Keystore en Android, Keychain en iOS).
class SecureSessionStore implements SessionStore {
  const SecureSessionStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String? value) =>
      value == null ? _storage.delete(key: key) : _storage.write(key: key, value: value);
}

/// Para pruebas.
class MemorySessionStore implements SessionStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async =>
      value == null ? values.remove(key) : values[key] = value;
}

enum SessionStatus { starting, loggedOut, choosingCompany, ready, failed }

/// Estado de la sesión: token, salón activo y perfil (`/me`).
class Session extends ChangeNotifier {
  Session(this.api, this.store) {
    api.onUnauthorized = () => _clear(notice: 'Tu sesión expiró. Vuelve a iniciar sesión.');
  }

  static const _tokenKey = 'token';
  static const _companyKey = 'company_id';

  final ApiClient api;
  final SessionStore store;

  SessionStatus status = SessionStatus.starting;
  List<Company> companies = [];
  Me? me;

  /// Error que impide continuar (pantalla de reintento o selector de salón).
  String? error;

  /// Aviso para la pantalla de inicio de sesión (p. ej. sesión vencida).
  String? notice;

  /// Turnos de caja abiertos del salón (para el botón de caja de la cabecera).
  List<({int id, String name})> openCash = [];

  /// Vuelve a consultar qué cajas están abiertas (solo con permiso de caja).
  Future<void> refreshCash() async {
    if (!(me?.can('cash_view') ?? false)) {
      openCash = [];
      return;
    }
    try {
      final d = await api.get('/cash') as Map<String, dynamic>;
      if (me == null) return; // se cerró la sesión mientras tanto
      openCash = [
        for (final r in (d['registers'] as List).cast<Map<String, dynamic>>())
          if (r['session'] is Map) (id: (r['session'] as Map)['id'] as int, name: '${r['name']}'),
      ];
      notifyListeners();
    } on ApiException {
      // Sin red o sin acceso: se conserva lo último conocido.
    }
  }

  /// Al abrir la app: si hay token guardado, se valida con `/me`.
  Future<void> restore() async {
    final token = await store.read(_tokenKey);
    if (token == null) {
      _set(SessionStatus.loggedOut);
      return;
    }
    api.token = token;
    api.companyId = int.tryParse(await store.read(_companyKey) ?? '');
    await _loadMe();
  }

  /// Lanza [ApiException] con el motivo si no puede entrar.
  Future<void> login(String login, String password, {String deviceName = 'App Glamora'}) async {
    final data = await api.post('/auth/login', {
      'login': login.trim(),
      'password': password,
      'device_name': deviceName,
    }) as Map<String, dynamic>;

    api.token = data['token'] as String;
    await store.write(_tokenKey, api.token);
    notice = null;
    companies = (data['companies'] as List).whereType<Map<String, dynamic>>().map(Company.fromJson).toList();

    if (companies.length == 1) {
      await selectCompany(companies.first);
    } else {
      api.companyId = null;
      error = null;
      _set(SessionStatus.choosingCompany);
    }
  }

  Future<void> selectCompany(Company company) async {
    api.companyId = company.id;
    await store.write(_companyKey, '${company.id}');
    await _loadMe();
  }

  /// Vuelve al selector de salón.
  Future<void> switchCompany() async {
    await _fetchCompanies();
    error = null;
    _set(SessionStatus.choosingCompany);
  }

  Future<void> refresh() => _loadMe();

  Future<void> logout() async {
    try {
      await api.post('/auth/logout');
    } catch (_) {
      // Sin conexión el token queda vivo en el servidor hasta vencer; igual se olvida aquí.
    }
    await _clear();
  }

  Future<void> _loadMe() async {
    try {
      me = Me.fromJson(await api.get('/me') as Map<String, dynamic>);
      api.companyId = me!.company.id;
      await store.write(_companyKey, '${me!.company.id}');
      error = null;
      if (companies.isEmpty) {
        await _fetchCompanies();
      }
      _set(SessionStatus.ready);
      refreshCash();
    } on ApiException catch (e) {
      if (e.status == 401) {
        return; // onUnauthorized ya cerró la sesión.
      }
      const pickAnother = {'company_required', 'company_forbidden', 'subscription_blocked'};
      if (pickAnother.contains(e.code)) {
        api.companyId = null;
        await store.write(_companyKey, null);
        await _fetchCompanies();
        error = e.code == 'company_required' ? null : e.message;
        _set(SessionStatus.choosingCompany);
        return;
      }
      error = e.message;
      _set(SessionStatus.failed);
    }
  }

  Future<void> _fetchCompanies() async {
    try {
      final list = await api.get('/auth/companies') as List;
      companies = list.whereType<Map<String, dynamic>>().map(Company.fromJson).toList();
    } on ApiException {
      // Se conserva la lista anterior.
    }
  }

  Future<void> _clear({String? notice}) async {
    api.token = null;
    api.companyId = null;
    me = null;
    companies = [];
    openCash = [];
    error = null;
    this.notice = notice;
    await store.write(_tokenKey, null);
    await store.write(_companyKey, null);
    _set(SessionStatus.loggedOut);
  }

  void _set(SessionStatus s) {
    status = s;
    notifyListeners();
  }
}
