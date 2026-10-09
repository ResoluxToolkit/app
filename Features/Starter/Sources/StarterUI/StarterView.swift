import BorderBeamKit
import ResoluxCore
import ResoluxDesignSystem
import ResoluxPlatform
import Starter
import SwiftUI

public struct StarterView: View {
    private let report: CapabilityReport
#if os(macOS)
    private let backupService = BackupService.shared
    @State private var lastBackupDate: Date? = BackupService.shared.lastBackupDate
#endif
    @State private var backupSpinning = false

    public init(report: CapabilityReport) {
        self.report = report
    }

    public var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 18) {
#if os(macOS)
                        GlassCard {
                            BackupCard(lastBackupDate: lastBackupDate, spinning: backupSpinning) {
                                guard !backupSpinning else { return }
                                backupSpinning = true
                                Task {
                                    do {
                                        let result = try await backupService.runBackup()
                                        lastBackupDate = result.finishedAt
                                    } catch {
                                        print("Backup falhou: \(error)")
                                    }
                                    backupSpinning = false
                                }
                            }
                        }
#endif

                        GlassCard {
                            TelegramQRCard()
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("Ferramentas iniciais", systemImage: "wrench.and.screwdriver.fill")
                                    .font(.headline)
                                ForEach(report.rows) { row in
                                    HStack(spacing: 12) {
                                        if row.available {
                                            CapabilityBadge(capability: row.capability, platform: report.platform)
                                        } else {
                                            Label(row.capability.title + " (indisponível)", systemImage: "xmark.circle")
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
            .padding(.horizontal, 16)
        }
        .foregroundStyle(Palette.foreground)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ToneIcon(symbol: "wrench.and.screwdriver.fill", tone: .violet)

            VStack(alignment: .leading, spacing: 2) {
                Text("Starter")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("utilitários · backup · capacidades")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }

            Spacer(minLength: 8)
            StatusPill(text: "pronto", tone: .green)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 12)
    }
}

private struct BackupCard: View {
    var lastBackupDate: Date?
    var spinning: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "externaldrive.fill.badge.timemachine")
                        .foregroundStyle(Palette.violet)
                        .font(.title3)
                    Text("Backup do sistema")
                        .font(.title3.weight(.bold))
                    Spacer()
                    Text(spinning ? "rodando…" : "pronto")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(spinning ? Palette.cyan : Palette.muted)
                }
                BackupCounter(lastBackupDate: lastBackupDate, running: spinning)
            }

            GlowButton(title: "Backup agora", spinning: spinning, beam: false, action: action)
                .borderBeam(
                    .pulseInner,
                    colorVariant: .ocean,
                    theme: .dark,
                    active: spinning,
                    borderRadius: 24
                )
        }
    }
}

private struct BackupCounter: View {
    var lastBackupDate: Date?
    var running: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let elapsed = running
                ? max(0, Int(now.timeIntervalSinceReferenceDate) % 10_000)
                : lastBackupDate.map { max(0, Int(now.timeIntervalSince($0))) }
            Text(counterText(elapsed: elapsed))
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(running ? Palette.cyan : Palette.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .modifier(BackupCounterGlassModifier(running: running))
                .contentTransition(.numericText())
                .animation(.default, value: elapsed)
        }
    }

    private func counterText(elapsed: Int?) -> String {
        if running {
            return String(format: "backup %04d s decorridos", elapsed ?? 0)
        }
        guard let elapsed else {
            return "nenhum backup nesta sessão"
        }
        let minutes = elapsed / 60
        return String(format: "último backup há %02d:%02d", minutes, elapsed % 60)
    }
}

private struct BackupCounterGlassModifier: ViewModifier {
    let running: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            content
                .glassEffect(.clear.tint(running ? Palette.cyan.opacity(0.14) : Color.white.opacity(0.04)), in: Capsule())
                .overlay(Capsule().strokeBorder(running ? Palette.cyan.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1))
        } else {
            content
                .background(Capsule().fill(Color.white.opacity(0.05)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        }
    }
}

extension CapabilityReport {
    public static func preview(for platform: PlatformTarget) -> CapabilityReport {
        CapabilityReport(
            catalog: CapabilityCatalog([
                Capability(id: "capture", title: "Captura", availability: [.macOS]),
                Capability(id: "share", title: "Compartilhar", availability: [.macOS, .iOS]),
            ]),
            descriptor: PlatformDescriptor(target: platform))
    }
}

public struct StarterView_Previews: PreviewProvider {
    public static var previews: some View {
        StarterView(report: .preview(for: .macOS))
        StarterView(report: .preview(for: .iOS))
    }
}
