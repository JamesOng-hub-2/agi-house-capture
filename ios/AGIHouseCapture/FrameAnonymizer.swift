import CoreImage
import CoreMedia
import CoreVideo
import ImageIO
import Metal
import Vision

final class FrameAnonymizer {
    private let context: CIContext
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    init() {
        let options: [CIContextOption: Any] = [.cacheIntermediates: false]
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: options)
        } else {
            context = CIContext(options: options)
        }
    }

    func anonymize(
        source: CVPixelBuffer,
        destination: CVPixelBuffer,
        presentationTime: CMTime
    ) -> SanitizedFrame {
        let image = CIImage(cvPixelBuffer: source)

        do {
            let faces = try detectFaces(in: source)
            let rendered = renderFaces(faces, over: image)
            render(rendered, to: destination)
            return SanitizedFrame(
                pixelBuffer: destination,
                presentationTime: presentationTime,
                detectedFaceCount: faces.count,
                usedFullFrameFallback: false
            )
        } catch {
            // Privacy failures fail closed. No path writes the source image unchanged.
            render(pixelated(image), to: destination)
            return SanitizedFrame(
                pixelBuffer: destination,
                presentationTime: presentationTime,
                detectedFaceCount: 0,
                usedFullFrameFallback: true
            )
        }
    }

    private func detectFaces(in pixelBuffer: CVPixelBuffer) throws -> [VNFaceObservation] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )
        try handler.perform([request])
        return request.results ?? []
    }

    private func renderFaces(_ faces: [VNFaceObservation], over image: CIImage) -> CIImage {
        faces.reduce(image) { output, face in
            let faceRect = VNImageRectForNormalizedRect(
                face.boundingBox,
                Int(image.extent.width),
                Int(image.extent.height)
            )
            let padding = max(faceRect.width, faceRect.height) * 0.22
            let paddedRect = faceRect
                .insetBy(dx: -padding, dy: -padding)
                .intersection(image.extent)

            guard !paddedRect.isEmpty else { return output }
            return pixelated(image)
                .cropped(to: paddedRect)
                .composited(over: output)
        }
    }

    private func pixelated(_ image: CIImage) -> CIImage {
        let scale = max(24, min(image.extent.width, image.extent.height) / 32)
        return image
            .clampedToExtent()
            .applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: scale])
            .cropped(to: image.extent)
    }

    private func render(_ image: CIImage, to destination: CVPixelBuffer) {
        context.render(
            image,
            to: destination,
            bounds: image.extent,
            colorSpace: colorSpace
        )
    }
}
