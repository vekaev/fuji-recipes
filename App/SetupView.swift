import FujiKit
import SwiftUI

/// No camera ready: how to set the camera up (from Fujifilm's X-E5 manual) next to the live five-step check that
/// `fuji doctor` runs, re-run every few seconds and on every plug-in. docs/CONNECT.md says the same in more words.
struct SetupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 44) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Connect your Fujifilm").font(.system(size: 24, weight: .semibold))
                    Text("Out of the box the camera connects as a card reader: the Mac sees your photos, not its settings. Set it up once, on the camera:")
                        .foregroundStyle(.secondary).padding(.top, 6).fixedSize(horizontal: false, vertical: true)
                    heading("Once, on the camera")
                    step(1, "Connection mode", crumbs: ["MENU/OK", "network/USB", "CONNECTION MODE", "USB RAW CONV./BACKUP RESTORE"],
                         why: "The default, USB CARD READER, shows only your photos.")
                    step(2, "Power and data", crumbs: ["same tab", "USB POWER SUPPLY/COMM SETTING", "AUTO"],
                         why: "“POWER SUPPLY ON/COMM OFF” charges but blocks data.")
                    heading("Every time")
                    plain(1, "Switch the camera **off**.")
                    plain(2, "Plug a USB-C **data** cable straight into the Mac.")
                    plain(3, "Switch the camera **on**. Its menu locks while connected; unplug to shoot.")
                    Text("Older bodies: SET UP › CONNECTION SETTING › PC CONNECTION MODE. The setting stays, and the camera shoots normally when unplugged.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 14)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("How to shoot with C1–C7 and FS1–FS3") { model.sheet = .help }
                        .buttonStyle(.link).font(.system(size: 12)).padding(.top, 6)
                }
                .frame(maxWidth: 440, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    heading("Connection check").padding(.top, -18)
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, r in checkRow(i, r) }
                    if !model.appsHolding.isEmpty {
                        Text("Running now: \(model.appsHolding.joined(separator: ", ")). Quit them if a step fails: they can hold on to the camera.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 10)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        PillButton(title: "Check again", primary: true) { Task { await model.check() } }
                        PillButton(title: "Troubleshooting") { model.sheet = .trouble }
                    }
                    .padding(.top, 14)
                    Button("No camera at hand? Try with a simulated X-E5") { model.trySimulated() }
                        .buttonStyle(.link).font(.system(size: 12)).padding(.top, 10)
                }
                .frame(width: 330, alignment: .leading)
            }
            .padding(.horizontal, 32).padding(.vertical, 44)
            .frame(maxWidth: .infinity)
        }
    }

    private struct Row { var name: String; var state: Int; var saw: String; var fix: String? }   // state: 0 waiting, 1 ok, 2 failed

    private var rows: [Row] {
        let names = ["USB", "Camera", "Session", "Mode", "Slots"]
        let waiting = ["A Fujifilm on USB", "macOS offers it as a camera", "It answers", "USB RAW CONV./BACKUP RESTORE", "C1–C7 readable"]
        return names.enumerated().map { i, n in
            if let s = model.steps.first(where: { $0.name == n }) { return Row(name: n, state: s.ok ? 1 : 2, saw: s.saw, fix: s.fix) }
            return Row(name: n, state: 0, saw: waiting[i], fix: nil)
        }
    }

    private func checkRow(_ i: Int, _ r: Row) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(r.state == 1 ? "✓" : r.state == 2 ? "✕" : "○").frame(width: 14)
                    .foregroundStyle(r.state == 0 ? .tertiary : .primary)
                Text("\(i + 1). \(r.name)").fontWeight(.medium).frame(width: 74, alignment: .leading)
                Text(r.saw).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let f = r.fix {
                Text(f).padding(.leading, 100).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(r.state == 2 ? Theme.raised : .clear, in: RoundedRectangle(cornerRadius: 5))
    }

    private func heading(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 10.5, weight: .medium)).tracking(0.5).foregroundStyle(.secondary)
            .padding(.top, 24).padding(.bottom, 8)
    }

    private func step(_ n: Int, _ title: String, crumbs: [String], why: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n).").foregroundStyle(.tertiary).monospacedDigit()
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.medium)
                Crumbs(parts: crumbs)
                Text(why).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 10)
    }

    private func plain(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n).").foregroundStyle(.tertiary).monospacedDigit()
            Text(text)
        }
        .padding(.bottom, 8)
    }
}
