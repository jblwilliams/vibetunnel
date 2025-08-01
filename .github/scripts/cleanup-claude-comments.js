#!/usr/bin/env node

/**
 * Script to clean up multiple Claude bot comments on a PR
 * Uses GitHub's minimizeComment mutation for a cleaner UI
 * Keeps only the most recent successful review visible
 * Minimizes outdated comments and deletes error comments
 */

async function cleanupClaudeComments({ github, context, core }) {
  const { owner, repo } = context.repo;
  const issue_number = context.issue.number;

  try {
    // Get all comments on the PR
    const allComments = [];
    let page = 1;
    let hasMore = true;

    while (hasMore) {
      const { data } = await github.rest.issues.listComments({
        owner,
        repo,
        issue_number,
        per_page: 100,
        page
      });

      allComments.push(...data);
      hasMore = data.length === 100;
      page++;
    }

    // Filter Claude bot comments
    const claudeComments = allComments
      .filter(comment => 
        comment.user.login === 'claude[bot]' || 
        comment.user.login === 'claude' ||
        (comment.user.type === 'Bot' && comment.body.includes('Claude'))
      )
      .sort((a, b) => new Date(b.created_at) - new Date(a.created_at));

    if (claudeComments.length <= 1) {
      core.info(`Found ${claudeComments.length} Claude comments, no cleanup needed`);
      return;
    }

    core.info(`Found ${claudeComments.length} Claude comments, cleaning up...`);

    // Categorize comments
    const successfulReviews = [];
    const errorComments = [];
    const statusComments = [];

    for (const comment of claudeComments) {
      if (comment.body.includes('Claude finished') && comment.body.includes('## 📋 Summary')) {
        successfulReviews.push(comment);
      } else if (comment.body.includes('Claude encountered an error')) {
        errorComments.push(comment);
      } else if (comment.body.includes('Claude Code is analyzing')) {
        statusComments.push(comment);
      }
    }

    // Keep the most recent successful review visible
    const commentsToMinimize = [];
    const commentsToDelete = [];
    let keptReview = false;

    if (successfulReviews.length > 0) {
      // Keep the first (most recent) successful review
      keptReview = true;
      commentsToMinimize.push(...successfulReviews.slice(1));
    }

    // Delete all error comments, minimize status comments
    commentsToDelete.push(...errorComments);
    commentsToMinimize.push(...statusComments);

    // If no successful review, keep the most recent non-error comment
    if (!keptReview && claudeComments.length > 0) {
      const nonErrorComments = claudeComments.filter(c => !errorComments.includes(c));
      if (nonErrorComments.length > 0) {
        commentsToMinimize.push(...nonErrorComments.slice(1));
      }
    }

    // Process comments to delete
    for (const comment of commentsToDelete) {
      try {
        await github.rest.issues.deleteComment({
          owner,
          repo,
          comment_id: comment.id
        });
        core.info(`Deleted Claude error comment ${comment.id}`);
      } catch (error) {
        core.warning(`Failed to delete error comment ${comment.id}: ${error.message}`);
      }
    }

    // Process comments to minimize using GraphQL
    for (const comment of commentsToMinimize) {
      try {
        const timestamp = new Date(comment.created_at).toLocaleString();
        const commentType = 
          comment.body.includes('encountered an error') ? 'error' :
          comment.body.includes('is analyzing') ? 'status' :
          comment.body.includes('finished') ? 'review' : 'comment';

        // Use minimizeComment mutation
        const result = await github.graphql(`
          mutation minimizeComment($nodeId: ID!) {
            minimizeComment(input: { 
              subjectId: $nodeId, 
              classifier: OUTDATED 
            }) {
              minimizedComment {
                id
                isMinimized
                minimizedReason
              }
            }
          }
        `, {
          nodeId: comment.node_id
        });

        core.info(`Minimized Claude ${commentType} comment ${comment.id} from ${timestamp}`);
      } catch (error) {
        // Fallback to the original approach if minimization fails
        core.warning(`Failed to minimize comment ${comment.id}, falling back to collapse: ${error.message}`);
        
        try {
          const timestamp = new Date(comment.created_at).toLocaleString();
          const commentType = 
            comment.body.includes('encountered an error') ? 'error' :
            comment.body.includes('is analyzing') ? 'status' :
            comment.body.includes('finished') ? 'review' : 'comment';

          // Collapse the comment using the original approach
          await github.rest.issues.updateComment({
            owner,
            repo,
            comment_id: comment.id,
            body: `<details><summary>Claude ${commentType} from ${timestamp} (outdated - click to expand)</summary>\n\n${comment.body}\n</details>`
          });

          core.info(`Collapsed Claude ${commentType} comment ${comment.id} from ${timestamp} (fallback)`);
        } catch (updateError) {
          // If update also fails, try to delete
          try {
            await github.rest.issues.deleteComment({
              owner,
              repo,
              comment_id: comment.id
            });
            core.info(`Deleted Claude comment ${comment.id} (fallback)`);
          } catch (deleteError) {
            core.warning(`Failed to minimize, update, or delete comment ${comment.id}: ${error.message}`);
          }
        }
      }
    }

    core.info(`Cleanup complete. Deleted ${commentsToDelete.length} error comments, minimized/collapsed ${commentsToMinimize.length} comments`);

  } catch (error) {
    core.error(`Failed to cleanup Claude comments: ${error.message}`);
    throw error;
  }
}

// Export for use in GitHub Actions
module.exports = cleanupClaudeComments;