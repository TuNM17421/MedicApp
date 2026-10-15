import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/account_page.dart';
import '../../features/booking/presentation/booking_page.dart';
import '../../features/booking/presentation/appointment_pages.dart';
import '../../features/booking/presentation/booking_demo_page.dart';
import '../../features/design_preview/design_preview_page.dart';
import '../../features/home/home_page.dart';
import '../../features/notifications/notification_pages.dart';
import '../../features/profiles/profile_pages.dart';
import '../../features/support/support_pages.dart';
import '../app_shell.dart';
import 'app_routes.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  // UI state changes must not recreate the router and lose branch history.
  final router = createAppRouter();
  ref.onDispose(router.dispose);
  return router;
});

// Explicit Flutter MaterialPage keeps page transitions compatible with the
// existing flutter/material.dart theme (go_router 18 also supports material_ui).
GoRoute _route({
  required String path,
  required Widget Function(BuildContext, GoRouterState) builder,
  List<RouteBase> routes = const [],
}) => GoRoute(
  path: path,
  routes: routes,
  pageBuilder: (context, state) =>
      MaterialPage<void>(key: state.pageKey, child: builder(context, state)),
);

GoRouter createAppRouter({String initialLocation = AppRoutes.home}) {
  final root = GlobalKey<NavigatorState>(debugLabel: 'root');
  return GoRouter(
    navigatorKey: root,
    initialLocation: initialLocation,
    errorPageBuilder: (context, state) => MaterialPage<void>(
      key: state.pageKey,
      child: const RouteNotFoundPage(),
    ),
    routes: [
      GoRoute(path: '/', redirect: (context, state) => AppRoutes.home),
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, shell) => MaterialPage<void>(
          key: state.pageKey,
          child: AppShell(navigationShell: shell),
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              _route(
                path: AppRoutes.home,
                builder: (_, _) => const HomePage(),
                routes: [
                  _route(
                    path: 'appointments',
                    builder: (_, _) => const AppointmentsPage(),
                    routes: [
                      _route(
                        path: ':id',
                        builder: (_, state) => AppointmentDetailPage(
                          id: state.pathParameters['id']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              _route(
                path: AppRoutes.profiles,
                builder: (_, _) => const ProfilesPage(),
                routes: [
                  _route(
                    path: ':id',
                    builder: (_, state) =>
                        ProfileDetailPage(id: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              _route(
                path: AppRoutes.notifications,
                builder: (_, _) => const NotificationsPage(),
                routes: [
                  _route(
                    path: ':id',
                    builder: (_, state) =>
                        NotificationDetailPage(id: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              _route(
                path: AppRoutes.account,
                builder: (_, _) => const AccountPage(),
              ),
            ],
          ),
        ],
      ),
      _route(path: AppRoutes.booking, builder: (_, _) => const BookingPage()),
      _route(path: AppRoutes.help, builder: (_, _) => const HelpPage()),
      _route(
        path: AppRoutes.bookingDemo,
        builder: (_, _) => const BookingDemoPage(),
      ),
      _route(
        path: AppRoutes.designPreview,
        builder: (_, _) => const DesignPreviewPage(),
      ),
    ],
  );
}
