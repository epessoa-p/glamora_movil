import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'shell.dart';

/// Nombres en mayúsculas mientras se escriben (cuentas, categorías, proveedores).
class UpperCaseFormatter extends TextInputFormatter {
  const UpperCaseFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

/// Etiqueta pequeña al lado de un título («Mensual», «Caja chica», «Inactiva»).
class FinanceTag extends StatelessWidget {
  const FinanceTag(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: muted.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: muted.withValues(alpha: .2)),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: muted)),
    );
  }
}

/// Fila de Finanzas: icono en recuadro, título con etiquetas, subtítulo y flecha.
class FinanceTile extends StatelessWidget {
  const FinanceTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.tags = const [],
    this.dimmed = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final List<String> tags;
  final bool dimmed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Opacity(
      opacity: dimmed ? .55 : 1,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Brand.soft.withValues(alpha: .55), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: Brand.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 6, runSpacing: 3, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                    for (final t in tags) FinanceTag(t),
                  ]),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(subtitle!, style: TextStyle(color: muted, fontSize: 13)),
                  ],
                ]),
              ),
              if (onTap != null) Icon(Icons.chevron_right, color: muted),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Título de un grupo de filas («SERVICIOS BÁSICOS»).
class FinanceSectionTitle extends StatelessWidget {
  const FinanceSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
}

/// Una pestaña de la barra inferior de Finanzas o Gastos.
class HubTab {
  const HubTab(this.label, this.icon, this.selectedIcon, this.builder);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() builder;
}

/// Sección con título, botón de caja, perfil y barra inferior. Cada pestaña se
/// monta al visitarla y se conserva; con una sola no hay barra.
class HubScreen extends StatefulWidget {
  const HubScreen({super.key, required this.title, required this.subtitle, required this.tabs});

  final String title;
  final String subtitle;
  final List<HubTab> tabs;

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  int _index = 0;
  final _visited = <int>{0};

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabs;
    final index = _index < tabs.length ? _index : 0;
    _visited.add(index);

    // HomeShell habilita aquí el botón de caja y el perfil.
    return HomeShell(
      openDrawer: () {},
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(widget.title),
            Text(widget.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ]),
          actions: const [CashButton(), ProfileButton()],
        ),
        body: IndexedStack(
          index: index,
          children: [
            for (var i = 0; i < tabs.length; i++) _visited.contains(i) ? tabs[i].builder() : const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: tabs.length < 2
            ? null
            : NavigationBar(
                selectedIndex: index,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: [
                  for (final t in tabs) NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selectedIcon), label: t.label),
                ],
              ),
      ),
    );
  }
}
