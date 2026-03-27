import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_text_styles.dart';
import '../../../../../core/i18n/locale_provider.dart';
import '../../../../../core/widgets/app_button.dart';
import '../../../../../core/utils/snackbar_utils.dart';
import '../../../../../services/api_service.dart';
import '../../../../../config/api_config.dart';
import '../../../../consumer/booking/data/repositories/booking_repository.dart';

class CheckoutScreen extends StatefulWidget {
  final String salonId;
  final String salonName;
  final List<Map<String, dynamic>> services;
  final String bookingDate;
  final String startTime;
  final String? endTime;
  final String? stylistMemberId;
  final String stylistName;
  final String? customerNotes;
  final double totalPrice;

  const CheckoutScreen({
    super.key,
    required this.salonId,
    required this.salonName,
    required this.services,
    required this.bookingDate,
    required this.startTime,
    this.endTime,
    this.stylistMemberId,
    required this.stylistName,
    this.customerNotes,
    required this.totalPrice,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _promoController = TextEditingController();
  final _api = ApiService();
  final _repo = BookingRepository();
  late Razorpay _razorpay;

  bool _isApplyingPromo = false;
  bool _isProcessing = false;
  String? _promoError;
  String? _appliedCode;
  double _discountAmount = 0;
  String? _promoCodeId;

  double get _subtotal => widget.totalPrice;
  double get _total => (_subtotal - _discountAmount).clamp(0, double.infinity);

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    _promoController.dispose();
    super.dispose();
  }

  Future<void> _applyPromo() async {
    final code = _promoController.text.trim();
    if (code.isEmpty) return;

    setState(() { _isApplyingPromo = true; _promoError = null; });
    try {
      final res = await _api.post(ApiConfig.validatePromo, body: {
        'code': code,
        'salon_id': widget.salonId,
        'subtotal': _subtotal,
      });
      final data = res['data'] ?? {};
      if (data['valid'] == true) {
        setState(() {
          _appliedCode = code.toUpperCase();
          _discountAmount = (data['discount_amount'] as num?)?.toDouble() ?? 0;
          _promoCodeId = data['promo_code_id'];
          _promoError = null;
        });
      } else {
        setState(() { _promoError = data['reason'] ?? 'Invalid promo code'; _appliedCode = null; _discountAmount = 0; });
      }
    } catch (e) {
      setState(() { _promoError = 'Could not validate promo code'; });
    }
    setState(() => _isApplyingPromo = false);
  }

  void _removePromo() {
    setState(() { _appliedCode = null; _discountAmount = 0; _promoCodeId = null; _promoController.clear(); });
  }

  Future<void> _proceedToPay() async {
    setState(() => _isProcessing = true);
    try {
      final res = await _repo.payAndBook(
        salonId: widget.salonId,
        serviceIds: widget.services.map((s) => s['id'] as String).toList(),
        bookingDate: widget.bookingDate,
        startTime: widget.startTime,
        stylistMemberId: widget.stylistMemberId,
        customerNotes: widget.customerNotes,
        promoCode: _appliedCode,
      );

      if (!mounted) return;
      final data = res['data'] ?? {};
      final booking = data['booking'] ?? {};
      final payment = data['payment'] ?? {};
      final orderId = payment['order_id'] ?? '';
      final amount = payment['amount'] ?? 0;
      final keyId = payment['key_id'] ?? '';

      if (orderId.toString().isEmpty) {
        setState(() => _isProcessing = false);
        SnackbarUtils.showError(context, 'Failed to create order');
        return;
      }

      final user = await _api.get(ApiConfig.userProfile);
      final userData = user['data'] ?? {};

      setState(() => _isProcessing = false);
      _razorpay.open({
        'key': keyId,
        'amount': amount,
        'name': 'Saloon',
        'description': widget.salonName,
        'order_id': orderId,
        'prefill': { 'email': userData['email'] ?? '', 'contact': userData['phone'] ?? '' },
        'theme': {'color': '#1F6A63'},
      });

      // Store booking ID for success handler
      _pendingBookingId = booking['id']?.toString();
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) SnackbarUtils.showError(context, e is ApiException ? e.message : 'Failed to create booking');
    }
  }

