import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/app_headers.dart';
import 'router/app_routes.dart';
import 'state/app_state.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;
  static const _navPositions = [0, 1, 3, 4];

  @override
  Widget build(BuildContext context, WidgetRef ref) => BackButtonListener(
    onBackButtonPressed: () async {
      // Nested pages and root overlays get the first opportunity to pop.
      if (GoRouter.of(context).canPop()) return false;
      if (navigationShell.currentIndex != 0) {
        navigationShell.goBranch(0);
        return true;
      }
      return false;
    },
    child: Scaffold(
      body: navigationShell,
      bottomNavigationBar: AppBottomNav(
        key: const Key('app-bottom-nav'),
        selectedIndex: _navPositions[navigationShell.currentIndex],
        unreadCount: ref.watch(unreadCountProvider),
        onSelected: (position) {
          if (position == 2) {
            context.push(AppRoutes.booking);
            return;
          }
          final branch = _navPositions.indexOf(position);
          navigationShell.goBranch(
            branch,
            initialLocation: branch == navigationShell.currentIndex,
          );
        },
      ),
    ),
  );
}
