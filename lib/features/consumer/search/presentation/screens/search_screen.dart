import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_text_styles.dart';
import '../../../../../core/widgets/skeletons/skeleton_layouts.dart';
import '../../../../../core/widgets/empty_state_widget.dart';
import '../../../../../core/widgets/salon_card.dart';
import '../../../../../services/api_service.dart';
import '../../../../../config/api_config.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late TabController _tabController;

  Timer? _debounce;
  bool _isLoading = false;
  String _query = '';
  List<Map<String, dynamic>> _salonResults = [];
  List<Map<String, dynamic>> _stylistResults = [];
  bool _hasSearched = false;
  List<String> _recentSearches = [];
  int _salonCount = 0;
  int _stylistCount = 0;

  static const String _recentSearchesKey = 'recent_searches';
  static const int _maxRecent = 8;

  static const List<String> _popularCategories = [
    'Haircut', 'Facial', 'Hair Color', 'Spa',
    'Bridal Makeup', 'Beard Trim', 'Manicure', 'Pedicure',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRecentSearches();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _focusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _recentSearches = prefs.getStringList(_recentSearchesKey) ?? []);
  }

  Future<void> _saveRecentSearch(String query) async {
    _recentSearches.remove(query);
    _recentSearches.insert(0, query);
    if (_recentSearches.length > _maxRecent) _recentSearches = _recentSearches.sublist(0, _maxRecent);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentSearchesKey, _recentSearches);
  }

  Future<void> _clearRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentSearchesKey);
    setState(() => _recentSearches = []);
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query == _query) return;
    _debounce?.cancel();
    if (query.isEmpty) {
      setState(() { _query = ''; _salonResults = []; _stylistResults = []; _hasSearched = false; _isLoading = false; });
      return;
    }
    setState(() { _query = query; _isLoading = true; });
    _debounce = Timer(const Duration(milliseconds: 300), () => _performSearch(query));
  }

  Future<void> _performSearch(String query) async {
    try {
      // Search both salons and stylists in parallel
      final results = await Future.wait([
        _api.get(ApiConfig.nearbySalons, queryParams: {'search': query}, auth: false),
        _api.get('/stylists/nearby', queryParams: {'search': query}, auth: false).catchError((_) => <String, dynamic>{'data': [], 'meta': {}}),
      ]);

      if (mounted && _query == query) {
        _saveRecentSearch(query);
        final salonData = (results[0]['data'] as List?) ?? [];
        final stylistData = (results[1]['data'] as List?) ?? [];
        final salonMeta = results[0]['meta'] as Map<String, dynamic>? ?? {};

        setState(() {
          _salonResults = salonData.cast<Map<String, dynamic>>();
          _stylistResults = stylistData.cast<Map<String, dynamic>>();
          _salonCount = (salonMeta['total'] as int?) ?? salonData.length;
          _stylistCount = stylistData.length;
          _isLoading = false;
          _hasSearched = true;
        });
      }
    } catch (e) {
      if (mounted && _query == query) {
        setState(() { _salonResults = []; _stylistResults = []; _isLoading = false; _hasSearched = true; });
      }
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _searchController,
          focusNode: _focusNode,
          autofocus: true,
          style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Search salons, stylists, services...',
            hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 16),
            border: InputBorder.none,
            prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
            suffixIcon: _query.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear, color: AppColors.textMuted), onPressed: _clearSearch)
                : null,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const SkeletonList(child: SalonCardSkeleton());

    if (_query.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_recentSearches.isNotEmpty) ...[
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Recent Searches', style: AppTextStyles.h4),
              GestureDetector(onTap: _clearRecentSearches, child: Text('Clear All', style: AppTextStyles.caption.copyWith(color: AppColors.primary))),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: _recentSearches.map((q) => GestureDetector(
              onTap: () => _searchController.text = q,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: AppColors.softSurface, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.history, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Text(q, style: AppTextStyles.bodySmall),
                ]),
              ),
            )).toList()),
            const SizedBox(height: 24),
          ],
          const Text('Popular Searches', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: _popularCategories.map((term) => ActionChip(
            label: Text(term),
            onPressed: () { _searchController.text = term; _performSearch(term); },
            backgroundColor: AppColors.softSurface,
            side: BorderSide.none,
          )).toList()),
        ]),
      );
    }

    if (_hasSearched && _salonResults.isEmpty && _stylistResults.isEmpty) {
      return EmptyStateWidget(icon: Icons.search_off, title: 'No results for \'$_query\'', subtitle: 'Try a different search term');
    }

    // Show results with Salon/Stylist tabs
    return Column(children: [
      // Tab bar
      Container(
        color: AppColors.cardBackground,
        child: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          tabs: [
            Tab(text: 'Salons ($_salonCount)'),
            Tab(text: 'Stylists ($_stylistCount)'),
          ],
        ),
      ),
      // Tab content
      Expanded(
        child: TabBarView(controller: _tabController, children: [
          _buildSalonList(),
          _buildStylistList(),
        ]),
      ),
    ]);
  }

  Widget _buildSalonList() {
    if (_salonResults.isEmpty) {
      return const EmptyStateWidget(icon: Icons.store_outlined, title: 'No salons found', subtitle: 'Try searching for something else');
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _salonResults.length,
      itemBuilder: (context, index) {
        final salon = _salonResults[index];
        final distance = salon['distance'] != null ? double.tryParse(salon['distance'].toString()) : null;
        String distanceText = '';
        if (distance != null) distanceText = distance < 1 ? '${(distance * 1000).round()}m' : '${distance.toStringAsFixed(1)} km';

        return SalonCard(
          name: salon['name'] ?? '',
          address: salon['address'] ?? '',
          coverImage: salon['cover_image'],
          rating: double.tryParse(salon['rating_avg']?.toString() ?? '0') ?? 0,
          ratingCount: salon['rating_count'] ?? 0,
          distance: distanceText.isNotEmpty ? distanceText : null,
          genderType: salon['gender_type'] ?? 'unisex',
          isOpen: true,
          onTap: () => Navigator.pushNamed(context, '/salon-detail', arguments: salon['id'] ?? ''),
        );
      },
    );
  }

  Widget _buildStylistList() {
    if (_stylistResults.isEmpty) {
      return const EmptyStateWidget(icon: Icons.person_search, title: 'No stylists found', subtitle: 'Try searching by name');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _stylistResults.length,
      itemBuilder: (context, index) {
        final stylist = _stylistResults[index];
        final user = stylist['user'] ?? {};
        final salon = stylist['salon'] ?? {};
        final name = user['name'] ?? 'Stylist';
        final photo = user['profile_photo'];
        final salonName = salon['name'] ?? '';
        final salonId = salon['id'] ?? '';
        final distance = salon['distance'] != null ? double.tryParse(salon['distance'].toString()) : null;
        final specializations = (stylist['specializations'] as List?)?.cast<String>() ?? [];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.pushNamed(context, '/salon-detail', arguments: salonId),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.primaryLight,
                  backgroundImage: photo != null ? NetworkImage(ApiConfig.imageUrl(photo) ?? photo) : null,
                  child: photo == null ? Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)) : null,
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: AppTextStyles.labelLarge),
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.store, size: 13, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Expanded(child: Text(salonName, style: AppTextStyles.caption, overflow: TextOverflow.ellipsis)),
                  ]),
                  if (distance != null) ...[
                    const SizedBox(height: 2),
                    Text('${distance < 1 ? '${(distance * 1000).round()}m' : '${distance.toStringAsFixed(1)} km'} away', style: AppTextStyles.caption.copyWith(color: AppColors.primary)),
                  ],
                  if (specializations.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, children: specializations.take(3).map((s) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                      child: Text(s, style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w500)),
                    )).toList()),
                  ],
                ])),
                const Icon(Icons.chevron_right, color: AppColors.textMuted),
              ]),
            ),
          ),
        );
      },
    );
  }
}
