import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_text_styles.dart';
import '../../../../../core/i18n/locale_provider.dart';
import '../../../../auth/presentation/providers/auth_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _kNotifPref = 'push_notifications_enabled';
  bool _pushNotifications = true;

  @override
  void initState() {
    super.initState();
    _loadNotificationPref();
  }

  Future<void> _loadNotificationPref() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _pushNotifications = prefs.getBool(_kNotifPref) ?? true;
    });
  }

  Future<void> _setNotificationPref(bool value) async {
    setState(() => _pushNotifications = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotifPref, value);
  }

  @override
  Widget build(BuildContext context) {
    final lp = context.watch<LocaleProvider>();
    final tr = lp.tr;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(tr('settings'))),
      body: ListView(
        children: [
          // General
          _SectionHeader(title: tr('general')),
          _SettingsTile(
            icon: Icons.language_outlined,
            title: tr('language'),
            trailing: Text(
              lp.isGujarati ? tr('gujarati') : tr('english'),
              style: AppTextStyles.bodySmall,
            ),
            onTap: () => _showLanguageDialog(context, lp, tr),
          ),
          _SettingsTile(
            icon: Icons.notifications_outlined,
            title: tr('notifications'),
            trailing: Switch.adaptive(
              value: _pushNotifications,
              onChanged: (v) => _setNotificationPref(v),
              activeTrackColor: AppColors.primary,
              activeThumbColor: AppColors.white,
            ),
          ),

          // Legal
          _SectionHeader(title: tr('legal')),
          _SettingsTile(
            icon: Icons.description_outlined,
            title: tr('terms_conditions'),
            onTap: () => _showTextPage(context, tr('terms_conditions'), _termsText),
          ),
          _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: tr('privacy_policy'),
            onTap: () => _showTextPage(context, tr('privacy_policy'), _privacyText),
          ),

          // Support
          _SectionHeader(title: tr('support')),
          _SettingsTile(
            icon: Icons.help_outline,
            title: tr('help_title'),
            onTap: () => Navigator.pushNamed(context, '/help'),
          ),
          _SettingsTile(
            icon: Icons.info_outline,
            title: tr('about'),
            onTap: () => _showAboutInfo(context),
          ),

          // Account
          _SectionHeader(title: tr('profile')),
          _SettingsTile(
            icon: Icons.logout,
            title: tr('logout'),
            titleColor: AppColors.error,
            onTap: () => _confirmLogout(context, tr),
          ),
          _SettingsTile(
            icon: Icons.delete_forever_outlined,
            title: tr('delete_account'),
            titleColor: AppColors.error,
            onTap: () => _confirmDeleteAccount(context, tr),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showLanguageDialog(BuildContext context, LocaleProvider lp, String Function(String) tr) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('language')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioGroup<String>(
              groupValue: lp.locale,
              onChanged: (v) {
                if (v != null) lp.setLocale(v);
                Navigator.pop(ctx);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    title: Text(tr('english')),
                    value: 'en',
                    activeColor: AppColors.primary,
                  ),
                  RadioListTile<String>(
                    title: Text(tr('gujarati')),
                    value: 'gu',
                    activeColor: AppColors.primary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTextPage(BuildContext context, String title, String body) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(title: Text(title)),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Text(body, style: AppTextStyles.bodyMedium.copyWith(height: 1.8)),
          ),
        ),
      ),
    );
  }

  void _showAboutInfo(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'HeloHair',
      applicationVersion: '1.0.0',
      applicationIcon: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.content_cut, color: AppColors.white, size: 24),
      ),
      children: [
        const Text('Book your favorite salons, discover new styles, and manage your beauty appointments with ease.'),
      ],
    );
  }

  void _confirmLogout(BuildContext context, String Function(String) tr) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('logout')),
        content: Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('logout'), style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AuthProvider>().logout();
      if (context.mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/phone', (route) => false);
      }
    }
  }

  void _confirmDeleteAccount(BuildContext context, String Function(String) tr) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('delete_account'), style: const TextStyle(color: AppColors.error)),
        content: Text(tr('delete_account_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('delete'), style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account deletion requested. We will contact you shortly.')),
      );
    }
  }

  static const String _termsText = '''
Terms & Conditions

Last updated: March 2026

1. Acceptance of Terms
By using HeloHair, you agree to these terms and conditions.

2. Services
HeloHair provides a platform to discover and book salon services. We are an intermediary between you and the salon.

3. Bookings & Cancellations
Bookings are subject to availability. Free cancellation is available up to 2 hours before the appointment time.

4. Payments
Payments are processed securely via Razorpay. Refunds are processed within 5-7 business days.

5. User Responsibilities
You agree to provide accurate information and maintain the confidentiality of your account.

6. Limitation of Liability
HeloHair is not responsible for the quality of services provided by salons.

7. Changes
We reserve the right to modify these terms at any time. Continued use constitutes acceptance.

For questions, contact support@helohair.com.
''';

  static const String _privacyText = '''
Privacy Policy

Last updated: March 2026

1. Information We Collect
We collect your name, phone number, email, location, and booking history to provide our services.

2. How We Use Your Information
Your information is used to facilitate bookings, process payments, and improve our services.

3. Data Sharing
We share necessary information with salons to fulfil your bookings. We do not sell your data to third parties.

4. Data Security
We use industry-standard encryption and security measures to protect your data.

5. Your Rights
You can request access to, correction of, or deletion of your personal data at any time.

6. Cookies & Analytics
We use analytics to improve user experience. No personal data is shared with analytics providers.

For questions, contact support@helohair.com.
''';
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        title.toUpperCase(),
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.textMuted,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color? titleColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.titleColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: titleColor ?? AppColors.textSecondary),
        title: Text(title, style: AppTextStyles.bodyMedium.copyWith(color: titleColor)),
        trailing: trailing ?? const Icon(Icons.chevron_right, color: AppColors.textMuted),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
