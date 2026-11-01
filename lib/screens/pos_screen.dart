import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'sales_screen.dart';

double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// Campo del carrito según el tipo de ítem del catálogo.
String _field(String kind) => switch (kind) {
      'product' => 'product_id',
      'combo' => 'combo_id',
      'package' => 'service_package_id',
      'membership' => 'membership_plan_id',
      _ => 'service_id',
    };

const _kindLabels = {
  'service': 'Servicios',
  'product': 'Productos',
  'combo': 'Combos',
  'package': 'Paquetes',
  'membership': 'Membresías',
};

// Insignia en el catálogo (los servicios no la llevan).
const _kindSingular = {'product': 'Producto', 'combo': 'Combo', 'package': 'Paquete', 'membership': 'Membresía'};

/// Línea del carrito.
class CartLine {
  CartLine({required this.kind, required this.id, required this.name, required this.price, this.quantity = 1});

  final String kind;
  final int id;
  final String name;
  double price;
  double quantity;

  Map<String, Object?> toJson() => {_field(kind): id, 'quantity': quantity, 'unit_price': price};
}

/// Cobro desde el celular. Los totales, beneficios (membresía, paquete,
/// promoción, cupón, puntos) y errores los calcula el servidor en vivo con
/// las mismas reglas del punto de venta web.
class PosScreen extends StatefulWidget {
  const PosScreen({super.key, this.client, this.lines = const [], this.specialistId});

  final ClientInfo? client;
  final List<CartLine> lines;
  final int? specialistId;

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  Map<String, dynamic>? _options;
  String? _error;

  ClientInfo? _client;
  late final List<CartLine> _lines = [...widget.lines];
  int? _principal;
  String? _method;
  int? _sessionId;
  bool _redeem = false;
  final _tip = TextEditingController();
  final _coupon = TextEditingController();
  final _received = TextEditingController();

  Map<String, dynamic>? _quote;
  bool _quoting = false;
  int _seq = 0;
  Timer? _debounce;
  bool _saving = false;
  String? _formError;

  ApiClient get _api => context.read<Session>().api;
  String get _cur => '${_options?['currency'] ?? context.read<Session>().me?.company.currencySymbol ?? 'Bs'}';

