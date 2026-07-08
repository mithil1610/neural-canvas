import UIKit
import Social
import receive_sharing_intent

class ShareViewController: RSIShareViewController {
    // Set to true to automatically skip the iOS compose window 
    // and route the image directly into your Flutter application layout.
    override func shouldAutoRedirect() -> Bool {
        return true
    }
}