import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models.dart';
import '../data/providers.dart';
import '../features/admin/access_log_page.dart';
import '../features/admin/accounts_page.dart';
import '../features/admin/metrics_page.dart';
import '../features/chart/chart_page.dart';
import '../features/login/login_page.dart';
import '../features/login/password_page.dart';
import '../features/worklist/worklist_page.dart';
import 'shell.dart';

abstract final class Routes {
  static const login = '/login';
  static const password = '/password';
  static const worklist = '/';
  // Bước 18: the clinic admin's pages.
  static const accounts = '/admin/accounts';
  static const metrics = '/admin/metrics';
  static const accessLog = '/admin/access-log';
  static String visit(String id, {String tab = 'summary'}) =>
      '/visit/$id?tab=$tab';
}

/// Where a signed-in account starts.
String homeOf(Staff staff) => staff.isAdmin ? Routes.accounts : Routes.worklist;

/// Re-runs the router's redirect whenever the session changes.
class _SessionListenable extends ChangeNotifier {
  _SessionListenable(Ref ref) {
    ref.listen(sessionProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _SessionListenable(ref);
  ref.onDispose(refresh.dispose);
  return GoRouter(
    initialLocation: Routes.worklist,
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final staff = session.value?.staff;
      final at = state.matchedLocation;
      final atLogin = at == Routes.login;
      // Until the server says who is signed in, wait on the login page (it
      // shows a spinner) so no page asks for data it may not see.
      final checking = session.isLoading && !session.hasValue;
      if (staff == null || checking) {
        if (atLogin) return null;
        final from = state.uri.toString();
        return from == Routes.worklist || from == Routes.password
            ? Routes.login
            : '${Routes.login}?from=${Uri.encodeComponent(from)}';
      }
      // A one-time password must be replaced before anything else.
      if (staff.mustChangePassword) {
        return at == Routes.password ? null : Routes.password;
      }
      if (atLogin) {
        return state.uri.queryParameters['from'] ?? homeOf(staff);
      }
      // Admins manage accounts and see no charts; doctors see no admin pages.
      // The server enforces the same (403 forbidden).
      final adminPage = at.startsWith('/admin');
      if (staff.isAdmin && !adminPage && at != Routes.password) {
        return Routes.accounts;
      }
      if (!staff.isAdmin && adminPage) return Routes.worklist;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: Routes.password,
        builder: (context, state) => const PasswordPage(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: Routes.worklist,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: WorklistPage()),
          ),
          GoRoute(
            path: Routes.accounts,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: AccountsPage()),
          ),
          GoRoute(
            path: Routes.metrics,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: MetricsPage()),
          ),
          GoRoute(
            path: Routes.accessLog,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: AccessLogAdminPage()),
          ),
          GoRoute(
            path: '/visit/:id',
            pageBuilder: (context, state) => NoTransitionPage(
              child: ChartPage(
                appointmentId: state.pathParameters['id']!,
                tab: state.uri.queryParameters['tab'] ?? 'summary',
              ),
            ),
          ),
        ],
      ),
    ],
  );
});
