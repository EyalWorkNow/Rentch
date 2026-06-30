import UserNotifications

// Rich (Duolingo-style) lock-screen notifications.
//
// The backend sends pushes with apns.payload.aps.mutable-content = 1 and an image
// URL. We resolve the image URL from any of:
//   - fcm_options.image                (FCM "image" — surfaced into the payload)
//   - aps.image / "image" / "media-url" (custom keys, best-effort)
// download it, and attach it so the system shows the big image.
class NotificationService: UNNotificationServiceExtension {

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        let mutable = (request.content.mutableCopy() as? UNMutableNotificationContent)
        self.bestAttempt = mutable

        guard let bestAttempt = mutable,
              let urlString = imageURLString(from: request.content.userInfo),
              let url = URL(string: urlString) else {
            contentHandler(mutable ?? request.content)
            return
        }

        downloadImage(from: url) { localURL in
            if let localURL = localURL,
               let attachment = try? UNNotificationAttachment(identifier: "rently-image", url: localURL, options: nil) {
                bestAttempt.attachments = [attachment]
            }
            contentHandler(bestAttempt)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // System is about to kill us: deliver whatever we have.
        if let contentHandler = contentHandler, let bestAttempt = bestAttempt {
            contentHandler(bestAttempt)
        }
    }

    // MARK: - Helpers

    private func imageURLString(from userInfo: [AnyHashable: Any]) -> String? {
        // FCM surfaces fcm_options.image as the top-level "fcm_options" dict.
        if let fcm = userInfo["fcm_options"] as? [AnyHashable: Any],
           let image = fcm["image"] as? String, !image.isEmpty {
            return image
        }
        // Common custom fallbacks.
        for key in ["image", "media-url", "imageURL", "image_url"] {
            if let value = userInfo[key] as? String, !value.isEmpty {
                return value
            }
        }
        if let aps = userInfo["aps"] as? [AnyHashable: Any],
           let image = aps["image"] as? String, !image.isEmpty {
            return image
        }
        return nil
    }

    private func downloadImage(from url: URL, completion: @escaping (URL?) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { tempURL, response, _ in
            guard let tempURL = tempURL else {
                completion(nil)
                return
            }
            // Move to a uniquely-named file, preserving a sensible extension so
            // the system can infer the media type.
            let ext = self.fileExtension(for: url, response: response)
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            do {
                try FileManager.default.moveItem(at: tempURL, to: destination)
                completion(destination)
            } catch {
                completion(nil)
            }
        }
        task.resume()
    }

    private func fileExtension(for url: URL, response: URLResponse?) -> String {
        let pathExt = url.pathExtension
        if !pathExt.isEmpty { return pathExt }
        switch response?.mimeType {
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/jpeg": return "jpg"
        default: return "jpg"
        }
    }
}
