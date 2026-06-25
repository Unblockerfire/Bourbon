//
//  BottleCreationView.swift
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

struct BottleCreationView: View {
    @Binding var newlyCreatedBottleURL: URL?

    @State private var newBottleName: String = ""
    @State private var newBottleVersion: WinVersion = .win10
    @State private var newBottleURL: URL = UserDefaults.standard.url(forKey: "defaultBottleLocation")
                                           ?? BottleData.defaultBottleDir
    @State private var nameValid: Bool = false
    @State private var missingDependencies: [Wine.RuntimeDependency] = Wine
        .missingRuntimeDependencies(requiredOnly: false)

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("create.name", text: $newBottleName)
                    .onChange(of: newBottleName) { _, name in
                        nameValid = !name.isEmpty
                    }

                Picker("create.win", selection: $newBottleVersion) {
                    ForEach(WinVersion.allCases.reversed(), id: \.self) {
                        Text($0.pretty())
                    }
                }

                ActionView(
                    text: "create.path",
                    subtitle: newBottleURL.prettyPath(),
                    actionName: "create.browse"
                ) {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = true
                    panel.directoryURL = BottleData.containerDir
                    panel.begin { result in
                        if result == .OK, let url = panel.urls.first {
                            newBottleURL = url
                        }
                    }
                }

                if !missingDependencies.isEmpty {
                    Section {
                        ForEach(missingDependencies) { dependency in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(dependency.displayName)
                                    .font(.headline)
                                Text(dependency.required ? "Required" : "Optional")
                                    .font(.caption)
                                    .foregroundStyle(dependency.required ? .red : .secondary)
                                Text(dependency.reason)
                                    .foregroundStyle(.secondary)
                                Text(dependency.installHint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 4)
                        }

                        Button("Re-check Dependencies") {
                            missingDependencies = Wine.missingRuntimeDependencies(requiredOnly: false)
                        }
                    } header: {
                        Text("Wine Runtime Dependencies")
                    } footer: {
                        Text(runtimeDependencyFooter)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("create.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("create.cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("create.create") {
                        submit()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!nameValid || hasMissingRequiredDependencies)
                }
            }
            .onSubmit {
                if nameValid && !hasMissingRequiredDependencies {
                    submit()
                }
            }
            .onAppear {
                missingDependencies = Wine.missingRuntimeDependencies(requiredOnly: false)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: ViewWidth.small)
    }

    func submit() {
        newlyCreatedBottleURL = BottleVM.shared.createNewBottle(bottleName: newBottleName,
                                                                winVersion: newBottleVersion,
                                                                bottleURL: newBottleURL)
        dismiss()
    }

    private var hasMissingRequiredDependencies: Bool {
        missingDependencies.contains(where: \.required)
    }

    private var runtimeDependencyFooter: String {
        if hasMissingRequiredDependencies {
            return "Bottle creation is blocked until required Wine runtime dependencies are available."
        }
        return "These optional Wine runtime dependencies are not currently bundled. Bottle creation can continue."
    }
}

#Preview {
    BottleCreationView(newlyCreatedBottleURL: .constant(nil))
}
