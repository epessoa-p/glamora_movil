import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../session.dart';
import '../widgets/finance_widgets.dart';
import 'accounts_screen.dart';
import 'expense_categories_screen.dart';
import 'expenses_screen.dart';

/// Finanzas: Cuentas y Categorías de gasto, según permisos.
class FinanceScreen extends StatelessWidget {
  const FinanceScreen({super.key});

  static bool visibleFor(Session session) {
    final me = session.me;
    return me != null && (me.can('accounts_view') || me.can('expense_categories_view'));
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me;
    if (me == null) return const Scaffold(); // sesión cerrada: la pantalla se está yendo

    return HubScreen(title: 'Finanzas', subtitle: me.company.name, tabs: [
      if (me.can('accounts_view')) HubTab('Cuentas', Icons.account_balance_outlined, Icons.account_balance, () => const AccountsTab()),
      if (me.can('expense_categories_view')) HubTab('Categorías', Icons.label_outline, Icons.label, () => const ExpenseCategoriesTab()),
    ]);
  }
}

/// Gastos: cada tipo en su pestaña, sin repetirse.
class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me;
    if (me == null) return const Scaffold(); // sesión cerrada: la pantalla se está yendo

    return HubScreen(title: 'Gastos', subtitle: me.company.name, tabs: [
      HubTab('Gastos', Icons.receipt_long_outlined, Icons.receipt_long, () => const ExpensesTab(group: 'general')),
      HubTab('Proveedores', Icons.local_shipping_outlined, Icons.local_shipping, () => const ExpensesTab(group: 'proveedor')),
      HubTab('Personal', Icons.badge_outlined, Icons.badge, () => const ExpensesTab(group: 'personal')),
      HubTab('Servicios', Icons.home_work_outlined, Icons.home_work, () => const ExpensesTab(group: 'basicos')),
    ]);
  }
}
