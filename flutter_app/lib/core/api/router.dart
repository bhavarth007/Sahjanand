import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'api_client.dart';
import '../constants/app_constants.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';

final appRouter = GoRouter(
  initialLocation: AppConstants.routeLogin,
  redirect: (context, state) async {
    final token = await ApiClient.instance.getToken();
    final isLoginPage = state.matchedLocation == AppConstants.routeLogin ||
        state.matchedLocation == AppConstants.routeForgotPassword;

    if (token == null && !isLoginPage) return AppConstants.routeLogin;
    if (token != null && isLoginPage) return AppConstants.routeDashboard;
    return null;
  },
  routes: [
    GoRoute(
      path: AppConstants.routeLogin,
      name: 'login',
      builder: (_, __) => const LoginScreen(),
    ),
    GoRoute(
      path: AppConstants.routeForgotPassword,
      name: 'forgot-password',
      builder: (_, __) => const ForgotPasswordScreen(),
    ),
    GoRoute(
      path: AppConstants.routeDashboard,
      name: 'dashboard',
      builder: (_, __) => const DashboardScreen(),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(child: Text('Page not found: ${state.error}')),
  ),
);
