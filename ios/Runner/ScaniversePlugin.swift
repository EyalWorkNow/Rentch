import Flutter
import UIKit
import NSDK

// ─── Flutter ↔ NSDK Method Channel ───────────────────────────────────────────
// Channel: com.rentch.scaniverse
// NSDK Sites API flow:
//   NSDKSession(accessToken:)         — init with JWT bearer token
//   .acquireSitesSession()            — get NSDKSitesSession
//   .requestSelfOrganizationInfo()    → OrganizationResult (.organizations[0].id)
//   .requestSitesForOrganization(orgId:) → SiteResult (.sites)
//   .requestAssetsForSite(siteId:)    → AssetResult (.assets where type == .splat/.mesh)

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
            result(["status": "ok", "sdk": "NSDK \(NSDKSession.version())", "sdkReady": true])

        case "listScans":
            let args = call.arguments as? [String: Any]
            let token = args?["token"] as? String ?? ""
            guard !token.isEmpty else {
                result(FlutterError(code: "NO_TOKEN",
                    message: "Bearer token is required", details: nil))
                return
            }
            Task { await self.fetchScans(token: token, flutterResult: result) }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - NSDK Sites API

    @MainActor
    private func createSessionAndSites(token: String) -> (NSDKSession, NSDKSitesSession) {
        let session = NSDKSession(accessToken: token, useLidar: false)
        let sites = session.acquireSitesSession()
        return (session, sites)
    }

    private func fetchScans(token: String, flutterResult: @escaping FlutterResult) async {
        do {
            // 1. Create session + Sites session on MainActor (NSDK requirement)
            let (_, sites) = await MainActor.run { createSessionAndSites(token: token) }

            // 3. Get organization for the service account
            let orgResult = try await sites.requestSelfOrganizationInfo()
            guard let org = orgResult.organizations.first else {
                flutterResult(["scans": [], "sdkReady": true])
                return
            }

            // 4. Get all Sites for the organization
            let siteResult = try await sites.requestSitesForOrganization(orgId: org.id)

            // 5. For each Site, collect its Assets (3D scans)
            var scans: [[String: Any]] = []
            for site in siteResult.sites {
                let assetResult = try await sites.requestAssetsForSite(siteId: site.id)
                for asset in assetResult.assets {
                    switch asset.assetType {
                    case AssetType.splat, AssetType.mesh:
                        scans.append(buildScanMap(asset: asset, site: site))
                    default:
                        break
                    }
                }
            }

            flutterResult(["scans": scans, "sdkReady": true])

        } catch {
            flutterResult(FlutterError(
                code: "NSDK_ERROR",
                message: error.localizedDescription,
                details: nil
            ))
        }
    }

    // MARK: - Map asset → Flutter dictionary

    private func buildScanMap(asset: AssetInfo, site: SiteInfo) -> [String: Any] {
        let status: String = {
            switch asset.pipelineJobStatus {
            case AssetPipelineJobStatus.succeeded, AssetPipelineJobStatus.ready:
                return "complete"
            case AssetPipelineJobStatus.failed:
                return "failed"
            case AssetPipelineJobStatus.running, AssetPipelineJobStatus.pending:
                return "processing"
            default:
                return "processing"
            }
        }()

        let viewerUrl: String = {
            if let splatData = asset.splatData, !splatData.rootNodeId.isEmpty {
                return "https://scaniverse.nianticspatial.com/scan/\(splatData.rootNodeId)"
            }
            return "https://portal-web.nianticspatial.com/sites/\(site.id)/assets/\(asset.id)"
        }()

        let assetTypeStr = asset.assetType == AssetType.splat ? "splat" : "mesh"

        return [
            "id":           asset.id,
            "title":        asset.name.isEmpty ? site.name : asset.name,
            "status":       status,
            "siteId":       site.id,
            "siteName":     site.name,
            "viewerUrl":    viewerUrl,
            "assetType":    assetTypeStr,
            "thumbnailUrl": "",
        ]
    }
}
