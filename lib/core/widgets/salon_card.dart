import 'package:flutter/material.dart';
import '../../config/api_config.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import 'skeletons/shimmer_image.dart';

class SalonCard extends StatelessWidget {
  final String name;
  final String address;
  final String? coverImage;
  final double rating;
  final int ratingCount;
  final String? distance;
  final String genderType;
  final bool isOpen;
  final VoidCallback? onTap;
  final VoidCallback? onFavorite;
  final bool isFavorite;
  final double? minPrice;
  final double? maxPrice;
  // Phase 1: New fields
  final String? closingTime; // e.g. "9:00 PM"
  final int stylistCount;
  final List<String> amenities;
  final List<String> gallery;

  const SalonCard({
    super.key,
    required this.name,
    required this.address,
    this.coverImage,
    this.rating = 0,
    this.ratingCount = 0,
    this.distance,
    this.genderType = 'unisex',
    this.isOpen = true,
    this.onTap,
    this.onFavorite,
    this.isFavorite = false,
    this.minPrice,
    this.maxPrice,
    this.closingTime,
    this.stylistCount = 0,
    this.amenities = const [],
    this.gallery = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image with overlays
            _buildImageSection(),
            // Info section
            _buildInfoSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    return Stack(
      children: [
        ShimmerImage(
          imageUrl: coverImage != null
              ? (ApiConfig.imageUrl(coverImage) ?? coverImage!)
              : null,
          height: 150,
          width: double.infinity,
          fit: BoxFit.cover,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          errorWidget: Container(
            height: 150,
            decoration: const BoxDecoration(
              color: AppColors.softSurface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: const Icon(Icons.store, size: 48, color: AppColors.textMuted),
          ),
        ),
        // Gradient overlay
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 60,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.5),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        // Open/Closed badge with closing time
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isOpen
                  ? AppColors.success.withValues(alpha: 0.9)
                  : AppColors.error.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  isOpen
                      ? (closingTime != null ? 'Open \u00b7 Closes $closingTime' : 'Open')
                      : 'Closed',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Favorite button
        if (onFavorite != null)
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: onFavorite,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: isFavorite ? AppColors.error : AppColors.textMuted,
                  size: 18,
                ),
              ),
            ),
          ),
        // Gallery thumbnails (bottom-right, show up to 3)
        if (gallery.isNotEmpty)
          Positioned(
            bottom: 8,
            right: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...gallery.take(3).map((img) => Container(
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.white, width: 1.5),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: ShimmerImage(
                      imageUrl: ApiConfig.imageUrl(img) ?? img,
                      height: 32,
                      width: 32,
                      fit: BoxFit.cover,
                    ),
                  ),
                )),
                if (gallery.length > 3)
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.white, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        '+${gallery.length - 3}',
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildInfoSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Name + Distance
          Row(
            children: [
              Expanded(
                child: Text(name, style: AppTextStyles.h4, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (distance != null) ...[
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.near_me, size: 12, color: AppColors.textMuted),
                    const SizedBox(width: 2),
                    Text(distance!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          // Row 2: Address
          Text(address, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          // Row 3: Rating + Stylists + Gender + Price
          Row(
            children: [
              // Rating
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: rating >= 4.0
                      ? const Color(0xFF16A34A).withValues(alpha: 0.1)
                      : rating > 0
                          ? AppColors.warningLight
                          : AppColors.softSurface,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.star_rounded,
                      color: rating >= 4.0
                          ? const Color(0xFF16A34A)
                          : rating > 0
                              ? AppColors.ratingStar
                              : AppColors.textMuted,
                      size: 14,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      rating > 0 ? rating.toStringAsFixed(1) : 'New',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: rating >= 4.0
                            ? const Color(0xFF16A34A)
                            : rating > 0
                                ? AppColors.textPrimary
                                : AppColors.textMuted,
                      ),
                    ),
                    if (ratingCount > 0)
                      Text(
                        ' ($ratingCount)',
                        style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                      ),
                  ],
                ),
              ),
              // Stylist count
              if (stylistCount > 0) ...[
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.content_cut, size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 3),
                    Text(
                      '$stylistCount stylist${stylistCount != 1 ? 's' : ''}',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
              const Spacer(),
              // Gender badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: genderType == 'unisex'
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : AppColors.accentLight,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  genderType[0].toUpperCase() + genderType.substring(1),
                  style: TextStyle(
                    fontSize: 10,
                    color: genderType == 'unisex' ? AppColors.primary : AppColors.accentDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          // Row 4: Amenities (top 3 as chips)
          if (amenities.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                ...amenities.take(3).map((a) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.softSurface,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_amenityIcon(a), size: 11, color: AppColors.textSecondary),
                        const SizedBox(width: 3),
                        Text(
                          a,
                          style: TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                )),
                if (amenities.length > 3)
                  Text(
                    '+${amenities.length - 3} more',
                    style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                  ),
              ],
            ),
          ],
          // Row 5: Price anchoring strip
          if (minPrice != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  Icon(Icons.local_offer_outlined, size: 13, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Starts from \u20B9${minPrice!.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  if (maxPrice != null && maxPrice! > minPrice!) ...[
                    Text(
                      '  \u00b7  ',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                    Text(
                      'Up to \u20B9${maxPrice!.toStringAsFixed(0)}',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _amenityIcon(String amenity) {
    final lower = amenity.toLowerCase();
    if (lower.contains('ac') || lower.contains('air')) return Icons.ac_unit;
    if (lower.contains('park')) return Icons.local_parking;
    if (lower.contains('wifi') || lower.contains('wi-fi')) return Icons.wifi;
    if (lower.contains('card') || lower.contains('upi') || lower.contains('pay')) return Icons.payment;
    if (lower.contains('music')) return Icons.music_note;
    if (lower.contains('tv') || lower.contains('screen')) return Icons.tv;
    if (lower.contains('coffee') || lower.contains('tea') || lower.contains('drink')) return Icons.coffee;
    if (lower.contains('magazine') || lower.contains('book')) return Icons.menu_book;
    if (lower.contains('child') || lower.contains('kid')) return Icons.child_care;
    if (lower.contains('wheel') || lower.contains('accessible')) return Icons.accessible;
    return Icons.check_circle_outline;
  }
}
