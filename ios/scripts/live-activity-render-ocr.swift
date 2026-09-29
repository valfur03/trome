import AppKit
import Vision

for path in CommandLine.arguments.dropFirst() {
    guard let image = NSImage(contentsOfFile: path),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("\((path as NSString).lastPathComponent)\tcannot read the image")
        continue
    }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["fr-FR", "en-US"]
    try VNImageRequestHandler(cgImage: cgImage).perform([request])
    for observation in request.results ?? [] {
        guard let text = observation.topCandidates(1).first?.string else { continue }
        print("\((path as NSString).lastPathComponent)\t\(text)")
    }
}
