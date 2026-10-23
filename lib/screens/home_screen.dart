import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../session.dart';
import 'agenda_screen.dart';
import 'attendance_screen.dart';
import 'clients_screen.dart';
import 'commissions_screen.dart';
import 'profile_screen.dart';

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon, this.page);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

/// Pestañas según lo que el usuario puede hacer en este salón (`abilities`).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().me!;

    final tabs = [
      if (me.seesAgenda) const _Tab('Agenda', Icons.calendar_today_outlined, Icons.calendar_today, AgendaScreen()),
      if (me.can('attendance')) const _Tab('Asistencia', Icons.schedule_outlined, Icons.schedule, AttendanceScreen()),
      if (me.can('commissions_own')) const _Tab('Comisiones', Icons.payments_outlined, Icons.payments, CommissionsScreen()),
      if (me.can('clients_view')) const _Tab('Clientes', Icons.people_outline, Icons.people, ClientsScreen()),
      const _Tab('Perfil', Icons.person_outline, Icons.person, ProfileScreen()),
    ];
    final index = _index.clamp(0, tabs.length - 1);

    return Scaffold(
      // IndexedStack conserva el estado (fecha elegida, búsqueda) al cambiar de pestaña.
      body: IndexedStack(index: index, children: [for (final t in tabs) t.page]),
      // Con una sola pestaña (solo Perfil) no hay barra: NavigationBar exige dos.
      bottomNavigationBar: tabs.length < 2 ? null : NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in tabs) NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selectedIcon), label: t.label),
        ],
      ),
    );
  }
}
