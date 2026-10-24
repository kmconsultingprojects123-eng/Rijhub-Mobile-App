import Foundation
import CoreImage
import AppKit

func decode(_ path: String) {
    guard let img = CIImage(contentsOf: URL(fileURLWithPath: path)) else {
        print("  \(path): could not load"); return
    }
    let ctx = CIContext()
    let det = CIDetector(ofType: CIDetectorTypeQRCode, context: ctx,
                         options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
    let feats = det.features(in: img).compactMap { $0 as? CIQRCodeFeature }
    if feats.isEmpty { print("  NO QR DETECTED") }
    for f in feats { print("  payload: \(f.messageString ?? "(nil)")") }
}
for p in CommandLine.arguments.dropFirst() { print(p); decode(p) }
