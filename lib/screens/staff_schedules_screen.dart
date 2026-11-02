import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';

const _dayLetters = {1: 'L', 2: 'M', 3: 'X', 4: 'J', 5: 'V', 6: 'S', 7: 'D'};

/// Horarios del personal: quién trabaja hoy y qué días; se edita por persona.
class StaffSchedulesScreen extends StatefulWidget {
  const StaffSchedulesScreen({super.key});

  @override
  State<StaffSchedulesScreen> createState() => _StaffSchedulesScreenState();
}

class _StaffSchedulesScreenState extends State<StaffSchedulesScreen> {
  Map<String, dynamic>? _data;
  String? _error;

  ApiClient get _api => context.read<Session>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await _api.get('/schedules');
      if (mounted) setState(() => _data = d as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  String _today(Map<String, dynamic> p) {
    final t = (p['today'] as Map).cast<String, dynamic>();
    if (p['configured'] != true && (t['blocks'] as List).isEmpty) return 'Sin horario cargado';
    if (t['off'] != null) return 'Hoy: ${t['off']}';
    final blocks = (t['blocks'] as List).cast<Map>();
    if (blocks.isEmpty) return 'Hoy no trabaja';
    return 'Hoy: ${blocks.map((b) => '${b['start']}–${b['end']}').join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final people = ((d?['people'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('Horarios')),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: people.isEmpty
                      ? ListView(children: const [SizedBox(height: 80), EmptyView(text: 'No hay personal activo.', icon: Icons.schedule_outlined)])
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
                          itemCount: people.length,
                          separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
                          itemBuilder: (_, i) {
                            final p = people[i];
                            final days = ((p['weekdays'] as List?) ?? const []).map((e) => e as int).toSet();
                            return ListTile(
                              leading: Avatar(name: '${p['name']}'),
                              title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text([if (p['cargo'] != null) p['cargo'], _today(p)].join(' · ')),
                                const SizedBox(height: 4),
                                Row(children: [
                                  for (final e in _dayLetters.entries)
                                    Container(
                                      width: 20,
                                      height: 20,
                                      margin: const EdgeInsets.only(right: 4),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: days.contains(e.key) ? Brand.primary : muted.withValues(alpha: .12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(e.value, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: days.contains(e.key) ? Colors.white : muted)),
                                    ),
                                ]),
                              ]),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () async {
                                final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ScheduleEditScreen(personalId: p['id'] as int, name: '${p['name']}')));
                                if (saved == true) _load();
                              },
                            );
                          },
                        ),
                ),
    );
  }
}

/// Horario semanal de una persona: días que trabaja y sus bloques de horas.
class ScheduleEditScreen extends StatefulWidget {
  const ScheduleEditScreen({super.key, required this.personalId, required this.name});

  final int personalId;
  final String name;

  @override
  State<ScheduleEditScreen> createState() => _ScheduleEditScreenState();
}

class _Day {
  _Day(this.weekday, this.label, this.on, this.blocks);

  final int weekday;
  final String label;
  bool on;
  final List<({String start, String end})> blocks;
}

class _ScheduleEditScreenState extends State<ScheduleEditScreen> {
  List<_Day>? _days;
  List<Map<String, dynamic>> _exceptions = const [];
  bool _canEdit = false;
  bool _saving = false;
  bool _changed = false;
  String? _loadError;
  Map<String, String> _dayErrors = const {};

