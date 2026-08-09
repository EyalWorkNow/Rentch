import 'dart:async';

import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/design/app_typography.dart';
import 'package:dating_app/core/services/behavior_insights_service.dart';
import 'package:dating_app/core/services/event_service.dart';
import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/scenario_layers.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/services/home_widget_service.dart';
import 'package:dating_app/core/services/notif_admin_gate.dart';
import 'package:dating_app/core/services/notification_permission_service.dart';
import 'package:dating_app/core/services/notification_service.dart';
import 'package:dating_app/core/services/push_notification_service.dart';
import 'package:dating_app/core/services/scaniverse_service.dart';
import 'package:dating_app/presentation/screens/admin/notif_console_screen.dart';
import 'package:dating_app/core/widgets/ipad_frame.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/home_screen.dart';
import 'package:dating_app/presentation/screens/onboarding_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:dating_app/firebase_options.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:dating_app/core/services/deep_link_service.dart';

/// Global navigator key so deep links can push the apartment page from outside
/// the widget tree.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
// Held so its link-stream subscription stays alive for the app's lifetime.
DeepLinkService? _deepLinks;

/// Single app-wide back-navigation observer. Created once (not per build) and
/// attached to the [MaterialApp.navigatorObservers]; see [_BackNavigationObserver].
final _BackNavigationObserver _backNavObserver = _BackNavigationObserver();

// Best-effort in-app-vs-system back disambiguation. `didPop` alone can't tell an
// OS/gesture back from a tapped in-app back, so an in-app back affordance may
// announce itself via [markInAppBack] right before popping; a pop within
// [_kInAppBackWindow] of that call is attributed to an in-app back.
DateTime? _inAppBackAt;
const Duration _kInAppBackWindow = Duration(milliseconds: 500);

/// Public adoption hook: in-app back affordances (AppBar back arrow, custom
/// "return" buttons) call this immediately before `Navigator.pop` so the
/// resulting `backNavigated` event is tagged `isSystemBack: false`. Screens that
/// don't call it simply have their backs counted as system/gesture backs
/// (the common default). No-op-safe to call from anywhere.
void markInAppBack() => _inAppBackAt = DateTime.now();

/// Privacy-safe screen label for a route. Uses an explicit [RouteSettings.name]
/// when a screen supplies one; otherwise falls back to the route's runtime type
/// so pages / dialogs / bottom-sheets are still distinguishable. Never emits a
/// URL, id, or argument — only a screen/route TYPE.
///
/// BLOCKER (documented, not fixable from the 3 owned files): this app pushes via
/// ~91 unnamed `MaterialPageRoute`s in screen files, so most labels resolve to
/// `<MaterialPageRoute<...>>` rather than a human screen name. Richer per-screen
/// names require adding `settings: RouteSettings(name: 'ScreenX')` at those push
/// sites (or wrapping screens with a RouteObserver-aware mixin) — all in files
/// this task does not own.
String _routeScreenName(Route<dynamic>? route) {
  if (route == null) return 'none';
  final name = route.settings.name;
  if (name != null && name.trim().isNotEmpty) {
    final n = name.trim();
    return n.length <= 64 ? n : n.substring(0, 64);
  }
  return '<${route.runtimeType}>';
}

