import AppKit
import SwiftUI

/// The menu's controls in a small window: a picker for each screen, Back to Computer and Set Up.
/// Call from the main thread only.
enum ControlWindow {
    private static var window: NSWindow?
    private static var host: NSHostingController<ControlView>?

    static func show(_ view: ControlView) {
        if window == nil {
            let host = NSHostingController(rootView: view)
            let new = NSWindow(contentViewController: host)
            new.title = "Switchboard"
            new.isReleasedWhenClosed = false
            new.center()
            (window, self.host) = (new, host)
        }
        update(view)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Shows the new state when the window exists; does nothing otherwise.
    static func update(_ view: ControlView) {
        host?.rootView = view
    }
}

struct ControlView: View {
    struct Row: Identifiable {
        let display: Display
        let name: String
        let choices: [(title: String, choice: Config.Choice)]
        let current: Config.Choice
        var id: CGDirectDisplayID { display.id }
    }

    let rows: [Row]
    let pick: (Display, Config.Choice) -> Void
    let back: () -> Void
    let setUp: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if rows.isEmpty { Text("No screen found.") }
                ForEach(rows) { row in
                    Picker(selection: Binding { row.current } set: { pick(row.display, $0) }) {
                        ForEach(row.choices, id: \.choice) { Text($0.title).tag($0.choice) }
                    } label: {
                        Label(row.name, systemImage: row.display.isBuiltin ? "laptopcomputer" : "display")
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("Set Up Screens…", action: setUp)
                Spacer()
                Button("Back to Computer", action: back).keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        // ponytail: fixed height fits about four screens; the form scrolls past that.
        .frame(width: 420, height: 300)
    }
}
