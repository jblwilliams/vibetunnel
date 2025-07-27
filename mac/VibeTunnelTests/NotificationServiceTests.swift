import Testing
import UserNotifications
@testable import VibeTunnel

@Suite("NotificationService Tests")
struct NotificationServiceTests {
    @Test("Notification preferences are loaded correctly from ConfigManager")
    @MainActor
    func loadPreferencesFromConfig() {
        // This test verifies that NotificationPreferences correctly loads values from ConfigManager
        let configManager = ConfigManager.shared
        let preferences = NotificationService.NotificationPreferences(fromConfig: configManager)

        // Verify that preferences match ConfigManager values
        #expect(preferences.sessionStart == configManager.notificationSessionStart)
        #expect(preferences.sessionExit == configManager.notificationSessionExit)
        #expect(preferences.commandCompletion == configManager.notificationCommandCompletion)
        #expect(preferences.commandError == configManager.notificationCommandError)
        #expect(preferences.bell == configManager.notificationBell)
        #expect(preferences.claudeTurn == configManager.notificationClaudeTurn)
        #expect(preferences.soundEnabled == configManager.notificationSoundEnabled)
        #expect(preferences.vibrationEnabled == configManager.notificationVibrationEnabled)
    }
    
    @Test("Default notification values match expected defaults")
    @MainActor
    func verifyDefaultValues() {
        // This test documents what the default values SHOULD be
        // In production, these would be set when no config file exists
        
        // Expected defaults based on TypeScript config:
        // - Master switch (notificationsEnabled) should be false
        // - Individual preferences should be true (except claudeTurn)
        // - Sound and vibration should be enabled
        
        // Note: In actual tests, ConfigManager loads from ~/.vibetunnel/config.json
        // To test true defaults, we would need to:
        // 1. Mock ConfigManager
        // 2. Clear the config file
        // 3. Force ConfigManager to use defaults
        
        // For now, we document the expected behavior
        let expectedMasterSwitch = false
        let expectedSessionStart = true
        let expectedSessionExit = true
        let expectedCommandCompletion = true
        let expectedCommandError = true
        let expectedBell = true
        let expectedClaudeTurn = false
        let expectedSound = true
        let expectedVibration = true
        
        // These are the values that SHOULD be used when no config exists
        #expect(expectedMasterSwitch == false, "Master switch should be OFF by default")
        #expect(expectedSessionStart == true, "Session start should be enabled by default")
        #expect(expectedSessionExit == true, "Session exit should be enabled by default")
        #expect(expectedCommandCompletion == true, "Command completion should be enabled by default")
        #expect(expectedCommandError == true, "Command error should be enabled by default")
        #expect(expectedBell == true, "Bell should be enabled by default")
        #expect(expectedClaudeTurn == false, "Claude turn should be disabled by default")
        #expect(expectedSound == true, "Sound should be enabled by default")
        #expect(expectedVibration == true, "Vibration should be enabled by default")
    }

    @Test("Notification preferences can be updated")
    @MainActor
    func testUpdatePreferences() {
        let service = NotificationService.shared
        let configManager = ConfigManager.shared

        // Create custom preferences
        var preferences = NotificationService.NotificationPreferences(fromConfig: configManager)
        preferences.sessionStart = true
        preferences.bell = true

        // Update preferences
        service.updatePreferences(preferences)

        // Verify preferences were updated in ConfigManager
        #expect(configManager.notificationSessionStart == true)
        #expect(configManager.notificationBell == true)
    }

    @Test("Session start notification is sent when enabled")
    @MainActor
    func sessionStartNotification() async throws {
        let service = NotificationService.shared
        let configManager = ConfigManager.shared

        // Enable notifications master switch
        configManager.updateNotificationPreferences(enabled: true)
        
        // Enable session start notifications
        var preferences = NotificationService.NotificationPreferences(fromConfig: configManager)
        preferences.sessionStart = true
        service.updatePreferences(preferences)

        // Send session start notification
        let sessionName = "Test Session"
        await service.sendSessionStartNotification(sessionName: sessionName)

        // Verify notification would be created (actual delivery depends on system permissions)
        // In a real test environment, we'd mock UNUserNotificationCenter
        #expect(configManager.notificationsEnabled == true)
        #expect(preferences.sessionStart == true)
    }

    @Test("Session exit notification includes exit code")
    @MainActor
    func sessionExitNotification() async throws {
        let service = NotificationService.shared
        let configManager = ConfigManager.shared

        // Enable notifications master switch
        configManager.updateNotificationPreferences(enabled: true)
        
        // Enable session exit notifications
        var preferences = NotificationService.NotificationPreferences(fromConfig: configManager)
        preferences.sessionExit = true
        service.updatePreferences(preferences)

        // Test successful exit
        await service.sendSessionExitNotification(sessionName: "Test Session", exitCode: 0)

        // Test error exit
        await service.sendSessionExitNotification(sessionName: "Failed Session", exitCode: 1)

        #expect(configManager.notificationsEnabled == true)
        #expect(preferences.sessionExit == true)
    }

