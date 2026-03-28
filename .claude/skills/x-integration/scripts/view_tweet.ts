#!/usr/bin/env npx tsx
/**
 * X Integration - View Tweet
 * Usage: echo '{"tweetUrl":"https://x.com/user/status/123","includeReplies":true,"replyCount":10}' | npx tsx view_tweet.ts
 *
 * Navigates to a tweet and extracts its content, metrics, and optionally replies.
 */

import { getBrowserContext, navigateToTweet, checkLogin, runScript, config, ScriptResult } from '../lib/browser.js';

interface ViewTweetInput {
  tweetUrl: string;
  includeReplies?: boolean;
  replyCount?: number;
}

interface TweetData {
  author: string;
  handle: string;
  text: string;
  timestamp: string;
  url: string;
  metrics: {
    replies?: string;
    reposts?: string;
    likes?: string;
  };
}

interface ReplyData {
  author: string;
  handle: string;
  text: string;
  timestamp: string;
  url: string;
}

async function viewTweet(input: ViewTweetInput): Promise<ScriptResult> {
  const { tweetUrl, includeReplies = false } = input;
  const replyCount = Math.min(Math.max(input.replyCount || 10, 1), 50);

  if (!tweetUrl) {
    return { success: false, message: 'Missing tweetUrl' };
  }

  let context = null;
  try {
    context = await getBrowserContext();
    const { page, success, error } = await navigateToTweet(context, tweetUrl);
    if (!success) return { success: false, message: error! };

    const loginError = await checkLogin(page);
    if (loginError) return loginError;

    // The main tweet is the first article on the page
    const mainArticle = page.locator('article[data-testid="tweet"]').first();
    await mainArticle.waitFor({ timeout: config.timeouts.elementWait });

    // Extract author and handle
    const userNameEl = mainArticle.locator('[data-testid="User-Name"]').first();
    const nameSpans = userNameEl.locator('span');
    const author = await nameSpans.first().textContent().catch(() => 'Unknown');
    const handleEl = await userNameEl.locator('a[href^="/"]').nth(1).textContent().catch(() => null)
      || await userNameEl.locator('span:has-text("@")').first().textContent().catch(() => '@unknown');

    // Extract tweet text
    const tweetText = mainArticle.locator('[data-testid="tweetText"]').first();
    const text = await tweetText.textContent().catch(() => '(no text)') || '(no text)';

    // Extract timestamp
    const timeEl = mainArticle.locator('time').first();
    const timestamp = await timeEl.getAttribute('datetime').catch(() => '') || '';

    // Extract URL
    const statusLink = await mainArticle.locator('a[href*="/status/"]').first().getAttribute('href').catch(() => null);
    const url = statusLink ? `https://x.com${statusLink}` : tweetUrl;

    // Extract metrics from action buttons' aria-labels
    const metrics: TweetData['metrics'] = {};

    const replyButton = mainArticle.locator('[data-testid="reply"]').first();
    const replyLabel = await replyButton.getAttribute('aria-label').catch(() => null);
    if (replyLabel) {
      const match = replyLabel.match(/(\d[\d,]*)/);
      if (match) metrics.replies = match[1];
    }

    const retweetButton = mainArticle.locator('[data-testid="retweet"]').first();
    const rtLabel = await retweetButton.getAttribute('aria-label').catch(() => null);
    if (rtLabel) {
      const match = rtLabel.match(/(\d[\d,]*)/);
      if (match) metrics.reposts = match[1];
    }

    // Check both like and unlike (if already liked)
    for (const testId of ['like', 'unlike']) {
      const btn = mainArticle.locator(`[data-testid="${testId}"]`).first();
      const label = await btn.getAttribute('aria-label').catch(() => null);
      if (label) {
        const match = label.match(/(\d[\d,]*)/);
        if (match) { metrics.likes = match[1]; break; }
      }
    }

    const tweet: TweetData = {
      author: author || 'Unknown',
      handle: handleEl || '@unknown',
      text,
      timestamp,
      url,
      metrics,
    };

    // Format main tweet
    let formatted = `${tweet.author} (${tweet.handle})`;
    if (tweet.timestamp) formatted += ` — ${new Date(tweet.timestamp).toLocaleString()}`;
    formatted += `\n${tweet.text}`;

    const metricParts = [];
    if (metrics.replies) metricParts.push(`${metrics.replies} replies`);
    if (metrics.reposts) metricParts.push(`${metrics.reposts} reposts`);
    if (metrics.likes) metricParts.push(`${metrics.likes} likes`);
    if (metricParts.length) formatted += `\n${metricParts.join(' · ')}`;
    formatted += `\n${tweet.url}`;

    if (!includeReplies) {
      return { success: true, message: formatted, data: { tweet, replies: [] } };
    }

    // Load replies — articles after the main tweet
    const replies: ReplyData[] = [];
    const seenUrls = new Set<string>();
    let scrollAttempts = 0;
    const maxScrollAttempts = 5;
    let lastReplyCount = 0;

    await page.waitForTimeout(config.timeouts.pageLoad);

    while (replies.length < replyCount && scrollAttempts < maxScrollAttempts) {
      const articles = page.locator('article[data-testid="tweet"]');
      const articleCount = await articles.count();

      // Skip first article (main tweet)
      for (let i = 1; i < articleCount && replies.length < replyCount; i++) {
        const article = articles.nth(i);

        const replyStatusLink = await article.locator('a[href*="/status/"]').first().getAttribute('href').catch(() => null);
        const replyUrl = replyStatusLink ? `https://x.com${replyStatusLink}` : '';

        if (replyUrl && seenUrls.has(replyUrl)) continue;

        const replyUserNameEl = article.locator('[data-testid="User-Name"]').first();
        const replyNameSpans = replyUserNameEl.locator('span');
        const replyAuthor = await replyNameSpans.first().textContent().catch(() => 'Unknown');
        const replyHandleEl = await replyUserNameEl.locator('a[href^="/"]').nth(1).textContent().catch(() => null)
          || await replyUserNameEl.locator('span:has-text("@")').first().textContent().catch(() => '@unknown');

        const replyText = await article.locator('[data-testid="tweetText"]').first().textContent().catch(() => '(no text)') || '(no text)';
        const replyTime = await article.locator('time').first().getAttribute('datetime').catch(() => '') || '';

        replies.push({
          author: replyAuthor || 'Unknown',
          handle: replyHandleEl || '@unknown',
          text: replyText,
          timestamp: replyTime,
          url: replyUrl,
        });
        if (replyUrl) seenUrls.add(replyUrl);
      }

      if (replies.length >= replyCount) break;

      if (replies.length === lastReplyCount) {
        scrollAttempts++;
      } else {
        scrollAttempts = 0;
        lastReplyCount = replies.length;
      }

      await page.evaluate(() => window.scrollBy(0, window.innerHeight * 2));
      await page.waitForTimeout(1500);
    }

    // Format with replies
    const repliesFormatted = replies.map((r, i) =>
      `  ${i + 1}. ${r.author} (${r.handle}) — ${r.timestamp ? new Date(r.timestamp).toLocaleString() : ''}\n     ${r.text.slice(0, 280)}`
    ).join('\n\n');

    const fullMessage = replies.length > 0
      ? `${formatted}\n\nReplies (${replies.length}):\n\n${repliesFormatted}`
      : `${formatted}\n\nNo replies found.`;

    return { success: true, message: fullMessage, data: { tweet, replies } };

  } finally {
    if (context) await context.close();
  }
}

runScript<ViewTweetInput>(viewTweet);
