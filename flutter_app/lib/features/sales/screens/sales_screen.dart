import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class SalesScreen extends StatelessWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            backgroundColor: Colors.white,
            title: const Text('Sales Dashboard'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_rounded),
                onPressed: () {},
                tooltip: 'Add Sale',
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Stats row
                Row(
                  children: [
                    _statCard('Total Revenue', '₹0', Icons.currency_rupee_rounded, AppColors.primary),
                    const SizedBox(width: 12),
                    _statCard('Orders', '0', Icons.shopping_bag_outlined, AppColors.accentDark),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _statCard('Customers', '0', Icons.people_outline_rounded, Colors.blue.shade700),
                    const SizedBox(width: 12),
                    _statCard('Samples Sent', '0', Icons.inventory_2_outlined, Colors.green.shade700),
                  ],
                ),
                const SizedBox(height: 24),

                // Recent sales
                const Text('Recent Sales', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                _emptyState(
                  icon: Icons.bar_chart_rounded,
                  message: 'No sales yet.\nTap + to add your first sale.',
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: color.withOpacity(0.08), blurRadius: 8)],
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState({required IconData icon, required String message}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: AppColors.border),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
        ],
      ),
    );
  }
}
