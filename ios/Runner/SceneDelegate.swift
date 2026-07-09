import UIKit
import Flutter

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let _ = (scene as? UIWindowScene) else { return }
        
        // Handle cold boot deep link from the share extension
        if let urlContext = connectionOptions.urlContexts.first {
            let _ = (UIApplication.shared.delegate as? FlutterAppDelegate)?.application(
                UIApplication.shared,
                open: urlContext.url,
                options: [:]
            )
        }
    }

    // Handle background wakeup deep link from the share extension
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let urlContext = URLContexts.first else { return }
        let _ = (UIApplication.shared.delegate as? FlutterAppDelegate)?.application(
            UIApplication.shared,
            open: urlContext.url,
            options: [:]
        )
    }
}
