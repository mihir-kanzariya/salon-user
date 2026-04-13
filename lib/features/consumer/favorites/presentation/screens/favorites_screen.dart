import '../../../../../core/i18n/locale_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/widgets/loading_widget.dart';
import '../../../../../core/widgets/skeletons/skeleton_layouts.dart';
import '../../../../../core/widgets/empty_state_widget.dart';
import '../../../../../core/widgets/salon_card.dart';
import '../../../../../services/api_service.dart';
import '../../../../../config/api_config.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final ApiService _api = ApiService();

  bool _isLoading = true;
  String _error = '';
  List<Map<String, dynamic>> _favorites = [];

  @override
  void initState() {
    super.initState();
    _fetchFavorites();
  }

  Future<void> _fetchFavorites() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final response = await _api.get(ApiConfig.favorites);
      final data = response['data'] as List<dynamic>? ?? [];
      setState(() {
        _favorites = data.cast<Map<String, dynamic>>();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<bool> _unfavorite(String salonId) async {
    try {
      await _api.delete('${ApiConfig.favorites}/$salonId');
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to remove from favorites')),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(context.watch<LocaleProvider>().tr('favorites')),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const SkeletonList(child: SalonCardSkeleton());
    }

    if (_error.isNotEmpty) {
      return EmptyStateWidget(
        icon: Icons.error_outline,
        title: 'Something went wrong',
        subtitle: _error,
        actionText: 'Retry',
        onAction: _fetchFavorites,
      );
    }

    if (_favorites.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.favorite_border,
        title: context.watch<LocaleProvider>().tr('no_favorites'),
        subtitle: context.watch<LocaleProvider>().tr('no_favorites'),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchFavorites,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        itemCount: _favorites.length,
        itemBuilder: (context, index) {
          final salon = _favorites[index];
          final salonData = salon['salon'] ?? salon;
          final salonId = salonData['id'] ?? '';

          return Dismissible(
            key: Key(salonId),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) => _unfavorite(salonId),
            onDismissed: (_) {
              setState(() => _favorites.removeAt(index));
            },
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.heart_broken, color: AppColors.white, size: 28),
                  SizedBox(height: 4),
                  Text(
                    'Remove',
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            child: SalonCard(
              name: salonData['name'] ?? '',
              address: salonData['address'] ?? '',
              coverImage: salonData['cover_image'],
              rating: double.tryParse(salonData['rating_avg']?.toString() ?? '0') ?? 0,
              ratingCount: salonData['rating_count'] ?? 0,
              genderType: salonData['gender_type'] ?? 'unisex',
              isOpen: true,
              isFavorite: true,
              onFavorite: () async {
                final removed = await _unfavorite(salonId);
                if (removed && mounted) {
                  setState(() => _favorites.removeAt(index));
                }
              },
              onTap: () => Navigator.pushNamed(context, '/salon-detail', arguments: salonId),
            ),
          );
        },
      ),
    );
  }
}
