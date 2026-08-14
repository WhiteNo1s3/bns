import Flutter
import UIKit
import Speech

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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppleFileStt") {
      AppleFileStt.register(messenger: registrar.messenger())
    }
  }
}

enum AppleFileStt {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "bns/apple_stt", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "transcribeFile" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any]
      let path = args?["path"] as? String ?? ""
      let locale = args?["locale"] as? String ?? "he-IL"
      transcribe(path: path, locale: locale, result: result)
    }
  }

  private static func transcribe(path: String, locale: String, result: @escaping FlutterResult) {
    SFSpeechRecognizer.requestAuthorization { status in
      guard status == .authorized else {
        DispatchQueue.main.async { result("") }
        return
      }
      guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)),
            recognizer.isAvailable else {
        DispatchQueue.main.async { result("") }
        return
      }
      let request = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: path))
      request.shouldReportPartialResults = false
      request.requiresOnDeviceRecognition = true
      recognizer.recognitionTask(with: request) { rec, error in
        if error != nil {
          DispatchQueue.main.async { result("") }
          return
        }
        guard let rec, rec.isFinal else { return }
        DispatchQueue.main.async { result(rec.bestTranscription.formattedString) }
      }
    }
  }
}
