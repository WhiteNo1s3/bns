import Cocoa
import FlutterMacOS
import Speech

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    AppleFileStt.register(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

/// On-device file transcription. The one mic records; this writes the words.
/// Never sends the voice off the Mac.
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
      // On-device only. The voice never leaves this Mac.
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
