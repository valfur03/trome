import AppKit
import Vision

// It exits with an error when the text recognition fails (as on GitHub's Mac, a virtual machine):
// an image with no text read must never pass for an image with no cut text.
func recognizedTexts(in image: CGImage) throws -> [String] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["fr-FR", "en-US"]
    try VNImageRequestHandler(cgImage: image).perform([request])
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
}

for path in CommandLine.arguments.dropFirst() {
    let name = (path as NSString).lastPathComponent
    guard let image = NSImage(contentsOfFile: path),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("\(name)\tcannot read the image")
        continue
    }
    do {
        for text in try recognizedTexts(in: cgImage) {
            print("\(name)\t\(text)")
        }
    } catch {
        FileHandle.standardError.write(Data("The text recognition of this Mac failed on \(name): \(error)\n".utf8))
        exit(1)
    }
}
