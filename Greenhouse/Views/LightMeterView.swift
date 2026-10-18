@preconcurrency import AVFoundation
import SwiftUI

/// Point the camera from a plant's spot toward its light and get a rough lux
/// reading, compared with what the species likes.
struct LightMeterView: View {
    let plant: Plant?
    @StateObject private var meter = LightMeterSession()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CameraPreview(session: meter.session)
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        if let problem = meter.problem {
                            Text(problem)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white)
                                .padding()
                        }
                    }

                if let lux = meter.lux {
                    VStack(spacing: 4) {
                        Text("\(Int(lux.rounded()).formatted()) lux")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("≈ \(Int(LightMeter.footCandles(lux: lux).rounded()).formatted()) foot-candles · \(LightMeter.describe(lux: lux))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let species = plant?.species, let level = LightMeter.level(lux: lux, for: species.light) {
                        Label {
                            Text("\(level.label) for \(plant?.displayName ?? species.primaryCommonName), which likes \(species.light.lowercased())")
                        } icon: {
                            Image(systemName: level == .aboutRight ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(level == .aboutRight ? .green : .orange)
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                } else if meter.problem == nil {
                    ProgressView("Reading the light…")
                }

                Text("Hold the phone where the plant sits with the back camera facing the window or lamp, at the time of day it usually gets light. The number is a rough estimate from the camera's exposure, good for comparing spots, not for exact values.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Light meter")
        .navigationBarTitleDisplayMode(.inline)
        .task { await meter.start() }
        .onDisappear { meter.stop() }
    }
}

/// Runs the back camera with automatic exposure and turns its settings into lux.
@MainActor
final class LightMeterSession: ObservableObject {
    @Published var lux: Double?
    @Published var problem: String?
    let session = AVCaptureSession()
    private var device: AVCaptureDevice?
    private var timer: Timer?
    private var recent: [Double] = []
    private let queue = DispatchQueue(label: "greenhouse.lightmeter")

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            problem = "Camera access is off. Turn it on in Settings → Greenhouse → Camera."
            return
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            problem = "No camera available."
            return
        }
        self.device = device
        if session.inputs.isEmpty {
            session.beginConfiguration()
            session.sessionPreset = .low
            if session.canAddInput(input) { session.addInput(input) }
            session.commitConfiguration()
        }
        let session = session
        queue.async { session.startRunning() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        let session = session
        queue.async { session.stopRunning() }
    }

    private func sample() {
        guard let device, session.isRunning else { return }
        let seconds = device.exposureDuration.seconds
        guard seconds > 0, device.iso > 0 else { return }
        let reading = LightMeter.lux(aperture: Double(device.lensAperture), exposureSeconds: seconds, iso: Double(device.iso))
        // A short running average keeps the number from jittering.
        recent = Array((recent + [reading]).suffix(5))
        withAnimation { lux = recent.reduce(0, +) / Double(recent.count) }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
