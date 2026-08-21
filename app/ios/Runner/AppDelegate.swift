import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  let flutterEngine = FlutterEngine(
    name: "allround_engine",
    project: nil,
    allowHeadlessExecution: true
  )
  private var clubImageConverterChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    guard flutterEngine.run() else {
      return false
    }
    GeneratedPluginRegistrant.register(with: flutterEngine)
    configureClubImageConverter(with: flutterEngine)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func configureClubImageConverter(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(
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
      let maxSide = (arguments["maxSide"] as? NSNumber)?.doubleValue ?? 1600
      let resized = Self.downscaled(image, maxSide: maxSide)
      guard let data = resized.jpegData(compressionQuality: quality) else {
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

  /// HEIC 원본은 4800만 화소까지 오고, 다른 경로(ImagePicker)는 이미 1600px 로 줄어든
  /// 뒤에 넘어온다. 여기서 줄이지 않으면 Dart 쪽 디코딩이 수백 MB 를 잡아 앱이 꺼진다.
  private static func downscaled(_ image: UIImage, maxSide: Double) -> UIImage {
    let longest = max(image.size.width, image.size.height)
    guard maxSide > 0, longest > CGFloat(maxSide) else { return image }

    let scale = CGFloat(maxSide) / longest
    let target = CGSize(
      width: (image.size.width * scale).rounded(),
      height: (image.size.height * scale).rounded()
    )
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    return UIGraphicsImageRenderer(size: target, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: target))
    }
  }
}
