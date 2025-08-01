import Foundation
import Observation
import OSLog

// MARK: - Logger

extension Logger {
    fileprivate static let repositoryDiscovery = Logger(
        subsystem: BundleIdentifiers.loggerSubsystem,
        category: "RepositoryDiscovery"
    )
}

// MARK: - FileSystemScanner

/// Actor to handle file system operations off the main thread
private actor FileSystemScanner {
    /// Scan directory contents
    func scanDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsSubdirectoryDescendants]
        )
    }

    /// Check if path is readable
    func isReadable(at path: String) -> Bool {
        FileManager.default.isReadableFile(atPath: path)
    }

    /// Check if Git repository exists
    func isGitRepository(at path: String) -> Bool {
        let gitPath = URL(fileURLWithPath: path).appendingPathComponent(".git").path
        return FileManager.default.fileExists(atPath: gitPath)
    }

    /// Get modification date for a file
    func getModificationDate(at path: String) throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        return attributes[.modificationDate] as? Date ?? Date.distantPast
    }

    /// Get directory and hidden status for URL
    func getDirectoryStatus(for url: URL) throws -> (isDirectory: Bool, isHidden: Bool) {
        let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
        return (
            isDirectory: resourceValues.isDirectory ?? false,
            isHidden: resourceValues.isHidden ?? false
        )
    }
}

/// Service for discovering Git repositories in a specified directory
///
/// Provides functionality to scan a base directory for Git repositories and
/// return them in a format suitable for display in the New Session form.
/// Includes caching and performance optimizations for large directory trees.
@MainActor
@Observable
public final class RepositoryDiscoveryService {
    // MARK: - Properties

    /// Published array of discovered repositories
    public private(set) var repositories: [DiscoveredRepository] = []

    /// Whether discovery is currently in progress
    public private(set) var isDiscovering = false

    /// Last error encountered during discovery
    public private(set) var lastError: String?

    /// Cache of discovered repositories by base path
    private var repositoryCache: [String: [DiscoveredRepository]] = [:]

    /// Maximum depth to search for repositories (prevents infinite recursion)
    private let maxSearchDepth = 3

    /// File system scanner actor for background operations
    private let fileScanner = FileSystemScanner()

    // MARK: - Lifecycle

    public init() {}

    // MARK: - Public Methods

    /// Discover repositories in the specified base path
    /// - Parameter basePath: The base directory to search (supports ~ expansion)
    public func discoverRepositories(in basePath: String) async {
        guard !isDiscovering else {
            Logger.repositoryDiscovery.debug("Discovery already in progress, skipping")
            return
        }

        isDiscovering = true
        lastError = nil

        let expandedPath = NSString(string: basePath).expandingTildeInPath
        Logger.repositoryDiscovery.info("Starting repository discovery in: \(expandedPath)")

        // Check cache first
        if let cachedRepositories = repositoryCache[expandedPath] {
            Logger.repositoryDiscovery.debug("Using cached repositories for path: \(expandedPath)")
            repositories = cachedRepositories
            isDiscovering = false
            return
        }

        let discoveredRepos = await self.performDiscovery(in: expandedPath)

        self.isDiscovering = false

        // Cache and update results
        self.repositoryCache[expandedPath] = discoveredRepos
        self.repositories = discoveredRepos

        Logger.repositoryDiscovery.info("Discovered \(discoveredRepos.count) repositories in: \(expandedPath)")
    }

    /// Clear the repository cache
    public func clearCache() {
        repositoryCache.removeAll()
        Logger.repositoryDiscovery.debug("Repository cache cleared")
    }

    // MARK: - Private Methods

    /// Perform the actual discovery work
    private func performDiscovery(in basePath: String) async -> [DiscoveredRepository] {
        // Move the heavy file system work to a background actor
        let allRepositories = await Task.detached(priority: .userInitiated) {
            await self.scanDirectory(basePath, depth: 0)
        }.value

        // Sort by folder name for consistent display
        return allRepositories.sorted { $0.folderName < $1.folderName }
    }

    /// Recursively scan a directory for Git repositories
    private func scanDirectory(_ path: String, depth: Int) async -> [DiscoveredRepository] {
        guard depth < maxSearchDepth else {
            Logger.repositoryDiscovery.debug("Max depth reached at: \(path)")
            return []
        }

        guard !Task.isCancelled else {
            return []
        }

        do {
            let url = URL(fileURLWithPath: path)

            // Check if directory is accessible using actor
            guard await fileScanner.isReadable(at: path) else {
                Logger.repositoryDiscovery.debug("Directory not readable: \(path)")
                return []
            }

            // Get directory contents using actor
            let contents = try await fileScanner.scanDirectory(at: url)

            var repositories: [DiscoveredRepository] = []

            for itemURL in contents {
                let (isDirectory, isHidden) = try await fileScanner.getDirectoryStatus(for: itemURL)

                // Skip files and hidden directories (except .git)
                guard isDirectory else { continue }
                if isHidden && itemURL.lastPathComponent != ".git" {
                    continue
                }

                let itemPath = itemURL.path

                // Check if this directory is a Git repository using actor
                if await fileScanner.isGitRepository(at: itemPath) {
                    let repository = await createDiscoveredRepository(at: itemPath)
                    repositories.append(repository)
                } else {
                    // Recursively scan subdirectories
                    let subdirectoryRepos = await scanDirectory(itemPath, depth: depth + 1)
                    repositories.append(contentsOf: subdirectoryRepos)
                }
            }

            return repositories
        } catch {
            Logger.repositoryDiscovery.error("Error scanning directory \(path): \(error)")
            return []
        }
    }

    /// Create a DiscoveredRepository from a path
    private func createDiscoveredRepository(at path: String) async -> DiscoveredRepository {
        let url = URL(fileURLWithPath: path)
        let folderName = url.lastPathComponent

        // Get last modified date
        let lastModified = await getLastModifiedDate(at: path)

        // Get GitHub URL in parallel (this might be slow)
        async let githubURL = Task.detached(priority: .background) {
            GitRepository.getGitHubURL(for: path)
        }.value

        return await DiscoveredRepository(
            path: path,
            folderName: folderName,
            lastModified: lastModified,
            githubURL: githubURL
        )
    }

    /// Get the last modified date of a repository
    private func getLastModifiedDate(at path: String) async -> Date {
        do {
            return try await fileScanner.getModificationDate(at: path)
        } catch {
            Logger.repositoryDiscovery.debug("Could not get modification date for \(path): \(error)")
            return Date.distantPast
        }
    }
}

// MARK: - DiscoveredRepository

/// A lightweight repository representation for discovery purposes
public struct DiscoveredRepository: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let path: String
    public let folderName: String
    public let lastModified: Date
    public let githubURL: URL?

    /// Display name for the repository
    public var displayName: String {
        folderName
    }

    /// Relative path from home directory if applicable
    public var relativePath: String {
        let homeDir = NSHomeDirectory()
        if path.hasPrefix(homeDir) {
            return "~" + path.dropFirst(homeDir.count)
        }
        return path
    }

    /// Formatted last modified date
    public var formattedLastModified: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: lastModified)
    }
}