  @override
  void initState() {
    super.initState();
    _client = widget.client;
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tip.dispose();
    _coupon.dispose();
    _received.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final o = await _api.get('/pos/options') as Map<String, dynamic>;
      if (!mounted) return;
      final methods = (o['payment_methods'] as List).cast<Map<String, dynamic>>();
      final sessions = (o['cash_sessions'] as List).cast<Map<String, dynamic>>();
      setState(() {
        _options = o;
        _principal = widget.specialistId ?? (o['default_principal'] as int?);
        _method = '${(methods.firstWhere((m) => m['default'] == true, orElse: () => methods.first))['code']}';
        if (sessions.length == 1) _sessionId = sessions.first['id'] as int;
      });
      _requote(now: true);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Map<String, Object?> _payload() => {
        'client_id': _client?.id,
        'personal_id': _principal,
        'payment_method': _method,
        'cash_session_id': _sessionId,
        'tip': double.tryParse(_tip.text.replaceAll(',', '.')) ?? 0,
        if (_coupon.text.trim().isNotEmpty) 'coupon_code': _coupon.text.trim().toUpperCase(),
        if (_redeem) 'redeem_points': _redeemablePoints,
        'items': [for (final l in _lines) l.toJson()],
      };

  int get _redeemablePoints => (_n(((_quote?['client'] as Map?)?['points'] as Map?)?['max_redeemable'])).toInt();

  /// Recalcula en el servidor (con una pausa corta mientras se escribe).
  void _requote({bool now = false}) {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: now ? 0 : 350), () async {
      final seq = ++_seq;
      setState(() => _quoting = true);
      try {
        final q = await _api.post('/pos/quote', _payload()) as Map<String, dynamic>;
        if (!mounted || seq != _seq) return;
        setState(() {
          _quote = q;
          _formError = null;
          // Si el canje ya no cabe (cambió el total o el cliente), se apaga.
          if (_redeem && _redeemablePoints == 0) _redeem = false;
        });
      } catch (e) {
        if (mounted && seq == _seq) setState(() => _formError = errorText(e));
      } finally {
        if (mounted && seq == _seq) setState(() => _quoting = false);
      }
    });
  }

  void _changed(VoidCallback change) {
    setState(change);
    _requote();
  }

  Future<void> _addItem() async {
    final item = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CatalogSheet(options: _options!, currency: _cur),
    );
    if (item == null) return;
    _changed(() {
      final kind = '${item['kind']}';
      final id = item['id'] as int;
      final existing = _lines.where((l) => l.kind == kind && l.id == id).firstOrNull;
      if (existing != null) {
        existing.quantity += 1;
      } else {
        _lines.add(CartLine(kind: kind, id: id, name: '${item['name']}', price: _n(item['price'])));
      }
    });
  }

  Future<void> _pickClient() async {
    final features = (_options!['features'] as Map).cast<String, dynamic>();
    final picked = await showModalBottomSheet<({ClientInfo? client})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ClientSheet(canCreate: features['clients_create'] == true),
    );
    if (picked == null) return;
    _changed(() {
      _client = picked.client;
      _redeem = false;
    });
  }

  Future<void> _editPrice(CartLine line) async {
    final ctrl = TextEditingController(text: line.price.toStringAsFixed(2));
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(line.name),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Precio unitario', prefixText: '$_cur '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, double.tryParse(ctrl.text.replaceAll(',', '.'))), child: const Text('Aplicar')),
        ],
      ),
    );
    // Sin dispose: el diálogo sigue dibujándose durante su animación de salida.
    if (value != null && value >= 0) _changed(() => line.price = value);
  }

  Future<void> _charge() async {
    final q = _quote!;
    final ok = await confirm(context, title: 'Cobrar', message: '¿Cobrar ${money(_n(q['charge_now']), _cur)}${_client != null ? ' a ${_client!.name}' : ''}?', ok: 'Cobrar');
    if (!ok || !mounted) return;

    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      final res = await _api.post('/sales', _payload()) as Map<String, dynamic>;
      if (!mounted) return;
      showMessage(context, '${res['message']}');
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SaleDetailScreen(sale: res['sale'] as Map<String, dynamic>, justCreated: true)));
    } on ApiException catch (e) {
      if (mounted) setState(() => _formError = e.message);
      _requote(now: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _options;
    final q = _quote;
    final errors = ((q?['errors'] as List?) ?? const []).map((e) => '$e').toList();
    final canCharge = o != null && q != null && _lines.isNotEmpty && errors.isEmpty && !_quoting && !_saving;

    return Scaffold(
      appBar: AppBar(title: const Text('Cobrar')),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : o == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: _content(o, q)),
      bottomNavigationBar: o == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final e in {...errors, ?_formError})
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(e, style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
                      ),
                    FilledButton.icon(
                      onPressed: canCharge ? _charge : null,
                      icon: _saving || _quoting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : const Icon(Icons.point_of_sale),
                      label: Text(q == null || _lines.isEmpty ? 'Cobrar' : 'Cobrar ${money(_n(q['charge_now']), _cur)}'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  List<Widget> _content(Map<String, dynamic> o, Map<String, dynamic>? q) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final specialists = (o['specialists'] as List).cast<Map<String, dynamic>>();
    final methods = (o['payment_methods'] as List).cast<Map<String, dynamic>>();
    final sessions = (o['cash_sessions'] as List).cast<Map<String, dynamic>>();
    final features = (o['features'] as Map).cast<String, dynamic>();
    final qLines = ((q?['lines'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final qClient = q?['client'] as Map<String, dynamic>?;
    final method = methods.where((m) => '${m['code']}' == _method).firstOrNull;
    final isCash = method?['cash'] == true;

    return [
      // Cliente
      Card(
        child: ListTile(
          leading: _client == null ? const CircleAvatar(child: Icon(Icons.person_outline)) : Avatar(name: _client!.name),
          title: Text(_client?.name ?? 'Cliente ocasional', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(_client == null ? 'Toca para elegir una clienta' : (_client!.phone ?? 'Sin teléfono')),
          trailing: const Icon(Icons.chevron_right),
          onTap: _saving ? null : _pickClient,
        ),
      ),
      if (qClient != null) ..._benefits(qClient, muted),
      const SizedBox(height: 10),
      DropdownButtonFormField<int?>(
        initialValue: _principal,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Atendió', isDense: true, prefixIcon: Icon(Icons.content_cut, size: 20)),
        items: [
          const DropdownMenuItem(value: null, child: Text('Sin profesional')),
          for (final s in specialists) DropdownMenuItem(value: s['id'] as int, child: Text('${s['name']}')),
        ],
        onChanged: _saving ? null : (v) => _changed(() => _principal = v),
      ),
      const SizedBox(height: 16),

      // Líneas
      Row(children: [
        const Expanded(child: Text('Detalle', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
        TextButton.icon(onPressed: _saving ? null : _addItem, icon: const Icon(Icons.add), label: const Text('Agregar')),
      ]),
      if (_lines.isEmpty)
        Card(
          child: InkWell(
            onTap: _addItem,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                Icon(Icons.add_shopping_cart, color: muted, size: 32),
                const SizedBox(height: 8),
                Text('Agrega servicios o productos', style: TextStyle(color: muted)),
              ]),
            ),
          ),
        )
      else
        Card(
          child: Column(children: [
            for (final (i, l) in _lines.indexed) ...[
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              _lineTile(l, i < qLines.length ? qLines[i] : null),
            ],
          ]),
        ),
      const SizedBox(height: 16),

      // Extras
      Row(children: [
        Expanded(
          child: TextField(
            controller: _tip,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Propina', prefixText: '$_cur ', isDense: true),
            onChanged: (_) => _requote(),
          ),
        ),
        if (features['coupons'] == true) ...[
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _coupon,
              enabled: !_saving,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Cupón',
                isDense: true,
                suffixIcon: q?['coupon'] != null ? const Icon(Icons.check_circle, color: Brand.success) : null,
              ),
              onChanged: (_) => _requote(),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 16),

      // Forma de pago
      const Text('Forma de pago', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final m in methods)
          ChoiceChip(
            label: Text('${m['name']}'),
            selected: '${m['code']}' == _method,
            onSelected: _saving ? null : (_) => _changed(() => _method = '${m['code']}'),
          ),
      ]),
      if (sessions.isNotEmpty || o['require_cash'] == true) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<int?>(
          initialValue: _sessionId,
          decoration: const InputDecoration(labelText: 'Caja', isDense: true, prefixIcon: Icon(Icons.point_of_sale, size: 20)),
          items: [
            if (o['require_cash'] != true) const DropdownMenuItem(value: null, child: Text('No registrar en caja')),
            for (final c in sessions) DropdownMenuItem(value: c['id'] as int, child: Text('${c['name']}')),
          ],
          onChanged: _saving ? null : (v) => _changed(() => _sessionId = v),
        ),
        if (o['require_cash'] == true && sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('No hay cajas abiertas: abre una en Caja para poder cobrar.', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
      if (isCash && q != null && _lines.isNotEmpty) ...[
        const SizedBox(height: 12),
        _change(_n(q['charge_now'])),
      ],
      if (q != null && _lines.isNotEmpty) ...[
        const SizedBox(height: 16),
        _totals(q),
      ],
    ];
  }

  /// Membresía, paquetes y puntos de la clienta elegida.
  List<Widget> _benefits(Map<String, dynamic> c, Color muted) {
    final membership = c['membership'] as Map<String, dynamic>?;
    final packages = ((c['packages'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final points = (c['points'] as Map?)?.cast<String, dynamic>() ?? const {};
    final credit = _n(c['credit']);
    final chips = <Widget>[
      if (membership != null) _chip(Icons.workspace_premium_outlined, '${membership['plan']} · hasta ${membership['ends_on']}'),
      for (final p in packages) _chip(Icons.inventory_2_outlined, '${p['name']} · ${p['remaining']} sesión(es)'),
      if (points['enabled'] == true) _chip(Icons.stars_outlined, '${points['balance']} puntos'),
      if (credit > 0) _chip(Icons.account_balance_wallet_outlined, 'Saldo a favor ${money(credit, _cur)}'),
    ];
    final redeemable = _n(points['max_redeemable']).toInt();

    return [
      if (chips.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 6, runSpacing: 6, children: chips)),
      if (redeemable > 0 || _redeem)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _redeem,
          title: Text('Canjear $redeemable puntos'),
          subtitle: Text('Descuenta ${money(redeemable * _n(points['point_value']), _cur)}'),
          onChanged: _saving ? null : (v) => _changed(() => _redeem = v),
        ),
    ];
  }

  Widget _chip(IconData icon, String text) => Chip(
        avatar: Icon(icon, size: 16, color: Brand.primary),
        label: Text(text, style: const TextStyle(fontSize: 12)),
        visualDensity: VisualDensity.compact,
        backgroundColor: Brand.soft.withValues(alpha: .35),
        side: BorderSide.none,
      );

  Widget _lineTile(CartLine l, Map<String, dynamic>? q) {
    final gross = q == null ? l.price * l.quantity : _n(q['gross']);
    final total = q == null ? gross : _n(q['total']);
    final badge = q == null
        ? null
        : q['uses_session'] == true || (_n(q['package_discount']) > 0 && total == 0)
            ? 'Sesión incluida'
            : (q['badge'] as String?);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              InkWell(
                onTap: _saving ? null : () => _editPrice(l),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('${money(l.price, _cur)} c/u ✎', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                ),
              ),
              if (badge != null && badge.isNotEmpty) Text(badge, style: const TextStyle(color: Brand.primary, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
          IconButton(
            tooltip: l.quantity <= 1 ? 'Quitar' : 'Menos',
            visualDensity: VisualDensity.compact,
            onPressed: _saving ? null : () => _changed(() => l.quantity <= 1 ? _lines.remove(l) : l.quantity -= 1),
            icon: Icon(l.quantity <= 1 ? Icons.delete_outline : Icons.remove_circle_outline),
          ),
          Text(l.quantity == l.quantity.roundToDouble() ? '${l.quantity.toInt()}' : '${l.quantity}', style: const TextStyle(fontWeight: FontWeight.w700)),
          IconButton(
            tooltip: 'Más',
            visualDensity: VisualDensity.compact,
            onPressed: _saving ? null : () => _changed(() => l.quantity += 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
          SizedBox(
            width: 84,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(money(total, _cur), style: const TextStyle(fontWeight: FontWeight.w800)),
              if (total < gross - 0.005)
                Text(money(gross, _cur), style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant, decoration: TextDecoration.lineThrough)),
            ]),
          ),
        ],
      ),
    );
  }

  /// Efectivo: cuánto entrega la clienta y el vuelto.
  Widget _change(double charge) {
    final received = double.tryParse(_received.text.replaceAll(',', '.'));
    final change = received == null ? null : received - charge;
    return Row(children: [
      Expanded(
        child: TextField(
          controller: _received,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Recibido', prefixText: '$_cur ', isDense: true),
          onChanged: (_) => setState(() {}),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          change == null ? 'Vuelto —' : (change < 0 ? 'Faltan ${money(-change, _cur)}' : 'Vuelto ${money(change, _cur)}'),
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: change != null && change < 0 ? Brand.danger : Brand.success),
        ),
      ),
    ]);
  }

  Widget _totals(Map<String, dynamic> q) {
    final discounts = ['line_discounts', 'global_discount', 'membership_discount', 'package_discount', 'promotion_discount', 'coupon_discount', 'loyalty_discount']
        .fold<double>(0, (sum, k) => sum + _n(q[k]));
    Widget row(String label, double value, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontSize: bold ? 18 : 14))),
            Text(money(value, _cur), style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: bold ? 18 : 14, color: color)),
          ]),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          row('Subtotal', _n(q['subtotal'])),
          if (discounts > 0) row('Descuentos', -discounts, color: Brand.success),
          if (_n(q['tax']) > 0) row('Impuesto', _n(q['tax'])),
          row('Total', _n(q['total'])),
          if (_n(q['tip']) > 0) row('Propina', _n(q['tip'])),
          if (_n(q['credit_applied']) > 0) row('Saldo a favor', -_n(q['credit_applied']), color: Brand.success),
          const Divider(height: 18),
          row('A cobrar', _n(q['charge_now']), bold: true),
          if (_n(q['points_to_earn']) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Gana ${_n(q['points_to_earn']).toInt()} puntos con esta compra', style: const TextStyle(color: Brand.primary, fontSize: 12)),
            ),
        ]),
      ),
    );
  }
}

