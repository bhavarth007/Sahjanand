import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';

class SahjanandLogo extends StatelessWidget {
  final double size;
  final bool showTagline;
  final Color? textColor;

  const SahjanandLogo({
    super.key,
    this.size = 80,
    this.showTagline = true,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo image — falls back to styled "S" if image not loaded
        Image.asset(
          'assets/images/logo.png',
          width: size,
          height: size,
          errorBuilder: (_, __, ___) => Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(size * 0.2),
            ),
            child: Center(
              child: Text(
                'S',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.55,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          AppConstants.appName,
          style: TextStyle(
            fontFamily: 'Cinzel',
            fontSize: size * 0.3,
            fontWeight: FontWeight.w700,
            color: textColor ?? AppColors.primary,
            letterSpacing: 2,
          ),
        ),
        if (showTagline) ...[
          const SizedBox(height: 4),
          Text(
            AppConstants.appTagline,
            style: TextStyle(
              fontSize: size * 0.14,
              color: (textColor ?? AppColors.accent).withOpacity(0.85),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ],
    );
  }
}
