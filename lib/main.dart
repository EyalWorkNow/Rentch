import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/constants/brand_palette.dart';
import 'package:dating_app/core/services/push_notification_service.dart';
import 'package:dating_app/core/services/scaniverse_service.dart';
import 'package:dating_app/core/widgets/ipad_frame.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/onboarding_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:dating_app/firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Startup must never throw before runApp — a failure here is the classic
  // cause of a launch crash on TestFlight/release. Every step is guarded so the
  // app always reaches runApp(); degraded features fail soft instead.
  if (AppConfig.enableGoogleSignIn) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (error) {
      // Never rethrow on launch — Firebase Auth can still recover later.
      debugPrint('Firebase initialization skipped: $error');
    }

    // Push notifications (e.g. "your 3D tour is ready"). Fail-soft: handlers are
    // wired once, and the device token is (re)registered with the backend
    // whenever a user is signed in, so the server-side tour poller can reach
    // them while the app is closed.
    try {
      await PushNotificationService.instance.initialize();
      FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null) PushNotificationService.instance.registerForUser();
      });
    } catch (error) {
      debugPrint('Push notifications skipped: $error');
    }
  }

  // Scaniverse is optional; a failure must not block launch.
  try {
    await ScaniverseService.instance.initialize();
  } catch (error) {
    debugPrint('Scaniverse initialization skipped: $error');
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const RentlyApp());
}

class RentlyApp extends StatelessWidget {
  const RentlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      lazy: false,
      create: (_) => DatingProvider()..initialize(),
      child: Consumer<DatingProvider>(
        builder: (context, provider, _) {
          // Real-estate brokers get their own accent identity; everyone else
          // keeps the signature teal. Swap the global brand accent first so the
          // 380+ `AppColors.primary` references across the app repaint in the
          // broker's indigo, then theme + rebuild on top.
          AppColors.applyRole(provider.userRole);
          final palette = BrandPalette.forRole(provider.userRole);
          return MaterialApp(
            title: 'Rently',
            debugShowCheckedModeBanner: false,
            theme: _buildTheme(palette),
            builder: (context, child) {
              return Directionality(
                textDirection: TextDirection.rtl,
                child: IpadFrame(child: child ?? const SizedBox.shrink()),
              );
            },
            home: const OnboardingScreen(),
          );
        },
      ),
    );
  }

  ThemeData _buildTheme(BrandPalette palette) {
    return ThemeData(
      useMaterial3: true,
      // SF Hebrew Rounded primary (Hebrew text + all Latin via SF Pro Rounded
      // weight instances); SF Pro Rounded for pure-Latin contexts; Rubik fallback.
      fontFamily: 'SF Hebrew Rounded',
      fontFamilyFallback: const ['SF Pro Rounded', 'Rubik'],
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.primary,
        primary: palette.primary,
        secondary: AppColors.coral,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: AppColors.navy),
        titleTextStyle: TextStyle(
          color: AppColors.navy,
          fontSize: 22,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.3,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.primaryLight2,
        selectedColor: palette.primary,
        labelStyle: const TextStyle(
          color: AppColors.navy,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.borderLight),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.primary,
        thumbColor: palette.primary,
        inactiveTrackColor: const Color(0xFFD0EDF0),
        overlayColor: palette.primary.withValues(alpha: 0.13),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            letterSpacing: 0.2,
          ),
        ),
      ),
      // Clean, soft, rounded text fields app-wide — matching the AI assistant's
      // input: a light-gray, borderless, rounded pill that reads well on any
      // background (no flat white-on-white boxes, no hard borders).
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF1F5F8),
        hintStyle: const TextStyle(color: AppColors.textDisabled),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: palette.primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navy,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      ),
    );
  }
}
