import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/providers.dart';
import '../features/chart/chart_page.dart';
import '../features/login/login_page.dart';
import '../features/worklist/worklist_page.dart';
import 'shell.dart';

abstract final class Routes {
  static const login = '/login';
  static const worklist = '/';
  static String visit(String id, {String tab = 'summary'}) =>
      '/visit/$id?tab=$tab';
}

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
      if (session.isLoading && !session.hasValue) return null;
      final signedIn = session.value != null;
      final atLogin = state.matchedLocation == Routes.login;
      if (!signedIn && !atLogin) {
        final from = state.uri.toString();
        return from == Routes.worklist
            ? Routes.login
            : '${Routes.login}?from=${Uri.encodeComponent(from)}';
      }
      if (signedIn && atLogin) {
        return state.uri.queryParameters['from'] ?? Routes.worklist;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginPage(),
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
