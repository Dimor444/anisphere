import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // A language picked in the app is written to the app's own
    // AppleLanguages — the value Settings › AniSphere › Language reads and
    // writes — so the picker and Settings are one setting. iOS applies it
    // from the next launch; the app has already switched.
    let language = FlutterMethodChannel(
      name: "anisphere/app_language",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    language.setMethodCallHandler { call, result in
      guard call.method == "set", let code = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      UserDefaults.standard.set([code], forKey: "AppleLanguages")
      result(nil)
    }
  }
}