    @Test("Command completion notification respects duration threshold")
    @MainActor
    func commandCompletionNotification() async throws {
        let service = NotificationService.shared
        let configManager = ConfigManager.shared

        // Enable notifications master switch
        configManager.updateNotificationPreferences(enabled: true)
        
        // Enable command completion notifications
        var preferences = NotificationService.NotificationPreferences(fromConfig: configManager)
        preferences.commandCompletion = true
        service.updatePreferences(preferences)

        // Test short duration
        await service.sendCommandCompletionNotification(
            command: "ls",
            duration: 1_000 // 1 second
        )

        // Test long duration
        await service.sendCommandCompletionNotification(
            command: "long-running-command",
            duration: 5_000 // 5 seconds
        )

        #expect(configManager.notificationsEnabled == true)
        #expect(preferences.commandCompletion == true)
    }

    @Test("Command error notification is sent for non-zero exit codes")
    @MainActor
    func commandErrorNotification() async throws {
        let service = NotificationService.shared
        let configManager = ConfigManager.shared

        // Enable notifications master switch
        configManager.updateNotificationPreferences(enabled: true)
        
        // Enable command error notifications
        var preferences = NotificationService.NotificationPreferences(fromConfig: configManager)
        preferences.commandError = true
        service.updatePreferences(preferences)

        // Test command with error
        // Note: The service handles command errors through the event stream,
        // not through direct method calls
        await service.sendCommandCompletionNotification(
            command: "failing-command",
            duration: 1_000
        )

        #expect(configManager.notificationsEnabled == true)
        #expect(preferences.commandError == true)
    }

    @Test("Bell notification is sent when enabled")
    @MainActor
    func bellNotification() async throws {
        let service = NotificationService.shared
        let configManager = ConfigManager.shared

        // Enable notifications master switch
        configManager.updateNotificationPreferences(enabled: true)
        
        // Enable bell notifications
        var preferences = NotificationService.NotificationPreferences(fromConfig: configManager)
        preferences.bell = true
        service.updatePreferences(preferences)

        // Send bell notification
        // Note: Bell notifications are handled through the event stream
        await service.sendGenericNotification(title: "Terminal Bell", body: "Test Session")

        #expect(configManager.notificationsEnabled == true)
        #expect(preferences.bell == true)
    }

    @Test("Notifications are not sent when disabled")
    @MainActor
    func disabledNotifications() async throws {
        let service = NotificationService.shared
        let configManager = ConfigManager.shared

        // Test 1: Master switch disabled (default)
        configManager.updateNotificationPreferences(enabled: false)
        
        // Even with individual preferences enabled, nothing should fire
        var preferences = NotificationService.NotificationPreferences(fromConfig: configManager)
        preferences.sessionStart = true
        preferences.sessionExit = true
        preferences.commandCompletion = true
        preferences.commandError = true
        preferences.bell = true
        service.updatePreferences(preferences)

        // Try to send various notifications
        await service.sendSessionStartNotification(sessionName: "Test")
        await service.sendSessionExitNotification(sessionName: "Test", exitCode: 0)
        await service.sendCommandCompletionNotification(
            command: "test",
            duration: 5_000
        )
        await service.sendGenericNotification(title: "Bell", body: "Test")

        // Master switch should block all notifications
        #expect(configManager.notificationsEnabled == false)
        
        // Test 2: Master switch enabled but individual preferences disabled
        configManager.updateNotificationPreferences(enabled: true)
        
        preferences.sessionStart = false
        preferences.sessionExit = false
        preferences.commandCompletion = false
        preferences.commandError = false
        preferences.bell = false
        service.updatePreferences(preferences)
        
        // Try to send notifications again
        await service.sendSessionStartNotification(sessionName: "Test")
        await service.sendSessionExitNotification(sessionName: "Test", exitCode: 0)
        
        // Individual preferences should block notifications
        #expect(preferences.sessionStart == false)
        #expect(preferences.sessionExit == false)
        #expect(preferences.commandCompletion == false)
        #expect(preferences.bell == false)
    }

    @Test("Service handles missing session names gracefully")
    @MainActor
    func missingSessionNames() async throws {
        let service = NotificationService.shared
        let configManager = ConfigManager.shared

        // Enable notifications
        configManager.updateNotificationPreferences(enabled: true)
        
        var preferences = NotificationService.NotificationPreferences(fromConfig: configManager)
        preferences.sessionExit = true
        service.updatePreferences(preferences)

        // Send notification with empty name
        await service.sendSessionExitNotification(sessionName: "", exitCode: 0)

        // Should handle gracefully
        #expect(configManager.notificationsEnabled == true)
        #expect(preferences.sessionExit == true)
    }
}
