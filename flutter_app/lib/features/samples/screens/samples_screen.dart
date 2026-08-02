import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class SamplesScreen extends StatelessWidget {
  const SamplesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Samples'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload_outlined),
            onPressed: () {},
            tooltip: 'Upload Sample',
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.image_outlined, size: 40, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            const Text(
              'No samples yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap the upload button to add your first sample.',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.cloud_upload_rounded),
              label: const Text('Upload Sample'),
            ),
          ],
        ),
      ),
    );
  }
}
