import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';

/// Mi horario: turnos de la semana, días libres y horario especial.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  DateTime _monday = dateOnly(DateTime.now()).subtract(Duration(days: DateTime.now().weekday - 1));
  List<ScheduleDay>? _days;
  bool _configured = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await context.read<Session>().api.get('/schedule', {'date': ymd(_monday)}) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _configured = data['configured'] == true;
        _days = (data['days'] as List).whereType<Map<String, dynamic>>().map(ScheduleDay.fromJson).toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  void _shift(int weeks) {
    setState(() {
      _monday = _monday.add(Duration(days: 7 * weeks));
      _days = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final days = _days;
    final total = days?.fold<int>(0, (s, d) => s + d.minutes) ?? 0;
    final sunday = _monday.add(const Duration(days: 6));

    return Scaffold(
      appBar: AppBar(title: const Text('Mi horario')),
      body: Column(
        children: [
          Row(
            children: [
              IconButton(tooltip: 'Semana anterior', onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: Column(
                  children: [
                    Text('${shortDay(_monday)} – ${shortDay(sunday)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (days != null) Text('${duration(Duration(minutes: total))} en la semana', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              IconButton(tooltip: 'Semana siguiente', onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
            ],
          ),
          Expanded(
            child: _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : days == null
                    ? const Center(child: CircularProgressIndicator())
                    : !_configured
                        ? const EmptyView(text: 'Todavía no tienes un horario cargado. Pídele al administrador que lo configure en Personal › Horarios.', icon: Icons.schedule)
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                              itemCount: days.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 8),
                              itemBuilder: (_, i) => _DayCard(day: days[i]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day});

  final ScheduleDay day;

  @override
  Widget build(BuildContext context) {
    final today = sameDay(day.date, DateTime.now());
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final working = day.blocks.isNotEmpty;

    return Card(
      key: ValueKey('schedule-${ymd(day.date)}'),
      shape: today ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Brand.primary, width: 1.5)) : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shortDay(day.date), style: TextStyle(fontWeight: FontWeight.w800, color: today ? Brand.primary : null)),
                  if (today) const Text('Hoy', style: TextStyle(fontSize: 12, color: Brand.primary)),
                ],
              ),
            ),
            Expanded(
              child: working
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(day.blocks.join('  ·  '), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        Text('${duration(Duration(minutes: day.minutes))}${day.special ? ' · horario especial' : ''}', style: TextStyle(fontSize: 12, color: muted)),
                      ],
                    )
                  : Text(day.off != null ? 'Libre · ${day.off}' : 'No trabaja', style: TextStyle(color: day.off != null ? Brand.warning : muted, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
