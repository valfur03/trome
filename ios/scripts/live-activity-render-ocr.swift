import AppKit
import CoreML
import Vision

// The text recognition of Vision, on the devices that it picks; on the CPU alone when that fails,
// as on a Mac in a virtual machine, which may have no Neural Engine and no GPU for it.
// It exits with an error when both fail: an image with no text read must never pass for an image with no cut text.
func recognizedTexts(in image: CGImage) throws -> [String] {
    func run(onCPU: Bool) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["fr-FR", "en-US"]
        if onCPU, let cpu = MLComputeDevice.allComputeDevices.first(where: { if case .cpu = $0 { true } else { false } }) {
            for stage in try request.supportedComputeStageDevices.keys {
                request.setComputeDevice(cpu, for: stage)
            }
        }
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
    do {
        return try run(onCPU: false)
    } catch {
        return try run(onCPU: true)
    }
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
