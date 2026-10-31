import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/shell.dart';

/// Mis comisiones del mes (las mismas cifras que "Mis comisiones" en la web).
class CommissionsScreen extends StatefulWidget {
  const CommissionsScreen({super.key});

  @override
  State<CommissionsScreen> createState() => _CommissionsScreenState();
}

class _CommissionsScreenState extends State<CommissionsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  CommissionReport? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final last = DateTime(_month.year, _month.month + 1, 0);
      final data = await context.read<Session>().api.get('/commissions', {'from': ymd(_month), 'to': ymd(last)});
      if (mounted) setState(() => _data = CommissionReport.fromJson(data as Map<String, dynamic>));
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shift(int months) {
    setState(() {
      _month = DateTime(_month.year, _month.month + months);
      _data = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;

    return Scaffold(
      appBar: AppBar(leading: shellLeading(context), title: const Text('Mis comisiones'), actions: const [ProfileButton()]),
      body: Column(
        children: [
          Row(
            children: [
              IconButton(tooltip: 'Mes anterior', onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
              Expanded(child: Text(monthName(_month), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              IconButton(tooltip: 'Mes siguiente', onPressed: isCurrent ? null : () => _shift(1), icon: const Icon(Icons.chevron_right)),
            ],
          ),
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
    final cur = data.currency;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Card(
            color: Brand.primary,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ganado en el mes', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text(money(data.earned, cur), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                  if (data.tips > 0) Text('+ ${money(data.tips, cur)} en propinas', style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _Kpi(label: 'Por cobrar', value: money(data.pending, cur), color: Brand.warning)),
              const SizedBox(width: 10),
              Expanded(child: _Kpi(label: 'Liquidado', value: money(data.settled, cur), color: Brand.success)),
            ],
          ),
          const SizedBox(height: 20),
          Text('Detalle', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (data.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text('Sin comisiones este mes.', textAlign: TextAlign.center),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final (i, c) in data.items.indexed) ...[
                    if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                    _ItemTile(item: c, currency: cur),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(radius: 4, backgroundColor: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
            ]),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          ],
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.currency});

  final CommissionItem item;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final c = item;

    return ListTile(
      title: Text(c.concept, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [
          if (c.date != null) shortDay(c.date!),
          if (c.sale != null) c.sale!,
          '${money(c.base, currency)} × ${c.rate}',
        ].join(' · '),
        style: TextStyle(color: muted, fontSize: 12),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(money(c.amount, currency), style: TextStyle(fontWeight: FontWeight.w800, color: c.amount < 0 ? Brand.danger : null)),
          const SizedBox(height: 2),
          Text(c.status, style: TextStyle(fontSize: 11, color: c.pending ? Brand.warning : Brand.success, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
