import SwiftUI

/// Runder Liquid-Glass-Button für HUD-Steuerelemente.
struct GlassIconButton: View {
    let systemName: String
    var size: CGFloat = 50
    var tint: Color? = nil
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(glass, in: .circle)
        .opacity(isEnabled ? 1 : 0.45)
        .disabled(!isEnabled)
    }

    private var glass: Glass {
        if let tint {
            return Glass.regular.tint(tint.opacity(0.55)).interactive()
        }
        return Glass.regular.interactive()
    }
}

/// Großer Aufnahme-Button, der sich beim Aufnehmen vom Kreis zum Quadrat verwandelt.
struct RecordButton: View {
    let isRecording: Bool
    var idleColor: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.85), lineWidth: 3)
                    .frame(width: 78, height: 78)
                RoundedRectangle(cornerRadius: isRecording ? 9 : 31, style: .continuous)
                    .fill(isRecording ? Color.red : idleColor)
                    .frame(width: isRecording ? 30 : 62, height: isRecording ? 30 : 62)
                    .shadow(color: (isRecording ? Color.red : Theme.accent).opacity(0.6), radius: 12)
            }
            .frame(width: 90, height: 90)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .animation(.spring(duration: 0.4, bounce: 0.35), value: isRecording)
        .sensoryFeedback(.impact(weight: .medium), trigger: isRecording)
    }
}

/// Kapsel mit Symbol und Text auf Liquid Glass.
struct GlassPill: View {
    let systemImage: String
    let text: String
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .foregroundStyle(tint ?? .white)
            Text(text)
                .contentTransition(.numericText())
        }
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }
}

/// Kopfzeile aller Scan-Bildschirme.
struct CaptureTopBar: View {
    let title: String
    let systemImage: String
    var tint: Color = Theme.accent
    let onClose: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            HStack {
                GlassIconButton(systemName: "xmark", size: 46, action: onClose)
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .foregroundStyle(tint)
                    Text(title)
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
                Spacer()
                Color.clear.frame(width: 46, height: 46)
            }
        }
        .padding(.horizontal, 18)
    }
}

/// Hinweis-Banner (z. B. Tracking-Status) mit sanftem Ein-/Ausblenden.
struct HintBanner: View {
    let text: String?
    var systemImage: String = "info.circle.fill"

    var body: some View {
        Group {
            if let text {
                Label(text, systemImage: systemImage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.tint(Theme.orange.opacity(0.25)), in: .capsule)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4), value: text)
    }
}

/// Kachel mit Kennzahl.
struct StatTile: View {
    let stat: ScanStat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: stat.icon)
                .font(.title3)
                .foregroundStyle(Theme.accent)
            Text(stat.formattedValue)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(stat.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

/// Speichern-Dialog für neue Scans.
struct SaveScanSheet: View {
    let kind: ScanKind
    @Binding var name: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: kind.icon)
                    .font(.title2)
                    .foregroundStyle(kind.tint)
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular.tint(kind.tint.opacity(0.3)), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(kind.title) speichern")
                        .font(.title3.weight(.bold))
                    Text("Wird in deiner Bibliothek abgelegt")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            TextField("Name", text: $name)
                .font(.headline)
                .padding(16)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(onSave)

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button("Abbrechen", role: .cancel, action: onCancel)
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                    Button(action: onSave) {
                        Label("Speichern", systemImage: "square.and.arrow.down.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(24)
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
    }
}

/// Vollbild-Overlay während Exporten/Berechnungen.
struct ProcessingOverlay: View {
    let title: String
    var progress: Double? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 18) {
                if let progress {
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.15), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Theme.laserGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.smooth, value: progress)
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                    }
                    .frame(width: 96, height: 96)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .glassEffect(.regular, in: .rect(cornerRadius: 32))
            .padding(40)
        }
        .transition(.opacity)
    }
}

/// Anzeige, wenn das Gerät eine Funktion nicht unterstützt.
struct UnsupportedFeatureView: View {
    let title: String
    let message: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 20) {
                Image(systemName: "sensor.tag.radiowaves.forward")
                    .font(.system(size: 54))
                    .foregroundStyle(Theme.titleGradient)
                    .frame(width: 110, height: 110)
                    .glassEffect(.regular, in: .circle)
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Schließen", action: onClose)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
            .padding(30)
            .glassEffect(.regular, in: .rect(cornerRadius: 36))
            .padding(24)
        }
    }
}
