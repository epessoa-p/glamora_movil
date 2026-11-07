import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/shell.dart';
import 'agenda_screen.dart';
import 'attendance_screen.dart';
import 'birthdays_screen.dart';
import 'cash_screen.dart';
import 'clients_screen.dart';
import 'commissions_screen.dart';
import 'dashboard_screen.dart';
import 'finance_screen.dart';
import 'pos_screen.dart';
import 'profile_screen.dart';
import 'receivables_screen.dart';
import 'reminders_screen.dart';
import 'reports_screen.dart';
import 'sales_screen.dart';
import 'schedule_screen.dart';
import 'services_screen.dart';
import 'settings_screen.dart';

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon, this.page);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

/// Pestañas según lo que el usuario puede hacer en este salón (`abilities`),
/// más un menú lateral con todas las secciones. El perfil se abre desde el
/// avatar de arriba a la derecha.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scaffold = GlobalKey<ScaffoldState>();
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me!;

    // Gerencia ve el Panel primero; sus comisiones quedan en el menú.
    final manager = me.can('dashboard');
    final tabs = [
      if (manager) const _Tab('Panel', Icons.dashboard_outlined, Icons.dashboard, DashboardScreen()),
      if (me.seesAgenda) const _Tab('Agenda', Icons.calendar_today_outlined, Icons.calendar_today, AgendaScreen()),
      if (me.can('attendance')) const _Tab('Asistencia', Icons.schedule_outlined, Icons.schedule, AttendanceScreen()),
      if (me.can('commissions_own') && !manager) const _Tab('Comisiones', Icons.payments_outlined, Icons.payments, CommissionsScreen()),
      if (me.can('clients_view')) const _Tab('Clientes', Icons.people_outline, Icons.people, ClientsScreen()),
    ];
    final index = tabs.isEmpty ? 0 : _index.clamp(0, tabs.length - 1);

    return HomeShell(
      openDrawer: () => _scaffold.currentState?.openDrawer(),
      child: Scaffold(
        key: _scaffold,
        drawer: _HomeDrawer(
          tabs: tabs,
          index: index,
          onTab: (i) => setState(() => _index = i),
        ),
        // IndexedStack conserva el estado (fecha elegida, búsqueda) al cambiar de pestaña.
        // Sin pestañas (sin ficha ni permisos) queda el perfil con la explicación.
        body: tabs.isEmpty ? const ProfileScreen() : IndexedStack(index: index, children: [for (final t in tabs) t.page]),
        // NavigationBar exige al menos dos destinos.
        bottomNavigationBar: tabs.length < 2 ? null : NavigationBar(
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

class _HomeDrawer extends StatelessWidget {
  const _HomeDrawer({required this.tabs, required this.index, required this.onTab});

  final List<_Tab> tabs;
  final int index;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final me = session.me!;
    final name = me.personal?.fullName ?? me.user.name;

    // Cierra el menú y abre la pantalla encima del inicio.
    void open(Widget screen) {
      Navigator.pop(context);
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    }

    final more = [
      if (me.can('sales_create')) ('Cobrar', Icons.point_of_sale, const PosScreen()),
      if (me.can('sales_create') || me.can('sales_view')) ('Ventas', Icons.receipt_outlined, const SalesScreen()),
      if (me.can('cash_view')) ('Caja', Icons.point_of_sale_outlined, const CashScreen()),
      if (me.can('expenses_view')) ('Gastos', Icons.request_quote_outlined, const ExpensesScreen()),
      if (FinanceScreen.visibleFor(session)) ('Finanzas', Icons.account_balance_outlined, const FinanceScreen()),
      if (me.can('services_view')) ('Servicios', Icons.content_cut, const ServicesScreen()),
      if (me.can('dashboard') && me.can('commissions_own')) ('Mis comisiones', Icons.payments_outlined, const CommissionsScreen()),
      if (me.can('receivables')) ('Cuentas por cobrar', Icons.receipt_long_outlined, const ReceivablesScreen()),
      if (me.can('reminders')) ('Recordatorios', Icons.notifications_active_outlined, const RemindersScreen()),
      if (me.can('birthdays')) ('Cumpleaños', Icons.cake_outlined, const BirthdaysScreen()),
      if (me.can('schedule')) ('Mi horario', Icons.calendar_month_outlined, const ScheduleScreen()),
    ];

    return Drawer(
      backgroundColor: Colors.white,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 20, 20, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Brand.primary, Brand.rose], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            // Logo del salón y, al costado, su nombre y el de quien usa la app.
            child: Row(
              children: [
                CompanyLogo(name: me.company.name, url: me.company.logoUrl, radius: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(me.company.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < tabs.length; i++)
            _item(
              context,
              tabs[i].label,
              i == index ? tabs[i].selectedIcon : tabs[i].icon,
              selected: i == index,
              onTap: () {
                Navigator.pop(context);
                onTab(i);
              },
            ),
          if (more.isNotEmpty) ...[
            const Divider(indent: 16, endIndent: 16),
            for (final (label, icon, screen) in more) _item(context, label, icon, onTap: () => open(screen)),
          ],
          // Mi perfil está en el avatar de arriba; aquí van Reportes y Configuración.
          const Divider(indent: 16, endIndent: 16),
          if (me.can('reports')) _item(context, 'Reportes', Icons.insights_outlined, onTap: () => open(const ReportsScreen())),
          if (SettingsScreen.visibleFor(me)) _item(context, 'Configuración', Icons.settings_outlined, onTap: () => open(const SettingsScreen())),
          if (session.companies.length > 1)
            _item(context, 'Cambiar de salón', Icons.swap_horiz, onTap: () {
              Navigator.pop(context);
              session.switchCompany();
            }),
          _item(context, 'Cerrar sesión', Icons.logout, danger: true, onTap: () async {
            // Se confirma con el menú abierto: al cerrarlo, este contexto deja de existir.
            final ok = await confirm(context, title: 'Cerrar sesión', message: '¿Salir de Glamora en este dispositivo?', ok: 'Salir');
            if (ok) await session.logout();
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, String label, IconData icon, {required VoidCallback onTap, bool selected = false, bool danger = false}) {
    final color = danger ? Theme.of(context).colorScheme.error : (selected ? Brand.primary : null);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label, style: TextStyle(color: color, fontWeight: selected || danger ? FontWeight.w700 : FontWeight.w500)),
        selected: selected,
        selectedTileColor: Brand.soft.withValues(alpha: .5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: onTap,
      ),
    );
  }
}
