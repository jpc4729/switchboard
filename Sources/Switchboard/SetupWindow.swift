import AppKit
import SwiftUI

/// The setup form for every external screen, in its own window.
@MainActor
enum SetupWindow {
    private static var window: NSWindow?
    private static var closing: NSObjectProtocol?

    static func show(switcher: Switcher, onSave: @escaping () -> Void) {
        switcher.displays { list in
            window?.close()
            // Built-in screens have no inputs to learn, so they are not listed.
            let rows = list.filter { !$0.isBuiltin }.map { display -> SetupRow in
                let saved = switcher.config.screens[display.key]
                var row = SetupRow(
                    id: display.id, key: display.key, systemName: display.name, saved: saved != nil, name: saved?.name ?? display.name,
                    mac: saved?.computerInput ?? inputs[0].code,
                    devices: Dictionary(uniqueKeysWithValues: (saved?.devices ?? []).map { ($0.input, $0.name) })
                )
                // Saved custom codes come back as rows, with their names.
                for code in [row.mac] + row.devices.keys.sorted() { row.add(code) }
                return row
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
            // Free the SwiftUI view on close, so a closed window costs no memory. queue nil runs it inside close().
            closing = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: new, queue: nil
            ) { _ in
                MainActor.assumeIsolated {
                    closing.map(NotificationCenter.default.removeObserver)
                    (window, closing) = (nil, nil)
                }
            }
            NSApp.bringToFront()
            new.makeKeyAndOrderFront(nil)
        }
    }

    /// The standard codes; each row adds the custom codes its monitor uses.
    // ponytail: no automatic probe of codes 0 to 32, because each write switches the monitor and blanks
    // the screen; add it if users ask, with a warning.
    nonisolated static let inputs: [(label: String, code: UInt8)] = [
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
    var inputs = SetupWindow.inputs
    /// The Add field's text.
    var newCode = ""

    /// Adds a custom code as "Input <code>", once.
    mutating func add(_ code: UInt8) {
        if !inputs.contains(where: { $0.code == code }) { inputs.append(("Input \(code)", code)) }
    }
}

private struct SetupView: View {
    let switcher: Switcher
    @State var rows: [SetupRow]
    let onSave: () -> Void
    @State private var message = "Press Test to see what is on each input for 5 seconds. Then type the device name."
    // Test and Save wait for the Mac's input to be read, so Test switches back to the right input
    // and Save does not keep the default.
    @State private var ready = false
    @State private var testing = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if rows.isEmpty { Text("No external screen found. Connect one, then open this window again.") }
                ForEach($rows) { $row in
                    Section(row.systemName) {
                        TextField("Name", text: $row.name)
                        Picker("This Mac is on", selection: $row.mac) {
                            ForEach(row.inputs, id: \.code) { Text($0.label).tag($0.code) }
                        }
                        ForEach(row.inputs.filter { $0.code != row.mac }, id: \.code) { input in
                            HStack {
                                let name = Binding { row.devices[input.code] ?? "" } set: { $row.wrappedValue.devices[input.code] = $0 }
                                TextField(input.label, text: name, prompt: Text("Not used"))
                                Button("Test") { test(row, input.code) }.disabled(!ready || testing)
                            }
                        }
                        HStack {
                            TextField("Other input code", text: $row.newCode, prompt: Text("1 to 255"))
                            Button("Add") {
                                if let code = UInt8(row.newCode.trimmingCharacters(in: .whitespaces)), code > 0 { row.add(code) }
                                row.newCode = ""
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Text(message).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Save", action: save).keyboardShortcut(.defaultAction).disabled(!ready)
            }
            .padding()
        }
        .frame(width: 480, height: 520)
        .onAppear(perform: readInputs)
    }

    /// Learns the Mac's input on each new screen from the screen itself; an unknown code is added as a row.
    /// A screen that does not answer keeps the default, and the message asks the user to check it.
    private func readInputs() {
        let ids = rows.filter { !$0.saved }.map(\.id)
        switcher.run({ _ in ids.map { ($0, DDC.readInput($0)) } }) { inputs in
            var unread: [String] = []
            for (id, input) in inputs {
                guard let index = rows.firstIndex(where: { $0.id == id }) else { continue }
                // 0 is not an input code in MCCS, so a monitor that answers 0 did not answer.
                guard let input, input > 0 else {
                    unread.append("“\(rows[index].name)”")
                    continue
                }
                rows[index].add(input)
                rows[index].mac = input
            }
            if !unread.isEmpty {
                message = "Switchboard could not read the Mac’s input on \(unread.joined(separator: ", ")). "
                    + "Check “This Mac is on” before you save."
            }
            ready = true
        }
    }

    // Only DDC: Test never turns a screen off in macOS, and it always switches back to the Mac.
    private func test(_ row: SetupRow, _ input: UInt8) {
        let (id, mac, name) = (row.id, row.mac, row.name)
        message = "Testing “\(name)”. The Mac comes back in 5 seconds."
        testing = true
        switcher.run({ _ in DDC.writeInput(input, to: id) }) { switched in
            // Waits on main, not on the queue, so Back to Computer does not wait behind a test. Switches
            // back even when the write reports a failure: the monitor may have taken it.
            Task {
                try? await Task.sleep(for: .seconds(5))
                switcher.run({ _ in DDC.writeInput(mac, to: id) }) { back in
                    testing = false
                    guard back else { return message = Switcher.didNotSwitchBack(name) }
                    message = switched ? "“\(name)” is back on the Mac." : Switcher.didNotSwitch(name)
                }
            }
        }
    }

    private func save() {
        var screens = switcher.config.screens
        for row in rows {
            let devices = row.inputs.compactMap { input -> Config.Device? in
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
