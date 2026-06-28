//
//  PinCreationView.swift
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

struct PinCreationView: View {
    let bottle: Bottle

    @State private var selectedProgram: Program?
    @State private var newPinName: String = ""
    @State private var isDuplicate: Bool = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if installedPrograms.isEmpty {
                    ContentUnavailableView {
                        Label("No installed apps yet", systemImage: "app.dashed")
                    } description: {
                        Text("Install a Windows app into this bottle before pinning it for quick access.")
                    }
                } else {
                    Picker("Installed app", selection: $selectedProgram) {
                        Text("Choose an app").tag(nil as Program?)
                        ForEach(installedPrograms, id: \.url) { program in
                            Text(program.name).tag(program as Program?)
                        }
                    }
                    TextField("Pin name", text: $newPinName)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Pin installed app")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("create.cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Pin app") {
                        submit()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newPinName.isEmpty || selectedProgram == nil)
                    .alert("pin.error.title", isPresented: $isDuplicate) {
                    } message: {
                        Text("This app is already pinned.")
                    }
                }
            }
            .onAppear {
                bottle.updateInstalledPrograms()
            }
            .onChange(of: selectedProgram) { _, program in
                guard let program else { return }
                newPinName = program.name
            }
            .onSubmit {
                submit()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: ViewWidth.small)
    }

    func submit() {
        guard let selectedProgram else { return }

        // Ensure this pin doesn't already exist
        guard !bottle.settings.pins.contains(where: { $0.url == selectedProgram.url })
        else {
            isDuplicate = true
            return
        }

        bottle.settings.pins.append(PinnedProgram(name: newPinName, url: selectedProgram.url))

        // Trigger a reload
        bottle.updateInstalledPrograms()
        dismiss()
    }

    private var installedPrograms: [Program] {
        bottle.programs
            .filter { FileManager.default.fileExists(atPath: $0.url.path(percentEncoded: false)) }
            .sorted { $0.name < $1.name }
    }
}

#Preview {
    PinCreationView(bottle: Bottle(bottleUrl: URL(filePath: "")))
}
