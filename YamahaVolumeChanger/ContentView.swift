import SwiftUI

// MARK: - AppDelegate（メニューバー）
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "hifispeaker", accessibilityDescription: "Yamaha Volume")
            
            // 左右クリック両方を捕捉
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover.contentViewController = NSHostingController(rootView: ContentView())
        popover.behavior = .transient

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
    }

    @objc func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        if event.type == .rightMouseUp {
            // 右クリックメニュー表示
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
        } else {
            // 左クリックポップオーバー
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            }
        }
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}


// MARK: - Yamaha API 操作クラス
@MainActor
class YamahaVolume: ObservableObject {
    @Published var volume: Int = 100

    private let ipKey = "yamahaAmpIP"

    @Published var ampIP: String {
        didSet {
            UserDefaults.standard.set(ampIP, forKey: ipKey)
        }
    }

    init() {
        self.ampIP = UserDefaults.standard.string(forKey: ipKey) ?? "192.168.10.107"
    }

    var dB: Double { (Double(volume) * 0.5) - 80.5 }
    var percent: Int { Int((Double(volume)/161.0)*100) }

    func fetchVolume() async {
        guard let url = URL(string: "http://\(ampIP)/YamahaExtendedControl/v1/main/getStatus") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let vol = json["volume"] as? Int {
                self.volume = vol
            }
        } catch {
            print("Fetch volume error: \(error)")
        }
    }

    func setVolume(_ newValue: Int) async {
        let clamped = min(max(newValue, 0), 161)
        guard let url = URL(string: "http://\(ampIP)/YamahaExtendedControl/v1/main/setVolume?volume=\(clamped)") else { return }
        do {
            _ = try await URLSession.shared.data(from: url)
            self.volume = clamped
        } catch {
            print("Set volume error: \(error)")
        }
    }

    func setVolume(dB: Double) async {
        let newVol = Int((dB + 80.5) / 0.5)
        await setVolume(newVol)
    }

    func setVolume(percent: Int) async {
        let newVol = Int(Double(percent) / 100.0 * 161.0)
        await setVolume(newVol)
    }
}

// MARK: - UI
struct ContentView: View {
    @StateObject var yamaha = YamahaVolume()
    @State private var inputDB: String = ""
    @State private var inputPercent: String = ""
    @State private var inputIP: String = ""

    var body: some View {
        VStack(spacing: 12) {
            Text("Yamaha V6A Volume")
                .font(.headline)

            // IP入力
            HStack {
                Text("IP:")
                TextField("Amp IP", text: $inputIP, onCommit: {
                    yamaha.ampIP = inputIP
                })
                .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            // スライダー
            Slider(
                value: Binding(
                    get: { Double(yamaha.volume) },
                    set: { newVal in
                        Task {
                            await yamaha.setVolume(Int(newVal))
                            // スライダー更新後に入力欄を同期
                            inputDB = String(format: "%.1f", yamaha.dB)
                            inputPercent = "\(yamaha.percent)"
                        }
                    }
                ),
                in: 0...161
            )

            // dB と % 入力欄
            VStack(spacing: 4) {
                Text(String(format: "%.1f dB (%d%%)", yamaha.dB, yamaha.percent))
                    .font(.subheadline)

                HStack(spacing: 12) {
                    HStack {
                        TextField("dB", text: $inputDB, onCommit: {
                            if let db = Double(inputDB) {
                                Task {
                                    await yamaha.setVolume(dB: db)
                                    // 反映後に入力欄を同期
                                    inputDB = String(format: "%.1f", yamaha.dB)
                                    inputPercent = "\(yamaha.percent)"
                                }
                            }
                        })
                        .frame(width: 60)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        Text("dB")
                    }

                    HStack {
                        TextField("%", text: $inputPercent, onCommit: {
                            if let pct = Int(inputPercent) {
                                Task {
                                    await yamaha.setVolume(percent: pct)
                                    // 反映後に入力欄を同期
                                    inputDB = String(format: "%.1f", yamaha.dB)
                                    inputPercent = "\(yamaha.percent)"
                                }
                            }
                        })
                        .frame(width: 60)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        Text("%")
                    }
                }
            }

            Button("Refresh") {
                Task {
                    await yamaha.fetchVolume()
                    inputDB = String(format: "%.1f", yamaha.dB)
                    inputPercent = "\(yamaha.percent)"
                }
            }
            .padding(.top, 4)
        }
        .padding()
        .frame(width: 300)
        // 初期値セット
        .onAppear {
            inputIP = yamaha.ampIP
            inputDB = String(format: "%.1f", yamaha.dB)
            inputPercent = "\(yamaha.percent)"
        }
        .task {
            await yamaha.fetchVolume()
            inputDB = String(format: "%.1f", yamaha.dB)
            inputPercent = "\(yamaha.percent)"
        }
    }
}
