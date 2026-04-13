import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_text_styles.dart';
import '../../../../../config/api_config.dart';
import '../../../../consumer/home/data/repositories/salon_repository.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final SalonRepository _repo = SalonRepository();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _debounce;
  String _query = '';
  bool _isLoadingSuggestions = false;
  bool _isLoadingTrending = false;

  // Recent searches
  List<String> _recentSearches = [];
  static const String _recentSearchesKey = 'recent_searches';
  static const int _maxRecent = 10;

  // Trending data
  List<Map<String, dynamic>> _trendingServices = [];
  List<Map<String, dynamic>> _topRatedSalons = [];

  // Suggestion data
  List<Map<String, dynamic>> _suggestedServices = [];
  List<Map<String, dynamic>> _suggestedSalons = [];
  List<Map<String, dynamic>> _suggestedStylists = [];

  double _userLat = 23.0225;
  double _userLng = 72.5714;

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
    _fetchUserLocation();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchUserLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _loadTrending();
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      _userLat = position.latitude;
      _userLng = position.longitude;
    } catch (_) {}
    _loadTrending();
  }

  Future<void> _loadTrending() async {
    setState(() => _isLoadingTrending = true);
    try {
      final data = await _repo.getTrending(_userLat, _userLng);
      if (mounted) {
        setState(() {
          _trendingServices = List<Map<String, dynamic>>.from(data['trending'] ?? []);
          _topRatedSalons = List<Map<String, dynamic>>.from(data['topRated'] ?? []);
          _isLoadingTrending = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingTrending = false);
    }
  }

  // ── Recent searches ──

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _recentSearches = prefs.getStringList(_recentSearchesKey) ?? []);
  }

  Future<void> _saveRecentSearch(String query) async {
    _recentSearches.remove(query);
    _recentSearches.insert(0, query);
    if (_recentSearches.length > _maxRecent) {
      _recentSearches = _recentSearches.sublist(0, _maxRecent);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentSearchesKey, _recentSearches);
    if (mounted) setState(() {});
  }

  Future<void> _removeRecentSearch(String query) async {
    _recentSearches.remove(query);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentSearchesKey, _recentSearches);
    if (mounted) setState(() {});
  }

  Future<void> _clearRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentSearchesKey);
    setState(() => _recentSearches = []);
  }

  // ── Search logic ──

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query == _query) return;
    _debounce?.cancel();

    if (query.isEmpty || query.length < 2) {
      setState(() {
        _query = query;
        _suggestedServices = [];
        _suggestedSalons = [];
        _suggestedStylists = [];
        _isLoadingSuggestions = false;
      });
      return;
    }

    setState(() {
      _query = query;
      _isLoadingSuggestions = true;
    });
    _debounce = Timer(const Duration(milliseconds: 300), () => _fetchSuggestions(query));
  }

  Future<void> _fetchSuggestions(String query) async {
    try {
      final data = await _repo.getSearchSuggestions(query);
      if (mounted && _query == query) {
        setState(() {
          _suggestedServices = List<Map<String, dynamic>>.from(data['services'] ?? []);
          _suggestedSalons = List<Map<String, dynamic>>.from(data['salons'] ?? []);
          _suggestedStylists = List<Map<String, dynamic>>.from(data['stylists'] ?? []);
          _isLoadingSuggestions = false;
        });
      }
    } catch (_) {
      if (mounted && _query == query) {
        setState(() => _isLoadingSuggestions = false);
      }
    }
  }

  void _onServiceTapped(String serviceName) {
    _saveRecentSearch(serviceName);
    final totalResults = _suggestedServices.length + _suggestedSalons.length + _suggestedStylists.length;
    _repo.trackSearch(serviceName, totalResults);
    Navigator.pop(context, {'type': 'service', 'query': serviceName});
  }

  void _onSalonTapped(String salonId, String salonName) {
    _saveRecentSearch(salonName);
    _repo.trackSearch(salonName, 1);
    Navigator.pushNamed(context, '/salon-detail', arguments: salonId);
  }

  void _onStylistTapped(String salonId, String stylistName) {
    _saveRecentSearch(stylistName);
    _repo.trackSearch(stylistName, 1);
    Navigator.pushNamed(context, '/salon-detail', arguments: salonId);
  }

  void _onRecentSearchTapped(String query) {
    _searchController.text = query;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
  }

  void _onSubmitSearch(String query) {
    if (query.trim().isEmpty) return;
    _saveRecentSearch(query.trim());
    _repo.trackSearch(query.trim(), 0);
    Navigator.pop(context, {'type': 'service', 'query': query.trim()});
  }

  void _clearSearch() {
    _searchController.clear();
    _focusNode.requestFocus();
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _searchController,
          focusNode: _focusNode,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: _onSubmitSearch,
          style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Search services, salons, stylists...',
            hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 16),
            border: InputBorder.none,
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: AppColors.textMuted),
                    onPressed: _clearSearch,
                  )
                : null,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Typing state: show autocomplete suggestions
    if (_query.length >= 2) {
      return _buildSuggestionsView();
    }

    // Empty state: show recent + trending
    return _buildEmptyStateView();
  }

  // ── Empty state view ──

  Widget _buildEmptyStateView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recent searches
          if (_recentSearches.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Recent Searches', style: AppTextStyles.h4),
                GestureDetector(
                  onTap: _clearRecentSearches,
                  child: Text('Clear all', style: AppTextStyles.caption.copyWith(color: AppColors.primary)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _recentSearches.map((q) => _RecentSearchChip(
                label: q,
                onTap: () => _onRecentSearchTapped(q),
                onRemove: () => _removeRecentSearch(q),
              )).toList(),
            ),
            const SizedBox(height: 24),
          ],

          // Trending Near You
          if (_isLoadingTrending) ...[
            const Text('Trending Near You', style: AppTextStyles.h4),
            const SizedBox(height: 12),
            const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
            )),
          ] else ...[
            if (_trendingServices.isNotEmpty) ...[
              const Row(
                children: [
                  Text('\uD83D\uDD25', style: TextStyle(fontSize: 18)),
                  SizedBox(width: 6),
                  Text('Trending Near You', style: AppTextStyles.h4),
                ],
              ),
              const SizedBox(height: 12),
              ..._trendingServices.take(6).map((service) => _TrendingServiceTile(
                name: service['name']?.toString() ?? '',
                bookingCount: int.tryParse(service['booking_count']?.toString() ?? '0') ?? 0,
                minPrice: double.tryParse(service['min_price']?.toString() ?? '0') ?? 0,
                onTap: () => _onServiceTapped(service['name']?.toString() ?? ''),
              )),
              const SizedBox(height: 24),
            ],

            // Top Rated Near You
            if (_topRatedSalons.isNotEmpty) ...[
              const Text('Top Rated Near You', style: AppTextStyles.h4),
              const SizedBox(height: 12),
              SizedBox(
                height: 180,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _topRatedSalons.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final salon = _topRatedSalons[index];
                    final dist = double.tryParse(salon['distance']?.toString() ?? '');
                    final distText = dist != null ? (dist < 1 ? '${(dist * 1000).round()}m' : '${dist.toStringAsFixed(1)} km') : null;
                    return _TopRatedSalonCard(
                      name: salon['name']?.toString() ?? '',
                      coverImage: salon['cover_image']?.toString(),
                      ratingAvg: double.tryParse(salon['rating_avg']?.toString() ?? '0') ?? 0,
                      distance: distText,
                      onTap: () => _onSalonTapped(salon['id']?.toString() ?? '', salon['name']?.toString() ?? ''),
                    );
                  },
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ── Suggestions view ──

  Widget _buildSuggestionsView() {
    if (_isLoadingSuggestions) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
        ),
      );
    }

    final hasServices = _suggestedServices.isNotEmpty;
    final hasSalons = _suggestedSalons.isNotEmpty;
    final hasStylists = _suggestedStylists.isNotEmpty;

    if (!hasServices && !hasSalons && !hasStylists) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 48, color: AppColors.textMuted),
              const SizedBox(height: 12),
              Text('No results for "$_query"', style: AppTextStyles.h4),
              const SizedBox(height: 4),
              const Text('Try a different search term', style: AppTextStyles.caption),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // Services section
        if (hasServices) ...[
          _SectionHeader(title: 'Services', count: _suggestedServices.length),
          ..._suggestedServices.take(6).map((service) {
            final name = service['name']?.toString() ?? '';
            final price = double.tryParse(service['min_price']?.toString() ?? '0') ?? 0;
            final count = int.tryParse(service['salon_count']?.toString() ?? '0') ?? 0;
            return ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_serviceIcon(name), color: AppColors.primary, size: 20),
              ),
              title: _highlightMatch(name, _query),
              subtitle: Text(
                'from \u20B9${price.toStringAsFixed(0)}  \u00B7  $count salon${count != 1 ? 's' : ''}',
                style: AppTextStyles.caption,
              ),
              trailing: const Icon(Icons.north_west, size: 16, color: AppColors.textMuted),
              onTap: () => _onServiceTapped(name),
            );
          }),
        ],

        // Salons section
        if (hasSalons) ...[
          _SectionHeader(title: 'Salons', count: _suggestedSalons.length),
          ..._suggestedSalons.take(5).map((salon) {
            final coverImage = salon['cover_image'];
            final rating = double.tryParse(salon['rating_avg']?.toString() ?? '0') ?? 0;
            return ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: coverImage != null
                    ? CachedNetworkImage(
                        imageUrl: ApiConfig.imageUrl(coverImage) ?? coverImage,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(width: 40, height: 40, color: AppColors.softSurface),
                        errorWidget: (_, __, ___) => Container(
                          width: 40, height: 40, color: AppColors.softSurface,
                          child: const Icon(Icons.store, size: 20, color: AppColors.textMuted),
                        ),
                      )
                    : Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.softSurface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.store, size: 20, color: AppColors.textMuted),
                      ),
              ),
              title: _highlightMatch(salon['name'] ?? '', _query),
              subtitle: Row(
                children: [
                  if (rating > 0) ...[
                    const Icon(Icons.star, size: 12, color: AppColors.ratingStar),
                    const SizedBox(width: 2),
                    Text(rating.toStringAsFixed(1), style: AppTextStyles.caption),
                    const SizedBox(width: 8),
                  ],
                  if (salon['city'] != null)
                    Expanded(
                      child: Text(salon['city'] ?? '', style: AppTextStyles.caption, overflow: TextOverflow.ellipsis),
                    ),
                ],
              ),
              trailing: const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
              onTap: () => _onSalonTapped(salon['id'] ?? '', salon['name'] ?? ''),
            );
          }),
        ],

        // Stylists section
        if (hasStylists) ...[
          _SectionHeader(title: 'Stylists', count: _suggestedStylists.length),
          ..._suggestedStylists.take(5).map((stylist) => ListTile(
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.primaryLight,
              child: Text(
                (stylist['name'] ?? 'S')[0].toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
            title: _highlightMatch(stylist['name'] ?? '', _query),
            subtitle: Row(
              children: [
                const Icon(Icons.store, size: 12, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(stylist['salon_name'] ?? '', style: AppTextStyles.caption, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
            onTap: () => _onStylistTapped(stylist['salon_id'] ?? stylist['id'] ?? '', stylist['name'] ?? ''),
          )),
        ],
      ],
    );
  }

  /// Highlights the matching portion of text in bold teal
  Widget _highlightMatch(String text, String query) {
    if (query.isEmpty) return Text(text, style: AppTextStyles.labelLarge);
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final matchIndex = lowerText.indexOf(lowerQuery);
    if (matchIndex < 0) return Text(text, style: AppTextStyles.labelLarge);

    return RichText(
      text: TextSpan(
        style: AppTextStyles.labelLarge.copyWith(color: AppColors.textPrimary),
        children: [
          if (matchIndex > 0) TextSpan(text: text.substring(0, matchIndex)),
          TextSpan(
            text: text.substring(matchIndex, matchIndex + query.length),
            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
          ),
          if (matchIndex + query.length < text.length)
            TextSpan(text: text.substring(matchIndex + query.length)),
        ],
      ),
    );
  }

  /// Maps service name to a relevant icon
  IconData _serviceIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('haircut') || lower.contains('cut')) return Icons.content_cut;
    if (lower.contains('color') || lower.contains('dye')) return Icons.palette;
    if (lower.contains('spa') || lower.contains('massage')) return Icons.spa;
    if (lower.contains('facial')) return Icons.face;
    if (lower.contains('beard') || lower.contains('shave')) return Icons.face_retouching_natural;
    if (lower.contains('bridal') || lower.contains('makeup')) return Icons.auto_awesome;
    if (lower.contains('nail') || lower.contains('manicure') || lower.contains('pedicure')) return Icons.back_hand;
    if (lower.contains('wax')) return Icons.local_fire_department;
    if (lower.contains('smooth') || lower.contains('keratin') || lower.contains('straighten')) return Icons.air;
    return Icons.content_cut;
  }
}