  String? _pendingBookingId;

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    setState(() => _isProcessing = true);
    try {
      await _api.post(ApiConfig.verifyPayment, body: {
        'razorpay_order_id': response.orderId,
        'razorpay_payment_id': response.paymentId,
        'razorpay_signature': response.signature,
      });
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
      Navigator.pushNamed(context, '/booking-success', arguments: {
        'booking_id': _pendingBookingId,
        'salon_name': widget.salonName,
        'date': widget.bookingDate,
        'time': widget.startTime,
        'stylist_name': widget.stylistName,
        'total_price': _total,
        'service_count': widget.services.length,
      });
    } catch (_) {
      if (mounted) SnackbarUtils.showError(context, 'Payment received but verification failed. Your booking will be confirmed shortly.');
    }
    setState(() => _isProcessing = false);
  }

  void _onPaymentError(PaymentFailureResponse response) {
    setState(() => _isProcessing = false);
    if (!mounted) return;
    final locale = context.read<LocaleProvider>();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(response.code == 2 ? locale.tr('payment_cancelled') : locale.tr('payment_failed')),
      content: Text(response.code == 2
        ? locale.tr('slot_held_msg')
        : locale.tr('slot_held_msg')),
      actions: [
        TextButton(onPressed: () { Navigator.pop(ctx); Navigator.pop(context); }, child: Text(locale.tr('go_back'))),
        ElevatedButton(onPressed: () { Navigator.pop(ctx); _proceedToPay(); }, child: Text(locale.tr('retry'))),
      ],
    ));
  }

  void _onExternalWallet(ExternalWalletResponse response) {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(context.watch<LocaleProvider>().tr('checkout'))),
      body: Column(
        children: [
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Salon + date info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.store, color: AppColors.primary)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.salonName, style: AppTextStyles.h4),
                    Text('${widget.bookingDate} at ${widget.startTime}', style: AppTextStyles.caption),
                    Text('Stylist: ${widget.stylistName}', style: AppTextStyles.caption),
                  ])),
                ]),
              ),
              const SizedBox(height: 16),

              // Services
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.watch<LocaleProvider>().tr('services'), style: AppTextStyles.h4),
                  const SizedBox(height: 12),
                  ...widget.services.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Expanded(child: Text('${s['name']} (${s['duration_minutes'] ?? s['duration']}min)', style: AppTextStyles.bodyMedium)),
                      Text('\u20B9${(s['discounted_price'] ?? s['price'] ?? 0).toString()}', style: AppTextStyles.labelLarge),
                    ]),
                  )),
                ]),
              ),
              const SizedBox(height: 16),

              // Promo code
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.watch<LocaleProvider>().tr('promo_code'), style: AppTextStyles.h4),
                  const SizedBox(height: 12),
                  if (_appliedCode != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.successLight, borderRadius: BorderRadius.circular(10)),
                      child: Row(children: [
                        const Icon(Icons.check_circle, color: AppColors.success, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text('$_appliedCode applied — \u20B9${_discountAmount.toStringAsFixed(0)} off', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600))),
                        GestureDetector(onTap: _removePromo, child: const Icon(Icons.close, size: 18, color: AppColors.textMuted)),
                      ]),
                    )
                  else
                    Row(children: [
                      Expanded(child: TextField(
                        controller: _promoController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          hintText: context.watch<LocaleProvider>().tr('enter_promo'),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          errorText: _promoError,
                        ),
                      )),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isApplyingPromo ? null : _applyPromo,
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
                        child: _isApplyingPromo ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(context.watch<LocaleProvider>().tr('apply')),
                      ),
                    ]),
                ]),
              ),
              const SizedBox(height: 16),

              // Price breakdown
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(14)),
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(context.watch<LocaleProvider>().tr('subtotal'), style: AppTextStyles.bodyMedium),
                    Text('\u20B9${_subtotal.toStringAsFixed(0)}', style: AppTextStyles.bodyMedium),
                  ]),
                  if (_discountAmount > 0) ...[
                    const SizedBox(height: 8),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(context.watch<LocaleProvider>().tr('discount'), style: const TextStyle(color: AppColors.success)),
                      Text('-\u20B9${_discountAmount.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
                    ]),
                  ],
                  const Divider(height: 24),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(context.watch<LocaleProvider>().tr('total'), style: AppTextStyles.h3),
                    Text('\u20B9${_total.toStringAsFixed(0)}', style: AppTextStyles.h3.copyWith(color: AppColors.primary)),
                  ]),
                ]),
              ),
            ]),
          )),

          // Pay button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.cardBackground, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -2))]),
            child: SafeArea(top: false, child: AppButton(
              text: _isProcessing ? context.watch<LocaleProvider>().tr('loading') : '${context.watch<LocaleProvider>().tr('proceed_to_pay')} \u20B9${_total.toStringAsFixed(0)}',
              onPressed: _isProcessing ? null : _proceedToPay,
              isLoading: _isProcessing,
              icon: Icons.payment,
            )),
          ),
        ],
      ),
    );
  }
}
