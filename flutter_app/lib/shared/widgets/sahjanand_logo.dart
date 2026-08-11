import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

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
    // Show only the top icon portion of the logo (crop out bottom text)
    return SizedBox(
      width: size,
      height: size,
      child: ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: 0.55,
          child: Image.asset(
            'assets/images/logo.png',
            width: size,
            fit: BoxFit.fitWidth,
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
        ),
      ),
    );
  }
}
