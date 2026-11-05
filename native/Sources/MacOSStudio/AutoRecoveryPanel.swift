import SwiftUI

/// "Aktivieren" → "Stecke jetzt ein iPhone an" → device goes into recovery mode without buttons.
/// Shared by Flasher and Extras; the state lives in DeviceMonitor so it keeps running across tabs.
struct AutoRecoveryPanel: View {
    @ObservedObject var monitor: DeviceMonitor
    var disabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.uturn.down.circle.fill").font(.system(size: 26)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Wiederherstellungsmodus per Anstecken").font(.headline)
                    Text("Ohne Tasten. Es wird nichts gelöscht. Ist das Gerät gesperrt oder fragt es nach „Vertrauen“, einfach entsperren bzw. tippen – es wird automatisch erneut versucht.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if monitor.auto == .off {
                    Button("Aktivieren", systemImage: "power") { monitor.activateAuto() }
                        .buttonStyle(.borderedProminent).disabled(disabled || !monitor.available)
                } else {
                    Button("Beenden") { monitor.deactivateAuto() }
                }
            }
            if !monitor.available {
                Text("Apples Gerätedienst ist auf diesem Mac nicht verfügbar.").font(.caption).foregroundStyle(.orange)
            }
            status
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(monitor.auto == .off ? AnyShapeStyle(.background) : AnyShapeStyle(Color.blue.opacity(0.10)),
                    in: RoundedRectangle(cornerRadius: 16))
        .animation(.default, value: monitor.auto)
    }

    @ViewBuilder private var status: some View {
        switch monitor.auto {
        case .off:
            EmptyView()
        case .waiting:
            banner {
                ProgressView().controlSize(.small)
                Text("Stecke jetzt ein iPhone oder iPad an …").font(.title3.weight(.semibold))
            }
            if monitor.blockedCount > 0 {
                Label("Gerät erkannt, aber gesperrt – es gibt per USB keine Daten frei. Bitte entsperren, dann geht es automatisch weiter. Ohne Code: Wiederherstellungsmodus per Tasten (Extras).",
                      systemImage: "lock.fill").font(.callout).foregroundStyle(.orange)
            }
        case .sending(let name):
            banner {
                ProgressView().controlSize(.small)
                Text("„\(name)“ erkannt – wird in den Wiederherstellungsmodus versetzt …").font(.callout.weight(.medium))
            }
        case .done(let name):
            banner {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("„\(name)“ startet im Wiederherstellungsmodus (Laptop und Kabel).").font(.callout.weight(.medium))
                    Text("Nächstes Gerät anstecken oder „Beenden“.").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .failed(let text):
            banner {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.isEmpty ? "Das Gerät hat abgelehnt." : text).font(.callout)
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Gerät entsperren – es wird automatisch alle paar Sekunden erneut versucht.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func banner<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
    }
}
