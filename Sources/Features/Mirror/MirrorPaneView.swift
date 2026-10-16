import AppKit
import AVFoundation

/// Webcam preview, for checking yourself before a call.
final class MirrorPaneView: NSView {
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let statusLabel = Style.label("Camera off", size: 11, color: Style.secondaryText)
    private lazy var toggleButton = Style.pushButton("Start", prominent: true, target: self, action: #selector(handleToggle))
    private let previewContainer = NSView()

    init() {
        super.init(frame: .zero)

        previewContainer.wantsLayer = true
        previewContainer.layer?.cornerRadius = 10
        previewContainer.layer?.cornerCurve = .continuous
        previewContainer.layer?.masksToBounds = true
        previewContainer.layer?.backgroundColor = Style.controlFill.cgColor

        let controls = NSStackView(views: [toggleButton, statusLabel])
        controls.orientation = .vertical
        controls.alignment = .leading
        controls.spacing = 6

        let root = NSStackView(views: [previewContainer, controls])
        root.orientation = .horizontal
        root.alignment = .centerY
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        NSLayoutConstraint.activate([
            previewContainer.widthAnchor.constraint(equalToConstant: 120),
            previewContainer.heightAnchor.constraint(equalToConstant: 68),
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            root.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            root.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The camera keeps running otherwise, light and all.
    func stopIfNeeded() {
        guard session.isRunning else { return }
        session.stopRunning()
        statusLabel.stringValue = "Camera off"
        toggleButton.title = "Start"
    }

    @objc private func handleToggle() {
        if session.isRunning {
            stopIfNeeded()
            return
        }

        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    self.statusLabel.stringValue = "Camera access denied"
                    return
                }
                self.startSession()
            }
        }
    }

    private func startSession() {
        if session.inputs.isEmpty {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                statusLabel.stringValue = "No camera found"
                return
            }
            session.addInput(input)

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = previewContainer.bounds
            layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            previewContainer.layer?.addSublayer(layer)
            previewLayer = layer
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
        statusLabel.stringValue = "Camera on"
        toggleButton.title = "Stop"
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = previewContainer.bounds
    }
}