/// Captures every back/pop navigation and emits a `backNavigated` event
/// (EventService) plus a note into [BehaviorInsights].
///
/// What it captures per pop:
///   • fromRoute  — the screen the user backed OUT of ([_routeScreenName]).
///   • toRoute    — the screen revealed underneath (returned TO).
///   • dwellMs    — time on the popped screen, measured didPush → didPop.
///   • isSystemBack — OS/gesture back (Android hardware back, iOS edge-swipe)
///     vs a tapped in-app back affordance. didPop alone can't tell them apart,
///     so an in-app back button MAY announce itself via [markInAppBack] just
///     before popping; a pop within [_kInAppBackWindow] of that call is tagged
///     in-app, otherwise it defaults to a system back (the common case).
class _BackNavigationObserver extends NavigatorObserver {
  // didPush timestamp per live route → dwell on didPop. Cleared on pop/remove/
  // replace, so it never grows past the current navigation stack depth.
  final Map<Route<dynamic>, DateTime> _pushedAt = <Route<dynamic>, DateTime>{};

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pushedAt[route] = DateTime.now();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _handlePop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pushedAt.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _pushedAt.remove(oldRoute);
    if (newRoute != null) _pushedAt[newRoute] = DateTime.now();
  }

  void _handlePop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    try {
      final pushedAt = _pushedAt.remove(route);
      final dwellMs = pushedAt == null
          ? 0
          : DateTime.now().difference(pushedAt).inMilliseconds;
      final from = _routeScreenName(route);
      final to = _routeScreenName(previousRoute);

      final marked = _inAppBackAt;
      final isInApp = marked != null &&
          DateTime.now().difference(marked) <= _kInAppBackWindow;
      _inAppBackAt = null;

      AppEvents.instance.service.logBackNavigation(
        fromRoute: from,
        toRoute: to,
        dwellMs: dwellMs,
        isSystemBack: !isInApp,
      );
      BehaviorInsights.instance.noteBackNavigation(
        fromScreen: from,
        dwellMs: dwellMs,
        isSystemBack: !isInApp,
      );
    } catch (_) {/* fail-soft: telemetry must never break navigation */}
  }
}

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
      // Show incoming pushes even while the app is OPEN (the OS won't auto-show
      // them in the foreground) — otherwise the user "gets no notifications".
      PushNotificationService.instance.onForegroundMessage = (message) {
        final n = message.notification;
        final title = (n?.title ?? message.data['title'] ?? '').toString();
        final body = (n?.body ?? message.data['body'] ?? '').toString();
        NotificationService.instance.showForegroundPush(title, body);
        // A match/message push means a new conversation exists server-side —
        // re-pull matches so it appears in the list now, not on next relaunch.
        final type = (message.data['type'] ?? '').toString();
        if (type == 'match' || type == 'message') {
          try {
            appNavigatorKey.currentContext
                ?.read<DatingProvider>()
                .refreshMatchesFromBackend();
          } catch (_) {/* provider not ready yet — resume hook will catch it */}
        }
      };
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

  // Draw edge-to-edge so the system nav bar (esp. Samsung One UI's 3-button /
  // gesture bar) becomes a transparent overlay and MediaQuery.viewPadding.bottom
  // reports its real height — otherwise it stays 0 and the floating app navbar
  // renders UNDER the Samsung bar (looked hidden). contrastEnforced:false stops
  // Android drawing a scrim behind the now-transparent bar.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  runApp(const RentlyApp());

  // PERF: the gov-data reference layer is ~9 MB of JSON (stat_areas 5.8 MB +
  // schools 1.6 MB + ~13 more) that used to be parsed on the main isolate
  // BEFORE runApp — a blank screen for the whole parse (the slow-launch cause).
  // It's only needed by the recommendation ranker, which is fully fail-soft, so
  // load it in the BACKGROUND after the first frame; ranking uses built-in
  // heuristics until it lands. See _loadReferenceData().
  unawaited(_loadReferenceData());

  // Deep links: rently://property/<id> → open the apartment in-app. Fail-soft.
  _deepLinks = DeepLinkService(appNavigatorKey);
  unawaited(_deepLinks!.init());
}

