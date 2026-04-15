import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../../config/api_config.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/widgets/empty_state_widget.dart';
import 'gallery_viewer_screen.dart';

class GalleryGridScreen extends StatelessWidget {
  final List<String> images;
  final String salonName;

  const GalleryGridScreen({
    super.key,
    required this.images,
    this.salonName = 'Gallery',
  });

  @override
  Widget build(BuildContext context) {
    // Filter out null/empty URLs
    final validImages = images.where((url) => url.isNotEmpty).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Gallery (${validImages.length})',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: validImages.isEmpty
          ? const EmptyStateWidget(
              icon: Icons.photo_library_outlined,
              title: 'No photos yet',
              subtitle: 'This salon has not uploaded any photos',
            )
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: validImages.length,
              itemBuilder: (context, index) {
                final imageUrl = ApiConfig.imageUrl(validImages[index]) ?? validImages[index];

                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GalleryViewerScreen(
                          images: validImages,
                          initialIndex: index,
                        ),
                      ),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Shimmer.fromColors(
                        baseColor: AppColors.shimmerBase,
                        highlightColor: AppColors.shimmerHighlight,
                        child: Container(color: Colors.white),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.softSurface,
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.broken_image_outlined, size: 24, color: AppColors.textMuted),
                            SizedBox(height: 4),
                            Text(
                              'Unavailable',
                              style: TextStyle(fontSize: 9, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
