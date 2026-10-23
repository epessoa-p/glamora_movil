import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Hora "de pared" del salón. El servidor manda `2026-10-22T10:00:00-04:00`;
/// se toma la fecha y hora tal cual, sin pasarla a la zona del celular,
/// para que la app muestre lo mismo que la agenda web.
DateTime wallTime(String iso) => DateTime.parse(iso.length >= 19 ? iso.substring(0, 19) : iso);

/// `2026-10-22`
String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// `2026-10-22T10:30:00` — sin zona: el servidor la toma como hora del salón.
String wallIso(DateTime d) => DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(d);

/// `10:30`
String hm(DateTime d) => DateFormat('HH:mm').format(d);

/// `Miércoles 22 de octubre`
String longDay(DateTime d) => _capitalize(DateFormat("EEEE d 'de' MMMM", 'es').format(d));

/// `Mié 22 oct`
String shortDay(DateTime d) => _capitalize(DateFormat('EEE d MMM', 'es').format(d).replaceAll('.', ''));

/// `Octubre 2026`
String monthName(DateTime d) => _capitalize(DateFormat('MMMM yyyy', 'es').format(d));

/// `Bs 1,250.00` (mismo formato que la web).
String money(num value, [String symbol = 'Bs']) => '$symbol ${NumberFormat('#,##0.00', 'en_US').format(value)}';

/// `1 h 25 min`
String duration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// `#3b82f6` → Color. Si no se puede leer, [fallback].
Color hexColor(String? hex, [Color fallback = Colors.grey]) {
  if (hex == null) return fallback;
  final clean = hex.replaceFirst('#', '');
  final value = int.tryParse(clean.length == 6 ? 'FF$clean' : clean, radix: 16);
  return value == null ? fallback : Color(value);
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return (parts.first[0] + (parts.length > 1 ? parts[1][0] : '')).toUpperCase();
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
