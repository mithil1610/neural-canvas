import UIKit
import Flutter
import receive_sharing_intent

class SceneDelegate: FlutterSceneDelegate {
    
    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        // CRITICAL INJECTION: Intercept cold-boot URL intents from the ShareExtension
        _ = ReceiveSharingIntentPlugin.instance.scene(scene, willConnectTo: session, options: connectionOptions)
        super.scene(scene, willConnectTo: session, options: connectionOptions)
    }

    override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        // CRITICAL INJECTION: Intercept warm-boot background events from the ShareExtension
        if ReceiveSharingIntentPlugin.instance.scene(scene, openURLContexts: URLContexts) {
            return
        }
        super.scene(scene, openURLContexts: URLContexts)
    }
}
