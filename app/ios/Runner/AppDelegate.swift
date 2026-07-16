import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var clubImageConverterChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "ClubImageConverter"
    ) else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "kr.allround.app/club-image-converter",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "convertHeicToJpeg" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let path = arguments["path"] as? String,
        let image = UIImage(contentsOfFile: path)
      else {
        result(
          FlutterError(
            code: "invalid_image",
            message: "The selected image could not be decoded.",
            details: nil
          )
        )
        return
      }

      let quality = (arguments["quality"] as? NSNumber)?.doubleValue ?? 0.86
      guard let data = image.jpegData(compressionQuality: quality) else {
        result(
          FlutterError(
            code: "conversion_failed",
            message: "The selected image could not be converted to JPEG.",
            details: nil
          )
        )
        return
      }
      result(FlutterStandardTypedData(bytes: data))
    }
    clubImageConverterChannel = channel
  }
}
