import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/go_router_refresh_stream.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/collections/presentation/screens/collection_detail_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/item/domain/entities/item.dart';
import '../../features/item/presentation/screens/item_detail_screen.dart';
import '../../features/item/presentation/screens/note_editor_screen.dart';
import '../../features/library/presentation/screens/library_screen.dart';
import '../../features/search/presentation/screens/search_hub_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import 'scaffold_with_nav_bar.dart';

abstract final class AppRoutes {
  static const login = '/login';
  static const register = '/register';
  static const home = '/home';
  static const library = '/library';
  static const settings = '/settings';
  static const newNote = '/item/new';
  static const search = '/search';
}

/// Central navigation graph. Auth-gated: signed-out users can only reach
/// `/login` and `/register`; signed-in users get redirected away from them
/// into the bottom-nav shell.
final goRouterProvider = Provider<GoRouter>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);

  return GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: GoRouterRefreshStream(authRepository.authStateChanges()),
    redirect: (context, state) {
      final isLoggedIn = authRepository.currentUser != null;
      final isAuthRoute = state.matchedLocation == AppRoutes.login ||
          state.matchedLocation == AppRoutes.register;

      if (!isLoggedIn && !isAuthRoute) return AppRoutes.login;
      if (isLoggedIn && isAuthRoute) return AppRoutes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.newNote,
        builder: (context, state) => const NoteEditorScreen(),
      ),
      GoRoute(
        path: '/item/:id/note',
        builder: (context, state) => NoteEditorScreen(item: state.extra as Item),
      ),
      GoRoute(
        path: '/item/:id',
        builder: (context, state) => ItemDetailScreen(item: state.extra as Item),
      ),
      GoRoute(
        path: AppRoutes.search,
        builder: (context, state) => const SearchHubScreen(),
      ),
      GoRoute(
        path: '/collections/:id',
        builder: (context, state) => CollectionDetailScreen(
          collectionId: state.pathParameters['id']!,
          name: state.extra as String? ?? '',
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ScaffoldWithNavBar(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.home, builder: (context, state) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.library, builder: (context, state) => const LibraryScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.settings, builder: (context, state) => const SettingsScreen()),
          ]),
        ],
      ),
    ],
  );
});
