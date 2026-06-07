import Flutter
import UIKit

// NSDK (Scaniverse) is not linked in the current build.
// All methods return stub data so the app compiles and runs without the framework.

@objc class ScaniversePlugin: NSObject, FlutterPlugin {

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.rentch.scaniverse",
            binaryMessenger: registrar.messenger()
        )
        let instance = ScaniversePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "ping":
            result(["status": "ok", "sdk": "NSDK (not linked)", "sdkReady": false])
        case "listScans":
            result(["scans": [] as [Any], "sdkReady": false])
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
