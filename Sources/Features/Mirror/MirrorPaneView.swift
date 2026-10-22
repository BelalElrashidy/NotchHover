import AppKit
import AVFoundation

/// Webcam preview, for checking yourself before a call. It fills the panel — a small
/// tile on the left with nothing beside it wasted most of the space — and is mirrored,
/// the way a mirror shows you. The camera only starts when you press Start.
final class MirrorPaneView: NSView {
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let previewContainer = NSView()
    private let placeholderIcon = NSImageView()
    private let statusLabel = Style.label("Camera off", size: 11, color: Style.secondaryText)
    private lazy var startButton = Style.pushButton("Start camera", prominent: true, target: self, action: #selector(handleToggle))
    private lazy var stopButton = Style.pushButton("Stop", prominent: false, target: self, action: #selector(handleToggle))

    private enum Layout {
        static let inset: CGFloat = 10
        static let cornerRadius: CGFloat = 14
    }

    init() {
        super.init(frame: .zero)

        previewContainer.wantsLayer = true
        previewContainer.layer?.cornerRadius = Layout.cornerRadius
        previewContainer.layer?.cornerCurve = .continuous
        previewContainer.layer?.masksToBounds = true
        previewContainer.layer?.backgroundColor = Style.controlFill.cgColor
        addSubview(previewContainer)

        placeholderIcon.image = Style.symbolImage("video.fill", pointSize: 20)
        placeholderIcon.contentTintColor = Style.tertiaryText

        // Off: the icon, the button and a word, in the middle of the frame.
        let offStack = NSStackView(views: [placeholderIcon, startButton, statusLabel])
        offStack.orientation = .vertical
        offStack.alignment = .centerX
        offStack.spacing = 8
        offStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(offStack)

        // On: just a small Stop, in the corner, over the picture.
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        stopButton.isHidden = true
        addSubview(stopButton)

        // Room around the button's words, and a status that wraps rather than cuts.
        startButton.widthAnchor.constraint(equalToConstant: ceil(startButton.intrinsicContentSize.width) + 28).isActive = true
        startButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
        stopButton.widthAnchor.constraint(equalToConstant: ceil(stopButton.intrinsicContentSize.width) + 24).isActive = true
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        statusLabel.alignment = .center
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusLabel.preferredMaxLayoutWidth = 360
        statusLabel.isHidden = true

        NSLayoutConstraint.activate([
            offStack.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
            offStack.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor),
            stopButton.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -10),
            stopButton.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: -10)
        ])
        self.offStack = offStack
    }

    private var offStack: NSStackView?

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        previewContainer.frame = bounds.insetBy(dx: Layout.inset, dy: Layout.inset)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = previewContainer.bounds
        CATransaction.commit()
    }

    /// The camera keeps running otherwise, light and all.
    func stopIfNeeded() {
        guard session.isRunning else { return }
        session.stopRunning()
        setRunning(false, status: "Camera off")
    }

    /// `status` is only shown when it says something the picture can't: no camera,
    /// access turned off.
    private func setRunning(_ running: Bool, status: String) {
        statusLabel.stringValue = status
        statusLabel.isHidden = running || status == "Camera off"
        offStack?.isHidden = running
        stopButton.isHidden = running == false
        previewLayer?.isHidden = running == false
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
                    self.setRunning(false, status: "Camera access is off — System Settings → Privacy & Security → Camera")
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
                setRunning(false, status: "No camera found")
                return
            }
            session.addInput(input)

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = previewContainer.bounds
            // A mirror shows you flipped; an unflipped picture feels wrong to look at.
            if let connection = layer.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
            previewContainer.layer?.addSublayer(layer)
            previewLayer = layer
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
        setRunning(true, status: "Camera on")
    }
}
