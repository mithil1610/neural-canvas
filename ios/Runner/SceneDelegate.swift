import UIKit
import Flutter

class SceneDelegate: FlutterSceneDelegate {
    
    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        // Forward the initial launch context to the native Flutter scene delegate pipeline
        super.scene(scene, willConnectTo: session, options: connectionOptions)
    }

    override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        // Forward the warm-boot background context to the native Flutter scene delegate pipeline
        super.scene(scene, openURLContexts: URLContexts)
    }
}
