import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/account_page.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/auth/auth_pages.dart';
import '../../features/booking/presentation/booking_page.dart';
import '../../features/consent/health_consent_page.dart';
import '../../features/booking/presentation/appointment_pages.dart';
import '../../features/booking/presentation/booking_demo_page.dart';
import '../../features/design_preview/design_preview_page.dart';
import '../../features/smart/presentation/smart_page.dart';
import '../../features/home/home_page.dart';
import '../../features/notifications/notification_pages.dart';
import '../../features/profiles/add_profile_pages.dart';
import '../../features/profiles/profile_pages.dart';
import '../../features/support/support_pages.dart';
import '../app_shell.dart';
import '../state/app_state.dart';
import 'app_routes.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  // UI state changes must not recreate the router and lose branch history,
  // so sign-in changes only re-run the redirect.
  final refresh = ValueNotifier(0);
  ref.listen(authSessionProvider, (_, _) => refresh.value++);
  ref.listen(profileCatalogProvider, (_, _) => refresh.value++);
  final router = createAppRouter(
    refreshListenable: refresh,
    redirect: (location) => authRedirect(
      location,
      signedIn: ref.read(authSessionProvider) != null,
      hasProfile: ref.read(profileCatalogProvider).isNotEmpty,
    ),
  );
  ref.onDispose(router.dispose);
  ref.onDispose(refresh.dispose);
  return router;
});

/// Signed out: only the welcome, sign-in and sign-up pages. Signed in without
/// an own profile yet: only the profile creation pages.
String? authRedirect(
  String location, {
  required bool signedIn,
  required bool hasProfile,
}) {
  final path = Uri.parse(location).path;
  final isAuth = AppRoutes.authPaths.contains(path);
  final isProfileSetup = AppRoutes.profileSetupPaths.contains(path);
  if (!signedIn) return isAuth ? null : AppRoutes.welcome;
  if (!hasProfile) {
    return isProfileSetup ? null : AppRoutes.addProfile(self: true);
  }
  return isAuth ? AppRoutes.home : null;
}

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

GoRouter createAppRouter({
  String initialLocation = AppRoutes.home,
  Listenable? refreshListenable,
  String? Function(String location)? redirect,
}) {
  final root = GlobalKey<NavigatorState>(debugLabel: 'root');
  return GoRouter(
    navigatorKey: root,
    initialLocation: initialLocation,
    refreshListenable: refreshListenable,
    redirect: redirect == null
        ? null
        : (context, state) => redirect(state.uri.toString()),
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
      _route(path: AppRoutes.welcome, builder: (_, _) => const WelcomePage()),
      _route(path: AppRoutes.signIn, builder: (_, _) => const SignInPage()),
      _route(path: AppRoutes.signUp, builder: (_, _) => const SignUpPage()),
      _route(
        path: AppRoutes.addProfilePath,
        builder: (_, state) =>
            AddProfilePage(self: state.uri.queryParameters['for'] == 'self'),
      ),
      _route(
        path: AppRoutes.scanCccdPath,
        builder: (_, state) =>
            CccdScanPage(self: state.uri.queryParameters['for'] == 'self'),
      ),
      _route(
        path: AppRoutes.profileFormPath,
        builder: (_, state) =>
            ProfileFormPage(self: state.uri.queryParameters['for'] == 'self'),
      ),
      _route(path: AppRoutes.booking, builder: (_, _) => const BookingPage()),
      _route(
        path: AppRoutes.smart,
        builder: (_, state) => SmartPage(
          fromBooking: state.uri.queryParameters['from'] == 'booking',
        ),
      ),
      _route(path: AppRoutes.help, builder: (_, _) => const HelpPage()),
      _route(
        path: AppRoutes.healthConsent,
        builder: (_, _) => const HealthConsentPage(),
      ),
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
