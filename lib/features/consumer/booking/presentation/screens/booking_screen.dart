import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../../../config/api_config.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_text_styles.dart';
import '../../../../../core/i18n/locale_provider.dart';
import '../../../../../core/widgets/app_button.dart';
import '../../../../../core/widgets/loading_widget.dart';
import '../../../../../core/utils/snackbar_utils.dart';
import '../../../../../core/utils/time_utils.dart';
import '../../../../../services/api_service.dart';
import '../../data/repositories/booking_repository.dart';

class BookingScreen extends StatefulWidget {
  final String salonId;
  final List<String> serviceIds;
  final int totalDuration;
  final double totalPrice;
  final String salonName;
  final List<dynamic> members;

  const BookingScreen({
    super.key,
    required this.salonId,
    required this.serviceIds,
    required this.totalDuration,
    required this.totalPrice,
    this.salonName = '',
    this.members = const [],
  });

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  final BookingRepository _repo = BookingRepository();

  DateTime _selectedDate = DateTime.now();
  String? _selectedTime;
  String? _selectedEndTime;
  String? _selectedStylistId; // null = Any Stylist
  String? _selectedStylistName;
  List<Map<String, dynamic>> _slots = [];
  List<Map<String, dynamic>> _smartSlots = [];
  Map<String, dynamic> _slotSummary = {};
  bool _isLoadingSlots = false;
  String _slotLoadError = '';
  bool _isBooking = false;
  final _notesController = TextEditingController();
  bool _notesExpanded = false;
  int _advanceBookingDays = 15;
  final Set<String> _expandedGroups = {};
  Timer? _slotRefreshTimer;
  bool _preciseMode = false; // false = 30-min intervals, true = 15-min (all slots)

