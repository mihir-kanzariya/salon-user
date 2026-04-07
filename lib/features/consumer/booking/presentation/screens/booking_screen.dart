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
  bool _isBooking = false;
  final _notesController = TextEditingController();
  bool _notesExpanded = false;
  int _advanceBookingDays = 15;
  final Set<String> _expandedGroups = {};

  @override
  void initState() {
    super.initState();
    _initRazorpay();
    _loadSalonSettings();
    _loadSlots();
  }

  @override
  void dispose() {
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

  Future<void> _loadSlots() async {
    try {
      setState(() {
        _isLoadingSlots = true;
        _selectedTime = null;
        _smartSlots = [];
        _slotSummary = {};
      });

      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

      // Try smart-slots API first; fall back to regular slots on failure
      try {
        final smartData = await _repo.getSmartSlots(
          salonId: widget.salonId,
          date: dateStr,
          duration: widget.totalDuration,
          price: widget.totalPrice,
          stylistMemberId: _selectedStylistId,
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

      // Nudge 1: Pre-select the best smart slot
      if (_smartSlots.isNotEmpty) {
        _selectedTime = _smartSlots.first['time'] as String?;
      }

      setState(() {
        _isLoadingSlots = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingSlots = false;
      });
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

  /// Pay-first flow: create booking (holds slot) + Razorpay order → open checkout
  Future<void> _confirmBooking() async {
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
        'booking_id': _pendingBookingId,
        'salon_name': widget.salonName,
        'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
        'time': _selectedTime!,
        'stylist_name': _selectedStylistName ?? context.read<LocaleProvider>().tr('any_stylist'),
        'total_price': widget.totalPrice,
        'service_count': widget.serviceIds.length,
      });
    } catch (e) {
      setState(() => _isBooking = false);
      if (mounted) {
        SnackbarUtils.showError(context,
          'Payment received but verification failed. Don\'t worry — your booking will be confirmed shortly.');
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
      return hour >= fromHour && hour < toHour;
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
          // Step indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppColors.white,
            child: Row(
              children: [
                _StepDot(label: context.watch<LocaleProvider>().tr('stylists'), isActive: true, isCompleted: _selectedStylistId != null || _selectedStylistName == null),
                Expanded(child: Container(height: 2, color: _selectedTime != null ? AppColors.primary : AppColors.border)),
                _StepDot(label: 'Date', isActive: true, isCompleted: true),
                Expanded(child: Container(height: 2, color: _selectedTime != null ? AppColors.primary : AppColors.border)),
                _StepDot(label: 'Time', isActive: _selectedDate != null, isCompleted: _selectedTime != null),
                Expanded(child: Container(height: 2, color: _selectedTime != null ? AppColors.primary : AppColors.border)),
                _StepDot(label: 'Confirm', isActive: _selectedTime != null, isCompleted: false),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section 1: Stylist Selection
                  _buildStylistSection(),
                  const SizedBox(height: 24),

                  // Section 2: Date Selection
                  _buildDateSection(),
                  const SizedBox(height: 24),

                  // Section 3: Time Slots
                  _buildTimeSlotsSection(),
                  const SizedBox(height: 24),

                  // Section 4: Notes
                  _buildNotesSection(),
                  const SizedBox(height: 24),
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
        Row(
          children: [
            Icon(Icons.person_outline, size: 20, color: AppColors.textPrimary),
            const SizedBox(width: 8),
            Text(context.watch<LocaleProvider>().tr('select_stylist'), style: AppTextStyles.h4),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 90,
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
        width: 72,
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
                      radius: 24,
                      backgroundColor: AppColors.softSurface,
                      child: Icon(
                        Icons.groups_outlined,
                        size: 24,
                        color: AppColors.textSecondary,
                      ),
                    )
                  : CircleAvatar(
                      radius: 24,
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
                fontSize: 11,
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
        Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 20, color: AppColors.textPrimary),
            const SizedBox(width: 8),
            Text(context.watch<LocaleProvider>().tr('select_date'), style: AppTextStyles.h4),
          ],
        ),
        const SizedBox(height: 12),
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
        Row(
          children: [
            Icon(Icons.access_time_outlined,
                size: 20, color: AppColors.textPrimary),
            const SizedBox(width: 8),
            Text(context.watch<LocaleProvider>().tr('select_time'), style: AppTextStyles.h4),
          ],
        ),
        const SizedBox(height: 12),
        if (_isLoadingSlots)
          const SizedBox(height: 80, child: LoadingWidget())
        else if (_slots.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            // D.2: Enhanced empty state with icon
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.event_busy_outlined, size: 40, color: AppColors.textMuted),
                  const SizedBox(height: 8),
                  Text(
                    context.watch<LocaleProvider>().tr('no_slots_available'),
                    style: AppTextStyles.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Try selecting a different date or stylist',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
          )
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
        // Best Times section (smart / perfect_fit slots)
        if (_smartSlots.isNotEmpty) ...[
          _buildBestTimesSection(locale),
          if (hasTimeGroups) const SizedBox(height: 20),
        ] else if (_slots.isNotEmpty) ...[
          // No smart slots means open day — show friendly message
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0D9488).withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF0D9488)),
                const SizedBox(width: 8),
                Text(
                  'All times available at regular price',
                  style: TextStyle(
                    fontSize: 12,
                    color: const Color(0xFF0D9488),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
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
                          formatTime12h(time),
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
                    // Price with discount
                    if (discount > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '\u20B9${finalPrice.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: borderColor,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '\u20B9${widget.totalPrice.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                      ),
                    // Label
                    if (isPerfectFit)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          locale.tr('perfect_fit'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: borderColor,
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
    final showCollapse = slots.length > 3;
    final visibleSlots = showCollapse && !isExpanded ? slots.take(3).toList() : slots;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.labelMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: visibleSlots.map((slot) => _buildSlotChip(slot)).toList(),
        ),
        if (showCollapse && !isExpanded)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _expandedGroups.add(label);
                });
              },
              child: Text(
                'Show all (${slots.length})',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                  formatTime12h(time),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ],
            ),
            if (isSpecial && discount > 0 && available)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '\u20B9${finalPrice.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isPerfectFit ? const Color(0xFFF59E0B) : const Color(0xFF0D9488),
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '\u20B9${widget.totalPrice.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.textMuted,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ],
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
    final dateStr = DateFormat('EEE, d MMM').format(_selectedDate);
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
                    Text(
                      '$dateStr at ${formatTime12h(_selectedTime)}',
                      style: AppTextStyles.labelLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _selectedStylistName ?? locale.tr('any_stylist'),
                      style: AppTextStyles.caption,
                    ),
                    if (smartLabel != null)
                      Row(
                        children: [
                          Text(
                            '\u20B9${displayPrice.toStringAsFixed(0)}',
                            style: AppTextStyles.caption.copyWith(
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
                        style: AppTextStyles.caption,
                      ),
                  ],
                ),
              ),
              AppButton(
                text: '${locale.tr('pay_and_book')} \u20B9${displayPrice.toStringAsFixed(0)}',
                onPressed: _confirmBooking,
                isLoading: _isBooking,
                icon: Icons.payment,
                width: 180,
                height: 42,
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
