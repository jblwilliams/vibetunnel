import AppKit
import os.log
import SwiftUI

/// General settings tab for basic app preferences
struct GeneralSettingsView: View {
    @AppStorage("autostart")
    private var autostart = false
    @AppStorage(AppConstants.UserDefaultsKeys.updateChannel)
    private var updateChannelRaw = UpdateChannel.stable.rawValue
    @AppStorage(AppConstants.UserDefaultsKeys.showInDock)
    private var showInDock = true
    @AppStorage(AppConstants.UserDefaultsKeys.preventSleepWhenRunning)
    private var preventSleepWhenRunning = true

    @Environment(ConfigManager.self) private var configManager
    @Environment(SystemPermissionManager.self) private var permissionManager

    @State private var isCheckingForUpdates = false
    @State private var permissionUpdateTrigger = 0

    private let startupManager = StartupManager()
    private let logger = Logger(subsystem: BundleIdentifiers.loggerSubsystem, category: "GeneralSettings")

    var updateChannel: UpdateChannel {
        UpdateChannel(rawValue: updateChannelRaw) ?? .stable
    }

    // MARK: - Helper Properties

    // IMPORTANT: These computed properties ensure the UI always shows current permission state.
    // The permissionUpdateTrigger dependency forces SwiftUI to re-evaluate these properties
    // when permissions change. Without this, the UI would not update when permissions are
    // granted in System Settings while this view is visible.
    private var hasAppleScriptPermission: Bool {
        _ = permissionUpdateTrigger
        return permissionManager.hasPermission(.appleScript)
    }

    private var hasAccessibilityPermission: Bool {
        _ = permissionUpdateTrigger
        return permissionManager.hasPermission(.accessibility)
    }

    var body: some View {
        NavigationStack {
            Form {
                // CLI Installation section
                CLIInstallationSection()

                // Repository section
                RepositorySettingsSection(repositoryBasePath: .init(
                    get: { configManager.repositoryBasePath },
                    set: { configManager.updateRepositoryBasePath($0) }
                ))

                Section {
                    // Launch at Login
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Launch at Login", isOn: launchAtLoginBinding)
                        Text("Automatically start VibeTunnel when you log into your Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Show in Dock
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Show in Dock", isOn: showInDockBinding)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show VibeTunnel icon in the Dock.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("The dock icon is always displayed when the Settings dialog is visible.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Prevent Sleep
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Prevent Sleep When Running", isOn: $preventSleepWhenRunning)
                        Text("Keep your Mac awake while VibeTunnel sessions are active.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Application")
                        .font(.headline)
                }

                // System Permissions section (moved from Security)
                PermissionsSection(
                    hasAppleScriptPermission: hasAppleScriptPermission,
                    hasAccessibilityPermission: hasAccessibilityPermission,
                    permissionManager: permissionManager
                )
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("General Settings")
        }
        .task {
            // Sync launch at login status
            autostart = startupManager.isLaunchAtLoginEnabled
            // Check permissions before first render to avoid UI flashing
            await permissionManager.checkAllPermissions()
        }
        .onAppear {
            // Register for continuous monitoring
            permissionManager.registerForMonitoring()
        }
        .onDisappear {
            permissionManager.unregisterFromMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: .permissionsUpdated)) { _ in
            // Increment trigger to force computed property re-evaluation
            permissionUpdateTrigger += 1
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { autostart },
            set: { newValue in
                autostart = newValue
                startupManager.setLaunchAtLogin(enabled: newValue)
            }
        )
    }

    private var showInDockBinding: Binding<Bool> {
        Binding(
            get: { showInDock },
            set: { newValue in
                showInDock = newValue
                // Don't change activation policy while settings window is open
                // The change will be applied when the settings window closes
            }
        )
    }

    private var updateChannelBinding: Binding<UpdateChannel> {
        Binding(
            get: { updateChannel },
            set: { newValue in
                updateChannelRaw = newValue.rawValue
                // Notify the updater manager about the channel change
                NotificationCenter.default.post(
                    name: Notification.Name("UpdateChannelChanged"),
                    object: nil,
                    userInfo: ["channel": newValue]
                )
            }
        )
    }

    private func checkForUpdates() {
        isCheckingForUpdates = true
        NotificationCenter.default.post(name: Notification.Name("checkForUpdates"), object: nil)

        // Reset after a delay
        Task {
            try? await Task.sleep(for: .seconds(2))
            isCheckingForUpdates = false
        }
    }
}

// MARK: - Permissions Section

private struct PermissionsSection: View {
    let hasAppleScriptPermission: Bool
    let hasAccessibilityPermission: Bool
    let permissionManager: SystemPermissionManager

    var body: some View {
        Section {
            // Automation permission
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Terminal Automation")
                        .font(.body)
                    Text("Required to launch and control terminal applications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if hasAppleScriptPermission {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Granted")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .frame(height: 22) // Match small button height
                    .contextMenu {
                        Button("Refresh Status") {
                            permissionManager.forcePermissionRecheck()
                        }
                        Button("Open System Settings...") {
                            permissionManager.requestPermission(.appleScript)
                        }
                    }
                } else {
                    Button("Grant Permission") {
                        permissionManager.requestPermission(.appleScript)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Accessibility permission
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Accessibility")
                        .font(.body)
                    Text("Required to enter terminal startup commands.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if hasAccessibilityPermission {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Granted")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .frame(height: 22) // Match small button height
                    .contextMenu {
                        Button("Refresh Status") {
                            permissionManager.forcePermissionRecheck()
                        }
                        Button("Open System Settings...") {
                            permissionManager.requestPermission(.accessibility)
                        }
                    }
                } else {
                    Button("Grant Permission") {
                        permissionManager.requestPermission(.accessibility)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        } header: {
            Text("System Permissions")
                .font(.headline)
        } footer: {
            if hasAppleScriptPermission && hasAccessibilityPermission {
                Text(
                    "All permissions granted. VibeTunnel has full functionality."
                )
                .font(.caption)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .foregroundColor(.green)
            } else {
                Text(
                    "Terminals can be captured without permissions, however new sessions won't load."
                )
                .font(.caption)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            }
        }
    }
}