// ── Reusable widgets ──

class _RecentSearchChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _RecentSearchChip({required this.label, required this.onTap, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 4, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: AppColors.softSurface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Text(label, style: AppTextStyles.bodySmall),
            const SizedBox(width: 2),
            GestureDetector(
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 12, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text(title, style: AppTextStyles.h4),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count', style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _TrendingServiceTile extends StatelessWidget {
  final String name;
  final int bookingCount;
  final double minPrice;
  final VoidCallback onTap;

  const _TrendingServiceTile({
    required this.name,
    required this.bookingCount,
    required this.minPrice,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(child: Text('\uD83D\uDD25', style: TextStyle(fontSize: 18))),
      ),
      title: Text(name, style: AppTextStyles.labelLarge),
      subtitle: Text(
        '$bookingCount booked this week  \u00B7  from \u20B9${minPrice.toStringAsFixed(0)}',
        style: AppTextStyles.caption,
      ),
      trailing: const Icon(Icons.north_west, size: 16, color: AppColors.textMuted),
      onTap: onTap,
    );
  }
}

class _TopRatedSalonCard extends StatelessWidget {
  final String name;
  final String? coverImage;
  final double ratingAvg;
  final String? distance;
  final VoidCallback onTap;

  const _TopRatedSalonCard({
    required this.name,
    required this.coverImage,
    required this.ratingAvg,
    required this.onTap,
    this.distance,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = coverImage != null ? ApiConfig.imageUrl(coverImage) : null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      width: 150,
                      height: 100,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(width: 150, height: 100, color: AppColors.softSurface),
                      errorWidget: (_, __, ___) => Container(
                        width: 150, height: 100, color: AppColors.softSurface,
                        child: const Icon(Icons.store, size: 32, color: AppColors.textMuted),
                      ),
                    )
                  : Container(
                      width: 150,
                      height: 100,
                      color: AppColors.softSurface,
                      child: const Icon(Icons.store, size: 32, color: AppColors.textMuted),
                    ),
            ),
            // Details
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: AppTextStyles.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (ratingAvg > 0) ...[
                        const Icon(Icons.star, size: 13, color: AppColors.ratingStar),
                        const SizedBox(width: 2),
                        Text(ratingAvg.toStringAsFixed(1), style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600)),
                      ],
                      if (distance != null) ...[
                        if (ratingAvg > 0) const SizedBox(width: 6),
                        Text(distance!, style: AppTextStyles.caption),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
