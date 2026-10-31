import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../session.dart';
import '../widgets/common.dart';
import '../widgets/shell.dart';
import 'commissions_screen.dart';
import 'receivables_screen.dart';
import 'schedule_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final me = session.me!;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(leading: shellLeading(context), title: const Text('Perfil')),
      body: RefreshIndicator(
        onRefresh: session.refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(child: Avatar(name: me.personal?.fullName ?? me.user.name, radius: 40)),
            const SizedBox(height: 12),
            Text(me.personal?.fullName ?? me.user.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            if (me.personal?.cargo != null) Text(me.personal!.cargo!, textAlign: TextAlign.center, style: TextStyle(color: muted)),
            if (me.user.email != null) Text(me.user.email!, textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 13)),
            const SizedBox(height: 20),
            if (me.personal == null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Sin ficha de personal'),
                  subtitle: const Text('Tu usuario no está vinculado al personal de este salón, por eso no ves tu agenda, asistencia ni comisiones. Pídele al administrador que te vincule en Configuración › Personal.'),
                  isThreeLine: true,
                ),
              ),
            if (me.personal == null) const SizedBox(height: 10),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.storefront_outlined),
                    title: Text(me.company.name),
                    subtitle: const Text('Salón activo'),
                  ),
                  // Con el Panel, Comisiones no tiene pestaña propia.
                  if (me.can('dashboard') && me.can('commissions_own')) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.payments_outlined),
                      title: const Text('Mis comisiones'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommissionsScreen())),
                    ),
                  ],
                  if (me.can('receivables')) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: const Text('Cuentas por cobrar'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReceivablesScreen())),
                    ),
                  ],
                  if (me.can('schedule')) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.calendar_month_outlined),
                      title: const Text('Mi horario'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScheduleScreen())),
                    ),
                  ],
                  if (session.companies.length > 1) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.swap_horiz),
                      title: const Text('Cambiar de salón'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: session.switchCompany,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
                title: Text('Cerrar sesión', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
                onTap: () async {
                  final ok = await confirm(context, title: 'Cerrar sesión', message: '¿Salir de Glamora en este dispositivo?', ok: 'Salir');
                  if (ok) await session.logout();
                },
              ),
            ),
            const SizedBox(height: 24),
            Text('Glamora · v${AppConfig.appVersion}', textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 12)),
            Text(Uri.parse(AppConfig.apiUrl).host, textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
