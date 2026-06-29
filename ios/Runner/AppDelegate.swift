import Flutter
import UIKit
import UserNotifications

// This project uses the Flutter UIScene lifecycle (Info.plist →
// FlutterSceneDelegate). Plugins MUST be registered through the implicit-engine
// bridge in didInitializeImplicitFlutterEngine — NOT via
// GeneratedPluginRegistrant.register(with: self) in didFinishLaunching, which is
// the classic (non-scene) pattern and crashes on launch under the scene lifecycle.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Push notifications (APNs / Firebase Cloud Messaging).
    // Do NOT call FirebaseApp.configure() here — the firebase_core Flutter
    // plugin already configures the default app from GoogleService-Info.plist.
    // With FirebaseAppDelegateProxyEnabled = true (the default), firebase_messaging
    // swizzles the APNs callbacks and forwards the device token to FCM automatically.
    // We just make foreground-presentation + registration robust here.
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Safe registration — never force-unwrap the registrar.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ScaniversePlugin") {
      ScaniversePlugin.register(with: registrar)
    }
    // RoomPlan (Tier-1 LiDAR scan): to activate, add RoomPlanChannel.swift to the
    // Runner target in Xcode, then restore the two lines below. Kept un-wired so
    // the build stays green until tested on a LiDAR device.
    // if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RoomPlanChannel") {
    //   RoomPlanChannel.register(with: registrar)
    // }
  }
}
