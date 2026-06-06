import Flutter
import UIKit
// NSDK import — requires adding SPM package in Xcode:
// File → Add Package Dependencies → https://github.com/nianticspatial/nsdk-library-xcframework
// #if canImport(NSDK)
// import NSDK
// #endif

// ─── Flutter ↔ Native Method Channel ──────────────────────────────────────────
// Channel: com.rentch.scaniverse
// Methods:
//   listScans(token: String) → { scans: [ScanMap] }
//   ping()                  → { status: "ok" }

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
            result(["status": "ok", "sdk": "nsdk-xcframework"])

        case "listScans":
            let args = call.arguments as? [String: Any]
            let token = args?["token"] as? String ?? ""
            guard !token.isEmpty else {
                result(FlutterError(code: "NO_TOKEN",
                    message: "Bearer token is required", details: nil))
                return
            }
            // Run async SDK calls off the main thread
            Task {
                await self.fetchScans(token: token, flutterResult: result)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - NSDK Sites API

    private func fetchScans(token: String, flutterResult: @escaping FlutterResult) async {
        // ── NSDK is enabled when the package is added in Xcode ────────────────
        // Uncomment the block below after adding the SPM dependency.
        // Until then this stub returns an empty list so Flutter compiles cleanly.

        /*
        do {
            // 1. Initialize session with bearer token
            let userConfig = NSDKSession.UserConfig(
                accessToken: token,
                refreshToken: nil,
                featureFlagFilePath: nil
            )
            let config = NSDKSession.Configuration(userConfig: userConfig)
            let session = NSDKSession(configuration: config)
            defer { session.destroy() }

            // 2. Acquire Sites session
            let sites = session.acquireSitesSession()
            defer { sites.destroy() }

            // 3. Get the service account's organization
            let orgInfo = try await sites.requestSelfOrganizationInfo()

            // 4. Get all Sites for the organization
            let sitesResult = try await sites.requestSitesForOrganization(
                organizationId: orgInfo.id
            )

            // 5. For each site, get its Assets (3D scans)
            var scans: [[String: Any]] = []
            for site in sitesResult.sites {
                let assetsResult = try await sites.requestAssetsForSite(
                    siteId: site.id
                )
                for asset in assetsResult.assets {
                    // Only include 3D scan assets (splat / mesh)
                    guard asset.assetType == .splat || asset.assetType == .mesh else {
                        continue
                    }
                    scans.append(buildScanMap(asset: asset, site: site))
                }
            }

            flutterResult(["scans": scans])

        } catch {
            flutterResult(FlutterError(
                code: "NSDK_ERROR",
                message: error.localizedDescription,
                details: nil
            ))
        }
        */

        // ── STUB — replace with the block above after adding NSDK package ──
        flutterResult(["scans": [], "sdkReady": false,
            "hint": "Add NSDK SPM package in Xcode, then uncomment fetchScans body"])
    }

    // MARK: - Helpers

    /* Enable after adding NSDK package:

    private func buildScanMap(asset: AssetInfo, site: SiteInfo) -> [String: Any] {
        let status: String = {
            switch asset.pipelineJobStatus {
            case .succeeded, .ready:  return "complete"
            case .failed:             return "failed"
            case .running, .pending:  return "processing"
            default:                  return "processing"
            }
        }()

        let viewerUrl: String = {
            // Splat scans: direct Scaniverse viewer
            if let splatData = asset.splatData, !splatData.rootNodeId.isEmpty {
                return "https://scaniverse.nianticspatial.com/scan/\(splatData.rootNodeId)"
            }
            // Mesh / fallback: portal web
            return "https://portal-web.nianticspatial.com/sites/\(site.id)/assets/\(asset.id)"
        }()

        return [
            "id":            asset.id,
            "title":         asset.name.isEmpty ? site.name : asset.name,
            "status":        status,
            "siteId":        site.id,
            "siteName":      site.name,
            "viewerUrl":     viewerUrl,
            "assetType":     asset.assetType == .splat ? "splat" : "mesh",
            "thumbnailUrl":  "",   // populate if NSDK exposes thumbnail
        ]
    }
    */
}
