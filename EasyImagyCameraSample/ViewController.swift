import UIKit
import AVFoundation
import EasyImagy

class ViewController: UIViewController {
    @IBOutlet private var previewView: PreviewView!
    
    private var session: AVCaptureSession!
    private var imageQueue: ArraySlice<Image<UInt8>> = []
    private static let maxQueueCount = 3
    
    override func viewDidLoad() {
        super.viewDidLoad()

        guard let device = AVCaptureDevice.default(for: .video) else {
            fatalError("No camera device found.")
        }
        do {
            try! device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            
            device.focusMode = .continuousAutoFocus
        }
        
        let preset: AVCaptureSession.Preset = .vga640x480
        guard device.supportsSessionPreset(preset) else {
            fatalError("\(preset) is not supported.")
        }
        
        let input = try! AVCaptureDeviceInput(device: device)
        
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        let queue = DispatchQueue.init(label: "Camera", qos: .userInteractive)
        output.setSampleBufferDelegate(self, queue: queue)
        
        let session = AVCaptureSession()
        do {
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            
            session.addInput(input)
            session.addOutput(output)
            session.sessionPreset = preset
        }
        self.session = session
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        session.startRunning()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        session.stopRunning()
        super.viewWillDisappear(animated)
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)

        var image: Image<UInt8>
        if imageQueue.count >= ViewController.maxQueueCount, let first = imageQueue.popFirst() {
            image = first
        } else {
            image = Image(width: width, height: height, pixel: 0)
        }
        if image.width != width || image.height != height {
            image = Image<UInt8>(width: width, height: height, pixel: 0)
        }
        
        do {
            CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }
            
            let baseAddress = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0)!
            let pointer = UnsafeRawBufferPointer(start: baseAddress, count: image.count)
            image.withUnsafeMutableBytes {
                $0.copyBytes(from: pointer)
            }
        }
        
        image.update { $0 ^= 0xff }
        previewView.nextImage = image
        
        imageQueue.append(image)
    }
}

class PreviewView: UIView {
    var nextImage: Image<UInt8>? { didSet { DispatchQueue.main.async { self.setNeedsDisplay() } } }
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        guard let image = nextImage else { return }

        let rect: CGRect
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        if frame.size.width / frame.size.height < width / height {
            let rectWidth = frame.size.height * width / height
            rect = CGRect(x: (frame.size.width - rectWidth) / 2, y: 0, width: rectWidth, height: frame.size.height)
        } else {
            let rectHeight = frame.size.width * height / width
            rect = CGRect(x: 0, y: (frame.size.height - rectHeight) / 2, width: frame.size.width, height: rectHeight)
        }

        context.translateBy(x: 0, y: frame.size.height)
        context.scaleBy(x: 1, y: -1)
        image.withCGImage { cgImage in
            context.draw(cgImage, in: rect)
        }
    }
}
