import 'util/format.dart';

// Modelos de la API v1. Solo leen JSON: la app no arma reglas de negocio,
// las aplica el servidor (horarios, choques, permisos, comisiones).

int _int(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
String? _str(dynamic v) => v == null ? null : '$v';
List<Map<String, dynamic>> _list(dynamic v) => v is List ? v.whereType<Map<String, dynamic>>().toList() : [];

/// Referencia simple (id + nombre): servicio, profesional…
class Ref {
  const Ref(this.id, this.name);

  factory Ref.fromJson(Map<String, dynamic> j) => Ref(_int(j['id']), _str(j['name']) ?? '');

  static Ref? maybe(dynamic j) => j is Map<String, dynamic> ? Ref.fromJson(j) : null;

  final int id;
  final String name;
}

class Company {
  const Company({required this.id, required this.name, this.logoUrl, this.primaryColor, this.currencySymbol = 'Bs'});

  factory Company.fromJson(Map<String, dynamic> j) => Company(
        id: _int(j['id']),
        name: _str(j['name']) ?? '',
        logoUrl: _str(j['logo_url']),
        primaryColor: _str(j['primary_color']),
        currencySymbol: _str(j['currency_symbol']) ?? 'Bs',
      );

  final int id;
  final String name;
  final String? logoUrl;
  final String? primaryColor;
  final String currencySymbol;
}

class UserInfo {
  const UserInfo({required this.id, required this.name, this.email, this.isSuperAdmin = false});

  factory UserInfo.fromJson(Map<String, dynamic> j) => UserInfo(
        id: _int(j['id']),
        name: _str(j['name']) ?? '',
        email: _str(j['email']),
        isSuperAdmin: j['is_super_admin'] == true,
      );

  final int id;
  final String name;
  final String? email;
  final bool isSuperAdmin;
}

class PersonalInfo {
  const PersonalInfo({required this.id, required this.fullName, this.cargo});

  factory PersonalInfo.fromJson(Map<String, dynamic> j) =>
      PersonalInfo(id: _int(j['id']), fullName: _str(j['full_name']) ?? '', cargo: _str(j['cargo']));

  final int id;
  final String fullName;
  final String? cargo;
}

/// Perfil de la sesión (`GET /me`): con `abilities` la app arma su menú.
class Me {
  const Me({required this.user, required this.company, this.personal, this.abilities = const {}});

  factory Me.fromJson(Map<String, dynamic> j) => Me(
        user: UserInfo.fromJson(j['user'] as Map<String, dynamic>),
        company: Company.fromJson(j['company'] as Map<String, dynamic>),
        personal: j['personal'] is Map<String, dynamic> ? PersonalInfo.fromJson(j['personal'] as Map<String, dynamic>) : null,
        abilities: {
          for (final e in ((j['abilities'] as Map?) ?? const {}).entries) '${e.key}': e.value == true,
        },
      );

  final UserInfo user;
  final Company company;
  final PersonalInfo? personal;
  final Map<String, bool> abilities;

  bool can(String ability) => abilities[ability] ?? false;

  bool get seesAgenda => can('agenda_own') || can('agenda_all');
}

class ClientInfo {
  const ClientInfo({required this.id, required this.name, this.phone, this.document, this.email});

  factory ClientInfo.fromJson(Map<String, dynamic> j) => ClientInfo(
        id: _int(j['id']),
        name: _str(j['name']) ?? '',
        phone: _str(j['phone']),
        document: _str(j['document']),
        email: _str(j['email']),
      );

  final int id;
  final String name;
  final String? phone;
  final String? document;
  final String? email;
}

class Appointment {
  const Appointment({
    required this.id,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.statusLabel,
    required this.statusColor,
    this.price = 0,
    this.notes,
    this.outsideSchedule = false,
    this.isMine = false,
    this.client,
    this.service,
    this.personal,
  });

  factory Appointment.fromJson(Map<String, dynamic> j) => Appointment(
        id: _int(j['id']),
        startsAt: wallTime(j['starts_at'] as String),
        endsAt: wallTime(j['ends_at'] as String),
        status: _str(j['status']) ?? '',
        statusLabel: _str(j['status_label']) ?? '',
        statusColor: _str(j['status_color']),
        price: _num(j['price']),
        notes: _str(j['notes']),
        outsideSchedule: j['outside_schedule'] == true,
        isMine: j['is_mine'] == true,
        client: j['client'] is Map<String, dynamic> ? ClientInfo.fromJson(j['client'] as Map<String, dynamic>) : null,
        service: Ref.maybe(j['service']),
        personal: Ref.maybe(j['personal']),
      );

  final int id;

  /// Hora del salón (sin zona): así la guarda el servidor.
  final DateTime startsAt;
  final DateTime endsAt;
  final String status;
  final String statusLabel;
  final String? statusColor;
  final double price;
  final String? notes;
  final bool outsideSchedule;
  final bool isMine;
  final ClientInfo? client;
  final Ref? service;
  final Ref? personal;
}

class ServiceOption {
  const ServiceOption({required this.id, required this.name, this.price = 0, this.duration});

  factory ServiceOption.fromJson(Map<String, dynamic> j) => ServiceOption(
        id: _int(j['id']),
        name: _str(j['name']) ?? '',
        price: _num(j['price']),
        duration: j['duration'] == null ? null : _int(j['duration']),
      );

  final int id;
  final String name;
  final double price;
  final int? duration;
}

class StatusOption {
  const StatusOption(this.key, this.label, this.color);

  factory StatusOption.fromJson(Map<String, dynamic> j) =>
      StatusOption(_str(j['key']) ?? '', _str(j['label']) ?? '', _str(j['color']));

  final String key;
  final String label;
  final String? color;
}

/// Datos para agendar (`GET /agenda/options`).
class AgendaOptions {
  const AgendaOptions({this.services = const [], this.specialists = const [], this.statuses = const []});

  factory AgendaOptions.fromJson(Map<String, dynamic> j) => AgendaOptions(
        services: _list(j['services']).map(ServiceOption.fromJson).toList(),
        specialists: _list(j['specialists']).map(Ref.fromJson).toList(),
        statuses: _list(j['statuses']).map(StatusOption.fromJson).toList(),
      );

  final List<ServiceOption> services;
  final List<Ref> specialists;
  final List<StatusOption> statuses;
}

class TimeBlock {
  const TimeBlock(this.start, this.end, [this.label]);

  factory TimeBlock.fromJson(Map<String, dynamic> j) =>
      TimeBlock(_str(j['start']) ?? '', _str(j['end']) ?? '', _str(j['label']));

  final String start;
  final String end;
  final String? label;

  @override
  String toString() => '$start–$end';
}

/// Horario y citas de un profesional en un día (`GET /agenda/availability`).
class DayAvailability {
  const DayAvailability({this.configured = false, this.off, this.special = false, this.blocks = const [], this.busy = const []});

  factory DayAvailability.fromJson(Map<String, dynamic> j) => DayAvailability(
        configured: j['configured'] == true,
        off: _str(j['off']),
        special: j['special'] == true,
        blocks: _list(j['blocks']).map(TimeBlock.fromJson).toList(),
        busy: _list(j['busy']).map(TimeBlock.fromJson).toList(),
      );

  final bool configured;
  final String? off;
  final bool special;
  final List<TimeBlock> blocks;
  final List<TimeBlock> busy;
}

class AttendanceRecord {
  const AttendanceRecord(this.checkIn, this.checkOut, this.edited);

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) =>
      AttendanceRecord(_str(j['check_in']) ?? '', _str(j['check_out']), j['edited'] == true);

  final String checkIn;
  final String? checkOut;
  final bool edited;
}

