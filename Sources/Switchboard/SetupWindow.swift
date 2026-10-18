import AppKit
import SwiftUI

/// The setup form for every external screen, in its own window. Call from the main thread only.
enum SetupWindow {
    private static var window: NSWindow?

    static func show(switcher: Switcher, onSave: @escaping () -> Void) {
        switcher.displays { list in
            window?.close()
            // ponytail: built-in screens have no inputs to learn, so they are not listed.
            let rows = list.filter { !$0.isBuiltin }.map { display -> SetupRow in
                let saved = switcher.config.screens[display.key]
                return SetupRow(
                    id: display.id, key: display.key, systemName: display.name, saved: saved != nil, name: saved?.name ?? display.name,
                    mac: saved?.computerInput ?? inputs[0].code,
                    devices: Dictionary(uniqueKeysWithValues: (saved?.devices ?? []).map { ($0.input, $0.name) })
                )
            }
            let view = SetupView(switcher: switcher, rows: rows) {
                window?.close()
                onSave()
            }
            let new = NSWindow(contentViewController: NSHostingController(rootView: view))
            new.title = "Set Up Screens"
            new.isReleasedWhenClosed = false
            new.center()
            window = new
            NSApp.activate(ignoringOtherApps: true)
            new.makeKeyAndOrderFront(nil)
        }
    }

    // ponytail: fixed input list, add custom codes when a monitor needs them
    static let inputs: [(label: String, code: UInt8)] = [
        ("DisplayPort 1", 0x0F), ("DisplayPort 2", 0x10), ("HDMI 1", 0x11), ("HDMI 2", 0x12), ("USB-C", 0x1B),
    ]
}

struct SetupRow: Identifiable {
    let id: CGDirectDisplayID
    let key: String
    let systemName: String
    let saved: Bool
    var name: String
    var mac: UInt8
    /// Input code to device name; an empty name means the input is not used.
    var devices: [UInt8: String]
}

private struct SetupView: View {
    let switcher: Switcher
    @State var rows: [SetupRow]
    let onSave: () -> Void
    @State private var message = "Give each device a name. Test shows it for 5 seconds, then the Mac comes back."
    // Test waits for the Mac's input to be read, so it switches back to the right input.
    @State private var ready = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if rows.isEmpty { Text("No external screen found. Connect one, then open this window again.") }
                ForEach($rows) { $row in
                    Section(row.systemName) {
                        TextField("Name", text: $row.name)
                        Picker("This Mac is on", selection: $row.mac) {
                            ForEach(SetupWindow.inputs, id: \.code) { Text($0.label).tag($0.code) }
                        }
                        ForEach(SetupWindow.inputs.filter { $0.code != row.mac }, id: \.code) { input in
                            HStack {
                                let name = Binding { row.devices[input.code] ?? "" } set: { $row.wrappedValue.devices[input.code] = $0 }
                                TextField(input.label, text: name, prompt: Text("Not used"))
                                Button("Test") { test(row, input.code) }.disabled(!ready)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Text(message).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 480, height: 520)
        .onAppear(perform: readInputs)
    }

    /// Learns the Mac's input on each new screen from the screen itself, when DDC answers with a known input.
    private func readInputs() {
        let ids = rows.filter { !$0.saved }.map(\.id)
        switcher.run({ ids.map { ($0, DDC.readInput($0)) } }) { inputs in
            for case let (id, input?) in inputs where SetupWindow.inputs.contains(where: { $0.code == input }) {
                if let index = rows.firstIndex(where: { $0.id == id }) { rows[index].mac = input }
            }
            ready = true
        }
    }

    // Only DDC: Test never turns a screen off in macOS, and it always switches back to the Mac.
    private func test(_ row: SetupRow, _ input: UInt8) {
        let (id, mac, name) = (row.id, row.mac, row.name)
        message = "Testing “\(name)”. The Mac comes back in 5 seconds."
        switcher.run({ () -> String in
            // Waits and switches back even when the write reports a failure: the monitor may have taken it.
            let switched = DDC.writeInput(input, to: id)
            sleep(5)
            guard DDC.writeInput(mac, to: id) else { return Switcher.didNotSwitchBack(name) }
            return switched ? "“\(name)” is back on the Mac." : Switcher.didNotSwitch(name)
        }) { message = $0 }
    }

    private func save() {
        var screens = switcher.config.screens
        for row in rows {
            let devices = SetupWindow.inputs.compactMap { input -> Config.Device? in
                let name = row.devices[input.code, default: ""].trimmingCharacters(in: .whitespaces)
                return input.code == row.mac || name.isEmpty ? nil : Config.Device(name: name, input: input.code)
            }
            let name = row.name.trimmingCharacters(in: .whitespaces)
            screens[row.key] = Config.Screen(name: name.isEmpty ? row.systemName : name, computerInput: row.mac, devices: devices)
        }
        switcher.config.screens = screens
        onSave()
    }
}
