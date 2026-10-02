import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/app_store.dart';
import '../data/app_config.dart';
import '../services/cloud_sync.dart';
import 'branding.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.store});
  final AppStore store;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<double>(begin: 20, end: 0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    final rawInput = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (rawInput.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your email or username and password.'),
          backgroundColor: Color(0xFF1C1C1E),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    // 1. Check for quick test / offline bypass credentials
    if (rawInput == 'test' && password == 'test123') {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        setState(() => _isLoading = false);
        final cloud = cloudFor(widget.store);
        unawaited(cloud.sync());
        context.go('/dashboard');
      }
      return;
    }

    // 2. Authenticate against Supabase Auth (supports both plain User ID and Email)
    try {
      final client = await AppConfig.getClient();
      final authEmail = AppConfig.formatAuthEmail(rawInput);
      final response = await client.auth.signInWithPassword(
        email: authEmail,
        password: password,
      );

      if (response.user != null) {
        // Switch local offline SQLite database so this shop only sees its own data
        await widget.store.switchShop(response.user!.id);

        // 3. Fetch and apply this user's shop profile from Supabase
        try {
          var shopRes = await client
              .from('shops')
              .select()
              .eq('id', response.user!.id)
              .maybeSingle();
          if (shopRes == null) {
            shopRes = await client
                .from('shops')
                .select()
                .eq('owner_id', response.user!.id)
                .maybeSingle();
          }
          if (shopRes != null) {
            await widget.store.saveSettings({
              'name': shopRes['shop_name'] ?? 'My Shop',
              'owner': shopRes['owner_name'] ?? '',
              'email': shopRes['email'] ?? (rawInput.contains('@') ? rawInput : ''),
              'phone': shopRes['phone'] ?? '',
              'gstin': shopRes['gstin'] ?? '',
              'address': shopRes['address'] ?? '',
              'state': shopRes['state'] ?? '',
            });
          } else {
            // Auto-create shop if this user logged in without completing onboarding
            await client.from('shops').upsert({
              'id': response.user!.id,
              'owner_id': response.user!.id,
              'shop_name': 'My Shop',
              'email': rawInput.contains('@') ? rawInput : '',
            });
          }
        } catch (_) {
          // Table might not exist yet if SQL migration is pending
        }

        if (mounted) {
          setState(() => _isLoading = false);
          // Trigger multi-device cloud sync
          final cloud = cloudFor(widget.store);
          unawaited(cloud.sync());
          context.go('/dashboard');
        }
      } else {
        throw const AuthException('Invalid login credentials.');
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: const Color(0xFF1C1C1E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login error: $e'),
            backgroundColor: const Color(0xFF1C1C1E),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F8),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Subtle background decoration
          Positioned(
            top: -150,
            left: -100,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blueGrey.withOpacity(0.03),
              ),
            ),
          ),
          
          Center(
            child: AnimatedBuilder(
              animation: _animController,
              builder: (context, child) {
                return Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.translate(
                    offset: Offset(0, _slideAnimation.value),
                    child: child,
                  ),
                );
              },
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      width: 400,
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 40,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.center,
                            child: srsLogoWidget(size: 60, radius: 16, showBorder: false),
                          ),
                          const SizedBox(height: 32),
                          const Text(
                            'Welcome Back',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w300,
                              letterSpacing: 1.5,
                              color: Color(0xFF1C1C1E),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Sign in to your workspace',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF8E8E93),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 40),
                          
                          // Username Field
                          TextField(
                            controller: _usernameController,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              labelText: 'Username or Email',
                              labelStyle: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.black.withOpacity(0.05)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.black.withOpacity(0.05)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFF1C1C1E)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Password Field
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              labelStyle: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.black.withOpacity(0.05)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.black.withOpacity(0.05)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFF1C1C1E)),
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton.icon(
                                onPressed: () => context.go('/onboard'),
                                icon: const Icon(Icons.storefront_outlined, size: 16, color: Color(0xFF007AFF)),
                                label: const Text(
                                  'Onboard New Shop',
                                  style: TextStyle(
                                    color: Color(0xFF007AFF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Password reset instructions will be sent to your registered email.'),
                                      backgroundColor: Color(0xFF1C1C1E),
                                    ),
                                  );
                                },
                                child: const Text(
                                  'Forgot Password?',
                                  style: TextStyle(
                                    color: Color(0xFF8E8E93),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          
                          // Login Button
                          FilledButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1C1C1E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: _isLoading 
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text(
                                  'Sign In',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'First time here? ',
                                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
                              ),
                              InkWell(
                                onTap: () => context.go('/onboard'),
                                child: const Text(
                                  'Start Onboarding',
                                  style: TextStyle(
                                    color: Color(0xFF1C1C1E),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
