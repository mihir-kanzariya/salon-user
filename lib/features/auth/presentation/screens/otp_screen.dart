import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/i18n/locale_provider.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/utils/snackbar_utils.dart';
import '../providers/auth_provider.dart';
import '../../../salon/providers/salon_provider.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  static const _otpLen = AppConstants.otpLength;
  final List<TextEditingController> _controllers = List.generate(_otpLen, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(_otpLen, (_) => FocusNode());
  bool _isVerifying = false;
  int _resendCountdown = 30;
  Timer? _resendTimer;
  int _resendAttempts = 0;
  static const int _maxResendAttempts = 5;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendCountdown = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        _resendCountdown--;
        if (_resendCountdown <= 0) {
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _otp => _controllers.map((c) => c.text).join();

  Future<void> _verifyOtp() async {
    if (_isVerifying) return;
    if (_otp.length != _otpLen) {
      SnackbarUtils.showError(context, 'Please enter complete OTP');
      return;
    }

    _isVerifying = true;
    try {
      final provider = context.read<AuthProvider>();
      final success = await provider.verifyOtp(_otp);

      if (!mounted) return;

      if (success) {
        if (provider.state == AuthState.profileIncomplete) {
          Navigator.pushReplacementNamed(context, '/profile-setup');
        } else {
          final role = provider.user?.role ?? 'customer';
          if (role == 'salon_user') {
            await context.read<SalonProvider>().loadSalonData();
            if (!mounted) return;
            Navigator.pushReplacementNamed(context, '/salon-home');
          } else {
            Navigator.pushReplacementNamed(context, '/home');
          }
        }
      } else {
        SnackbarUtils.showError(context, provider.error);
      }
    } finally {
      _isVerifying = false;
    }
  }

  Future<void> _resendOtp() async {
    if (_resendAttempts >= _maxResendAttempts) {
      SnackbarUtils.showError(context, 'Maximum resend attempts reached. Please go back and try again.');
      return;
    }
    final provider = context.read<AuthProvider>();
    final success = await provider.sendOtp(provider.phone);
    if (mounted) {
      if (success) {
        _resendAttempts++;
        SnackbarUtils.showSuccess(context, 'OTP resent');
        _startResendTimer();
      } else {
        SnackbarUtils.showError(context, provider.error);
      }
    }
  }

  void _onChanged(int index, String value) {
    if (value.isNotEmpty && index < _otpLen - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    if (_otp.length == _otpLen) {
      _verifyOtp();
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = context.read<AuthProvider>().phone;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.watch<LocaleProvider>().tr('verify_otp'), style: AppTextStyles.h2),
              const SizedBox(height: 8),
              Text(
                'Enter the $_otpLen-digit code sent to +91 $phone',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(_otpLen, (index) {
                  return SizedBox(
                    width: 56,
                    height: 56,
                    child: TextField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 1,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: AppColors.cardBackground,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.primary, width: 2),
                        ),
                      ),
                      onChanged: (value) => _onChanged(index, value),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              Consumer<AuthProvider>(
                builder: (context, auth, _) {
                  return AppButton(
                    text: context.watch<LocaleProvider>().tr('verify_otp'),
                    onPressed: _verifyOtp,
                    isLoading: auth.state == AuthState.loading,
                  );
                },
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: (_resendCountdown > 0 || _resendAttempts >= _maxResendAttempts) ? null : _resendOtp,
                  child: Text(
                    _resendAttempts >= _maxResendAttempts
                        ? 'Max resend attempts reached'
                        : _resendCountdown > 0
                            ? 'Resend in ${_resendCountdown}s'
                            : context.watch<LocaleProvider>().tr('resend_otp'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
