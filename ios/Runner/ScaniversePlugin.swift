import Flutter
import UIKit
import UniformTypeIdentifiers

// NSDK (Scaniverse) is not linked in the current build.
// All methods return stub data so the app compiles and runs without the framework.

@objc class ScaniversePlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate {

    private var pendingPickResult: FlutterResult?

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
            result([
                "status": "ok",
                "sdk": "NSDK (not linked)",
                "sdkReady": false,
                "importReady": true
            ])
        case "listScans":
            result(["scans": [] as [Any], "sdkReady": false])
        case "pick3dAssets":
            presentAssetPicker(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func presentAssetPicker(result: @escaping FlutterResult) {
        guard pendingPickResult == nil else {
            result(
                FlutterError(
                    code: "picker_busy",
                    message: "3D asset picker is already active.",
                    details: nil
                )
            )
            return
        }

        guard let presenter = topViewController() else {
            result(
                FlutterError(
                    code: "no_presenter",
                    message: "Could not find a view controller to present the picker.",
                    details: nil
                )
            )
            return
        }

        pendingPickResult = result
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: supportedContentTypes(),
            asCopy: true
        )
        picker.delegate = self
        picker.allowsMultipleSelection = true
        presenter.present(picker, animated: true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pendingPickResult?([] as [Any])
        pendingPickResult = nil
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        let picked = urls.compactMap(copyAssetMetadata)
        pendingPickResult?(picked)
        pendingPickResult = nil
    }

    private func copyAssetMetadata(from url: URL) -> [String: Any]? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scaniverse-imports", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )

        let destination = tempDir.appendingPathComponent(
            "\(UUID().uuidString)_\(url.lastPathComponent)"
        )

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            let values = try destination.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
            let ext = destination.pathExtension.lowercased()
            let contentType = values.contentType?.preferredMIMEType ?? mimeType(forExtension: ext)
            return [
                "path": destination.path,
                "fileName": url.lastPathComponent,
                "kind": kind(forExtension: ext),
                "contentType": contentType,
                "sizeBytes": values.fileSize ?? 0
            ]
        } catch {
            return nil
        }
    }

    private func supportedContentTypes() -> [UTType] {
        let extensions = [
            "glb", "gltf", "obj", "mtl", "usdz", "spz", "ply", "sog",
            "bin", "png", "jpg", "jpeg", "webp", "ktx2"
        ]
        let types = extensions.compactMap { UTType(filenameExtension: $0) }
        return types.isEmpty ? [.item] : types
    }

    private func kind(forExtension ext: String) -> String {
        switch ext {
        case "glb", "gltf":
            return "glb"
        case "obj":
            return "obj"
        case "mtl":
            return "mtl"
        case "usdz":
            return "usdz"
        case "spz":
            return "spz"
        case "ply":
            return "ply"
        case "sog":
            return "sog"
        case "png", "jpg", "jpeg", "webp", "ktx2":
            return "texture"
        case "bin":
            return "buffer"
        default:
            return ext.isEmpty ? "asset" : ext
        }
    }

    private func mimeType(forExtension ext: String) -> String {
        switch ext {
        case "glb":
            return "model/gltf-binary"
        case "gltf":
            return "model/gltf+json"
        case "usdz":
            return "model/vnd.usdz+zip"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "webp":
            return "image/webp"
        case "obj", "mtl":
            return "text/plain"
        default:
            return "application/octet-stream"
        }
    }

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
