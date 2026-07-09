import UIKit
import Flutter

class SceneDelegate: FlutterSceneDelegate {
    
    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        // Natively hands off the initial window scene configuration and cold-boot deep links to Flutter
        super.scene(scene, willConnectTo: session, options: connectionOptions)
    }

    override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        // Natively forwards warm-boot background deep links directly into the Flutter engine stream
        super.scene(scene, openURLContexts: URLContexts)
    }
}