/// Background load of the ranker's gov-data reference layer, off the first-frame
/// path. Each await yields so the UI keeps rendering between loaders. Fully
/// fail-soft: any failure just leaves the ranker on its built-in heuristics.
Future<void> _loadReferenceData() async {
  try {
    await GovData.instance.init();
    await ScenarioLayers.instance.ensureLoaded(); // curated persona→display-layer spec
    await IsraelGeoIndex.loadParks(); // public-park proximity for the ranker
    await IsraelGeoIndex.loadSchools(); // named + typed school proximity
    await IsraelGeoIndex.loadNightlife(); // bar/pub/café density (vibrant areas)
    await IsraelGeoIndex.loadSupermarkets(); // real supermarket density (retail_access)
    await IsraelGeoIndex.loadClinics(); // real clinic density (health_access)
    await IsraelGeoIndex.loadSynagogues(); // synagogue density (religious_area)
  } catch (error) {
    debugPrint('GovData init skipped: $error');
  }
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
          //
          // ponytail: the accent is derived from `provider.themeRole` (the
          // SINGLE SOURCE OF TRUTH), NOT the raw `userRole`. themeRole only
          // resolves to 'broker' for a confirmed, in-app broker (broker role +
          // active session) and is neutral teal for the entire login / signup /
          // onboarding entry flow — so black can never leak into the entry flow
          // on a first launch or relaunch, regardless of any stale/transient
          // role or leftover global statics (which we overwrite here every
          // build from this one gated source).
          final themeRole = provider.themeRole;
          AppColors.applyRole(themeRole);
          return MaterialApp(
            title: 'Rently',
            navigatorKey: appNavigatorKey,
            navigatorObservers: [_backNavObserver],
            debugShowCheckedModeBanner: false,
            theme: _buildTheme(),
            locale: Locale(provider.languageCode),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) {
              // Cross-platform rendering parity (Android ↔ iOS):
              // 1) Clamp text scaling so a large Android system font-size can't
              //    inflate the tightly-designed buttons/text (iOS default = 1.0).
              // 2) Distribute line leading EVENLY so SF Hebrew Rounded's tall
              //    metrics sit the same vertically on Android as on iOS — this is
              //    what made buttons look taller / mis-aligned on Android.
              return MediaQuery.withClampedTextScaling(
                minScaleFactor: 1.0,
                maxScaleFactor: 1.15,
                child: DefaultTextHeightBehavior(
                  textHeightBehavior: const TextHeightBehavior(
                    leadingDistribution: TextLeadingDistribution.even,
                  ),
                  child: Directionality(
                    textDirection:
                        provider.isRtl ? TextDirection.rtl : TextDirection.ltr,
                    // Tap anywhere outside a field to dismiss the keyboard — app-wide,
                    // so it works on every page. translucent → real buttons/fields
                    // still get their taps; only "empty" taps unfocus.
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                      child: IpadFrame(child: child ?? const SizedBox.shrink()),
                    ),
                  ),
                ),
              );
            },
            home: const _SessionLifecycleTracker(child: _StartupGate()),
          );
        },
      ),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      // SF Hebrew Rounded primary (Hebrew text + all Latin via SF Pro Rounded
      // weight instances); SF Pro Rounded for pure-Latin contexts; Rubik fallback.
      fontFamily: AppType.family,
      fontFamilyFallback: AppType.familyFallback,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
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
      // Make heading/title roles clearly extrabold so they stand out from the
      // lighter body/label text (kept at their default weights for contrast).
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontWeight: FontWeight.w900),
        headlineMedium: TextStyle(fontWeight: FontWeight.w800),
        headlineSmall: TextStyle(fontWeight: FontWeight.w800),
        titleLarge: TextStyle(fontWeight: FontWeight.w800),
        titleMedium: TextStyle(fontWeight: FontWeight.w700),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.primaryLight2,
        selectedColor: AppColors.primary,
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
        activeTrackColor: AppColors.primary,
        thumbColor: AppColors.primary,
        inactiveTrackColor: AppColors.mist,
        overlayColor: AppColors.primary.withValues(alpha: 0.13),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
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
        // White fields (with a subtle border so they stay visible on any surface).
        fillColor: Colors.white,
        hintStyle: const TextStyle(color: AppColors.textDisabled),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: AppColors.slate200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: AppColors.slate200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
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

/// Decides the first screen on launch so a returning, already-signed-in user
/// goes straight to [HomeScreen] instead of being sent back through onboarding/
/// login every time.
///
/// A user is considered "already in" when EITHER a non-anonymous Firebase user
/// is restored (real email/Google/Apple account) OR the provider re-hydrated an
/// active session with an explicitly chosen role (covers guest mode, which also
/// bypassed onboarding previously). We wait for the provider to finish its
/// async restore ([DatingProvider.isLoading]) before deciding, so there is no
/// flash of the wrong screen — a brief splash is shown while auth resolves.
class _StartupGate extends StatelessWidget {
  const _StartupGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        return Consumer<DatingProvider>(
          builder: (context, provider, _) {
            // Hold on the splash until both auth state and the persisted
            // session have resolved, to avoid showing onboarding for a beat
            // before bouncing a logged-in user to home.
            if (authSnapshot.connectionState == ConnectionState.waiting ||
                provider.isLoading) {
              return const _StartupSplash();
            }

            final user = authSnapshot.data;
            final hasRealAccount = user != null && !user.isAnonymous;
            final hasRestoredSession =
                provider.hasActiveSession && provider.roleExplicitlyChosen;

            if (hasRealAccount || hasRestoredSession) {
              // A returning user goes straight to the in-app experience, so we
              // are now "inside the app": let broker-black theming apply. Done
              // after this frame so we never call notifyListeners() mid-build.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                provider.markEnteredApp();
              });
              // The notification-broadcast admin (custom claim notifAdmin) is
              // routed to the console; everyone else lands on HomeScreen.
              return const _PostLoginRouter();
            }
            return const OnboardingScreen();
          },
        );
      },
    );
  }
}

/// Resolves the post-login destination for a returning, signed-in user:
/// the notification-admin (custom claim `notifAdmin`) gets the broadcast
/// console; everyone else gets [HomeScreen] and the first-launch notification
/// permission prompt. The admin claim read is async, so we hold the splash for
/// the brief moment it takes to resolve (fail-soft → HomeScreen).
class _PostLoginRouter extends StatefulWidget {
  const _PostLoginRouter();

