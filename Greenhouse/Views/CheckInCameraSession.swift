@preconcurrency import AVFoundation
import SwiftUI

/// A still photo from the check-in camera: the image for the timeline, and
/// the camera's own file (with its metadata) for the photo library.
struct CapturedPhoto {
    let image: UIImage
    let data: Data
}

/// The capture session behind the check-in camera: back or front camera,
/// portrait stills.
///
/// Every touch of the AVCaptureSession (inputs, outputs, start, stop,
/// capture) happens on one serial queue. Configuring on the main thread while
/// `startRunning` runs on another is what AVFoundation warns about.
@MainActor
final class CheckInCameraSession: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var problem: String?
    @Published private(set) var position: AVCaptureDevice.Position = .back
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "greenhouse.checkin-camera")
    /// Only touched on `queue`.
    private let hardware: Hardware
    private var delegate: PhotoDelegate?
    private var flipping = false
    /// False once the screen has asked the camera to stop. A start that was
    /// waiting on the permission prompt checks it, so closing the sheet over
    /// the prompt doesn't leave the camera running (and its light on) behind.
    private var wanted = false

    init() {
        hardware = Hardware(session: session, output: output)
    }

    var canFlip: Bool { isRunning && Self.device(at: position == .back ? .front : .back) != nil }

    private static func device(at position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    func start() async {
        wanted = true
        guard !isRunning else { return }
        // Checked before asking, so a phone (or simulator) without a camera
        // never shows the permission prompt.
        guard let device = Self.device(at: position) else {
            problem = "There's no camera here. You can check in with a photo from your library instead."
            return
        }
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            problem = "Camera access is off. Turn it on in Settings → Greenhouse → Camera, or use a photo from your library."
            return
        }
        // The sheet closed while the prompt was up: nothing to start.
        guard wanted, !Task.isCancelled else { return }
        let hardware = hardware
        let queue = queue
        let started: Bool? = await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: hardware.start(with: device)) }
        }
        guard let started else {
            problem = "The camera couldn't start. Try again, or use a photo from your library."
            return
        }
        // A stop() that arrived mid-start is queued behind this start and
        // runs next, so the session is already on its way down.
        isRunning = started && wanted
    }

    func stop() {
        wanted = false
        isRunning = false
        let hardware = hardware
        queue.async { hardware.stop() }
    }

    func flip() {
        let next: AVCaptureDevice.Position = position == .back ? .front : .back
        guard !flipping, let device = Self.device(at: next) else { return }
        flipping = true
        let hardware = hardware
        let queue = queue
        Task {
            let swapped = await withCheckedContinuation { continuation in
                queue.async { continuation.resume(returning: hardware.swapInput(to: device)) }
            }
            if swapped { position = next }
            flipping = false
        }
    }

    func capture() async -> CapturedPhoto? {
        guard isRunning, delegate == nil else { return nil }
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        let hardware = hardware
        let queue = queue
        let result: CapturedPhoto? = await withCheckedContinuation { continuation in
            let delegate = PhotoDelegate { continuation.resume(returning: $0) }
            self.delegate = delegate
            queue.async { hardware.capture(with: settings, delegate: delegate) }
        }
        delegate = nil
        return result
    }

    /// The session and its inputs. Every method runs on the camera queue.
    private final class Hardware: @unchecked Sendable {
        let session: AVCaptureSession
        let output: AVCapturePhotoOutput
        private var input: AVCaptureDeviceInput?

        init(session: AVCaptureSession, output: AVCapturePhotoOutput) {
            self.session = session
            self.output = output
        }

        /// Sets up (first time) and starts the session. Nil when the camera
        /// couldn't be opened.
        func start(with device: AVCaptureDevice) -> Bool? {
            if session.inputs.isEmpty {
                guard let newInput = try? AVCaptureDeviceInput(device: device) else { return nil }
                session.beginConfiguration()
                session.sessionPreset = .photo
                if session.canAddInput(newInput) {
                    session.addInput(newInput)
                    input = newInput
                }
                if session.canAddOutput(output) { session.addOutput(output) }
                session.commitConfiguration()
            }
            session.startRunning()
            return session.isRunning
        }

        func stop() {
            session.stopRunning()
        }

        func swapInput(to device: AVCaptureDevice) -> Bool {
            guard let newInput = try? AVCaptureDeviceInput(device: device) else { return false }
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            if let input { session.removeInput(input) }
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                input = newInput
                return true
            }
            if let input { session.addInput(input) }
            return false
        }

        func capture(with settings: AVCapturePhotoSettings, delegate: AVCapturePhotoCaptureDelegate) {
            if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90  // the app is portrait only
            }
            output.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
        private var finish: ((CapturedPhoto?) -> Void)?

        init(finish: @escaping (CapturedPhoto?) -> Void) { self.finish = finish }

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            let data = error == nil ? photo.fileDataRepresentation() : nil
            let shot = data.flatMap { data in UIImage(data: data).map { CapturedPhoto(image: $0, data: data) } }
            finish?(shot)
            finish = nil
        }
    }
}
