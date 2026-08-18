import Foundation
import Vision
import AppKit

guard CommandLine.arguments.count > 1 else { fputs("need path\n", stderr); exit(2) }
let path = CommandLine.arguments[1]
guard let img = NSImage(contentsOfFile: path),
      let tiff = img.tiffRepresentation,
      let ci = CIImage(data: tiff) else { fputs("bad image\n", stderr); exit(2) }
let req = VNRecognizeTextRequest()
req.recognitionLevel = .accurate
req.usesLanguageCorrection = true
req.recognitionLanguages = ["he-IL", "en-US"]
let h = VNImageRequestHandler(ciImage: ci, options: [:])
try h.perform([req])
for o in (req.results ?? []) {
    if let t = o.topCandidates(1).first {
        print(String(format: "%.2f\t%@", t.confidence, t.string))
    }
}
