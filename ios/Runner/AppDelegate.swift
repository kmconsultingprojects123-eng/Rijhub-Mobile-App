import UIKit
import Flutter
import GoogleSignIn
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Create a FlutterEngine early and register plugins on it. This ensures plugin
  // registration runs before any platform views (like Google Maps) are created,
  // preventing 'unregistered_view_type' errors.
  lazy var flutterEngine: FlutterEngine = {
    let engine = FlutterEngine(name: "shared_engine")
    engine.run()
    // Register generated plugins with this engine
    GeneratedPluginRegistrant.register(with: engine)
    return engine
  }()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Provide Google Maps API key for iOS native SDK
    GMSServices.provideAPIKey("AIzaSyAjdDayJe-TVV8Cz6a-kHFCoJm6oNgeix8")

    // Ensure the engine is instantiated and plugins registered early
    _ = flutterEngine

    // Configure GoogleSignIn client ID if present in Info.plist
    if let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String {
      GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // iOS 9+ open url handler
  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    // Let Google Sign-In SDK attempt to handle the URL first
    if GIDSignIn.sharedInstance.handle(url) {
      return true
    }
    return super.application(app, open: url, options: options)
  }

  // If the project uses scenes (iOS 13+), also handle incoming URLs here.
  override func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
    if let url = userActivity.webpageURL {
      if GIDSignIn.sharedInstance.handle(url) {
        return true
      }
    }
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }
}
