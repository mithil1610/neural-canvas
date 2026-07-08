import UIKit
import receive_sharing_intent

class ShareViewController: RSIShareViewController {
    // Automatically redirect data streams straight into the host application
    override func shouldAutoRedirect() -> Bool {
        return true
    }
}
