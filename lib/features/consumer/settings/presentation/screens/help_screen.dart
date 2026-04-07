import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_text_styles.dart';
import '../../../../../core/i18n/locale_provider.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tr = context.watch<LocaleProvider>().tr;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(tr('help_title'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.support_agent, color: AppColors.white, size: 32),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr('help_subtitle'),
                    style: AppTextStyles.h3.copyWith(color: AppColors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Contact section
            Text(
              tr('contact_us').toUpperCase(),
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.textMuted,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            _ContactTile(
              icon: Icons.email_outlined,
              title: tr('email_us'),
              subtitle: 'support@helohair.com',
              onTap: () => _launchUrl('mailto:support@helohair.com'),
            ),
            const SizedBox(height: 8),
            _ContactTile(
              icon: Icons.phone_outlined,
              title: tr('call_us'),
              subtitle: '+91 1800-000-0000',
              onTap: () => _launchUrl('tel:+911800000000'),
            ),
            const SizedBox(height: 24),

            // FAQ section
            Text(
              tr('faq').toUpperCase(),
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.textMuted,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _FaqTile(question: tr('faq_booking'), answer: tr('faq_booking_answer')),
                  const Divider(height: 1, color: AppColors.border),
                  _FaqTile(question: tr('faq_cancel'), answer: tr('faq_cancel_answer')),
                  const Divider(height: 1, color: AppColors.border),
                  _FaqTile(question: tr('faq_payment'), answer: tr('faq_payment_answer')),
                  const Divider(height: 1, color: AppColors.border),
                  _FaqTile(question: tr('faq_refund'), answer: tr('faq_refund_answer')),
                  const Divider(height: 1, color: AppColors.border),
                  _FaqTile(question: tr('faq_reschedule'), answer: tr('faq_reschedule_answer')),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _launchUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not launch $url: $e');
    }
  }
}

class _ContactTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ContactTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
        title: Text(title, style: AppTextStyles.labelLarge),
        subtitle: Text(subtitle, style: AppTextStyles.bodySmall),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final String question;
  final String answer;

  const _FaqTile({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(question, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w500)),
      iconColor: AppColors.primary,
      collapsedIconColor: AppColors.textMuted,
      children: [
        Text(
          answer,
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary, height: 1.6),
        ),
      ],
    );
  }
}
