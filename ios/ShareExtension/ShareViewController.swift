import UIKit
import Social
import MobileCoreServices
import Photos

class ShareViewController: SLComposeServiceViewController {
    
    // The App Group container ID mapped to your Apple Developer Account
    let hostAppBundleIdentifier = "com.mithil.neuralcanvas"
    let sharedAppGroupIdentifier = "group.com.mithil.axiom"
    
    override func isContentValid() -> Bool {
        return true
    }

    override func didSelectPost() {
        // Intercept incoming share items cleanly
        guard let extensionContext = extensionContext,
              let item = extensionContext.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else {
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            return
        }
        
        let imageType = kUTTypeImage as String
        let fileType = kUTTypeFileURL as String
        var sharedMedia: [String] = []
        let group = DispatchGroup()
        
        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(imageType) {
                group.enter()
                provider.loadItem(forTypeIdentifier: imageType, options: nil) { [weak self] (item, error) in
                    defer { group.leave() }
                    if let url = item as? URL {
                        sharedMedia.append(url.absoluteString)
                    } else if let image = item as? UIImage, let url = self?.saveImageToSharedContainer(image) {
                        sharedMedia.append(url.absoluteString)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(fileType) {
                group.enter()
                provider.loadItem(forTypeIdentifier: fileType, options: nil) { (item, error) in
                    defer { group.leave() }
                    if let url = item as? URL {
                        sharedMedia.append(url.absoluteString)
                    }
                }
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            // Write to the shared user defaults suite so receive_sharing_intent can find it on launch
            if let userDefaults = UserDefaults(suiteName: self.sharedAppGroupIdentifier) {
                userDefaults.set(sharedMedia, forKey: "sharing_intent_items")
                userDefaults.synchronize()
            }
            
            // Wake up the main Axiom application shell container
            var responder: UIResponder? = self
            while responder != nil {
                if let application = responder as? UIApplication {
                    let url = URL(string: "axiom://")!
                    application.perform(NSSelectorFromString("openURL:"), with: url)
                    break
                }
                responder = responder?.next
            }
            
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
    
    private func saveImageToSharedContainer(_ image: UIImage) -> URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedAppGroupIdentifier) else { return nil }
        let fileName = "shared_img_\(Date().timeIntervalSince1970).jpg"
        let fileURL = container.appendingPathComponent(fileName)
        guard let data = image.jpegData(compressionQuality: 0.75) else { return nil }
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }
}
