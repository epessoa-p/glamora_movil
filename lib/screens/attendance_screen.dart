import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/shell.dart';
import 'schedule_screen.dart';

/// Marcar entrada/salida y ver el resumen del mes.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  AttendanceSummary? _data;
  bool _loading = true;
  bool _marking = false;
  String? _error;
  Timer? _ticker;

  ApiClient get _api => context.read<Session>().api;

  @override
  void initState() {
    super.initState();
    _load();
    // Refresca el "llevas X h" cada minuto.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && (_data?.isWorking ?? false)) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.get('/attendance');
      if (mounted) setState(() => _data = AttendanceSummary.fromJson(data as Map<String, dynamic>));
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _mark() async {
    final working = _data?.isWorking ?? false;
    final ok = await confirm(
      context,
      title: working ? 'Marcar salida' : 'Marcar entrada',
      message: working
          ? '¿Terminas tu turno ahora (${hm(DateTime.now())})?'
          : '¿Registrar tu entrada ahora (${hm(DateTime.now())})?',
      ok: working ? 'Marcar salida' : 'Marcar entrada',
    );
    if (!ok || !mounted) return;

    setState(() => _marking = true);
    try {
      // La acción explícita evita marcar dos veces si la pantalla quedó vieja.
      final data = await _api.post('/attendance', {'action': working ? 'out' : 'in'}) as Map<String, dynamic>;
      if (!mounted) return;
      showMessage(context, '${data['message']}');
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _marking = false);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: shellLeading(context),
        title: const Text('Asistencia'),
        actions: [
          if (context.read<Session>().me?.can('schedule') ?? false)
            TextButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScheduleScreen())),
              icon: const Icon(Icons.calendar_month_outlined),
              label: const Text('Mi horario'),
            ),
          const CashButton(),
          const ProfileButton(),
        ],
      ),
      body: Column(
        children: [
          if (_loading && _data != null) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    final data = _data;
    if (data == null) {
      if (_error != null) return ErrorView(message: _error!, onRetry: _load);
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ClockCard(data: data, marking: _marking, onMark: _mark),
          const SizedBox(height: 20),
          Text('Este mes', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.1,
            children: [
              _Stat(label: 'Días trabajados', value: '${data.workedDays}', icon: Icons.event_available, color: Brand.success),
              _Stat(label: 'Horas', value: data.hoursLabel, icon: Icons.timer_outlined, color: Brand.primary),
              _Stat(label: 'Tardanzas', value: '${data.lateDays}', hint: data.lateMinutes > 0 ? '${data.lateMinutes} min' : null, icon: Icons.running_with_errors, color: Brand.warning),
              _Stat(label: 'Faltas', value: '${data.absences}', icon: Icons.event_busy, color: Brand.danger),
            ],
          ),
          const SizedBox(height: 20),
          Text('Días', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Card(
            child: Column(
              children: [
                for (final (i, d) in data.days.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                  _DayTile(day: d),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClockCard extends StatelessWidget {
  const _ClockCard({required this.data, required this.marking, required this.onMark});

  final AttendanceSummary data;
  final bool marking;
  final VoidCallback onMark;

  @override
  Widget build(BuildContext context) {
    final working = data.isWorking;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final blocks = data.today?.blocks ?? const <TimeBlock>[];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(longDay(DateTime.now()), style: TextStyle(color: muted)),
            const SizedBox(height: 6),
            Text(
              working ? 'En turno desde las ${hm(data.openSince!)}' : 'Fuera de turno',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: working ? Brand.success : null),
            ),
            if (working)
              Text('Llevas ${duration(DateTime.now().difference(data.openSince!))}', style: TextStyle(color: muted)),
            const SizedBox(height: 4),
            Text(
              blocks.isEmpty ? 'Hoy no tienes horario asignado' : 'Tu horario hoy: ${blocks.join(', ')}',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 13),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 60),
                  backgroundColor: working ? Brand.deep : Brand.success,
                ),
                onPressed: marking ? null : onMark,
                icon: marking
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : Icon(working ? Icons.logout : Icons.login),
                label: Text(working ? 'Marcar salida' : 'Marcar entrada', style: const TextStyle(fontSize: 18)),
              ),
            ),
            if ((data.today?.records ?? const []).isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  for (final r in data.today!.records)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('${r.checkIn} → ${r.checkOut ?? '…'}'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.icon, required this.color, this.hint});

  final String label;
  final String value;
  final String? hint;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  Text(hint == null ? label : '$label · $hint', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({required this.day});

  final AttendanceDay day;

  static Color colorFor(String state, Color muted) => switch (state) {
        'working' => Brand.primary,
        'present' => Brand.success,
        'late' => Brand.warning,
        'absent' || 'missing' => Brand.danger,
        _ => muted,
      };

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final records = day.records.map((r) => '${r.checkIn}–${r.checkOut ?? '…'}${r.edited ? ' (corregido)' : ''}').join('  ');

    return ListTile(
      dense: true,
      title: Text(shortDay(day.date), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: records.isEmpty
          ? (day.blocks.isEmpty ? null : Text('Horario ${day.blocks.join(', ')}'))
          : Text(records),
      trailing: StatusPill(label: day.label, color: colorFor(day.state, muted)),
    );
  }
}
