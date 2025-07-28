/**
 * Git File Watcher Service
 *
 * Monitors git repositories for file changes and broadcasts git status updates via SSE.
 * Simply watches for any file system changes and lets Git determine what's important.
 */

import * as chokidar from 'chokidar';
import type { Response } from 'express';
import { type GitStatusCounts, getDetailedGitStatus } from '../utils/git-status.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('git-watcher');

interface WatcherInfo {
  watcher: chokidar.FSWatcher;
  sessionId: string;
  workingDir: string;
  gitRepoPath: string;
  lastStatus?: GitStatusCounts;
  debounceTimer?: NodeJS.Timeout;
  clients: Set<Response>;
}

export class GitWatcher {
  private watchers = new Map<string, WatcherInfo>();

  /**
   * Start watching git repository for a session
   */
  startWatching(sessionId: string, workingDir: string, gitRepoPath: string): void {
    // Don't create duplicate watchers
    if (this.watchers.has(sessionId)) {
      logger.debug(`Git watcher already exists for session ${sessionId}`);
      return;
    }

    logger.debug(`Starting git watcher for session ${sessionId} at ${gitRepoPath}`);

    // Watch the repository root, but ignore performance-killing directories
    const watcher = chokidar.watch(gitRepoPath, {
      ignoreInitial: true,
      ignored: [
        // Ignore directories that would kill performance
        '**/node_modules/**',
        '**/.git/objects/**', // Git's object database - huge and changes don't matter
        '**/.git/logs/**', // Git's log files - not relevant for status
        '**/dist/**',
        '**/build/**',
        '**/.next/**',
        '**/coverage/**',
        '**/.turbo/**',
        '**/*.log',
      ],
      // Don't follow symlinks to avoid infinite loops
      followSymlinks: false,
      // Use native events for better performance
      usePolling: false,
      // Optimize for performance
      awaitWriteFinish: {
        stabilityThreshold: 200,
        pollInterval: 100,
      },
    });

    const watcherInfo: WatcherInfo = {
      watcher,
      sessionId,
      workingDir,
      gitRepoPath,
      clients: new Set(),
    };

    // Handle any file system change
    const handleChange = (changedPath: string, eventType: string) => {
      // Only log significant events to reduce noise
      const isGitFile = changedPath.includes('.git');
      if (isGitFile || eventType !== 'change') {
        logger.debug(`Git watcher event for session ${sessionId}: ${eventType} ${changedPath}`);
      }

      // Clear existing debounce timer
      if (watcherInfo.debounceTimer) {
        clearTimeout(watcherInfo.debounceTimer);
      }

      // Debounce rapid changes
      watcherInfo.debounceTimer = setTimeout(() => {
        this.checkAndBroadcastStatus(watcherInfo);
      }, 300);
    };

    // Listen to all events
    watcher.on('all', (eventType, path) => handleChange(path, eventType));

    watcher.on('error', (error) => {
      logger.error(`Git watcher error for session ${sessionId}:`, error);
    });

    this.watchers.set(sessionId, watcherInfo);

    // Get initial status
    this.checkAndBroadcastStatus(watcherInfo);
  }

  /**
   * Add a client to receive git status updates
   */
  addClient(sessionId: string, client: Response): void {
    const watcherInfo = this.watchers.get(sessionId);
    if (!watcherInfo) {
      logger.debug(`No git watcher found for session ${sessionId}`);
      return;
    }

    watcherInfo.clients.add(client);
    logger.debug(
      `Added SSE client to git watcher for session ${sessionId} (${watcherInfo.clients.size} total)`
    );

    // Send current status to new client
    if (watcherInfo.lastStatus) {
      this.sendStatusUpdate(client, sessionId, watcherInfo.lastStatus);
    }
  }

  /**
   * Remove a client from git status updates
   */
  removeClient(sessionId: string, client: Response): void {
    const watcherInfo = this.watchers.get(sessionId);
    if (!watcherInfo) {
      return;
    }

    watcherInfo.clients.delete(client);
    logger.debug(
      `Removed SSE client from git watcher for session ${sessionId} (${watcherInfo.clients.size} remaining)`
    );

    // If no more clients, stop watching
    if (watcherInfo.clients.size === 0) {
      this.stopWatching(sessionId);
    }
  }

  /**
   * Stop watching git directory for a session
   */
  stopWatching(sessionId: string): void {
    const watcherInfo = this.watchers.get(sessionId);
    if (!watcherInfo) {
      return;
    }

    logger.debug(`Stopping git watcher for session ${sessionId}`);

    // Clear debounce timer
    if (watcherInfo.debounceTimer) {
      clearTimeout(watcherInfo.debounceTimer);
    }

    // Close watcher
    watcherInfo.watcher.close();

    // Remove from map
    this.watchers.delete(sessionId);
  }

  /**
   * Check git status and broadcast if changed
   */
  private async checkAndBroadcastStatus(watcherInfo: WatcherInfo): Promise<void> {
    try {
      const status = await getDetailedGitStatus(watcherInfo.workingDir);

      // Check if status has changed
      if (this.hasStatusChanged(watcherInfo.lastStatus, status)) {
        logger.debug(`Git status changed for session ${watcherInfo.sessionId}:`, status);
        watcherInfo.lastStatus = status;

        // Broadcast to all clients
        this.broadcastStatusUpdate(watcherInfo, status);
      }
    } catch (error) {
      logger.error(`Failed to get git status for session ${watcherInfo.sessionId}:`, error);
    }
  }

  /**
   * Check if git status has changed
   */
  private hasStatusChanged(
    oldStatus: GitStatusCounts | undefined,
    newStatus: GitStatusCounts
  ): boolean {
    if (!oldStatus) return true;

    return (
      oldStatus.modified !== newStatus.modified ||
      oldStatus.untracked !== newStatus.untracked ||
      oldStatus.staged !== newStatus.staged ||
      oldStatus.ahead !== newStatus.ahead ||
      oldStatus.behind !== newStatus.behind
    );
  }

  /**
   * Broadcast status update to all clients
   */
  private broadcastStatusUpdate(watcherInfo: WatcherInfo, status: GitStatusCounts): void {
    for (const client of watcherInfo.clients) {
      this.sendStatusUpdate(client, watcherInfo.sessionId, status);
    }
  }

  /**
   * Send status update to a specific client
   */
  private sendStatusUpdate(client: Response, sessionId: string, status: GitStatusCounts): void {
    try {
      const event = {
        type: 'git-status-update',
        sessionId,
        gitModifiedCount: status.modified,
        gitUntrackedCount: status.untracked,
        gitStagedCount: status.staged,
        gitAheadCount: status.ahead,
        gitBehindCount: status.behind,
      };

      client.write(`event: session-update\ndata: ${JSON.stringify(event)}\n\n`);
    } catch (error) {
      logger.error(`Failed to send git status update to client:`, error);
    }
  }

  /**
   * Clean up all watchers
   */
  cleanup(): void {
    logger.debug('Cleaning up all git watchers');
    for (const [sessionId] of this.watchers) {
      this.stopWatching(sessionId);
    }
  }
}

// Export singleton instance
export const gitWatcher = new GitWatcher();
