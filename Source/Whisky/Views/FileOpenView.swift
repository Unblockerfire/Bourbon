//
//  FileOpenView.swift
//  Whisky
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import SwiftUI
import AppKit
import WhiskyKit

struct FileOpenView: View {
    var fileURL: URL
    var currentBottle: URL?
    var bottles: [Bottle]

    @State private var selection: URL = URL(filePath: "")
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("run.bottle", selection: $selection) {
                    ForEach(bottles, id: \.self) {
                        Text($0.settings.name)
                            .tag($0.url)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .formStyle(.grouped)
            .navigationTitle(String(format: String(localized: "run.title"), fileURL.lastPathComponent))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("create.cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("button.run") {
                        run()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: ViewWidth.small)
        .onAppear {
            // Makes sure there are more than 0 bottles.
            // Otherwise, it will crash on the nil cascade
            if bottles.count <= 0 {
                dismiss()
                return
            }

            selection = bottles.first(where: { $0.url == currentBottle })?.url ?? bottles[0].url

            if bottles.count == 1 {
                // If the user only has one bottle
                // there's nothing for them to select
                run()
            }
        }
    }

    func run() {
        if let bottle = bottles.first(where: { $0.url == selection }) {
            Task.detached(priority: .userInitiated) {
                do {
                    if fileURL.pathExtension == "bat" {
                        try await Wine.runBatchFile(url: fileURL,
                                                    bottle: bottle)
                    } else {
                        try await Wine.runProgram(at: fileURL, bottle: bottle)
                    }
                } catch is Wine.ProgramLaunchIntentionalTermination {
                    return
                } catch {
                    await showRunError(message: error.localizedDescription)
                }
            }
            dismiss()
        }
    }

    @MainActor private func showRunError(message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.message")
        alert.informativeText = String(localized: "alert.info") + " \(fileURL.lastPathComponent)"
        alert.alertStyle = .critical
        alert.accessoryView = fileOpenDiagnosticScrollView(message: message)
        alert.addButton(withTitle: String(localized: "button.ok"))
        alert.addButton(withTitle: "Report")
        alert.addButton(withTitle: "Copy Diagnostics")
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            BourbonReportCenter.openRuntimeReport(
                title: "Failed to open \(fileURL.lastPathComponent)",
                errorMessage: message
            )
        } else if response == .alertThirdButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message, forType: .string)
        }
    }
}

@MainActor
private func fileOpenDiagnosticScrollView(message: String) -> NSScrollView {
    let availableHeight = max(96, (NSScreen.main?.visibleFrame.height ?? 800) - 300)
    let height = min(360, availableHeight)
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: height))
    scrollView.borderType = .bezelBorder
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true

    let textView = NSTextView(frame: scrollView.bounds)
    textView.string = message
    textView.isEditable = false
    textView.isSelectable = true
    textView.drawsBackground = false
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.minSize = NSSize(width: 0, height: height)
    textView.maxSize = NSSize(width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
    textView.textContainer?.widthTracksTextView = true
    textView.textContainerInset = NSSize(width: 8, height: 8)
    scrollView.documentView = textView
    return scrollView
}
