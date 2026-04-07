import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_text_styles.dart';
import '../../../../../core/i18n/locale_provider.dart';

class ReceiptScreen extends StatelessWidget {
  final String bookingNumber;
  final String salonName;
  final String date;
  final String time;
  final String stylistName;
  final List<Map<String, dynamic>> services;
  final double totalAmount;
  final String paymentMethod;
  final String paymentId;
  final String paidOn;
  final double discountAmount;
  final double smartDiscount;

  const ReceiptScreen({
    super.key,
    required this.bookingNumber,
    required this.salonName,
    required this.date,
    required this.time,
    required this.stylistName,
    required this.services,
    required this.totalAmount,
    required this.paymentMethod,
    required this.paymentId,
    required this.paidOn,
    this.discountAmount = 0,
    this.smartDiscount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final tr = context.watch<LocaleProvider>().tr;
    final subtotal = services.fold<double>(
      0,
      (sum, s) => sum + ((s['price'] as num?)?.toDouble() ?? 0),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(tr('receipt')),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => _shareReceipt(tr),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Gradient header card
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, color: AppColors.white, size: 32),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr('thank_you'),
                    style: AppTextStyles.h3.copyWith(color: AppColors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${tr('invoice_number')} #BK-$bookingNumber',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.white.withValues(alpha: 0.8)),
                  ),
                ],
              ),
            ),

            // Body card
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Booking Details
                  Text(
                    tr('booking').toUpperCase(),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.textMuted,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DetailRow(label: 'Salon', value: salonName),
                  const SizedBox(height: 8),
                  _DetailRow(label: 'Date', value: _formatDate()),
                  const SizedBox(height: 8),
                  _DetailRow(label: 'Time', value: time),
                  const SizedBox(height: 8),
                  _DetailRow(label: 'Stylist', value: stylistName),

                  const Divider(height: 32, color: AppColors.border),

                  // Services
                  Text(
                    tr('services').toUpperCase(),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.textMuted,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...services.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            s['name']?.toString() ?? '',
                            style: AppTextStyles.bodyMedium,
                          ),
                        ),
                        Text(
                          '\u20B9${((s['price'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                          style: AppTextStyles.labelLarge,
                        ),
                      ],
                    ),
                  )),

                  const Divider(height: 32, color: AppColors.border),

                  // Payment Summary
                  Text(
                    tr('payment_summary').toUpperCase(),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.textMuted,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DetailRow(
                    label: tr('subtotal'),
                    value: '\u20B9${subtotal.toStringAsFixed(0)}',
                  ),
                  if (discountAmount > 0) ...[
                    const SizedBox(height: 8),
                    _DetailRow(
                      label: tr('discount'),
                      value: '- \u20B9${discountAmount.toStringAsFixed(0)}',
                      valueColor: AppColors.success,
                    ),
                  ],
                  if (smartDiscount > 0) ...[
                    const SizedBox(height: 8),
                    _DetailRow(
                      label: tr('smart_discount'),
                      value: '- \u20B9${smartDiscount.toStringAsFixed(0)}',
                      valueColor: AppColors.success,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(tr('total'), style: AppTextStyles.h4),
                      Text(
                        '\u20B9${totalAmount.toStringAsFixed(0)}',
                        style: AppTextStyles.h3.copyWith(color: AppColors.primary),
                      ),
                    ],
                  ),

                  const Divider(height: 32, color: AppColors.border),

                  _DetailRow(label: tr('payment_method'), value: paymentMethod),
                  const SizedBox(height: 8),
                  _DetailRow(label: tr('transaction_id'), value: paymentId),
                  const SizedBox(height: 8),
                  _DetailRow(label: tr('paid_on'), value: _formatPaidOn()),

                  // Dashed separator
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: CustomPaint(
                      size: const Size(double.infinity, 1),
                      painter: _DashedLinePainter(),
                    ),
                  ),

                  // Footer
                  Center(
                    child: Text(
                      'HeloHair Technologies',
                      style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _shareReceipt(tr),
              icon: const Icon(Icons.share_outlined, size: 18),
              label: Text(tr('share_receipt'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _shareReceipt(String Function(String) tr) {
    final subtotal = services.fold<double>(
      0,
      (sum, s) => sum + ((s['price'] as num?)?.toDouble() ?? 0),
    );

    final buffer = StringBuffer();
    buffer.writeln('--- HeloHair Receipt ---');
    buffer.writeln('Invoice #BK-$bookingNumber');
    buffer.writeln();
    buffer.writeln('Salon: $salonName');
    buffer.writeln('Date: ${_formatDate()}');
    buffer.writeln('Time: $time');
    buffer.writeln('Stylist: $stylistName');
    buffer.writeln();
    buffer.writeln('Services:');
    for (final s in services) {
      final name = s['name']?.toString() ?? '';
      final price = ((s['price'] as num?)?.toDouble() ?? 0).toStringAsFixed(0);
      buffer.writeln('  $name - \u20B9$price');
    }
    buffer.writeln();
    buffer.writeln('Subtotal: \u20B9${subtotal.toStringAsFixed(0)}');
    if (discountAmount > 0) {
      buffer.writeln('Discount: - \u20B9${discountAmount.toStringAsFixed(0)}');
    }
    if (smartDiscount > 0) {
      buffer.writeln('Smart Slot Saving: - \u20B9${smartDiscount.toStringAsFixed(0)}');
    }
    buffer.writeln('Total: \u20B9${totalAmount.toStringAsFixed(0)}');
    buffer.writeln();
    buffer.writeln('Payment: $paymentMethod');
    buffer.writeln('Transaction ID: $paymentId');
    buffer.writeln('Paid on: ${_formatPaidOn()}');
    buffer.writeln();
    buffer.writeln('HeloHair Technologies');

    Share.share(buffer.toString());
  }

  String _formatDate() {
    try {
      final dt = DateTime.parse(date);
      return DateFormat('EEE, d MMM yyyy').format(dt);
    } catch (_) {
      return date;
    }
  }

  String _formatPaidOn() {
    try {
      final dt = DateTime.parse(paidOn);
      return DateFormat('d MMM yyyy, hh:mm a').format(dt);
    } catch (_) {
      return paidOn;
    }
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
        Flexible(
          child: Text(
            value,
            style: AppTextStyles.labelMedium.copyWith(color: valueColor),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(Offset(startX, 0), Offset(startX + dashWidth, 0), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
