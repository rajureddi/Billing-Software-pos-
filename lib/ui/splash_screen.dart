import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/app_store.dart';
import 'branding.dart';
import 'common.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.store});
  final AppStore store;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    _scaleAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();

    _timer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) {
        context.go('/dashboard');
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  // SRS Logo with glowing shadow
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFC42B2B).withValues(alpha: 0.18),
                          blurRadius: 36,
                          spreadRadius: 8,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: srsLogoWidget(size: 140, radius: 70, showBorder: false),
                  ),
                  const SizedBox(height: 28),

                  // Brand Name
                  const Text(
                    'SRS AGENCIES',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Tagline
                  const Text(
                    'HARDWARE & BUILDING MATERIALS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: Color(0xFFC42B2B),
                    ),
                  ),
                  const Spacer(),

                  // Bottom subtle loader
                  SizedBox(
                    width: 120,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: const LinearProgressIndicator(
                        minHeight: 3,
                        backgroundColor: Color(0xFFEEEEEE),
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFFC42B2B)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Offline-Ready Retail Billing System',
                    style: TextStyle(
                      fontSize: 11,
                      color: muted,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
