import Foundation
import Vision

struct ReceiptTextRecognizer {
    enum RecognitionError: Error {
        case emptyImage
        case noTextFound
    }

    func recognizeText(in imageData: Data) async throws -> String {
        guard !imageData.isEmpty else { throw RecognitionError.emptyImage }

        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(data: imageData).perform([request])

            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            guard !lines.isEmpty else { throw RecognitionError.noTextFound }
            return lines.joined(separator: "\n")
        }.value
    }
}