  @override
  void initState() {
    super.initState();
    _initRazorpay();
    _loadSalonSettings();
    _loadSlots();
    _slotRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _loadSlots(silent: true);
    });
  }

  @override
  void dispose() {
    _slotRefreshTimer?.cancel();
    _disposeRazorpay();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadSalonSettings() async {
    try {
      final res = await ApiService().get('${ApiConfig.salonDetail}/${widget.salonId}');
      final salon = res['data'] ?? {};
      final settings = salon['booking_settings'] as Map<String, dynamic>?;
      if (settings != null && mounted) {
        setState(() {
          _advanceBookingDays = (settings['advance_booking_days'] as num?)?.toInt() ?? 15;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadSlots({bool silent = false}) async {
    try {
      if (!silent) {
        setState(() {
          _isLoadingSlots = true;
          _slotLoadError = '';
          _selectedTime = null;
          _smartSlots = [];
          _slotSummary = {};
        });
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

      // Try smart-slots API first; fall back to regular slots on failure
      try {
        final smartData = await _repo.getSmartSlots(
          salonId: widget.salonId,
          date: dateStr,
          duration: widget.totalDuration,
          price: widget.totalPrice,
          stylistMemberId: _selectedStylistId,
          displayInterval: _preciseMode ? null : 30,
        );
        final allSlots = List<Map<String, dynamic>>.from(smartData['slots'] ?? []);
        _smartSlots = allSlots
            .where((s) =>
                s['slotType'] == 'smart' || s['slotType'] == 'perfect_fit')
            .toList();
        _slotSummary = Map<String, dynamic>.from(smartData['summary'] ?? {});
        _slots = allSlots;
      } catch (_) {
        // Fallback to regular slots API
        _slots = await _repo.getAvailableSlots(
          salonId: widget.salonId,
          date: dateStr,
          duration: widget.totalDuration,
          stylistMemberId: _selectedStylistId,
        );
        _smartSlots = [];
        _slotSummary = {};
      }

      if (silent) {
        // Check if previously selected slot is still available
        if (_selectedTime != null) {
          final stillAvailable = _slots.any(
              (s) => s['time'] == _selectedTime && s['available'] == true);
          if (!stillAvailable) {
            _selectedTime = null;
            if (mounted) {
              SnackbarUtils.showError(context,
                  context.read<LocaleProvider>().tr('slot_just_booked'));
            }
          }
        }
        setState(() {});
      } else {
        // Nudge 1: Pre-select the best smart slot
        if (_smartSlots.isNotEmpty) {
          _selectedTime = _smartSlots.first['time'] as String?;
        }
        setState(() {
          _isLoadingSlots = false;
        });
      }
    } catch (e) {
      if (!silent) {
        setState(() {
          _isLoadingSlots = false;
          _slots = [];
          _smartSlots = [];
          _slotLoadError = 'Failed to load available slots';
        });
      }
    }
  }

  late Razorpay _razorpay;
  String? _pendingBookingId;
  String? _pendingBookingNumber;

  void _initRazorpay() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  void _disposeRazorpay() {
    _razorpay.clear();
  }

  /// Show order summary bottom sheet before payment
  void _showOrderSummary() {
    if (_selectedTime == null) {
      SnackbarUtils.showError(context, 'Please select a time slot');
      return;
    }
    final locale = context.read<LocaleProvider>();
    final selectedSlot = _smartSlots.isNotEmpty
        ? _smartSlots.firstWhere((s) => s['time'] == _selectedTime, orElse: () => {})
        : <String, dynamic>{};
    final slotType = selectedSlot['slotType'] as String? ?? 'regular';
    final discount = (selectedSlot['discount'] as num?)?.toDouble() ?? 0;
    final finalPrice = (selectedSlot['finalPrice'] as num?)?.toDouble() ?? widget.totalPrice;
    final formattedDate = DateFormat('EEE, d MMM yyyy').format(_selectedDate);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text(locale.tr('order_summary'), style: AppTextStyles.h3),
              const SizedBox(height: 16),
              // Salon & schedule
              Row(children: [
                const Icon(Icons.storefront, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.salonName, style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600))),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.calendar_today, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Text(formattedDate, style: AppTextStyles.bodyMedium),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.access_time, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Text('$_selectedTime  •  ${widget.totalDuration} min', style: AppTextStyles.bodyMedium),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.person, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Text(_selectedStylistName ?? locale.tr('any_stylist'), style: AppTextStyles.bodyMedium),
              ]),
              const Divider(height: 24),
              // Services
              Text('${locale.tr('services')} (${widget.serviceIds.length})', style: AppTextStyles.labelLarge),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(locale.tr('subtotal'), style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                Text('\u20B9${widget.totalPrice.toStringAsFixed(0)}', style: AppTextStyles.bodyMedium),
              ]),
              if (discount > 0) ...[
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Row(children: [
                    const Icon(Icons.bolt, size: 14, color: AppColors.success),
                    const SizedBox(width: 4),
                    Text(locale.tr('smart_discount'), style: AppTextStyles.bodyMedium.copyWith(color: AppColors.success)),
                  ]),
                  Text('-${discount.toStringAsFixed(0)}%', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.success, fontWeight: FontWeight.w600)),
                ]),
              ],
              const Divider(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(locale.tr('total'), style: AppTextStyles.h4),
                Text('\u20B9${finalPrice.toStringAsFixed(0)}', style: AppTextStyles.h3.copyWith(color: AppColors.primary)),
              ]),
              const SizedBox(height: 16),
              // Cancellation policy
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.warningLight, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.accentDark),
                  const SizedBox(width: 8),
                  Expanded(child: Text(locale.tr('cancellation_policy_note'), style: AppTextStyles.caption.copyWith(color: AppColors.accentDark))),
                ]),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  text: '${locale.tr('confirm_and_pay')} \u20B9${finalPrice.toStringAsFixed(0)}',
                  onPressed: _isBooking ? null : () {
                    Navigator.pop(ctx);
                    _confirmBooking();
                  },
                  isLoading: _isBooking,
                  icon: Icons.payment,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Pay-first flow: create booking (holds slot) + Razorpay order → open checkout
  Future<void> _confirmBooking() async {
    if (_isBooking) return;
    if (_selectedTime == null) {
      SnackbarUtils.showError(context, 'Please select a time slot');
      return;
    }

    try {
      setState(() => _isBooking = true);

      // Step 1: Create booking + Razorpay order in one call
      final response = await _repo.payAndBook(
        salonId: widget.salonId,
        serviceIds: widget.serviceIds,
        bookingDate: DateFormat('yyyy-MM-dd').format(_selectedDate),
        startTime: _selectedTime!,
        stylistMemberId: _selectedStylistId,
        customerNotes: _notesController.text.isNotEmpty ? _notesController.text : null,
        slotType: _selectedSlotType(),
      );

      if (!mounted) return;

      final data = response['data'] ?? {};
      final booking = data['booking'] ?? {};
      final payment = data['payment'] ?? {};

      _pendingBookingId = booking['id']?.toString();
      _pendingBookingNumber = booking['booking_number']?.toString();

      final orderId = payment['order_id'] ?? '';
      final amount = payment['amount'] ?? 0;
      final keyId = payment['key_id'] ?? '';

      if (orderId.toString().isEmpty) {
        setState(() => _isBooking = false);
        SnackbarUtils.showError(context, 'Failed to create payment order');
        return;
      }

      // Step 2: Open Razorpay checkout
      final user = await ApiService().get(ApiConfig.userProfile);
      final userData = user['data'] ?? {};

      _razorpay.open({
        'key': keyId,
        'amount': amount,
        'name': 'Saloon',
        'description': widget.salonName,
        'order_id': orderId,
        'prefill': {
          'email': userData['email'] ?? '',
          'contact': userData['phone'] ?? '',
        },
        'theme': {'color': '#1F6A63'},
      });

      setState(() => _isBooking = false);
    } on ApiException catch (e) {
      setState(() => _isBooking = false);
      if (mounted) SnackbarUtils.showError(context, e.message);
    } catch (e) {
      setState(() => _isBooking = false);
      if (mounted) SnackbarUtils.showError(context, 'Failed to create booking. Please try again.');
    }
  }

  /// Payment succeeded — verify with backend, then navigate to success
  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    try {
      setState(() => _isBooking = true);

      await ApiService().post(ApiConfig.verifyPayment, body: {
        'razorpay_order_id': response.orderId,
        'razorpay_payment_id': response.paymentId,
        'razorpay_signature': response.signature,
      });

      if (!mounted) return;
      setState(() => _isBooking = false);

      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
      Navigator.pushNamed(context, '/booking-success', arguments: {
        'booking_id': _pendingBookingId ?? '',
        'salon_name': widget.salonName,
        'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
        'time': _selectedTime ?? '',
        'stylist_name': _selectedStylistName ?? context.read<LocaleProvider>().tr('any_stylist'),
        'total_price': widget.totalPrice,
        'service_count': widget.serviceIds.length,
        'total_duration': widget.totalDuration,
      });
    } catch (e) {
      setState(() => _isBooking = false);
      if (mounted) {
        SnackbarUtils.showError(context,
          'Payment received but verification failed. Don\'t worry — your booking will be confirmed shortly.');
        // Navigate to booking detail so user can track status
        if (_pendingBookingId != null) {
          Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
          Navigator.pushNamed(context, '/booking-detail', arguments: _pendingBookingId);
        }
      }
    }
  }

  /// Payment failed — show retry dialog
  void _onPaymentError(PaymentFailureResponse response) {
    setState(() => _isBooking = false);
    if (!mounted) return;

    final isCancelled = response.code == 2;
    final locale = context.read<LocaleProvider>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isCancelled ? locale.tr('payment_cancelled') : locale.tr('payment_failed')),
        content: Text(isCancelled
          ? locale.tr('slot_held_msg')
          : locale.tr('slot_held_msg')),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(ctx); Navigator.pop(context); },
            child: Text(locale.tr('cancel_booking')),
          ),
          ElevatedButton(
            onPressed: () { Navigator.pop(ctx); _confirmBooking(); },
            child: Text(locale.tr('retry')),
          ),
        ],
      ),
    );
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    if (mounted) SnackbarUtils.showInfo(context, 'Redirecting to ${response.walletName}...');
  }

  List<Map<String, dynamic>> _filterSlots(int fromHour, int toHour) {
    return _slots.where((slot) {
      final hour = int.tryParse((slot['time'] as String).split(':')[0]) ?? 0;
      final available = slot['available'] as bool? ?? true;
      final slotType = slot['slotType'] as String?;
      // Exclude smart/perfect_fit slots already shown in Best Times section
      if (_smartSlots.isNotEmpty && (slotType == 'smart' || slotType == 'perfect_fit')) {
        return false;
      }
      return hour >= fromHour && hour < toHour && available;
    }).toList();
  }

  /// Returns the slot type for the currently selected time, or null.
  String? _selectedSlotType() {
    if (_selectedTime == null) return null;
    final match = _slots.where((s) => s['time'] == _selectedTime);
    if (match.isEmpty) return null;
    final type = match.first['slotType'];
    if (type == 'smart' || type == 'perfect_fit') return type as String;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          widget.salonName.isNotEmpty ? widget.salonName : 'Book Appointment',
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section 1: Stylist Selection
                  _buildStylistSection(),
                  const SizedBox(height: 10),

                  // Section 2: Date Selection
                  _buildDateSection(),
                  const SizedBox(height: 10),

                  // Section 3: Time Slots
                  _buildTimeSlotsSection(),
                  const SizedBox(height: 10),

                  // Section 4: Notes
                  _buildNotesSection(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // Section 5: Sticky Confirm Bar
          if (_selectedTime != null) _buildConfirmBar(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section 1: Stylist Selection
  // ---------------------------------------------------------------------------
  Widget _buildStylistSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 72,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: widget.members.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildStylistItem(
                  id: null,
                  name: context.watch<LocaleProvider>().tr('any_stylist'),
                  photoUrl: null,
                  isAny: true,
                );
              }
              final member = widget.members[index - 1] as Map<String, dynamic>;
              final memberUser = member['user'] as Map<String, dynamic>?;
              return _buildStylistItem(
                id: member['id']?.toString() ?? member['_id']?.toString(),
                name: (memberUser?['name'] ?? member['name'])?.toString() ?? 'Stylist',
                photoUrl: (memberUser?['avatar'] ?? memberUser?['profile_photo'] ?? member['profile_photo'])?.toString(),
                isAny: false,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStylistItem({
    required String? id,
    required String name,
    required String? photoUrl,
    required bool isAny,
  }) {
    final isSelected = _selectedStylistId == id;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedStylistId = id;
          _selectedStylistName = isAny ? null : name;
        });
        _loadSlots();
      },
      child: Container(
        width: 68,
        margin: const EdgeInsets.only(right: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: isSelected
                    ? Border.all(color: AppColors.primary, width: 2.5)
                    : null,
              ),
              padding: isSelected ? const EdgeInsets.all(2) : null,
              child: isAny
                  ? CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.softSurface,
                      child: Icon(
                        Icons.groups_outlined,
                        size: 24,
                        color: AppColors.textSecondary,
                      ),
                    )
                  : CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.softSurface,
                      backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                          ? CachedNetworkImageProvider(ApiConfig.imageUrl(photoUrl) ?? photoUrl)
                          : null,
                      child: photoUrl == null || photoUrl.isEmpty
                          ? Icon(
                              Icons.person,
                              size: 24,
                              color: AppColors.textSecondary,
                            )
                          : null,
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color:
                    isSelected ? AppColors.textPrimary : AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section 2: Date Selection
  // ---------------------------------------------------------------------------
  Widget _buildDateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 70,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _advanceBookingDays + 1,
            itemBuilder: (context, index) {
              final date = DateTime.now().add(Duration(days: index));
              final isSelected = _selectedDate.day == date.day &&
                  _selectedDate.month == date.month &&
                  _selectedDate.year == date.year;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedDate = date;
                  });
                  _loadSlots();
                },
                child: Container(
                  width: 52,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.border,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('EEE').format(date),
                        style: TextStyle(
                          fontSize: 11,
                          color: isSelected
                              ? AppColors.white.withValues(alpha: 0.8)
                              : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('d').format(date),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? AppColors.white
                              : AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        DateFormat('MMM').format(date),
                        style: TextStyle(
                          fontSize: 10,
                          color: isSelected
                              ? AppColors.white.withValues(alpha: 0.8)
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Section 3: Time Slots (grouped)
  // ---------------------------------------------------------------------------
  Widget _buildTimeSlotsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isLoadingSlots)
          const SizedBox(height: 80, child: LoadingWidget())
        else if (_slotLoadError.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Column(
                children: [
                  const Icon(Icons.error_outline, size: 40, color: AppColors.error),
                  const SizedBox(height: 8),
                  Text(_slotLoadError, style: AppTextStyles.bodySmall),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _loadSlots,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          )
        else if (_slots.isEmpty)
          Builder(builder: (context) {
            final total = (_slotSummary['totalPossibleSlots'] as num?)?.toInt() ?? 0;
            final message = total > 0
                ? context.watch<LocaleProvider>().tr('all_slots_booked')
                : context.watch<LocaleProvider>().tr('no_availability');
            final subtitle = total > 0
                ? context.watch<LocaleProvider>().tr('try_another_date')
                : 'Try selecting a different date or stylist';
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      total > 0 ? Icons.event_busy : Icons.event_busy_outlined,
                      size: 40,
                      color: total > 0 ? AppColors.warning : AppColors.textMuted,
                    ),
                    const SizedBox(height: 8),
                    Text(message, style: AppTextStyles.bodySmall),
                    const SizedBox(height: 4),
                    Text(subtitle, style: AppTextStyles.caption),
                  ],
                ),
              ),
            );
          })
        else
          _buildGroupedSlots(),
      ],
    );
  }

  Widget _buildGroupedSlots() {
    final earlyMorning = _filterSlots(0, 6);
    final morning = _filterSlots(6, 12);
    final afternoon = _filterSlots(12, 17);
    final evening = _filterSlots(17, 24);

    final locale = context.watch<LocaleProvider>();
    final hasTimeGroups = earlyMorning.isNotEmpty ||
        morning.isNotEmpty ||
        afternoon.isNotEmpty ||
        evening.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Duration context banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.timer_outlined, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                locale.tr('your_appointment_duration').replaceAll('{duration}', '${widget.totalDuration}'),
                style: TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        // Scarcity banner
        Builder(builder: (context) {
          final booked = (_slotSummary['bookedSlots'] as num?)?.toInt() ?? 0;
          final total = (_slotSummary['totalPossibleSlots'] as num?)?.toInt() ?? 0;
          final remaining = total - booked;
          if (booked <= 0 || total <= 0) return const SizedBox.shrink();
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: AppColors.warningLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Text('\u{1F525} ', style: TextStyle(fontSize: 14)),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 12, color: const Color(0xFF92400E), fontFamily: 'DM Sans'),
                      children: [
                        TextSpan(text: '$booked of $total slots booked today \u2014 '),
                        TextSpan(text: '$remaining remaining', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        // "More times" toggle — switches between 30-min and 15-min intervals
        if (hasTimeGroups || _smartSlots.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _preciseMode = !_preciseMode;
                      _expandedGroups.clear();
                    });
                    _loadSlots();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _preciseMode ? AppColors.primary.withValues(alpha: 0.1) : AppColors.softSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _preciseMode ? AppColors.primary.withValues(alpha: 0.3) : AppColors.border,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _preciseMode ? Icons.view_comfortable : Icons.more_time,
                          size: 14,
                          color: _preciseMode ? AppColors.primary : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _preciseMode ? 'Fewer times' : 'More times',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: _preciseMode ? AppColors.primary : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Best Times section (smart / perfect_fit slots)
        if (_smartSlots.isNotEmpty) ...[
          _buildBestTimesSection(locale),
          if (hasTimeGroups) const SizedBox(height: 20),
        ],
        if (earlyMorning.isNotEmpty) _buildSlotGroup(locale.tr('early_morning'), earlyMorning),
        if (morning.isNotEmpty) ...[
          if (earlyMorning.isNotEmpty) const SizedBox(height: 16),
          _buildSlotGroup(locale.tr('morning'), morning),
        ],
        if (afternoon.isNotEmpty) ...[
          if (morning.isNotEmpty || earlyMorning.isNotEmpty) const SizedBox(height: 16),
          _buildSlotGroup(locale.tr('afternoon'), afternoon),
        ],
        if (evening.isNotEmpty) ...[
          if (morning.isNotEmpty || afternoon.isNotEmpty)
            const SizedBox(height: 16),
          _buildSlotGroup(locale.tr('evening'), evening),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Best Times — Smart / Perfect-fit slots
  // ---------------------------------------------------------------------------
  Widget _buildBestTimesSection(LocaleProvider locale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, size: 18, color: Color(0xFF0D9488)),
            const SizedBox(width: 6),
            Text(
              locale.tr('best_times'),
              style: AppTextStyles.labelMedium.copyWith(
                color: const Color(0xFF0D9488),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Text(
            'Most customers pick these times',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        // Nudge 5: Scarcity — "Only X discounted slots left today"
        Builder(builder: (context) {
          final smartCount = _smartSlots.where((s) =>
              s['slotType'] != 'regular' && s['available'] == true).length;
          if (smartCount > 0 && smartCount <= 5) {
            return Padding(
              padding: const EdgeInsets.only(left: 24, top: 3),
              child: Text(
                'Only $smartCount discounted slot${smartCount == 1 ? '' : 's'} left today',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFD97706), // amber-600
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        }),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 10,
          children: _smartSlots.map((slot) {
            final time = slot['time'] as String;
            final available = slot['available'] as bool? ?? true;
            final slotType = slot['slotType'] as String? ?? 'smart';
            final discount = (slot['discount'] as num?)?.toDouble() ?? 0;
            final finalPrice = (slot['finalPrice'] as num?)?.toDouble() ?? widget.totalPrice;
            final reason = slot['reason'] as String? ?? '';
            final isSelected = _selectedTime == time;
            final isPerfectFit = slotType == 'perfect_fit';

            final borderColor = isPerfectFit
                ? const Color(0xFFF59E0B) // amber
                : const Color(0xFF0D9488); // teal

            return GestureDetector(
              onTap: available
                  ? () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedTime = time;
                      });
                    }
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? borderColor.withValues(alpha: 0.15)
                      : AppColors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? borderColor : borderColor.withValues(alpha: 0.5),
                    width: isSelected ? 2 : 1.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isPerfectFit ? '\u2726 ' : '\u2605 ',
                          style: TextStyle(
                            fontSize: 13,
                            color: borderColor,
                          ),
                        ),
                        Text(
                          formatSlotRange12h(time, slot['endTime'] as String?, widget.totalDuration),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? borderColor
                                : AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // Nudge 2: Anchoring — strikethrough original + bold discount + Save badge
                    if (discount > 0) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '\u20B9${widget.totalPrice.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '\u20B9${finalPrice.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: borderColor,
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          'Save ${discount.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF16A34A), // green-600
                          ),
                        ),
                      ),
                    ],
                    // Nudge 4: Social proof — badge based on slot reason/type
                    if (isPerfectFit)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '\u2726 Perfect fit!',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: borderColor,
                          ),
                        ),
                      )
                    else if (reason == 'first_available')
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text(
                          '\uD83D\uDD25 Popular',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFEA580C), // orange-600
                          ),
                        ),
                      )
                    else if (reason == 'right_after_booking')
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text(
                          'Quick fill',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF0D9488),
                          ),
                        ),
                      )
                    else if (reason == 'right_before_booking')
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text(
                          'Last gap',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF7C3AED), // violet-600
                          ),
                        ),
                      )
                    else if (reason.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          reason,
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSlotGroup(String label, List<Map<String, dynamic>> slots) {
    final isExpanded = _expandedGroups.contains(label);
    final collapseThreshold = _preciseMode ? 4 : 6;
    final showCollapse = slots.length > collapseThreshold;
    final visibleSlots = showCollapse && !isExpanded ? slots.take(collapseThreshold).toList() : slots;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label (${slots.length} available)', style: AppTextStyles.labelMedium),
        const SizedBox(height: 8),
        // Heat bar
        Builder(builder: (context) {
          final periodKey = label.toLowerCase().contains('morning') && !label.toLowerCase().contains('early') ? 'morning'
              : label.toLowerCase().contains('afternoon') ? 'afternoon'
              : label.toLowerCase().contains('evening') ? 'evening'
              : 'earlyMorning';
          final stats = _slotSummary[periodKey] as Map<String, dynamic>?;
          if (stats == null) return const SizedBox.shrink();
          final available = (stats['available'] as num?)?.toInt() ?? 0;
          final total = (stats['total'] as num?)?.toInt() ?? 0;
          if (total <= 0) return const SizedBox.shrink();
          final bookedPct = ((total - available) / total * 100).round();
          final isHot = bookedPct >= 70;
          final isCool = bookedPct <= 30;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: bookedPct / 100,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isHot ? AppColors.error : isCool ? AppColors.success : AppColors.warning,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isHot ? '$bookedPct% booked \u2014 Filling fast'
                      : isCool ? '$bookedPct% booked \u2014 Most available'
                      : '$bookedPct% booked',
                  style: TextStyle(
                    fontSize: 10,
                    color: isHot ? AppColors.error : isCool ? AppColors.success : AppColors.textMuted,
                    fontWeight: isHot || isCool ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          );
        }),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: visibleSlots.map((slot) => _buildSlotChip(slot)).toList(),
        ),
        if (showCollapse)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedGroups.remove(label);
                  } else {
                    _expandedGroups.add(label);
                  }
                });
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isExpanded ? 'Show less' : 'Show ${slots.length - collapseThreshold} more',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Check if a regular slot is within 30 min of any smart slot
  double? _lossAversionExtra(String time) {
    if (_smartSlots.isEmpty) return null;
    final parts = time.split(':');
    final slotMin = (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);

    double? bestSmartPrice;
    for (final smart in _smartSlots) {
      final sTime = smart['time'] as String;
      final sParts = sTime.split(':');
      final sMin = (int.tryParse(sParts[0]) ?? 0) * 60 + (int.tryParse(sParts[1]) ?? 0);
      if ((slotMin - sMin).abs() <= 30) {
        final fp = (smart['finalPrice'] as num?)?.toDouble() ?? widget.totalPrice;
        if (bestSmartPrice == null || fp < bestSmartPrice) {
          bestSmartPrice = fp;
        }
      }
    }
    if (bestSmartPrice != null && bestSmartPrice < widget.totalPrice) {
      return widget.totalPrice - bestSmartPrice;
    }
    return null;
  }

  Widget _buildSlotChip(Map<String, dynamic> slot) {
    final time = slot['time'] as String;
    final available = slot['available'] as bool? ?? true;
    final isSelected = _selectedTime == time;
    final slotType = slot['slotType'] as String?;
    final isSmart = slotType == 'smart';
    final isPerfectFit = slotType == 'perfect_fit';
    final isSpecial = isSmart || isPerfectFit;
    final discount = (slot['discount'] as num?)?.toDouble() ?? 0;
    final finalPrice = (slot['finalPrice'] as num?)?.toDouble() ?? widget.totalPrice;
    final reason = slot['reason'] as String? ?? '';

    // Nudge 3: Loss aversion for regular slots near smart slots
    final double? extraCost = (!isSpecial && available) ? _lossAversionExtra(time) : null;

    Color borderColor;
    Color bgColor;
    Color textColor;

    if (isSelected) {
      if (isPerfectFit) {
        borderColor = const Color(0xFFF59E0B);
        bgColor = const Color(0xFFF59E0B).withValues(alpha: 0.15);
        textColor = const Color(0xFFF59E0B);
      } else if (isSmart) {
        borderColor = const Color(0xFF0D9488);
        bgColor = const Color(0xFF0D9488).withValues(alpha: 0.15);
        textColor = const Color(0xFF0D9488);
      } else {
        borderColor = AppColors.primary;
        bgColor = AppColors.primary;
        textColor = AppColors.white;
      }
    } else if (!available) {
      borderColor = AppColors.softSurface;
      bgColor = AppColors.softSurface;
      textColor = AppColors.textMuted;
    } else if (isPerfectFit) {
      borderColor = const Color(0xFFF59E0B).withValues(alpha: 0.5);
      bgColor = AppColors.white;
      textColor = AppColors.textPrimary;
    } else if (isSmart) {
      borderColor = const Color(0xFF0D9488).withValues(alpha: 0.5);
      bgColor = AppColors.white;
      textColor = AppColors.textPrimary;
    } else {
      borderColor = AppColors.border;
      bgColor = AppColors.white;
      textColor = AppColors.textPrimary;
    }

    return GestureDetector(
      onTap: available
          ? () {
              HapticFeedback.selectionClick();
              setState(() {
                _selectedTime = time;
              });
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: isSpecial ? 1.5 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isPerfectFit)
                  Text('\u2726 ', style: TextStyle(fontSize: 12, color: const Color(0xFFF59E0B)))
                else if (isSmart)
                  Text('\u2605 ', style: TextStyle(fontSize: 12, color: const Color(0xFF0D9488))),
                Text(
                  formatSlotRange12h(time, slot['endTime'] as String?, widget.totalDuration),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ],
            ),
            // Nudge 2: Anchoring — strikethrough original + bold discount + Save badge
            if (isSpecial && discount > 0 && available) ...[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '\u20B9${widget.totalPrice.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.textMuted,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '\u20B9${finalPrice.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isPerfectFit ? const Color(0xFFF59E0B) : const Color(0xFF0D9488),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  'Save ${discount.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF16A34A), // green-600
                  ),
                ),
              ),
            ],
            // Nudge 4: Social proof — badge based on slot reason/type
            if (isSpecial && available)
              if (isPerfectFit)
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Text(
                    '\u2726 Perfect fit!',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                )
              else if (reason == 'first_available')
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Text(
                    '\uD83D\uDD25 Popular',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFEA580C),
                    ),
                  ),
                )
              else if (reason == 'right_after_booking')
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Text(
                    'Quick fill',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF0D9488),
                    ),
                  ),
                )
              else if (reason == 'right_before_booking')
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Text(
                    'Last gap',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF7C3AED),
                    ),
                  ),
                ),
            // Nudge 3: Loss aversion hint on regular slots near smart slots
            if (extraCost != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '+\u20B9${extraCost.toStringAsFixed(0)} more',
                  style: const TextStyle(
                    fontSize: 9,
                    color: Color(0xFFD97706), // amber-600
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section 4: Notes (collapsible)
  // ---------------------------------------------------------------------------
  Widget _buildNotesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              _notesExpanded = !_notesExpanded;
            });
          },
          child: Row(
            children: [
              Icon(Icons.note_alt_outlined,
                  size: 20, color: AppColors.textPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(context.watch<LocaleProvider>().tr('customer_notes'), style: AppTextStyles.h4),
              ),
              Icon(
                _notesExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 22,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
        if (_notesExpanded) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            maxLines: 3,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: context.watch<LocaleProvider>().tr('notes_hint'),
              hintStyle: TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primary),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Section 5: Sticky Confirm Bar
  // ---------------------------------------------------------------------------
  Widget _buildConfirmBar() {
    final locale = context.watch<LocaleProvider>();

    // Determine if the selected slot has a smart discount
    double displayPrice = widget.totalPrice;
    String? smartLabel;
    if (_selectedTime != null) {
      final match = _slots.where((s) => s['time'] == _selectedTime);
      if (match.isNotEmpty) {
        final s = match.first;
        final slotType = s['slotType'] as String?;
        final fp = (s['finalPrice'] as num?)?.toDouble();
        if ((slotType == 'smart' || slotType == 'perfect_fit') && fp != null && fp < widget.totalPrice) {
          displayPrice = fp;
          smartLabel = locale.tr('smart_discount');
        }
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (smartLabel != null)
                      Row(
                        children: [
                          Text(
                            '\u20B9${displayPrice.toStringAsFixed(0)}',
                            style: AppTextStyles.labelLarge.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0D9488),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '\u20B9${widget.totalPrice.toStringAsFixed(0)}',
                            style: AppTextStyles.caption.copyWith(
                              decoration: TextDecoration.lineThrough,
                              color: AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            smartLabel,
                            style: TextStyle(
                              fontSize: 10,
                              color: const Color(0xFF0D9488),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        '\u20B9${widget.totalPrice.toStringAsFixed(0)}',
                        style: AppTextStyles.labelLarge,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: AppButton(
                  text: 'Pay \u20B9${displayPrice.toStringAsFixed(0)}',
                  onPressed: _selectedTime == null || _isBooking ? null : _showOrderSummary,
                  isLoading: _isBooking,
                  icon: Icons.payment,
                  height: 42,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isCompleted;

  const _StepDot({required this.label, required this.isActive, required this.isCompleted});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted ? AppColors.primary : isActive ? AppColors.white : AppColors.softSurface,
            border: Border.all(
              color: isActive ? AppColors.primary : AppColors.border,
              width: 2,
            ),
          ),
          child: isCompleted
              ? const Icon(Icons.check, size: 14, color: AppColors.white)
              : null,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isActive ? AppColors.textPrimary : AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}
