import Metal
import MetalKit
import SwiftUI
import UIKit

struct MetalSmokeView: UIViewRepresentable {
    let renderer: MetalSmokeRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.clearColor = MTLClearColor(red: 0.035, green: 0.075, blue: 0.13, alpha: 1.0)
        view.preferredFramesPerSecond = 60
        view.delegate = renderer
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        uiView.setNeedsDisplay()
    }
}

final class MetalSmokeRenderer: NSObject, ObservableObject, MTKViewDelegate {
    let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    @Published private(set) var frameCount = 0

    let deviceName: String
    let gpuStatus: String
    let maxBufferLength: String
    let workingSet: String
    let message: String
    var deviceAvailable: Bool { device != nil }

    override init() {
        let selectedDevice = MTLCreateSystemDefaultDevice()
        device = selectedDevice
        commandQueue = selectedDevice?.makeCommandQueue()
        deviceName = selectedDevice?.name ?? "No Metal device"
        gpuStatus = selectedDevice?.hasUnifiedMemory == true ? "Unified memory" : "Unavailable / discrete"
        maxBufferLength = selectedDevice.map { ByteCountFormatter.string(fromByteCount: Int64($0.maxBufferLength), countStyle: .memory) } ?? "—"
        if let selectedDevice {
            workingSet = ByteCountFormatter.string(fromByteCount: Int64(selectedDevice.recommendedMaxWorkingSetSize), countStyle: .memory)
            message = "Metal device created. Waiting for the first presented frame."
        } else {
            workingSet = "—"
            message = "Metal device creation failed on this device."
        }
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let queue = commandQueue,
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [weak self] _ in
            DispatchQueue.main.async {
                self?.frameCount += 1
            }
        }
        commandBuffer.commit()
    }
}
