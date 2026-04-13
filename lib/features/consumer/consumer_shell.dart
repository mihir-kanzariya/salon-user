import 'dart:async';
import 'package:provider/provider.dart';
import '../../core/i18n/locale_provider.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/api_service.dart';
import '../../config/api_config.dart';
import '../../services/supabase_chat_service.dart';
import '../auth/presentation/providers/auth_provider.dart';
import 'home/presentation/screens/home_screen.dart';
import 'bookings_list/presentation/screens/bookings_list_screen.dart';
import 'favorites/presentation/screens/favorites_screen.dart';
import '../chat/presentation/screens/chat_list_screen.dart';
import 'profile/presentation/screens/consumer_profile_screen.dart';

class ConsumerShell extends StatefulWidget {
  const ConsumerShell({super.key});

  @override
  State<ConsumerShell> createState() => _ConsumerShellState();
}

class _ConsumerShellState extends State<ConsumerShell> {
  int _currentIndex = 0;
  final Set<int> _loadedTabs = {0}; // Only load home initially
  int _favoritesRefreshKey = 0;
  int _chatUnreadCount = 0;
  SupabaseChatSubscription? _chatSubscription;

  @override
  void initState() {
    super.initState();
    _fetchChatUnreadCount();
    _subscribeToChatUpdates();
  }

  @override
  void dispose() {
    _chatSubscription?.unsubscribe();
    super.dispose();
  }

  Future<void> _fetchChatUnreadCount() async {
    try {
      final response = await ApiService().get(ApiConfig.chatRooms);
      final rooms = response['data'] as List? ?? [];
      int total = 0;
      for (final room in rooms) {
        total += int.tryParse(room['unread_count']?.toString() ?? '0') ?? 0;
      }
      if (mounted) setState(() => _chatUnreadCount = total);
    } catch (_) {}
  }

  Future<void> _subscribeToChatUpdates() async {
    // Read userId before async gap to avoid using context after await
    final currentUserId = context.read<AuthProvider>().user?.id;
    if (currentUserId == null) return;

    final chatService = SupabaseChatService();
    if (!chatService.isReady) {
      await chatService.initFromBackend();
    }
    if (!chatService.isReady || !mounted) return;

    _chatSubscription = chatService.subscribeToUserChannel(
      userId: currentUserId,
      onUnreadUpdate: (roomId, unreadCount) {
        if (!mounted) return;
        _fetchChatUnreadCount();
      },
    );
  }

  Widget _buildScreen(int index) {
    // Only build screens that have been visited
    if (!_loadedTabs.contains(index)) {
      return const SizedBox.shrink();
    }
    switch (index) {
      case 0:
        return const HomeScreen();
      case 1:
        return const BookingsListScreen();
      case 2:
        return FavoritesScreen(key: ValueKey(_favoritesRefreshKey));
      case 3:
        return const ChatListScreen();
      case 4:
        return const ConsumerProfileScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: List.generate(5, _buildScreen),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) {
          setState(() {
            _loadedTabs.add(i);
            _currentIndex = i;
            // Force favorites to reload when tab is selected
            if (i == 2) _favoritesRefreshKey++;
            // Refresh unread count when navigating away from chat
            if (i != 3) _fetchChatUnreadCount();
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textMuted,
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.explore_outlined), activeIcon: const Icon(Icons.explore), label: context.watch<LocaleProvider>().tr('explore')),
          BottomNavigationBarItem(icon: const Icon(Icons.calendar_today_outlined), activeIcon: const Icon(Icons.calendar_today), label: context.watch<LocaleProvider>().tr('bookings')),
          BottomNavigationBarItem(icon: const Icon(Icons.favorite_border), activeIcon: const Icon(Icons.favorite), label: context.watch<LocaleProvider>().tr('favorites')),
          BottomNavigationBarItem(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.chat_bubble_outline),
                if (_chatUnreadCount > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        _chatUnreadCount > 9 ? '9+' : '$_chatUnreadCount',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            activeIcon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.chat_bubble),
                if (_chatUnreadCount > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        _chatUnreadCount > 9 ? '9+' : '$_chatUnreadCount',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            label: context.watch<LocaleProvider>().tr('chat'),
          ),
          BottomNavigationBarItem(icon: const Icon(Icons.person_outline), activeIcon: const Icon(Icons.person), label: context.watch<LocaleProvider>().tr('profile')),
        ],
      ),
    );
  }
}
