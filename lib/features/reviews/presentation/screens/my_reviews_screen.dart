import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/utils/snackbar_utils.dart';
import '../../../../core/widgets/empty_state_widget.dart';
import '../../../../core/widgets/skeletons/skeleton_layouts.dart';
import '../../../../services/api_service.dart';
import '../../../../config/api_config.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class MyReviewsScreen extends StatefulWidget {
  const MyReviewsScreen({super.key});

  @override
  State<MyReviewsScreen> createState() => _MyReviewsScreenState();
}

class _MyReviewsScreenState extends State<MyReviewsScreen> {
  final ApiService _api = ApiService();
  List<dynamic> _reviews = [];
  bool _isLoading = true;
  bool _hasError = false;

  int _page = 1;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
        _page = 1;
        _hasMore = true;
      });
      final response = await _api.get(
        '${ApiConfig.reviews}/my',
        queryParams: {'page': _page.toString(), 'limit': '10'},
      );
      final meta = response['meta'];
      _reviews = response['data'] ?? [];
      setState(() {
        _isLoading = false;
        if (meta != null) {
          _hasMore = (meta['page'] as num) < (meta['totalPages'] as num);
        } else {
          _hasMore = false;
        }
      });
    } catch (e) {
      if (mounted) ErrorHandler.handle(context, e);
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);
    _page++;

    try {
      final response = await _api.get(
        '${ApiConfig.reviews}/my',
        queryParams: {'page': _page.toString(), 'limit': '10'},
      );
      final meta = response['meta'];
      final newReviews = response['data'] ?? [];
      setState(() {
        _reviews.addAll(newReviews);
        if (meta != null) {
          _hasMore = (meta['page'] as num) < (meta['totalPages'] as num);
        } else {
          _hasMore = false;
        }
        _isLoadingMore = false;
      });
    } catch (e) {
      if (mounted) ErrorHandler.handle(context, e);
      _page--;
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _deleteReview(String reviewId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Review'),
        content: const Text(
            'Are you sure you want to delete this review? This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _api.delete('${ApiConfig.reviews}/$reviewId');
      if (!mounted) return;
      SnackbarUtils.showSuccess(context, 'Review deleted successfully');
      _load();
    } catch (e) {
      if (mounted) ErrorHandler.handle(context, e);
    }
  }

  void _editReview(Map<String, dynamic> review) async {
    final result = await Navigator.pushNamed(
      context,
      '/submit-review',
      arguments: {
        'booking_id': review['booking_id'] ?? review['booking'] ?? '',
        'salon_id': review['salon_id'] ?? review['salon']?['_id'] ?? review['salon']?['id'] ?? '',
        'salon_name': review['salon']?['name'],
        'stylist_id': review['stylist_id'],
        'review_id': review['_id'] ?? review['id'],
        'existing_salon_rating': (review['salon_rating'] as num?)?.toInt(),
        'existing_stylist_rating': (review['stylist_rating'] as num?)?.toInt(),
        'existing_comment': review['comment'] as String?,
      },
    );
    if (result == true) _load();
  }

  String _relativeDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays == 0) return 'Today';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays} days ago';
      if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} weeks ago';
      if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} months ago';
      return '${(diff.inDays / 365).floor()} years ago';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('My Reviews')),
      body: _isLoading
          ? const SkeletonList(child: ReviewCardSkeleton())
          : _hasError
              ? EmptyStateWidget(
                  icon: Icons.error_outline,
                  title: 'Something went wrong',
                  subtitle: 'Failed to load reviews',
                  actionText: 'Retry',
                  onAction: _load,
                )
          : _reviews.isEmpty
              ? const EmptyStateWidget(
                  icon: Icons.rate_review_outlined,
                  title: 'No reviews yet',
                  subtitle: "You haven't reviewed any salons yet",
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _reviews.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _reviews.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }

                      final review = _reviews[index];
                      final salonName = review['salon']?['name'] ?? 'Salon';
                      final salonRating =
                          (review['salon_rating'] as num?)?.toInt() ?? 0;
                      final stylistRating = review['stylist_rating'];
                      final comment = review['comment'] ?? '';
                      final createdAt = review['created_at'] as String?;
                      final reviewId = review['_id'] ?? review['id'];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header row: salon name + actions
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: AppColors.primaryLight,
                                    child: const Icon(Icons.store,
                                        color: AppColors.white, size: 18),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(salonName,
                                            style: AppTextStyles.labelLarge),
                                        if (createdAt != null)
                                          Text(_relativeDate(createdAt),
                                              style: AppTextStyles.caption),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: List.generate(
                                      5,
                                      (i) => Icon(
                                        i < salonRating
                                            ? Icons.star
                                            : Icons.star_border,
                                        color: AppColors.ratingStar,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert,
                                        size: 20,
                                        color: AppColors.textMuted),
                                    padding: EdgeInsets.zero,
                                    onSelected: (value) {
                                      if (value == 'edit') {
                                        _editReview(
                                            Map<String, dynamic>.from(review));
                                      } else if (value == 'delete') {
                                        _deleteReview(reviewId);
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Edit')),
                                      const PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete',
                                              style: TextStyle(
                                                  color: AppColors.error))),
                                    ],
                                  ),
                                ],
                              ),

                              // Comment
                              if (comment.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(comment,
                                    style: AppTextStyles.bodyMedium),
                              ],

                              // Stylist rating
                              if (stylistRating != null) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Text('Stylist: ',
                                        style: AppTextStyles.caption),
                                    ...List.generate(
                                      5,
                                      (i) => Icon(
                                        i < (stylistRating as num).toInt()
                                            ? Icons.star
                                            : Icons.star_border,
                                        color: AppColors.accent,
                                        size: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ],

                              // Salon reply
                              if (review['reply'] != null) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.softSurface,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Salon Reply',
                                          style: AppTextStyles.labelMedium
                                              .copyWith(
                                                  color: AppColors.primary)),
                                      const SizedBox(height: 4),
                                      Text(review['reply'],
                                          style: AppTextStyles.bodySmall),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
