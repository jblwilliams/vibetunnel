import Foundation
import OSLog
import UserNotifications

/// Handles notification control messages via the unified control socket
@MainActor
final class NotificationControlHandler {
    private let logger = Logger(subsystem: "sh.vibetunnel.vibetunnel", category: "NotificationControl")

    // MARK: - Singleton

    static let shared = NotificationControlHandler()

    // MARK: - Properties

    private let notificationService = NotificationService.shared

    // MARK: - Initialization

    private init() {
        // Register handler with the shared socket manager for notification category
        SharedUnixSocketManager.shared.registerControlHandler(for: .notification) { [weak self] data in
            _ = await self?.handleMessage(data)
            return nil // No response needed for notifications
        }
        
        // Also register for session-monitor category
        SharedUnixSocketManager.shared.registerControlHandler(for: .sessionMonitor) { [weak self] data in
            _ = await self?.handleSessionMonitorMessage(data)
            return nil // No response needed for events
        }

        logger.info("NotificationControlHandler initialized for notification and session-monitor categories")
    }

    // MARK: - Message Handling

    private func handleMessage(_ data: Data) async -> Data? {
        do {
            // First decode just to get the action
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let action = json["action"] as? String
            {
                switch action {
                case "show":
                    return await handleShowNotification(json)
                default:
                    logger.warning("Unknown notification action: \(action)")
                }
            }
        } catch {
            logger.error("Failed to decode notification message: \(error)")
        }

        return nil
    }

    private func handleShowNotification(_ json: [String: Any]) async -> Data? {
        guard let payload = json["payload"] as? [String: Any],
              let title = payload["title"] as? String,
              let body = payload["body"] as? String
        else {
            logger.error("Notification message missing required fields")
            return nil
        }

        // Try to parse as ServerEvent-compatible structure
        let typeString = payload["type"] as? String
        let sessionId = payload["sessionId"] as? String
        let sessionName = payload["sessionName"] as? String
        let exitCode = payload["exitCode"] as? Int
        let duration = payload["duration"] as? Int
        let command = payload["command"] as? String

        logger.info("Received notification: \(title) - \(body) (type: \(typeString ?? "unknown"))")

        // Map type string to ServerEventType and create ServerEvent
        if let typeString,
           let eventType = ServerEventType(rawValue: typeString)
        {
            let serverEvent = ServerEvent(
                type: eventType,
                sessionId: sessionId,
                sessionName: sessionName ?? title,
                command: command,
                exitCode: exitCode,
                duration: duration,
                message: body
            )

            // Use the consolidated notification method
            await notificationService.sendNotification(for: serverEvent)
        } else {
            // Unknown event type - log and ignore
            logger.warning("Unknown event type '\(typeString ?? "nil")' - ignoring notification request")
        }

        return nil
    }
    
    // MARK: - Session Monitor Message Handling
    
    private func handleSessionMonitorMessage(_ data: Data) async -> Data? {
        do {
            // Decode the control message
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let action = json["action"] as? String,
               let payload = json["payload"] as? [String: Any]
            {
                logger.debug("Received session-monitor event: \(action)")
                
                // Check if notifications are enabled
                guard ConfigManager.shared.notificationsEnabled else {
                    logger.debug("Notifications disabled, ignoring session-monitor event")
                    return nil
                }
                
                // Map action to notification preference check
                let shouldNotify = switch action {
                case "session-start": ConfigManager.shared.notificationSessionStart
                case "session-exit": ConfigManager.shared.notificationSessionExit
                case "command-finished": ConfigManager.shared.notificationCommandCompletion
                case "command-error": ConfigManager.shared.notificationCommandError
                case "bell": ConfigManager.shared.notificationBell
                case "claude-turn": ConfigManager.shared.notificationClaudeTurn
                default: false
                }
                
                guard shouldNotify else {
                    logger.debug("Notification type \(action) disabled by user preference")
                    return nil
                }
                
                // Extract common fields
                let sessionId = payload["sessionId"] as? String
                let sessionName = payload["sessionName"] as? String ?? "Session"
                let timestamp = payload["timestamp"] as? String
                
                // Map to ServerEventType
                let eventType: ServerEventType? = switch action {
                case "session-start": .sessionStart
                case "session-exit": .sessionExit
                case "command-finished": .commandFinished
                case "command-error": .commandError
                case "bell": .bell
                case "claude-turn": .claudeTurn
                default: nil
                }
                
                guard let eventType else {
                    logger.warning("Unknown session-monitor action: \(action)")
                    return nil
                }
                
                // Extract event-specific fields
                let exitCode = payload["exitCode"] as? Int
                let command = payload["command"] as? String
                let duration = payload["duration"] as? Int
                
                // Create message based on event type
                let message: String? = switch eventType {
                case .claudeTurn: "Claude has finished responding"
                default: nil
                }
                
                // Parse timestamp if provided, otherwise use current date
                let eventDate: Date
                if let timestamp {
                    let formatter = ISO8601DateFormatter()
                    eventDate = formatter.date(from: timestamp) ?? Date()
                } else {
                    eventDate = Date()
                }
                
                // Create ServerEvent
                let serverEvent = ServerEvent(
                    type: eventType,
                    sessionId: sessionId,
                    sessionName: sessionName,
                    command: command,
                    exitCode: exitCode,
                    duration: duration,
                    message: message,
                    timestamp: eventDate
                )
                
                // Send notification
                await notificationService.sendNotification(for: serverEvent)
                
                logger.info("Processed session-monitor event: \(action) for session: \(sessionName)")
            }
        } catch {
            logger.error("Failed to decode session-monitor message: \(error)")
        }
        
        return nil
    }
}

// MARK: - Supporting Types

/// Notification payload that can be converted to ServerEvent
private struct NotificationPayload: Codable {
    let title: String
    let body: String
    let type: String?
    let sessionId: String?
    let sessionName: String?
    let command: String?
    let exitCode: Int?
    let duration: Int?
}
