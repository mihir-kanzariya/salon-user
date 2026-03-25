# Salon User — Customer App

## Project Overview
Flutter mobile app for **customers** to discover salons, book appointments, and pay online. Part of the Saloon marketplace platform.

## Tech Stack
- **Framework**: Flutter (Dart)
- **State Management**: Provider
- **Payment**: Razorpay Flutter SDK (`razorpay_flutter`)
- **Storage**: SharedPreferences + FlutterSecureStorage
- **Push Notifications**: Firebase Messaging
- **Chat**: Supabase Realtime
- **Backend**: `saloon-backend` API (shared with salon-owner app)

## Key Commands
```bash
flutter pub get                    # Install deps
flutter run                        # Run on connected device
flutter run -d chrome --web-port 8080  # Run on web (Razorpay won't work on web)
flutter build apk --debug         # Build Android debug APK
flutter build apk --release       # Build release APK
```

## Project Structure
```
lib/
├── config/              # API endpoints (api_config.dart)
├── core/
│   ├── constants/       # Colors, text styles, routes, app constants
│   ├── utils/           # Storage service, snackbar utils
│   └── widgets/         # Reusable widgets (AppButton, LoadingWidget)
├── features/
│   ├── auth/            # Phone login, OTP verification
│   ├── consumer/        # ALL CUSTOMER FEATURES:
│   │   ├── home/        # Salon discovery, nearby salons
│   │   ├── booking/     # Booking flow (select slot → pay → confirm)
│   │   ├── booking_detail/  # View/cancel bookings
│   │   ├── payment/     # Razorpay payment screen
│   │   ├── profile/     # Edit profile
│   │   ├── favorites/   # Saved salons
│   │   └── salon_detail/ # Salon page with services
│   ├── salon/           # Salon owner features (NOT used in this app — for salon-owner repo)
│   ├── chat/            # Customer-salon messaging
│   ├── notifications/   # Push notification list
│   ├── reviews/         # Submit/view reviews
│   └── splash/          # Splash + routing
├── services/            # API service (HTTP client with auth)
└── main.dart            # App entry, routes, providers
```

## Key Flows
1. **Booking + Pay**: Select salon → services → date/time → tap "Pay & Book ₹XXX" → Razorpay checkout → payment verified → booking confirmed
2. **Payment**: Uses `razorpay_flutter` SDK (Android/iOS only, NOT web). Test card: `4111 1111 1111 1111`
3. **Auth**: Phone OTP login. Dev mode: OTP is always `1111`

## API Configuration
- Base URL configured in `lib/config/api_config.dart`
- Default: `http://localhost:3000/api/v1`
- For mobile testing: change to your laptop's WiFi IP (e.g., `http://192.168.x.x:3000/api/v1`)
- Or use `--dart-define=API_BASE_URL=http://your-ip:3000/api/v1` at build time

## Coding Conventions
- Feature-based folder structure (`features/consumer/booking/...`)
- Repository pattern for API calls (`BookingRepository`, etc.)
- Provider for state management
- `ApiService` handles auth headers, token refresh, error mapping
- `SnackbarUtils` for user-facing messages
- Screens are StatefulWidgets with `_load*()` methods in initState

## Important Notes
- `razorpay_flutter` only works on Android/iOS, NOT on web — web build will show payment button but checkout won't open
- The `features/salon/` directory contains salon owner screens — these are NOT part of the customer app. They exist because the original monorepo had both. For this repo, ignore/remove salon features over time.

## Related Repos
- **saloon-backend**: Shared backend API (github.com/mihir-kanzariya/saloon-backend)
- **salon-owner**: Salon owner app (github.com/mihir-kanzariya/salon-owner)
