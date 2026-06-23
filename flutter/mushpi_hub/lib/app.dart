import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'providers/app_state_provider.dart';
import 'providers/auth_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/monitoring_screen.dart';
import 'screens/control_screen.dart';
import 'screens/stage_screen.dart';
import 'screens/farm_detail_screen.dart';
import 'screens/add_farm_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/history_screen.dart';
import 'screens/environmental_chart_screen.dart';
import 'widgets/main_scaffold.dart';

class MushPiApp extends ConsumerStatefulWidget {
  const MushPiApp({super.key});

  @override
  ConsumerState<MushPiApp> createState() => _MushPiAppState();
}

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

class _MushPiAppState extends ConsumerState<MushPiApp> {
  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'MushPi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}

class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier(this._ref) {
    _ref.listen<AuthState>(authProvider, (_, __) => notifyListeners());
  }
  final Ref _ref;
}

final _authChangeNotifierProvider = Provider<_AuthChangeNotifier>((ref) {
  return _AuthChangeNotifier(ref);
});

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(_authChangeNotifierProvider);

  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    observers: [routeObserver],
    refreshListenable: notifier,
    redirect: (context, state) {
      final authStatus = ref.read(authProvider).status;

      final isAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/signup';
      final isSplash = state.matchedLocation == '/';

      // Let splash handle its own navigation
      if (isSplash) return null;

      // If logged in, kick out of auth screens to home
      if (authStatus == AuthStatus.authenticated && isAuthRoute)
        return '/farms';

      // If not logged in, block access to protected routes
      if (authStatus != AuthStatus.authenticated && !isAuthRoute)
        return '/login';

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/signup',
        name: 'signup',
        builder: (context, state) => const SignupScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainScaffold(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/farms',
                name: 'farms',
                builder: (context, state) => const HomeScreen(),
                routes: [
                  GoRoute(
                    path: 'add',
                    name: 'add-farm',
                    builder: (context, state) => const AddFarmScreen(),
                  ),
                  GoRoute(
                    path: 'history',
                    name: 'history',
                    builder: (context, state) => const HistoryScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/monitoring',
                name: 'monitoring',
                builder: (context, state) => const MonitoringScreen(),
                routes: [
                  GoRoute(
                    path: 'charts',
                    name: 'environmental-charts',
                    builder: (context, state) =>
                        const EnvironmentalChartScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/control',
                name: 'control',
                builder: (context, state) => const ControlScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/stage',
                name: 'stage',
                builder: (context, state) => const StageScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                name: 'settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/farm/:id',
        name: 'farm-detail',
        builder: (context, state) {
          final farmId = state.pathParameters['id']!;
          return FarmDetailScreen(farmId: farmId);
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Error')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Page not found',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(state.uri.toString(),
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.go('/farms'),
              icon: const Icon(Icons.home),
              label: const Text('Go to Farms'),
            ),
          ],
        ),
      ),
    ),
  );
});
