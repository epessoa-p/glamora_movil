import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../util/contact.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'client_edit_screen.dart';
import 'client_photos.dart';

/// Ficha del cliente: contacto, indicadores, beneficios, deuda e historial.
class ClientDetailScreen extends StatefulWidget {
  const ClientDetailScreen({super.key, required this.client});

  /// Lo que ya se conoce (nombre, teléfono) para mostrar algo mientras carga.
  final ClientInfo client;

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  ClientProfile? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await context.read<Session>().api.get('/clients/${widget.client.id}');
      if (mounted) setState(() => _data = ClientProfile.fromJson(data as Map<String, dynamic>));
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _edit() async {
    final d = _data!;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ClientEditScreen(
          clientId: d.client.id,
          name: d.client.name,
          phone: d.client.phone,
          document: d.client.document,
          email: d.client.email,
          birthdate: d.birthdate,
          notes: d.notes,
        ),
      ),
    );
    if (saved == true && mounted) {
      showMessage(context, 'Cliente actualizado.');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _data?.client ?? widget.client;
    final company = context.read<Session>().me?.company.name ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ficha del cliente'),
        actions: [
          if (_data != null && (context.read<Session>().me?.can('clients_edit') ?? false))
            IconButton(tooltip: 'Editar', onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(child: Avatar(name: c.name, radius: 34)),
            const SizedBox(height: 10),
            Text(c.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            if (c.phone != null) Text(c.phone!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            if (c.phone != null) ContactButtons(phone: c.phone!, message: 'Hola ${c.name.split(' ').first}, te escribimos de $company.'),
            const SizedBox(height: 16),
            if (_error != null)
              ErrorView(message: _error!, onRetry: _load)
            else if (_data == null)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else
              ..._sections(_data!),
          ],
        ),
      ),
    );
  }

  List<Widget> _sections(ClientProfile d) {
    final cur = d.currency;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return [
      Row(
        children: [
          Expanded(child: _Stat(label: 'Visitas', value: '${d.visits}')),
          const SizedBox(width: 8),
          Expanded(child: _Stat(label: 'Última visita', value: d.lastVisit == null ? '—' : shortDay(d.lastVisit!))),
          if (d.spent != null) ...[const SizedBox(width: 8), Expanded(child: _Stat(label: 'Gastado', value: money(d.spent!, cur)))],
        ],
      ),
      if (d.account != null && (d.account!.enabled || d.account!.debt > 0))
        _Block(
          icon: Icons.receipt_long_outlined,
          color: d.account!.overdue ? Brand.danger : (d.account!.debt > 0 ? Brand.warning : Brand.success),
          title: d.account!.debt > 0 ? 'Debe ${money(d.account!.debt, cur)}' : 'Sin deuda',
          lines: [
            if (d.account!.enabled) 'Puede fiar hasta ${money(d.account!.available, cur)}' else 'Sin crédito habilitado',
            if (d.account!.overdue) 'Tiene cuentas vencidas',
          ],
        ),
      if (d.membership != null)
        _Block(
          icon: Icons.workspace_premium_outlined,
          color: const Color(0xFFEC4899),
          title: 'Membresía ${d.membership!.plan}',
          lines: [
            'Vence el ${d.membership!.endsOn}${d.membership!.discount > 0 ? ' · ${d.membership!.discount.toStringAsFixed(0)} % de descuento' : ''}',
            ...d.membership!.sessions,
          ],
        ),
      for (final p in d.packages)
        _Block(
          icon: Icons.confirmation_number_outlined,
          color: Brand.success,
          title: 'Paquete ${p.name}',
          lines: [p.expiry, ...p.items.where((i) => i.remaining > 0).map((i) => '${i.service}: ${i.remaining} de ${i.included}')],
        ),
      if (d.points != null && d.points!.balance > 0)
        _Block(icon: Icons.stars_outlined, color: Brand.warning, title: '${d.points!.balance} puntos', lines: ['Equivalen a ${money(d.points!.value, cur)}']),
      if (d.credit != null && d.credit! > 0)
        _Block(icon: Icons.account_balance_wallet_outlined, color: Colors.blue, title: 'Saldo a favor ${money(d.credit!, cur)}', lines: const ['Se usa como pago en el punto de venta']),
      const SizedBox(height: 16),
      Text('Últimas citas', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      if (d.appointments.isEmpty)
        Text('Sin citas.', style: TextStyle(color: muted))
      else
        Card(
          child: Column(children: [
            for (final (i, a) in d.appointments.indexed) ...[
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                dense: true,
                title: Text(a.service ?? 'Sin servicio', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${shortDay(a.startsAt)} · ${hm(a.startsAt)}${a.personal != null ? ' · ${a.personal}' : ''}'),
                trailing: StatusPill(label: a.status, color: hexColor(a.color)),
              ),
            ],
          ]),
        ),
      if (d.sales != null) ...[
        const SizedBox(height: 16),
        Text('Últimas compras', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        if (d.sales!.isEmpty)
          Text('Sin compras.', style: TextStyle(color: muted))
        else
          Card(
            child: Column(children: [
              for (final (i, s) in d.sales!.indexed) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  dense: true,
                  title: Text(s.number, style: TextStyle(fontWeight: FontWeight.w600, decoration: s.voided ? TextDecoration.lineThrough : null)),
                  subtitle: s.date == null ? null : Text(shortDay(s.date!)),
                  trailing: Text(s.voided ? 'Anulada' : money(s.total, cur), style: TextStyle(fontWeight: FontWeight.w700, color: s.voided ? muted : null)),
                ),
              ],
            ]),
          ),
      ],
      if (context.read<Session>().me?.can('photos_view') ?? false) ...[
        const SizedBox(height: 16),
        ClientPhotosSection(clientId: d.client.id),
      ],
      if (d.client.document != null || d.client.email != null) ...[
        const SizedBox(height: 16),
        Card(
          child: Column(children: [
            if (d.client.document != null) ListTile(dense: true, leading: const Icon(Icons.badge_outlined), title: Text(d.client.document!)),
            if (d.client.email != null) ListTile(dense: true, leading: const Icon(Icons.mail_outline), title: Text(d.client.email!)),
          ]),
        ),
      ],
      const SizedBox(height: 24),
    ];
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          children: [
            FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.icon, required this.color, required this.title, this.lines = const []});

  final IconData icon;
  final Color color;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: .25))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                for (final l in lines) Text(l, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
