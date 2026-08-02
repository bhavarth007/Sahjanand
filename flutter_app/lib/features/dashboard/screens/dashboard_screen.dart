import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/auth_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/sahjanand_logo.dart';
import '../../sales/screens/sales_screen.dart';
import '../../reminders/screens/reminders_screen.dart';
import '../../samples/screens/samples_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  final _screens = const [
    SalesScreen(),
    RemindersScreen(),
    SamplesScreen(),
  ];

  final _navItems = const [
    NavigationDestination(
      icon: Icon(Icons.bar_chart_outlined),
      selectedIcon: Icon(Icons.bar_chart_rounded),
      label: 'Sales',
    ),
    NavigationDestination(
      icon: Icon(Icons.notifications_outlined),
      selectedIcon: Icon(Icons.notifications_active_rounded),
      label: 'Reminders',
    ),
    NavigationDestination(
      icon: Icon(Icons.inventory_2_outlined),
      selectedIcon: Icon(Icons.inventory_2_rounded),
      label: 'Samples',
    ),
  ];

  final _titles = ['Sales', 'Reminders', 'Samples'];

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await AuthService().logout();
      context.go(AppConstants.routeLogin);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width > 700;
    return isWide ? _buildWideLayout() : _buildNarrowLayout();
  }

  // ── Desktop / tablet — persistent rail sidebar ──
  Widget _buildWideLayout() {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: AppColors.sidebarBg,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            extended: true,
            minExtendedWidth: 220,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
              child: SahjanandLogo(size: 48, textColor: Colors.white),
            ),
            trailing: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: InkWell(
                onTap: _logout,
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.logout_rounded, color: Colors.white54, size: 20),
                      SizedBox(width: 12),
                      Text('Sign Out', style: TextStyle(color: Colors.white54)),
                    ],
                  ),
                ),
              ),
            ),
            labelType: NavigationRailLabelType.none,
            destinations: _navItems.map((d) => NavigationRailDestination(
              icon: IconTheme(
                data: const IconThemeData(color: Colors.white54),
                child: d.icon,
              ),
              selectedIcon: IconTheme(
                data: const IconThemeData(color: Colors.white),
                child: d.selectedIcon ?? d.icon,
              ),
              label: Text(
                d.label,
                style: const TextStyle(color: Colors.white70),
              ),
              padding: const EdgeInsets.symmetric(vertical: 4),
            )).toList(),
          ),
          Expanded(child: _screens[_selectedIndex]),
        ],
      ),
    );
  }

  // ── Mobile — bottom navigation ──
  Widget _buildNarrowLayout() {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: _logout,
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        backgroundColor: Colors.white,
        indicatorColor: AppColors.primary.withOpacity(0.12),
        destinations: _navItems,
      ),
    );
  }
}
