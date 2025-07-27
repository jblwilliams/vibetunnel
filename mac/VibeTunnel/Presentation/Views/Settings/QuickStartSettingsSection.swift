import AppKit
import SwiftUI

/// Settings section for managing quick start commands
struct QuickStartSettingsSection: View {
    @Environment(ConfigManager.self) private var configManager
    @State private var selection = Set<QuickStartCommand.ID>()
    @State private var editingCommand: QuickStartCommand?
    @State private var editingName = ""
    @State private var editingCommandText = ""
    @FocusState private var focusedField: Field?
    @FocusState private var isTableFocused: Bool

    private enum Field: Hashable {
        case name
        case command
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                // Native table view
                Table(configManager.quickStartCommands, selection: $selection) {
                    TableColumn("Name") { command in
                        Group {
                            if editingCommand?.id == command.id {
                                TextField("", text: $editingName)
                                    .textFieldStyle(.plain)
                                    .padding(.horizontal, -3) // Compensate for TextField's internal padding
                                    .focused($focusedField, equals: .name)
                                    .onSubmit {
                                        saveEdit()
                                    }
                                    .onExitCommand {
                                        cancelEdit()
                                    }
                            } else {
                                Text(command.displayName)
                                    .onTapGesture(count: 2) {
                                        startEditing(command)
                                    }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .width(min: 100, ideal: 150, max: 200)

                    TableColumn("Command") { command in
                        Group {
                            if editingCommand?.id == command.id {
                                TextField("", text: $editingCommandText)
                                    .textFieldStyle(.plain)
                                    .font(.system(.body, design: .monospaced))
                                    .padding(.horizontal, -3) // Compensate for TextField's internal padding
                                    .focused($focusedField, equals: .command)
                                    .onSubmit {
                                        saveEdit()
                                    }
                                    .onExitCommand {
                                        cancelEdit()
                                    }
                            } else {
                                Text(command.command)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .onTapGesture(count: 2) {
                                        startEditing(command)
                                    }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .frame(minHeight: 200)
                .focused($isTableFocused)
                .onDeleteCommand {
                    deleteSelected()
                }
                .onKeyPress(.return) {
                    // Don't handle return if we're already editing
                    if editingCommand != nil {
                        return .ignored
                    }

                    if let selectedId = selection.first,
                       let command = configManager.quickStartCommands.first(where: { $0.id == selectedId })
                    {
                        startEditing(command)
                        return .handled
                    }
                    return .ignored
                }

                // Action buttons
                HStack(spacing: 8) {
                    // Add/Remove buttons
                    HStack(spacing: 4) {
                        Button(action: addCommand) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.accessoryBar)

                        Button(action: deleteSelected) {
                            ZStack {
                                // Invisible plus to match the size
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .medium))
                                    .opacity(0)
                                // Visible minus
                                Image(systemName: "minus")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.accessoryBar)
                        .disabled(selection.isEmpty)
                    }

                    Spacer()

                    Button("Reset to Defaults") {
                        resetToDefaults()
                    }
                    .buttonStyle(.link)
                }
            }
        } header: {
            Text("Quick Start Commands")
                .font(.headline)
        } footer: {
            Text("Commands shown in the new session form for quick access.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    private func startEditing(_ command: QuickStartCommand) {
        editingCommand = command
        // Use displayName to handle cases where name is nil
        editingName = command.name ?? command.command
        editingCommandText = command.command

        // Focus the name field after a brief delay to ensure the TextField is rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedField = .name
        }
    }

    private func saveEdit() {
        guard let command = editingCommand else { return }

        let trimmedName = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = editingCommandText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedCommand.isEmpty {
            // If name equals command, save as nil (no custom name needed)
            let finalName = (trimmedName.isEmpty || trimmedName == trimmedCommand) ? nil : trimmedName

            configManager.updateCommand(
                id: command.id,
                name: finalName,
                command: trimmedCommand
            )
        }

        editingCommand = nil
        editingName = ""
        editingCommandText = ""
        focusedField = nil

        // Restore focus to table after editing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isTableFocused = true
        }
    }

    private func cancelEdit() {
        editingCommand = nil
        editingName = ""
        editingCommandText = ""
        focusedField = nil

        // Restore focus to table after canceling
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isTableFocused = true
        }
    }

    private func addCommand() {
        let newCommand = QuickStartCommand(
            name: nil,
            command: "new-command"
        )
        configManager.addCommand(name: newCommand.name, command: newCommand.command)

        // Start editing the new command immediately
        if let addedCommand = configManager.quickStartCommands.last {
            startEditing(addedCommand)
        }
    }

    private func deleteSelected() {
        for id in selection {
            configManager.deleteCommand(id: id)
        }
        selection.removeAll()
    }

    private func resetToDefaults() {
        configManager.resetToDefaults()
        selection.removeAll()
        editingCommand = nil
    }
}
