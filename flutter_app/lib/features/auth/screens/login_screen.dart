import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/auth_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/sahjanand_logo.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePass   = true;
  bool _isLoading     = false;
  String? _errorMsg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _errorMsg = null; });

    try {
      await AuthService().login(
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
      );
      if (mounted) context.go(AppConstants.routeDashboard);
    } catch (e) {
      setState(() => _errorMsg = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width > 700;

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: isWide ? _buildWideLayout() : _buildNarrowLayout(),
    );
  }

  // ── Wide layout (tablet/desktop) — two columns ──
  Widget _buildWideLayout() {
    return Row(
      children: [
        Expanded(child: _buildHeroPanel()),
        Expanded(child: _buildFormPanel()),
      ],
    );
  }

  // ── Narrow layout (phone) — single column ──
  Widget _buildNarrowLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      child: Column(
        children: [
          const SahjanandLogo(size: 160),
          const SizedBox(height: 40),
          _buildForm(),
        ],
      ),
    );
  }

  Widget _buildHeroPanel() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1C0A04), Color(0xFF6B1208), AppColors.primary],
        ),
      ),
      child: const Center(
        child: SahjanandLogo(
          size: 300,
          textColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildFormPanel() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome back',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Sign in to your Sahjanand account',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 32),

          // Error alert
          if (_errorMsg != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.error.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMsg!,
                      style: const TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Email field
          _fieldLabel('Email Address'),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            validator: Validators.email,
            decoration: const InputDecoration(
              hintText: 'you@example.com',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 16),

          // Password field
          _fieldLabel('Password'),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscurePass,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            validator: Validators.password,
            decoration: InputDecoration(
              hintText: 'Enter your password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePass ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Forgot password
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.go(AppConstants.routeForgotPassword),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              child: const Text('Forgot password?'),
            ),
          ),
          const SizedBox(height: 8),

          // Submit button
          PrimaryButton(
            label: 'Sign In',
            icon: Icons.login_rounded,
            isLoading: _isLoading,
            onPressed: _submit,
          ),

          const SizedBox(height: 32),
          Center(
            child: Text(
              '© 2026 Sahjanand. All rights reserved.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
