import Flutter
import UIKit

// RoomPlan (Apple) native room-scan bridge for the Flutter app.
//
// RoomPlan is a Tier-1, LiDAR-only capability (iPhone Pro / iPad Pro on iOS 16+).
// On every other device the framework is unavailable, so EVERYTHING that touches
// a RoomPlan symbol is guarded behind `#available(iOS 16.0, *)` AND the runtime
// `RoomCaptureSession.isSupported` check. The app must keep building and running
// on older iOS and non-LiDAR hardware — `isSupported` simply returns false there.
//
// Channel: "rently/roomplan"
//   isSupported -> Bool   (LiDAR + iOS 16 capability check)
//   startScan   -> String (path to exported .usdz) | nil (user cancelled)
//                  | FlutterError (capture/export failure)
//
// `RoomPlan` is imported lazily inside the `@available` types below so the module
// is only referenced on SDKs/devices that ship it.

@objc class RoomPlanChannel: NSObject, FlutterPlugin {

    static let channelName = "rently/roomplan"

    // Holds the in-flight scan controller so we keep a strong reference while the
    // modal capture session is on screen, and so we reject overlapping scans.
    private var activeScan: AnyObject?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = RoomPlanChannel()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isSupported":
            result(Self.roomPlanSupported())
        case "startScan":
            startScan(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Capability

    /// True only on iOS 16+ devices whose hardware supports a RoomPlan capture
    /// session (i.e. LiDAR-equipped). Safe to call on any device / OS.
    static func roomPlanSupported() -> Bool {
        if #available(iOS 16.0, *) {
            return RoomPlanScanController.isSupported
        }
        return false
    }

    // MARK: - Scan

    private func startScan(result: @escaping FlutterResult) {
        guard Self.roomPlanSupported() else {
            result(FlutterError(
                code: "unsupported",
                message: "RoomPlan requires a LiDAR-equipped device running iOS 16 or later.",
                details: nil
            ))
            return
        }

        guard activeScan == nil else {
            result(FlutterError(
                code: "scan_busy",
                message: "A room scan is already in progress.",
                details: nil
            ))
            return
        }

        guard let presenter = topViewController() else {
            result(FlutterError(
                code: "no_presenter",
                message: "Could not find a view controller to present the scanner.",
                details: nil
            ))
            return
        }

        if #available(iOS 16.0, *) {
            let controller = RoomPlanScanController { [weak self] outcome in
                // Drop our strong reference once the flow finishes.
                self?.activeScan = nil
                switch outcome {
                case .success(let usdzPath):
                    result(usdzPath)
                case .cancelled:
                    result(nil)
                case .failure(let code, let message):
                    result(FlutterError(code: code, message: message, details: nil))
                }
            }
            activeScan = controller
            controller.present(over: presenter)
        } else {
            // Unreachable: roomPlanSupported() already gated on iOS 16.
            result(FlutterError(
                code: "unsupported",
                message: "RoomPlan requires iOS 16 or later.",
                details: nil
            ))
        }
    }

    // MARK: - Helpers

    /// Walks the active scene's view-controller stack to find the front-most
    /// controller we can safely present the modal capture session over.
    private func topViewController(
        base: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: \.isKeyWindow)?
            .rootViewController
    ) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}

// MARK: - RoomPlan capture controller (iOS 16+ only)

import RoomPlan

/// Result of a guided RoomPlan capture, reported back to the channel.
@available(iOS 16.0, *)
private enum RoomScanOutcome {
    case success(usdzPath: String)
    case cancelled
    case failure(code: String, message: String)
}

/// Hosts a `RoomCaptureView`, runs the guided capture session, and on a clean
/// finish exports the resulting `CapturedRoom` to a USDZ file in the app's temp
/// directory. Presented modally over the Flutter view controller.
///
/// Lifecycle: created by `RoomPlanChannel`, which keeps a strong reference until
/// `completion` fires exactly once (success / cancel / failure).
@available(iOS 16.0, *)
private final class RoomPlanScanController: NSObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {

    /// Exposes the framework's hardware capability check at the type level so the
    /// channel can stay free of any direct RoomPlan reference outside this block.
    static var isSupported: Bool { RoomCaptureSession.isSupported }

    private let completion: (RoomScanOutcome) -> Void
    private var didComplete = false

    // Built lazily so no RoomPlan UIKit object is constructed unless we actually scan.
    private var hostController: UIViewController?
    private var captureView: RoomCaptureView?

    /// The processed room handed to us by the view delegate; held until the user
    /// taps "Done" so we export the finished result rather than a partial one.
    private var processedRoom: CapturedRoom?
    private var processingError: Error?

    init(completion: @escaping (RoomScanOutcome) -> Void) {
        self.completion = completion
        super.init()
    }

    // MARK: Presentation

    func present(over presenter: UIViewController) {
        let host = UIViewController()
        host.modalPresentationStyle = .fullScreen

        let view = RoomCaptureView(frame: host.view.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.delegate = self
        view.captureSession.delegate = self
        host.view.addSubview(view)

        // "Done" finishes the guided capture; "Cancel" aborts it.
        let bar = UINavigationBar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        let item = UINavigationItem(title: "סריקת חדר")
        item.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(doneTapped)
        )
        item.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped)
        )
        bar.items = [item]
        host.view.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
        ])

        self.hostController = host
        self.captureView = view

        presenter.present(host, animated: true) { [weak self] in
            // Begin the guided capture once the modal is on screen.
            self?.captureView?.captureSession.run(configuration: RoomCaptureSession.Configuration())
        }
    }

    // MARK: Toolbar actions

    @objc private func doneTapped() {
        // Stop the session; the view delegate then post-processes into a CapturedRoom.
        captureView?.captureSession.stop()
    }

    @objc private func cancelTapped() {
        captureView?.captureSession.stop()
        finish(.cancelled)
    }

    // MARK: RoomCaptureViewDelegate

    /// Return `true` to let RoomCaptureView post-process the raw scan into a
    /// final `CapturedRoom` (delivered to `didPresent:` below).
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        if let error { processingError = error }
        return error == nil
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        if let error {
            processingError = error
            finish(.failure(code: "process_failed", message: error.localizedDescription))
            return
        }
        processedRoom = processedResult
        exportAndFinish(processedResult)
    }

    // MARK: Export

    private func exportAndFinish(_ room: CapturedRoom) {
        do {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("roomplan-scans", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let url = dir.appendingPathComponent("room_\(UUID().uuidString).usdz")
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }

            // `.parametric` exports the clean, reconstructed room geometry as USDZ.
            try room.export(to: url, exportOptions: .parametric)
            finish(.success(usdzPath: url.path))
        } catch {
            finish(.failure(code: "export_failed", message: error.localizedDescription))
        }
    }

    // MARK: Completion / teardown

    /// Fires `completion` at most once and dismisses the modal.
    private func finish(_ outcome: RoomScanOutcome) {
        guard !didComplete else { return }
        didComplete = true

        let deliver = { [completion] in completion(outcome) }
        if let host = hostController, host.presentingViewController != nil {
            host.dismiss(animated: true) { deliver() }
        } else {
            deliver()
        }
        hostController = nil
        captureView = nil
    }

    // MARK: RoomCaptureSessionDelegate

    /// Called if the underlying ARSession fails outright (e.g. tracking lost in a
    /// way that cannot recover). Only treat it as a hard failure if we haven't
    /// already produced a room.
    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        if let error, processedRoom == nil, processingError == nil {
            finish(.failure(code: "session_failed", message: error.localizedDescription))
        }
    }
}
