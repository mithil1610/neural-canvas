import UIKit
import Social
import receive_sharing_intent

class ShareViewController: RSIShareViewController {
    
    override func shouldAutoRedirect() -> Bool {
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // FORCED PROGRAMMATIC OVERRIDE:
        // Bypasses the property sheet lookups to prevent the plugin from falling back 
        // to a mismatched group identifier during headless cloud compilation.
        self.appGroupId = "group.com.mithil.axiom"
    }
}