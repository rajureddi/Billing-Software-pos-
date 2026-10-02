import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/app_store.dart';
import '../data/app_config.dart';
import '../services/cloud_sync.dart';
import 'branding.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.store});
  final AppStore store;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  final int _totalSteps = 3;

  // Controllers for onboarding form fields
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _shopNameController = TextEditingController();
  final _categoryController = TextEditingController(text: 'Hardware, Cement & Steel');
  final _taglineController = TextEditingController();
  final _phoneController = TextEditingController();
  final _taxIdController = TextEditingController();
  final _addressController = TextEditingController();
  final _stateController = TextEditingController();

  bool _obscurePassword = true;
  bool _isSubmitting = false;

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
    _fadeAnimation = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnimation = Tween<double>(begin: 20, end: 0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _shopNameController.dispose();
    _categoryController.dispose();
    _taglineController.dispose();
    _phoneController.dispose();
    _taxIdController.dispose();
    _addressController.dispose();
    _stateController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep == 0) {
      if (_nameController.text.trim().isEmpty) {
        _showToast('Please enter your full name');
        return;
      }
      if (_emailController.text.trim().isEmpty) {
        _showToast('Please enter your email or user ID');
        return;
      }
      if (_passwordController.text.trim().length < 6) {
        _showToast('Password must be at least 6 characters');
        return;
      }
    } else if (_currentStep == 1) {
      if (_shopNameController.text.trim().isEmpty) {
        _showToast('Please enter your shop or business name');
        return;
      }
    }

    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finishOnboarding();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF1C1C1E),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _finishOnboarding() async {
    final rawIdentifier = _emailController.text.trim();
    final authEmail = AppConfig.formatAuthEmail(rawIdentifier);
    final password = _passwordController.text.trim();
    final ownerName = _nameController.text.trim();
    final customTagline = _taglineController.text.trim();
    final tagline = customTagline.isNotEmpty
        ? customTagline
        : (ownerName.isNotEmpty ? 'Proprietor: $ownerName' : '');

    setState(() => _isSubmitting = true);

    try {
      final url = AppConfig.supabaseUrl;
      final key = AppConfig.supabaseAnonKey;

      if (url.isEmpty || key.isEmpty) {
        throw Exception('Supabase URL or Key not found in .env. Please check your .env configuration.');
      }

      final client = await AppConfig.getClient();

      // 1. Real Supabase Auth Registration (supports both plain User ID and Email)
      final authRes = await client.auth.signUp(
        email: authEmail,
        password: password,
        data: {
          'user_id': rawIdentifier,
          'owner_name': ownerName,
          'shop_name': _shopNameController.text.trim(),
        },
      );

      final user = authRes.user;

      if (user == null) {
        throw const AuthException('Could not create account. Please try again.');
      }

      // 2. Switch local SQLite database to be completely isolated for this new shop
      await widget.store.switchShop(user.id);

      // 3. Save new shop settings into store
      await widget.store.saveSettings({
        'name': _shopNameController.text.trim(),
        'owner': ownerName,
        'tagline': tagline,
        'category': _categoryController.text.trim().isNotEmpty
            ? _categoryController.text.trim()
            : 'Hardware, Cement & Steel',
        'email': rawIdentifier.contains('@') ? rawIdentifier : '',
        'userId': rawIdentifier,
        'phone': _phoneController.text.trim(),
        'gstin': _taxIdController.text.trim(),
        'address': _addressController.text.trim(),
        'state': _stateController.text.trim(),
      });

      // 4. Record shop in Supabase with id matching user.id
      try {
        await client.from('shops').upsert({
          'id': user.id,
          'owner_id': user.id,
          'shop_name': _shopNameController.text.trim(),
          'owner_name': ownerName,
          'email': rawIdentifier.contains('@') ? rawIdentifier : '',
          'phone': _phoneController.text.trim(),
          'gstin': _taxIdController.text.trim(),
          'address': _addressController.text.trim(),
          'state': _stateController.text.trim(),
        });
      } catch (_) {
        // Table might not exist yet if user hasn't run the SQL script
      }

      // Configure & trigger multi-device cloud sync
      final cloud = cloudFor(widget.store);
      unawaited(cloud.sync());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_shopNameController.text.trim()} onboarded successfully!'),
            backgroundColor: const Color(0xFF1C1C1E),
          ),
        );
        context.go('/dashboard');
      }
    } on AuthException catch (e) {
      if (mounted) {
        _showToast(e.message);
      }
    } catch (e) {
      if (mounted) {
        _showToast('Registration error: ${e.toString().replaceAll('Exception:', '')}');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    int maxLines = 1,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.black.withOpacity(0.06)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.black.withOpacity(0.06)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF1C1C1E)),
          ),
        ),
      ),
    );
  }

  Widget _buildStep1() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Account & Credentials',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w300, letterSpacing: 1.0),
          ),
          const SizedBox(height: 6),
          const Text(
            'Create your owner account to manage your shop.',
            style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
          ),
          const SizedBox(height: 24),
          _buildTextField(label: 'Owner Full Name', controller: _nameController),
          _buildTextField(
            label: 'User ID or Email',
            controller: _emailController,
            keyboardType: TextInputType.text,
          ),
          _buildTextField(
            label: 'Set Password (min 6 chars)',
            controller: _passwordController,
            obscureText: _obscurePassword,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 18,
                color: const Color(0xFF8E8E93),
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Shop Information',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w300, letterSpacing: 1.0),
          ),
          const SizedBox(height: 6),
          const Text(
            'Details printed on your invoices and reports.',
            style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
          ),
          const SizedBox(height: 24),
          _buildTextField(label: 'Shop / Business Name', controller: _shopNameController),
          _buildTextField(label: 'Business Category', controller: _categoryController),
          _buildTextField(label: 'Tagline (Optional)', controller: _taglineController),
          _buildTextField(
            label: 'Contact Phone Number',
            controller: _phoneController,
            keyboardType: TextInputType.phone,
          ),
          _buildTextField(label: 'GSTIN / Tax ID (Optional)', controller: _taxIdController),
        ],
      ),
    );
  }

  Widget _buildStep3() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Location & City',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w300, letterSpacing: 1.0),
          ),
          const SizedBox(height: 6),
          const Text(
            'Where is your business located?',
            style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
          ),
          const SizedBox(height: 24),
          _buildTextField(label: 'State / Region', controller: _stateController),
          _buildTextField(
            label: 'Store Address / Street',
            controller: _addressController,
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F8),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            bottom: -150,
            right: -100,
            child: Container(
              width: 600,
              height: 600,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blueGrey.withOpacity(0.04),
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
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      width: 480,
                      constraints: const BoxConstraints(minHeight: 560),
                      padding: const EdgeInsets.all(36),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white, width: 1.5),
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
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              srsLogoWidget(size: 38, radius: 12, showBorder: false),
                              TextButton.icon(
                                onPressed: () => context.go('/login'),
                                icon: const Icon(Icons.arrow_back, size: 14, color: Color(0xFF8E8E93)),
                                label: const Text(
                                  'Already have account? Sign In',
                                  style: TextStyle(
                                    color: Color(0xFF1C1C1E),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          
                          // Progress Indicator
                          Row(
                            children: List.generate(_totalSteps, (index) {
                              return Expanded(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  margin: const EdgeInsets.only(right: 8),
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: index <= _currentStep 
                                      ? const Color(0xFF1C1C1E) 
                                      : Colors.black.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 28),
                          
                          SizedBox(
                            height: 330,
                            child: PageView(
                              controller: _pageController,
                              physics: const NeverScrollableScrollPhysics(),
                              onPageChanged: (index) {
                                setState(() => _currentStep = index);
                              },
                              children: [
                                _buildStep1(),
                                _buildStep2(),
                                _buildStep3(),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (_currentStep > 0)
                                TextButton(
                                  onPressed: _previousStep,
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF8E8E93),
                                  ),
                                  child: const Text('Back', style: TextStyle(letterSpacing: 0.5)),
                                )
                              else
                                const SizedBox.shrink(),
                                
                              FilledButton(
                                onPressed: _isSubmitting ? null : _nextStep,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF1C1C1E),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: _isSubmitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : Text(
                                      _currentStep == _totalSteps - 1 ? 'Complete & Launch' : 'Continue',
                                      style: const TextStyle(fontWeight: FontWeight.w500, letterSpacing: 0.5),
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