  @override
  State<_PostLoginRouter> createState() => _PostLoginRouterState();
}

class _PostLoginRouterState extends State<_PostLoginRouter> {
  late final Future<bool> _isAdmin;

  @override
  void initState() {
    super.initState();
    _isAdmin = NotifAdminGate.isAdmin();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isAdmin,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _StartupSplash();
        }
        if (snapshot.data == true) {
          return const NotifConsoleScreen();
        }
        // Non-admin returning user: ask for notification permission once.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            NotificationPermissionService.maybeRequestOnFirstLaunch(context);
          }
        });
        return const HomeScreen();
      },
    );
  }
}

/// Minimal branded splash shown while startup auth/session state resolves.
class _StartupSplash extends StatelessWidget {
  const _StartupSplash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }
}

/// Transparent wrapper that emits one ambient [EventService.logSessionContext]
/// signal per session boundary (when the app is backgrounded or detached),
/// reusing the existing root tree. Fail-soft and renders [child] unchanged.
class _SessionLifecycleTracker extends StatefulWidget {
  const _SessionLifecycleTracker({required this.child});
  final Widget child;

  @override
  State<_SessionLifecycleTracker> createState() =>
      _SessionLifecycleTrackerState();
}

class _SessionLifecycleTrackerState extends State<_SessionLifecycleTracker>
    with WidgetsBindingObserver {
  final DateTime _sessionStart = DateTime.now();
  bool _emitted = false;

  DatingProvider? _provider;
  Timer? _widgetSyncDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Begin the rolling behavioural-insights window for this session; it
    // auto-flushes a `sessionInsights` summary periodically and on session end
    // (see _emitSessionContext). Fail-soft and self-contained.
    BehaviorInsights.instance.start();
    // Refresh the home-screen widget after relevant data changes (new match,
    // like, read state). Debounced so a burst of notifyListeners() coalesces
    // into a single widget write + network fetch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _provider = context.read<DatingProvider>();
      _provider?.addListener(_onProviderChanged);
      HomeWidgetService.sync(_provider!);
    });
  }

  void _onProviderChanged() {
    _widgetSyncDebounce?.cancel();
    _widgetSyncDebounce = Timer(const Duration(seconds: 2), () {
      final p = _provider;
      if (p != null) HomeWidgetService.sync(p);
    });
  }

  @override
  void dispose() {
    _widgetSyncDebounce?.cancel();
    _provider?.removeListener(_onProviderChanged);
    WidgetsBinding.instance.removeObserver(this);
    // Cancel the insights flush timer (and emit any final summary) on teardown.
    BehaviorInsights.instance.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _emitSessionContext();
      // Flush the final per-session behavioural summary as the app leaves the
      // foreground (stop() cancels the periodic timer and emits once).
      BehaviorInsights.instance.stop();
    } else if (state == AppLifecycleState.resumed) {
      // Refresh the home-screen widget's activity summary whenever the app
      // comes back to the foreground. Fail-soft inside the service.
      final provider = context.read<DatingProvider>();
      HomeWidgetService.sync(provider);
      // Re-pull matches: a landlord may have accepted a like (or a message may
      // have arrived) while we were backgrounded — otherwise the new conversation
      // wouldn't appear until a full relaunch.
      unawaited(provider.refreshMatchesFromBackend());
      // Re-attempt push registration on resume: on a fresh install the APNs
      // token often provisions only after the first foreground cycle, so this
      // catches devices that hadn't registered a token yet. Cheap + idempotent
      // (skips if the token is unchanged).
      if (FirebaseAuth.instance.currentUser != null) {
        unawaited(PushNotificationService.instance.registerForUser());
      }
      // Restart the insights window's periodic flush (stopped on pause).
      BehaviorInsights.instance.start();
    }
  }

  String _timeOfDayBucket(int hour) {
    if (hour < 6) return 'night';
    if (hour < 12) return 'morning';
    if (hour < 18) return 'afternoon';
    return 'evening';
  }

  void _emitSessionContext() {
    if (_emitted) return;
    _emitted = true;
    try {
      final now = DateTime.now();
      final locale =
          WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag();
      AppEvents.instance.service.logSessionContext(
        timeOfDayBucket: _timeOfDayBucket(now.hour),
        dayOfWeek: now.weekday, // 1 = Monday … 7 = Sunday
        sessionDurationMs: now.difference(_sessionStart).inMilliseconds,
        platform: defaultTargetPlatform.name,
        appVersion: '1.0.0+110',
        locale: locale,
      );
    } catch (_) {/* fail-soft */}
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