class AttendanceDay {
  const AttendanceDay({
    required this.date,
    required this.state,
    required this.label,
    this.blocks = const [],
    this.late = 0,
    this.worked = 0,
    this.records = const [],
  });

  factory AttendanceDay.fromJson(Map<String, dynamic> j) => AttendanceDay(
        date: DateTime.parse(j['date'] as String),
        state: _str(j['state']) ?? '',
        label: _str(j['label']) ?? '',
        blocks: _list(j['blocks']).map(TimeBlock.fromJson).toList(),
        late: _int(j['late']),
        worked: _int(j['worked']),
        records: _list(j['records']).map(AttendanceRecord.fromJson).toList(),
      );

  final DateTime date;

  /// working · present · late · absent · missing · pending · off · rest · free
  final String state;
  final String label;
  final List<TimeBlock> blocks;
  final int late;
  final int worked;
  final List<AttendanceRecord> records;
}

class AttendanceSummary {
  const AttendanceSummary({
    this.openSince,
    this.today,
    this.workedDays = 0,
    this.hoursLabel = '',
    this.lateDays = 0,
    this.lateMinutes = 0,
    this.absences = 0,
    this.days = const [],
  });

  factory AttendanceSummary.fromJson(Map<String, dynamic> j) {
    final totals = (j['totals'] as Map<String, dynamic>?) ?? const {};
    final open = j['open'];

    return AttendanceSummary(
      openSince: open is Map<String, dynamic> ? wallTime(open['check_in'] as String) : null,
      today: j['today'] is Map<String, dynamic> ? AttendanceDay.fromJson(j['today'] as Map<String, dynamic>) : null,
      workedDays: _int(totals['worked_days']),
      hoursLabel: _str(totals['hours_label']) ?? '',
      lateDays: _int(totals['late_days']),
      lateMinutes: _int(totals['late_min']),
      absences: _int(totals['absences']),
      days: _list(j['days']).map(AttendanceDay.fromJson).toList(),
    );
  }

