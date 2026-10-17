import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/widgets/widgets.dart';
import '../data/providers.dart';
import 'router.dart';
import 'theme.dart';

/// Top bar with the clinic and the doctor, and a slim navigation rail, like
/// the prototype. On phones the rail is hidden; the worklist is one tap away
/// from every page through the back link.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = DwColors.of(context);
    final session = ref.watch(sessionProvider).value;
    final wide = MediaQuery.sizeOf(context).width > 640;
    final location = GoRouterState.of(context).uri.path;
    final admin = session?.staff.isAdmin ?? false;
    final adminIndex = _adminPages.indexWhere((p) => p.$1 == location);
    return Scaffold(
      // Phones have no rail: the admin switches pages at the bottom.
      bottomNavigationBar: admin && !wide
          ? NavigationBar(
              height: 64,
              selectedIndex: adminIndex < 0 ? 0 : adminIndex,
              onDestinationSelected: (i) => context.go(_adminPages[i].$1),
              destinations: [
                for (final (_, icon, label) in _adminPages)
                  NavigationDestination(icon: Icon(icon), label: label),
              ],
            )
          : null,
      body: Column(
        children: [
          Container(
            height: Dw.bar,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(bottom: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: c.brand,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    LucideIcons.stethoscope,
                    size: 17,
                    color: c.brandFg,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'MedicApp Bác sĩ',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (wide && session != null) ...[
                  const SizedBox(width: 14),
                  Container(width: 1, height: 20, color: c.line),
                  const SizedBox(width: 14),
                  Flexible(
                    child: Text(
                      session.clinic.name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
                const Spacer(),
                if (session != null)
                  PopupMenuButton<String>(
                    tooltip: 'Tài khoản',
                    onSelected: (value) => value == 'password'
                        ? context.go(Routes.password)
                        : ref.read(sessionProvider.notifier).logout(),
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'password',
                        child: Row(
                          children: [
                            Icon(LucideIcons.keyRound, size: 16),
                            SizedBox(width: 10),
                            Text('Đổi mật khẩu'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'logout',
                        child: Row(
                          children: [
                            Icon(LucideIcons.logOut, size: 16),
                            SizedBox(width: 10),
                            Text('Đăng xuất'),
                          ],
                        ),
                      ),
                    ],
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 15,
                          backgroundColor: c.brandSoft,
                          child: Text(
                            initials(session.staff.name),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: c.brandInk,
                            ),
                          ),
                        ),
                        if (wide) ...[
                          const SizedBox(width: 8),
                          Text(
                            session.staff.name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        Icon(LucideIcons.chevronDown, size: 16, color: c.muted),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide)
                  Container(
                    width: Dw.rail,
                    decoration: BoxDecoration(
                      color: c.surface,
                      border: Border(right: BorderSide(color: c.line)),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      spacing: 4,
                      children: [
                        if (admin)
                          for (final (route, icon, label) in _adminPages)
                            _RailItem(
                              icon: icon,
                              label: label,
                              selected: location == route,
                              onTap: () => context.go(route),
                            )
                        else
                          _RailItem(
                            icon: LucideIcons.listTodo,
                            label: 'Hàng chờ',
                            selected:
                                location == Routes.worklist ||
                                location.startsWith('/visit'),
                            onTap: () => context.go(Routes.worklist),
                          ),
                      ],
                    ),
                  ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The admin's pages, in rail order.
const _adminPages = [
  (Routes.accounts, LucideIcons.usersRound, 'Tài khoản'),
  (Routes.metrics, LucideIcons.chartColumn, 'Số liệu'),
  (Routes.accessLog, LucideIcons.scrollText, 'Nhật ký'),
];

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Dw.radius),
        child: Container(
          width: 64,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? c.brandSoft : null,
            borderRadius: BorderRadius.circular(Dw.radius),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: selected ? c.brandInk : c.fg2),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? c.brandInk : c.fg2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
