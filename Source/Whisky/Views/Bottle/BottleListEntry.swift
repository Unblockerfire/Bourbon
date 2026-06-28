//
//  BottleListEntry.swift
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
import WhiskyKit

struct BottleListEntry: View {
    let bottle: Bottle
    @Binding var selected: URL?
    @Binding var refresh: Bool

    @State private var showBottleRename: Bool = false
    @State private var name: String = ""

    var body: some View {
        Text(name)
            .opacity(bottle.isAvailable ? 1.0 : 0.5)
            .onChange(of: refresh, initial: true) {
                name = bottle.settings.name
            }
            .sheet(isPresented: $showBottleRename) {
                RenameView("rename.bottle.title", name: name) { newName in
                    name = newName
                    bottle.rename(newName: newName)
                }
            }
            .contextMenu {
                Button("Rename Bottle", systemImage: "pencil.line") {
                    showBottleRename.toggle()
                }
                .disabled(!bottle.isAvailable)
                .labelStyle(.titleAndIcon)
                Button("Show in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([bottle.url])
                }
                .disabled(!bottle.isAvailable)
                .labelStyle(.titleAndIcon)
                Button("Delete Bottle", systemImage: "trash") {
                    showDeleteAlert(bottle: bottle)
                }
                .disabled(!bottle.isAvailable)
                .labelStyle(.titleAndIcon)
            }
    }

    func showDeleteAlert(bottle: Bottle) {
        let alert = NSAlert()
        alert.messageText = "Delete Bottle?"
        alert.informativeText = """
        This will permanently delete this bottle and its installed apps. This cannot be undone.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        let delete = alert.addButton(withTitle: "Delete Bottle")
        delete.hasDestructiveAction = true

        if alert.runModal() == .alertSecondButtonReturn {
            Task(priority: .userInitiated) {
                let deletedURL = bottle.url
                await bottle.remove(delete: true)
                await selectBottleAfterDeleting(deletedURL)
            }
        }
    }

    @MainActor
    private func selectBottleAfterDeleting(_ deletedURL: URL) {
        guard selected == deletedURL else { return }
        selected = BottleVM.shared.bottles.first(where: { $0.isAvailable })?.url
    }
}

#Preview {
    BottleListEntry(
        bottle: Bottle(bottleUrl: URL(filePath: "")),
        selected: .constant(nil),
        refresh: .constant(false)
    )
}
