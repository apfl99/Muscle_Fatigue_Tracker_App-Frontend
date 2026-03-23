import Flutter
import GoogleMobileAds
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var registeredPluginRegistryIDs = Set<ObjectIdentifier>()

  private func registerPluginsIfNeeded(with registry: FlutterPluginRegistry) {
    let registryID = ObjectIdentifier(registry as AnyObject)
    if registeredPluginRegistryIDs.contains(registryID) {
      return
    }
    registeredPluginRegistryIDs.insert(registryID)
    if registry.hasPlugin("AppLinksIosPlugin") {
      return
    }
    GeneratedPluginRegistrant.register(with: registry)
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    registerPluginsIfNeeded(with: self)
    GADMobileAds.sharedInstance().start(completionHandler: nil)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    registerPluginsIfNeeded(with: engineBridge.pluginRegistry)
  }
}
