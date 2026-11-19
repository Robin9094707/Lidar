import SwiftUI
import RealityKit

@MainActor
@Observable
final class ObjectCaptureModel {
    enum Phase: Equatable {
        case capturing
        case reconstructing(Double)
        case finished
        case failed(String)
    }

    enum CaptureStep: Equatable {
        case initializing, ready, detecting, capturing, finishing, completed
    }

    var phase: Phase = .capturing
    var step: CaptureStep = .initializing
    var session: ObjectCaptureSession?
    var shotCount = 0
    var userCompletedPass = false
    var passCount = 1
    var feedback: String?
    var modelFileName: String?

    let scanID = UUID()
    private var folder: URL?
    private var imagesURL: URL?
    private var checkpointURL: URL?
    private var pollTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?

    func start(folder: URL) {
        guard session == nil else { return }
        self.folder = folder
        let images = folder.appending(path: "Bilder", directoryHint: .isDirectory)
        let checkpoint = folder.appending(path: "Checkpoint", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: checkpoint, withIntermediateDirectories: true)
        imagesURL = images
        checkpointURL = checkpoint

        let session = ObjectCaptureSession()
        var configuration = ObjectCaptureSession.Configuration()
        configuration.checkpointDirectory = checkpoint
        configuration.isOverCaptureEnabled = false
        session.start(imagesDirectory: images, configuration: configuration)
        self.session = session

        stateTask = Task { [weak self] in
            for await state in session.stateUpdates {
                self?.handle(state)
            }
        }
        feedbackTask = Task { [weak self] in
            for await feedback in session.feedbackUpdates {
                self?.feedback = Self.describe(feedback)
            }
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, let session = self.session else { return }
                self.shotCount = session.numberOfShotsTaken
                self.userCompletedPass = session.userCompletedScanPass
            }
        }
    }

    private func handle(_ state: ObjectCaptureSession.CaptureState) {
        switch state {
        case .initializing: step = .initializing
        case .ready: step = .ready
        case .detecting: step = .detecting
        case .capturing: step = .capturing
        case .finishing: step = .finishing
        case .completed:
            step = .completed
            beginReconstruction()
        case .failed(let error):
            phase = .failed(error.localizedDescription)
            teardownSession()
        @unknown default:
            break
        }
    }

    private static func describe(_ feedback: Set<ObjectCaptureSession.Feedback>) -> String? {
        for item in feedback {
            switch item {
            case .objectTooClose: return "Zu nah am Objekt"
            case .objectTooFar: return "Näher an das Objekt heran"
            case .movingTooFast: return "Langsamer bewegen"
            case .environmentLowLight: return "Mehr Licht nötig"
            case .environmentTooDark: return "Zu dunkel"
            case .outOfFieldOfView: return "Objekt im Bild halten"
            case .objectNotFlippable: return "Objekt nicht wendbar"
            case .overCapturing: return "Genug Bilder in diesem Bereich"
            case .objectNotDetected: return "Kein Objekt erkannt"
            default: continue
            }
        }
        return nil
    }

    // MARK: Aktionen

    func detect() {
        guard let session else { return }
        _ = session.startDetecting()
    }

    func capture() {
        session?.startCapturing()
    }

    func resetDetection() {
        session?.resetDetection()
    }

    func newPass(flip: Bool) {
        guard let session else { return }
        if flip {
            session.beginNewScanPassAfterFlip()
        } else {
            session.beginNewScanPass()
        }
        passCount += 1
    }

    func finish() {
        session?.finish()
    }

    func cancel() {
        session?.cancel()
        teardownSession()
        if let folder {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func teardownSession() {
        pollTask?.cancel()
        stateTask?.cancel()
        feedbackTask?.cancel()
        session = nil
    }

    // MARK: Rekonstruktion

    private func beginReconstruction() {
        teardownSession()
        guard let folder, let imagesURL, let checkpointURL else { return }
        phase = .reconstructing(0)

        Task {
            do {
                guard PhotogrammetrySession.isSupported else {
                    throw NSError(domain: "LidarStudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photogrammetrie wird auf diesem Gerät nicht unterstützt."])
                }
                var configuration = PhotogrammetrySession.Configuration()
                configuration.checkpointDirectory = checkpointURL
                let photogrammetry = try PhotogrammetrySession(input: imagesURL, configuration: configuration)
                let fileName = "Objekt.usdz"
                let output = folder.appending(path: fileName)
                try photogrammetry.process(requests: [.modelFile(url: output)])

                for try await result in photogrammetry.outputs {
                    switch result {
                    case .requestProgress(_, fractionComplete: let fraction):
                        phase = .reconstructing(fraction)
                    case .requestError(_, let error):
                        throw error
                    case .processingComplete:
                        modelFileName = fileName
                    case .processingCancelled:
                        throw CancellationError()
                    default:
                        break
                    }
                }

                guard modelFileName != nil, FileManager.default.fileExists(atPath: output.path) else {
                    throw NSError(domain: "LidarStudio", code: 2, userInfo: [NSLocalizedDescriptionKey: "Es konnte kein Modell erzeugt werden."])
                }
                try? FileManager.default.removeItem(at: checkpointURL)
                phase = .finished
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    var imagesFolder: URL? { imagesURL }
}

struct ObjectCaptureFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScanStore.self) private var store
    @State private var model = ObjectCaptureModel()
    @State private var name = "Objekt \(Date().scanDefaultName)"
    @State private var isSaving = false
    @State private var keepImages = false

    var body: some View {
        ZStack {
            if !DeviceCapabilities.supportsObjectCapture {
                UnsupportedFeatureView(
                    title: "Object Capture nicht verfügbar",
                    message: "Die Objekterfassung benötigt ein Gerät mit LiDAR-Scanner und iOS 17 oder neuer.",
                    onClose: { dismiss() }
                )
            } else {
                switch model.phase {
                case .capturing:
                    captureScreen
                case .reconstructing(let progress):
                    ZStack {
                        AuroraBackground()
                        ProcessingOverlay(title: "3D-Modell wird berechnet …\nDas kann einige Minuten dauern.", progress: progress)
                    }
                case .finished:
                    finishedScreen
                case .failed(let message):
                    UnsupportedFeatureView(title: "Erfassung fehlgeschlagen", message: message, onClose: {
                        model.cancel()
                        dismiss()
                    })
                }
            }
            if isSaving {
                ProcessingOverlay(title: "Wird gespeichert …")
            }
        }
        .statusBarHidden()
        .onAppear {
            if DeviceCapabilities.supportsObjectCapture {
                model.start(folder: store.folderURL(for: model.scanID))
            }
        }
    }

    // MARK: Erfassung

    private var captureScreen: some View {
        ZStack {
            if let session = model.session {
                ObjectCaptureView(session: session)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            VStack(spacing: 14) {
                CaptureTopBar(title: "Objekt", systemImage: "cube.fill", tint: Theme.orange, onClose: {
                    model.cancel()
                    dismiss()
                })

                HintBanner(text: model.feedback ?? stepHint, systemImage: model.feedback == nil ? "cube.transparent" : "exclamationmark.triangle.fill")

                Spacer()

                if model.step == .capturing {
                    GlassEffectContainer(spacing: 10) {
                        HStack(spacing: 10) {
                            GlassPill(systemImage: "camera.fill", text: "\(model.shotCount)", tint: Theme.orange)
                            GlassPill(systemImage: "arrow.triangle.2.circlepath", text: "Durchgang \(model.passCount)", tint: Theme.accent)
                        }
                    }
                }

                controls
                    .padding(.bottom, 20)
            }
            .padding(.top, 8)
            .animation(.spring(duration: 0.4), value: model.step)
            .animation(.spring(duration: 0.4), value: model.userCompletedPass)
        }
    }

    private var stepHint: String? {
        switch model.step {
        case .initializing: "Kamera wird vorbereitet …"
        case .ready: "Richte den Punkt auf das Objekt"
        case .detecting: "Passe den Rahmen an das Objekt an"
        case .capturing: model.userCompletedPass ? "Durchgang abgeschlossen!" : "Langsam um das Objekt herumgehen"
        case .finishing: "Aufnahme wird abgeschlossen …"
        case .completed: nil
        }
    }

    @ViewBuilder
    private var controls: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                switch model.step {
                case .ready:
                    Button("Objekt erkennen") { Haptics.tap(); model.detect() }
                        .buttonStyle(.glassProminent).controlSize(.large)
                case .detecting:
                    Button("Zurücksetzen") { model.resetDetection() }
                        .buttonStyle(.glass).controlSize(.large)
                    Button("Aufnahme starten") { Haptics.tap(); model.capture() }
                        .buttonStyle(.glassProminent).controlSize(.large)
                case .capturing:
                    if model.userCompletedPass {
                        Button("Weiter") { model.newPass(flip: false) }
                            .buttonStyle(.glass).controlSize(.large)
                        Button("Wenden") { model.newPass(flip: true) }
                            .buttonStyle(.glass).controlSize(.large)
                    }
                    Button {
                        Haptics.tap()
                        model.finish()
                    } label: {
                        Label("Fertig", systemImage: "checkmark")
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(model.shotCount < 10)
                case .initializing, .finishing, .completed:
                    ProgressView()
                        .tint(.white)
                        .padding(18)
                        .glassEffect(.regular, in: .circle)
                }
            }
        }
    }

    // MARK: Abschluss

    private var finishedScreen: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 22) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Theme.titleGradient)
                    .symbolEffect(.bounce, options: .nonRepeating)
                    .frame(width: 120, height: 120)
                    .glassEffect(.regular.tint(Theme.orange.opacity(0.25)), in: .circle)
                Text("Modell fertig!")
                    .font(.largeTitle.weight(.bold))
                Text("\(model.shotCount) Aufnahmen · \(model.passCount) Durchgänge")
                    .foregroundStyle(.secondary)

                TextField("Name", text: $name)
                    .font(.headline)
                    .padding(16)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))

                Toggle("Einzelbilder behalten", isOn: $keepImages)
                    .padding(.horizontal, 6)

                Button {
                    save()
                } label: {
                    Label("In Bibliothek speichern", systemImage: "square.and.arrow.down.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
            .padding(28)
            .glassEffect(.regular, in: .rect(cornerRadius: 36))
            .padding(20)
        }
    }

    private func save() {
        guard let fileName = model.modelFileName else { return }
        isSaving = true
        let id = model.scanID
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let scanName = trimmed.isEmpty ? "Objekt" : trimmed

        Task {
            let folder = store.folderURL(for: id)
            let finalName = "\(scanName.sanitizedFileName).usdz"
            let source = folder.appending(path: fileName)
            let target = folder.appending(path: finalName)
            var primary = fileName
            if finalName != fileName, (try? FileManager.default.moveItem(at: source, to: target)) != nil {
                primary = finalName
            }
            if !keepImages, let images = model.imagesFolder {
                try? FileManager.default.removeItem(at: images)
            }

            var stats: [ScanStat] = [
                ScanStat(label: "Aufnahmen", icon: "camera.fill", value: Double(model.shotCount), unit: .count),
                ScanStat(label: "Durchgänge", icon: "arrow.triangle.2.circlepath", value: Double(model.passCount), unit: .count),
                ScanStat(label: "Dateigröße", icon: "doc.fill", value: 0, unit: .text, text: Units.bytes(ScanStore.fileSize(folder.appending(path: primary))))
            ]
            if let prepared = await Task.detached(priority: .utility, operation: { SceneLoader.prepare(url: folder.appending(path: primary)) }).value,
               let bounds = SceneLoader.worldBounds(of: prepared.scene.rootNode) {
                let size = bounds.1 - bounds.0
                stats.append(ScanStat(label: "Breite", icon: "arrow.left.and.right", value: Double(size.x), unit: .length))
                stats.append(ScanStat(label: "Höhe", icon: "arrow.up.and.down", value: Double(size.y), unit: .length))
                stats.append(ScanStat(label: "Tiefe", icon: "arrow.up.left.and.arrow.down.right", value: Double(size.z), unit: .length))
            }

            await store.generateThumbnail(forID: id, primaryFile: primary)
            store.add(ScanItem(
                id: id, name: scanName, kind: .object, createdAt: Date(),
                primaryFile: primary, files: [primary], stats: stats
            ))
            Haptics.success()
            isSaving = false
            dismiss()
        }
    }
}
