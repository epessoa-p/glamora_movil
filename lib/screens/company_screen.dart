import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../session.dart';
import '../util/format.dart';
import '../widgets/common.dart';

/// Selector de salón (para quien trabaja en más de uno).
class CompanyScreen extends StatefulWidget {
  const CompanyScreen({super.key});

  @override
  State<CompanyScreen> createState() => _CompanyScreenState();
}

class _CompanyScreenState extends State<CompanyScreen> {
  int? _loadingId;

  Future<void> _pick(Company company) async {
    setState(() => _loadingId = company.id);
    await context.read<Session>().selectCompany(company);
    if (mounted) setState(() => _loadingId = null);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Elige el salón'),
        actions: [TextButton(onPressed: session.logout, child: const Text('Salir'))],
      ),
      body: session.companies.isEmpty
          ? EmptyView(text: session.error ?? 'Tu usuario no tiene salones activos.', icon: Icons.storefront_outlined)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (session.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(session.error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
                  ),
                for (final c in session.companies)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: hexColor(c.primaryColor, Theme.of(context).colorScheme.primary),
                          foregroundImage: c.logoUrl == null ? null : NetworkImage(c.logoUrl!),
                          child: Text(initials(c.name), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: _loadingId == c.id
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                            : const Icon(Icons.chevron_right),
                        onTap: _loadingId == null ? () => _pick(c) : null,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