/// Catálogo con buscador y filtro por tipo.
class _CatalogSheet extends StatefulWidget {
  const _CatalogSheet({required this.options, required this.currency});

  final Map<String, dynamic> options;
  final String currency;

  @override
  State<_CatalogSheet> createState() => _CatalogSheetState();
}

class _CatalogSheetState extends State<_CatalogSheet> {
  String _q = '';
  String? _kind;

  @override
  Widget build(BuildContext context) {
    final all = (widget.options['catalog'] as List).cast<Map<String, dynamic>>();
    final kinds = [for (final k in _kindLabels.keys) if (all.any((i) => i['kind'] == k)) k];
    final q = _q.toLowerCase();
    final items = all.where((i) => (_kind == null || i['kind'] == _kind) && (q.isEmpty || '${i['name']}'.toLowerCase().contains(q))).toList();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Buscar servicio o producto', prefixIcon: Icon(Icons.search), isDense: true),
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
        ),
        if (kinds.length > 1)
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              Padding(padding: const EdgeInsets.all(4), child: ChoiceChip(label: const Text('Todo'), selected: _kind == null, onSelected: (_) => setState(() => _kind = null))),
              for (final k in kinds)
                Padding(padding: const EdgeInsets.all(4), child: ChoiceChip(label: Text(_kindLabels[k]!), selected: _kind == k, onSelected: (_) => setState(() => _kind = k))),
            ]),
          ),
        Expanded(
          child: items.isEmpty
              ? const EmptyView(text: 'Nada coincide con la búsqueda.', icon: Icons.search_off)
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (_, i) {
                    final it = items[i];
                    final stock = it['stock'];
                    final noStock = stock != null && _n(stock) <= 0;
                    final detail = [
                      ?_kindSingular[it['kind']],
                      if (it['duration'] != null) it['kind'] == 'service' ? '${it['duration']} min' : '${it['duration']}',
                      if (stock != null) noStock ? 'Sin stock' : 'Stock ${_n(stock) % 1 == 0 ? _n(stock).toInt() : _n(stock)}',
                      if (it['detail'] != null && '${it['detail']}'.isNotEmpty) '${it['detail']}',
                    ].join(' · ');
                    return ListTile(
                      enabled: !noStock,
                      title: Text('${it['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: detail.isEmpty ? null : Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: noStock ? Brand.danger : muted)),
                      trailing: Text(money(_n(it['price']), widget.currency), style: const TextStyle(fontWeight: FontWeight.w800)),
                      onTap: () => Navigator.pop(context, it),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

/// Elegir clienta: búsqueda, ocasional o alta rápida.
class _ClientSheet extends StatefulWidget {
  const _ClientSheet({required this.canCreate});

  final bool canCreate;

  @override
  State<_ClientSheet> createState() => _ClientSheetState();
}

class _ClientSheetState extends State<_ClientSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<ClientInfo>? _rows;
  String? _error;

  ApiClient get _api => context.read<Session>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await _api.get('/pos/clients', {'q': _search.text.trim()}) as List;
      if (mounted) setState(() => _rows = [for (final r in rows) ClientInfo.fromJson(r as Map<String, dynamic>)]);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _create() async {
    final name = TextEditingController(text: _search.text.trim());
    final phone = TextEditingController();
    final created = await showDialog<ClientInfo>(
      context: context,
      builder: (context) {
        String? error;
        var saving = false;
        return StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('Nueva clienta'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, autofocus: true, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: 'Nombre', errorText: error)),
              const SizedBox(height: 10),
              TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono (opcional)')),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        setLocal(() => saving = true);
                        try {
                          final c = await _api.post('/clients', {'full_name': name.text.trim(), 'phone': phone.text.trim().isEmpty ? null : phone.text.trim()});
                          if (context.mounted) Navigator.pop(context, ClientInfo.fromJson(c as Map<String, dynamic>));
                        } catch (e) {
                          setLocal(() {
                            saving = false;
                            error = e is ApiException ? (e.fieldErrors['full_name']?.first ?? e.message) : errorText(e);
                          });
                        }
                      },
                child: const Text('Guardar'),
              ),
            ],
          ),
        );
      },
    );
    // Sin dispose: el diálogo sigue dibujándose durante su animación de salida.
    if (created != null && mounted) Navigator.pop(context, (client: created));
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _search,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Nombre, teléfono o documento', prefixIcon: Icon(Icons.search), isDense: true),
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), _load);
            },
          ),
        ),
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
          title: const Text('Cliente ocasional'),
          subtitle: const Text('Sin ficha: no suma puntos ni usa membresías'),
          onTap: () => Navigator.pop(context, (client: null)),
        ),
        if (widget.canCreate)
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_add_alt)),
            title: const Text('Nueva clienta'),
            onTap: _create,
          ),
        const Divider(height: 1),
        Expanded(
          child: _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : rows == null
                  ? const Center(child: CircularProgressIndicator())
                  : rows.isEmpty
                      ? const EmptyView(text: 'Sin resultados.', icon: Icons.search_off)
                      : ListView.builder(
                          itemCount: rows.length,
                          itemBuilder: (_, i) => ListTile(
                            leading: Avatar(name: rows[i].name),
                            title: Text(rows[i].name),
                            subtitle: rows[i].phone == null ? null : Text(rows[i].phone!),
                            onTap: () => Navigator.pop(context, (client: rows[i])),
                          ),
                        ),
        ),
      ]),
    );
  }
}
