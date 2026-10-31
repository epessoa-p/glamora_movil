import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/shell.dart';
import 'birthdays_screen.dart';
import 'receivables_screen.dart';

/// Panel del día para gerencia: ventas, citas, caja, equipo y cuentas por
/// cobrar. Cada bloque aparece si el usuario tiene permiso (lo decide el servidor).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await context.read<Session>().api.get('/dashboard');
      if (mounted) setState(() => _data = data as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me!;
    final d = _data;

    return Scaffold(
      appBar: AppBar(leading: shellLeading(context), title: Text(me.company.name), actions: const [ProfileButton()]),
      body: _error != null && d == null
          ? ErrorView(message: _error!, onRetry: _load)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: _blocks(d, me))),
    );
  }

  List<Widget> _blocks(Map<String, dynamic> d, Me me) {
    final cur = '${d['currency'] ?? 'Bs'}';
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final blocks = <Widget>[
      Text(longDay(DateTime.parse(d['date'] as String)), style: TextStyle(color: muted)),
      const SizedBox(height: 10),
    ];

    final sales = d['sales'] as Map<String, dynamic>?;
    if (sales != null) {
      blocks.add(Card(
        color: Brand.primary,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Vendido hoy', style: TextStyle(color: Colors.white70)),
              Text(money(_n(sales['today']), cur), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
              Text('${sales['today_count']} venta(s)${_n(sales['tips_today']) > 0 ? ' · propinas ${money(_n(sales['tips_today']), cur)}' : ''} · mes ${money(_n(sales['month']), cur)}',
                  style: const TextStyle(color: Colors.white)),
              if ((sales['by_method'] as List).isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final m in (sales['by_method'] as List).cast<Map<String, dynamic>>())
                      Chip(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.white24,
                        side: BorderSide.none,
                        label: Text('${m['method']}: ${money(_n(m['amount']), cur)}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ));
      blocks.add(const SizedBox(height: 12));
    }

    final agenda = d['agenda'] as Map<String, dynamic>?;
    if (agenda != null) {
      final next = (agenda['next'] as List).cast<Map<String, dynamic>>().map(Appointment.fromJson).toList();
      blocks.add(_Section(
        icon: Icons.calendar_today_outlined,
        title: 'Citas de hoy',
        trailing: '${agenda['total']}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 6, children: [
              _Pill('Por atender', '${agenda['pending']}', Brand.warning),
              _Pill('Atendidas', '${agenda['completed']}', Brand.success),
              if (agenda['canceled'] != 0) _Pill('Canceladas', '${agenda['canceled']}', Colors.grey),
            ]),
            if (next.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final a in next)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    SizedBox(width: 48, child: Text(hm(a.startsAt), style: const TextStyle(fontWeight: FontWeight.w700))),
                    Expanded(child: Text('${a.client?.name ?? 'Sin cliente'} · ${a.service?.name ?? ''}', overflow: TextOverflow.ellipsis)),
                    Text(a.personal?.name.split(' ').first ?? '', style: TextStyle(color: muted, fontSize: 12)),
                  ]),
                ),
            ],
          ],
        ),
      ));
    }

    final cash = d['cash'] as List?;
    if (cash != null) {
      blocks.add(_Section(
        icon: Icons.point_of_sale_outlined,
        title: 'Caja',
        trailing: cash.isEmpty ? 'Cerrada' : '${cash.length} abierta(s)',
        child: cash.isEmpty
            ? Text('No hay cajas abiertas.', style: TextStyle(color: muted))
            : Column(children: [
                for (final c in cash.cast<Map<String, dynamic>>())
                  Row(children: [
                    Expanded(child: Text('${c['name']}${c['opened_at'] != null ? ' · desde ${hm(wallTime(c['opened_at'] as String))}' : ''}')),
                    Text(money(_n(c['expected']), cur), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
              ]),
      ));
    }

    final team = d['team'] as Map<String, dynamic>?;
    if (team != null) {
      final people = (team['people'] as List).cast<Map<String, dynamic>>();
      blocks.add(_Section(
        icon: Icons.groups_outlined,
        title: 'Equipo',
        trailing: '${team['working']} en turno',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 6, children: [
              _Pill('En turno', '${team['working']}', Brand.primary),
              if (team['late'] != 0) _Pill('Tarde', '${team['late']}', Brand.warning),
              if (team['absent'] != 0) _Pill('Faltan', '${team['absent']}', Brand.danger),
            ]),
            const SizedBox(height: 6),
            for (final p in people)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Expanded(child: Text('${p['name']}', overflow: TextOverflow.ellipsis)),
                  if (p['check_in'] != null) Text('${p['check_in']}  ', style: TextStyle(color: muted, fontSize: 12)),
                  StatusPill(label: '${p['label']}', color: _stateColor('${p['state']}', muted)),
                ]),
              ),
          ],
        ),
      ));
    }

    final rec = d['receivables'] as Map<String, dynamic>?;
    if (rec != null) {
      blocks.add(_Section(
        icon: Icons.receipt_long_outlined,
        title: 'Cuentas por cobrar',
        trailing: money(_n(rec['balance']), cur),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReceivablesScreen())),
        child: Row(children: [
          Expanded(child: Text('Vencido ${money(_n(rec['overdue']), cur)}', style: TextStyle(color: _n(rec['overdue']) > 0 ? Brand.danger : muted, fontWeight: FontWeight.w600))),
          Text('Cobrado hoy ${money(_n(rec['collected_today']), cur)}', style: TextStyle(color: muted, fontSize: 13)),
        ]),
      ));
    }

    final clients = d['clients'] as Map<String, dynamic>?;
    final stockLow = d['stock_low'];
    if (clients != null || stockLow != null) {
      blocks.add(Row(children: [
        if (clients != null)
          Expanded(
            child: _MiniCard(
              icon: Icons.cake_outlined,
              value: '${clients['birthdays_today']}',
              label: 'Cumpleaños hoy',
              onTap: me.can('birthdays') ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BirthdaysScreen())) : null,
            ),
          ),
        if (clients != null) ...[
          const SizedBox(width: 8),
          Expanded(child: _MiniCard(icon: Icons.person_add_alt, value: '${clients['new_month']}', label: 'Clientes nuevos (mes)')),
        ],
        if (stockLow != null) ...[
          const SizedBox(width: 8),
          Expanded(child: _MiniCard(icon: Icons.inventory_2_outlined, value: '$stockLow', label: 'Stock bajo', alert: stockLow != 0)),
        ],
      ]));
    }

    blocks.add(const SizedBox(height: 24));
    return blocks;
  }

  Color _stateColor(String state, Color muted) => switch (state) {
        'working' => Brand.primary,
        'present' => Brand.success,
        'late' => Brand.warning,
        'absent' || 'missing' => Brand.danger,
        _ => muted,
      };
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.child, this.trailing, this.onTap});

  final IconData icon;
  final String title;
  final String? trailing;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(icon, size: 20, color: Brand.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
                  if (trailing != null) Text(trailing!, style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (onTap != null) const Icon(Icons.chevron_right),
                ]),
                const SizedBox(height: 8),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => StatusPill(label: '$label $value', color: color);
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.icon, required this.value, required this.label, this.onTap, this.alert = false});

  final IconData icon;
  final String value;
  final String label;
  final VoidCallback? onTap;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Icon(icon, color: alert ? Brand.danger : Brand.primary),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: alert ? Brand.danger : null)),
            Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}