  ApiClient get _api => context.read<Session>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _apply(Map<String, dynamic> d) {
    _days = [
      for (final day in (d['days'] as List).cast<Map<String, dynamic>>())
        _Day(
          day['weekday'] as int,
          '${day['label']}',
          day['on'] == true,
          [for (final b in (day['blocks'] as List).cast<Map>()) (start: '${b['start']}', end: '${b['end']}')],
        ),
    ];
    _exceptions = ((d['exceptions'] as List?) ?? const []).cast<Map<String, dynamic>>();
    if (d['can'] != null) _canEdit = (d['can'] as Map)['edit'] == true;
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final d = await _api.get('/schedules/${widget.personalId}') as Map<String, dynamic>;
      if (mounted) setState(() => _apply(d));
    } catch (e) {
      if (mounted) setState(() => _loadError = errorText(e));
    }
  }

  Future<String?> _pickTime(String current) async {
    final parts = current.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(parts.first) ?? 9, minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _editBlock(_Day day, int i, {required bool start}) async {
    final b = day.blocks[i];
    final v = await _pickTime(start ? b.start : b.end);
    if (v == null || !mounted) return;
    setState(() {
      day.blocks[i] = start ? (start: v, end: b.end) : (start: b.start, end: v);
      _changed = true;
    });
  }

  void _toggle(_Day day, bool on) => setState(() {
        day.on = on;
        // Al activar un día sin bloques se propone el horario de otro día (o 09:00–18:00).
        if (on && day.blocks.isEmpty) {
          final model = _days!.firstWhere((d) => d.on && d.blocks.isNotEmpty && d != day, orElse: () => _Day(0, '', true, [(start: '09:00', end: '18:00')]));
          day.blocks.addAll(model.blocks);
        }
        _changed = true;
      });

  void _addBlock(_Day day) => setState(() {
        final last = day.blocks.isEmpty ? null : day.blocks.last;
        day.blocks.add(last == null ? (start: '09:00', end: '13:00') : (start: last.end, end: last.end.compareTo('18:00') < 0 ? '18:00' : '23:00'));
        _changed = true;
      });

  /// Copia el horario de este día a todos los días que trabaja.
  void _copyToAll(_Day from) => setState(() {
        for (final d in _days!) {
          if (d == from) continue;
          if (d.on) {
            d.blocks
              ..clear()
              ..addAll(from.blocks);
          }
        }
        _changed = true;
      });

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _dayErrors = const {};
    });
    try {
      final res = await _api.put('/schedules/${widget.personalId}', {
        'days': {
          for (final d in _days!)
            '${d.weekday}': {
              'on': d.on,
              'blocks': [for (final b in d.blocks) {'start': b.start, 'end': b.end}],
            },
        },
      }) as Map<String, dynamic>;
      if (!mounted) return;
      showMessage(context, '${res['message']}');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _dayErrors = {for (final entry in e.fieldErrors.entries) entry.key: entry.value.first});
        if (e.fieldErrors.isEmpty) showMessage(context, e.message, error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = _days;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final enabled = _canEdit && !_saving;

    return PopScope(
      canPop: !_changed || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirm(context, title: 'Cambios sin guardar', message: '¿Salir sin guardar el horario?', ok: 'Salir');
        if (leave && context.mounted) {
          setState(() => _changed = false);
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.name)),
        bottomNavigationBar: _canEdit && days != null
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Icon(Icons.check),
                    label: const Text('Guardar horario'),
                  ),
                ),
              )
            : null,
        body: _loadError != null
            ? ErrorView(message: _loadError!, onRetry: _load)
            : days == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
                    if (!_canEdit)
                      const Padding(padding: EdgeInsets.all(8), child: Text('Solo lectura: no tienes permiso para editar horarios.')),
                    for (final d in days)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(d.label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: d.on ? null : muted))),
                              if (d.on && enabled && d.blocks.isNotEmpty)
                                IconButton(tooltip: 'Copiar a los demás días', onPressed: () => _copyToAll(d), icon: const Icon(Icons.copy_all_outlined, size: 20)),
                              Switch(value: d.on, onChanged: enabled ? (v) => _toggle(d, v) : null),
                            ]),
                            if (!d.on) Text('No trabaja', style: TextStyle(color: muted)),
                            if (d.on) ...[
                              for (var i = 0; i < d.blocks.length; i++)
                                Row(children: [
                                  _TimeChip(label: d.blocks[i].start, onTap: enabled ? () => _editBlock(d, i, start: true) : null),
                                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('a')),
                                  _TimeChip(label: d.blocks[i].end, onTap: enabled ? () => _editBlock(d, i, start: false) : null),
                                  const Spacer(),
                                  if (enabled && d.blocks.length > 1)
                                    IconButton(tooltip: 'Quitar bloque', onPressed: () => setState(() {
                                      d.blocks.removeAt(i);
                                      _changed = true;
                                    }), icon: const Icon(Icons.remove_circle_outline, color: Brand.danger)),
                                ]),
                              if (enabled)
                                TextButton.icon(onPressed: () => _addBlock(d), icon: const Icon(Icons.add, size: 18), label: const Text('Agregar bloque (p. ej. después del almuerzo)')),
                            ],
                            if (_dayErrors['days.${d.weekday}'] != null)
                              Padding(padding: const EdgeInsets.only(top: 4), child: Text(_dayErrors['days.${d.weekday}']!, style: const TextStyle(color: Brand.danger, fontWeight: FontWeight.w600))),
                          ]),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text('Próximos libres y horarios especiales', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    if (_exceptions.isEmpty) Text('Ninguno.', style: TextStyle(color: muted)),
                    for (final e in _exceptions)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(e['start'] == null ? Icons.beach_access_outlined : Icons.more_time, color: Brand.primary),
                        title: Text([
                          e['from'] == e['to'] ? shortDay(DateTime.parse('${e['from']}')) : '${shortDay(DateTime.parse('${e['from']}'))} – ${shortDay(DateTime.parse('${e['to']}'))}',
                          if (e['start'] != null) '${e['start']}–${e['end']}',
                        ].join(' · ')),
                        subtitle: Text([e['type'], if ((e['reason'] ?? '').toString().isNotEmpty) e['reason']].join(' · ')),
                      ),
                    Text('Los libres, vacaciones y horarios especiales se registran desde la web.', style: TextStyle(color: muted, fontSize: 12)),
                  ]),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: Brand.soft.withValues(alpha: .45), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.access_time, size: 16, color: Brand.primary),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}
