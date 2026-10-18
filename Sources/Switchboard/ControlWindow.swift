import AppKit
import SwiftUI

/// The menu's controls in a small window: a picker for each screen, Back to Computer and Set Up.
@MainActor
enum ControlWindow {
    private static var window: NSWindow?
    private static var host: NSHostingController<ControlView>?
    private static var closing: NSObjectProtocol?

    static func show(_ view: ControlView) {
        if window == nil {
            let host = NSHostingController(rootView: view)
            let new = NSWindow(contentViewController: host)
            new.title = "Switchboard"
            new.isReleasedWhenClosed = false
            new.center()
            (window, self.host) = (new, host)
            // Free the SwiftUI view on close, so a closed window costs no memory and no updates.
            // queue nil runs it inside close().
            closing = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: new, queue: nil
            ) { _ in
                MainActor.assumeIsolated {
                    closing.map(NotificationCenter.default.removeObserver)
                    (window, self.host, closing) = (nil, nil, nil)
                }
            }
        }
        update(view)
        NSApp.bringToFront()
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
        // ponytail: fixed height fits about four screens and the form scrolls past that; size it to the
        // rows if users have more screens.
        .frame(width: 420, height: 300)
    }
}
