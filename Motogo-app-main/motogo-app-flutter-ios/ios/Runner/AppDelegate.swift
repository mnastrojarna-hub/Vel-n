import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    // firebase_messaging řeší APNs registraci i forwarding tokenů přes
    // FirebaseAppDelegateProxyEnabled (default YES) — žádný další kód není třeba.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }
    registerTrayNotificationsChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Dart `PushService.clearDelivered()` — otevření appky = zákazník upozornění
  /// viděl: smazat doručená oznámení z Centra oznámení a vynulovat odznak na
  /// ikoně (send-push ho nastavuje na 1 a nic jiného ho nemazalo).
  /// Pozn.: registrar(forPlugin:) bere messenger z hlavního FlutterViewController
  /// (storyboard) stejně jako GeneratedPluginRegistrant — při přechodu na UIScene
  /// přesunout do didInitializeImplicitFlutterEngine.
  private func registerTrayNotificationsChannel() {
    guard let registrar = self.registrar(forPlugin: "MotoGoTrayNotifications") else { return }
    let channel = FlutterMethodChannel(name: "cz.motogo24/notifications",
                                       binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "clearAll" else {
        result(FlutterMethodNotImplemented)
        return
      }
      UNUserNotificationCenter.current().removeAllDeliveredNotifications()
      if #available(iOS 16.0, *) {
        UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
      } else {
        UIApplication.shared.applicationIconBadgeNumber = 0
      }
      result(nil)
    }
  }
}