  /// Hora de la entrada sin salida, si está en turno.
  final DateTime? openSince;
  final AttendanceDay? today;
  final int workedDays;
  final String hoursLabel;
  final int lateDays;
  final int lateMinutes;
  final int absences;
  final List<AttendanceDay> days;

  bool get isWorking => openSince != null;
}

class CommissionItem {
  const CommissionItem({
    required this.id,
    this.date,
    this.sale,
    required this.concept,
    this.base = 0,
    this.rate = '',
    this.amount = 0,
    this.pending = true,
    this.status = '',
    this.reversal = false,
  });

  factory CommissionItem.fromJson(Map<String, dynamic> j) => CommissionItem(
        id: _int(j['id']),
        date: j['date'] == null ? null : DateTime.tryParse('${j['date']}'),
        sale: _str(j['sale']),
        concept: _str(j['concept']) ?? '',
        base: _num(j['base']),
        rate: _str(j['rate']) ?? '',
        amount: _num(j['amount']),
        pending: j['pending'] == true,
        status: _str(j['status']) ?? '',
        reversal: j['reversal'] == true,
      );

  final int id;
  final DateTime? date;
  final String? sale;
  final String concept;
  final double base;
  final String rate;
  final double amount;
  final bool pending;
  final String status;
  final bool reversal;
}

class CommissionReport {
  const CommissionReport({
    this.currency = 'Bs',
    this.earned = 0,
    this.pending = 0,
    this.settled = 0,
    this.tips = 0,
    this.items = const [],
  });

  factory CommissionReport.fromJson(Map<String, dynamic> j) {
    final k = (j['kpis'] as Map<String, dynamic>?) ?? const {};

    return CommissionReport(
      currency: _str(j['currency']) ?? 'Bs',
      earned: _num(k['earned']),
      pending: _num(k['pending']),
      settled: _num(k['settled']),
      tips: _num(k['tips']),
      items: _list(j['items']).map(CommissionItem.fromJson).toList(),
    );
  }

  final String currency;
  final double earned;
  final double pending;
  final double settled;
  final double tips;
  final List<CommissionItem> items;
}
