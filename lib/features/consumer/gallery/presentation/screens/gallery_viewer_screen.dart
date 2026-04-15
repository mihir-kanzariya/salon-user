import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../../config/api_config.dart';
import '../../../../../core/constants/app_colors.dart';

class GalleryViewerScreen extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const GalleryViewerScreen({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  @override
  State<GalleryViewerScreen> createState() => _GalleryViewerScreenState();
}

class _GalleryViewerScreenState extends State<GalleryViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;
  late List<String> _validImages;
  final Map<int, TransformationController> _transformControllers = {};

  @override
  void initState() {
    super.initState();
    // Filter out null/empty URLs
    _validImages = widget.images
        .where((url) => url.isNotEmpty)
        .toList();
    _currentIndex = widget.initialIndex.clamp(0, (_validImages.length - 1).clamp(0, 999999));
    _pageController = PageController(initialPage: _currentIndex);

    // Auto-pop if no valid images
    if (_validImages.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _transformControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TransformationController _getTransformController(int index) {
    return _transformControllers.putIfAbsent(index, () => TransformationController());
  }

  void _onDoubleTap(int index) {
    final controller = _getTransformController(index);
    if (controller.value != Matrix4.identity()) {
      controller.value = Matrix4.identity();
    } else {
      // ignore: deprecated_member_use
      controller.value = Matrix4.identity()
        ..translate(-100.0, -100.0) // ignore: deprecated_member_use
        ..scale(2.5); // ignore: deprecated_member_use
    }
  }

  void _jumpToIndex(int index) {
    // Reset zoom on current page before jumping
    final currentController = _transformControllers[_currentIndex];
    if (currentController != null) {
      currentController.value = Matrix4.identity();
    }
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _shareCurrentImage() {
    if (_validImages.isEmpty) return;
    final url = ApiConfig.imageUrl(_validImages[_currentIndex]) ?? _validImages[_currentIndex];
    Share.share(url);
  }

  @override
  Widget build(BuildContext context) {
    if (_validImages.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: AppColors.white),
          title: const Text('Gallery', style: TextStyle(color: AppColors.white)),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.photo_library_outlined, size: 64, color: AppColors.textMuted),
              SizedBox(height: 16),
              Text('No photos', style: TextStyle(color: AppColors.white, fontSize: 16)),
            ],
          ),
        ),
      );
    }

    final showThumbnails = _validImages.length > 1;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.5),
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.white),
        title: Text(
          '${_currentIndex + 1} of ${_validImages.length}',
          style: const TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w500),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: AppColors.white),
            onPressed: _shareCurrentImage,
          ),
        ],
      ),
      body: Column(
        children: [
          // Main image viewer
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: _validImages.length,
              onPageChanged: (index) {
                // Reset zoom on previous page
                final prevController = _transformControllers[_currentIndex];
                if (prevController != null) {
                  prevController.value = Matrix4.identity();
                }
                setState(() => _currentIndex = index);
              },
              itemBuilder: (context, index) {
                final imageUrl = ApiConfig.imageUrl(_validImages[index]) ?? _validImages[index];
                final transformController = _getTransformController(index);

                return GestureDetector(
                  onDoubleTap: () => _onDoubleTap(index),
                  child: InteractiveViewer(
                    transformationController: transformController,
                    minScale: 1.0,
                    maxScale: 5.0,
                    child: Center(
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => Shimmer.fromColors(
                          baseColor: AppColors.shimmerBase,
                          highlightColor: AppColors.shimmerHighlight,
                          child: Container(
                            width: double.infinity,
                            height: 300,
                            color: Colors.white,
                          ),
                        ),
                        errorWidget: (_, __, ___) => const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.broken_image_outlined, size: 64, color: AppColors.textMuted),
                            SizedBox(height: 12),
                            Text(
                              'Image unavailable',
                              style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Bottom thumbnail strip
          if (showThumbnails)
            Container(
              height: 72,
              color: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _validImages.length,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemBuilder: (context, index) {
                  final isActive = index == _currentIndex;
                  final thumbUrl = ApiConfig.imageUrl(_validImages[index]) ?? _validImages[index];

                  return GestureDetector(
                    onTap: () => _jumpToIndex(index),
                    child: Container(
                      width: 56,
                      height: 56,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isActive ? AppColors.primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: CachedNetworkImage(
                          imageUrl: thumbUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: AppColors.shimmerBase),
                          errorWidget: (_, __, ___) => Container(
                            color: AppColors.softSurface,
                            child: const Icon(Icons.broken_image, size: 16, color: AppColors.textMuted),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
