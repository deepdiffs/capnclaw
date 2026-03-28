#!/usr/bin/env npx tsx
/**
 * X Integration - Read Bookmarks
 * Usage: echo '{"count":10}' | npx tsx bookmarks.ts
 *
 * Scrolls the bookmarks page and extracts tweet data.
 * Default: 10 bookmarks. Pass a higher count to fetch more.
 */

import { getBrowserContext, checkLogin, runScript, config, ScriptResult } from '../lib/browser.js';

interface BookmarksInput {
  count?: number;
}

interface BookmarkTweet {
  author: string;
  handle: string;
  text: string;
  timestamp: string;
  url: string;
}

async function readBookmarks(input: BookmarksInput): Promise<ScriptResult> {
  const count = Math.min(Math.max(input.count || 10, 1), 100);

  let context = null;
  try {
    context = await getBrowserContext();
    const page = context.pages()[0] || await context.newPage();

    await page.goto('https://x.com/i/bookmarks', {
      timeout: config.timeouts.navigation,
      waitUntil: 'domcontentloaded',
    });
    await page.waitForTimeout(config.timeouts.pageLoad);

    const loginError = await checkLogin(page);
    if (loginError) return loginError;

    // Check for empty bookmarks
    const emptyState = await page.locator('text="Save posts for later"').isVisible().catch(() => false);
    if (emptyState) {
      return { success: true, message: 'No bookmarks found.', data: [] };
    }

    // Wait for first tweet to appear
    await page.locator('article[data-testid="tweet"]').first().waitFor({ timeout: config.timeouts.elementWait * 2 });

    const bookmarks: BookmarkTweet[] = [];
    const seenUrls = new Set<string>();
    let lastCount = 0;
    let scrollAttempts = 0;
    const maxScrollAttempts = 5;

    while (bookmarks.length < count && scrollAttempts < maxScrollAttempts) {
      const articles = page.locator('article[data-testid="tweet"]');
      const articleCount = await articles.count();

      for (let i = 0; i < articleCount && bookmarks.length < count; i++) {
        const article = articles.nth(i);

        const statusLink = await article.locator('a[href*="/status/"]').first().getAttribute('href').catch(() => null);
        const url = statusLink ? `https://x.com${statusLink}` : '';

        if (url && seenUrls.has(url)) continue;

        // Extract author display name and handle
        const userNameEl = article.locator('[data-testid="User-Name"]').first();
        const nameSpans = userNameEl.locator('span');
        const author = await nameSpans.first().textContent().catch(() => 'Unknown');
        const handleEl = await userNameEl.locator('a[href^="/"]').nth(1).textContent().catch(() => null)
          || await userNameEl.locator('span:has-text("@")').first().textContent().catch(() => '@unknown');

        // Extract tweet text
        const tweetText = article.locator('[data-testid="tweetText"]').first();
        const text = await tweetText.textContent().catch(() => '(no text)') || '(no text)';

        // Extract timestamp
        const timeEl = article.locator('time').first();
        const timestamp = await timeEl.getAttribute('datetime').catch(() => '') || '';

        bookmarks.push({
          author: author || 'Unknown',
          handle: handleEl || '@unknown',
          text,
          timestamp,
          url,
        });
        if (url) seenUrls.add(url);
      }

      // If we have enough, stop
      if (bookmarks.length >= count) break;

      // If no new tweets were found after scrolling, we've hit the end
      if (bookmarks.length === lastCount) {
        scrollAttempts++;
      } else {
        scrollAttempts = 0;
        lastCount = bookmarks.length;
      }

      // Scroll down to load more
      await page.evaluate(() => window.scrollBy(0, window.innerHeight * 2));
      await page.waitForTimeout(1500);
    }

    // Format output
    const formatted = bookmarks.map((b, i) =>
      `${i + 1}. ${b.author} (${b.handle}) — ${b.timestamp ? new Date(b.timestamp).toLocaleDateString() : 'unknown date'}\n   ${b.text.slice(0, 280)}\n   ${b.url}`
    ).join('\n\n');

    return {
      success: true,
      message: `Found ${bookmarks.length} bookmark${bookmarks.length === 1 ? '' : 's'}:\n\n${formatted}`,
      data: bookmarks,
    };

  } finally {
    if (context) await context.close();
  }
}

runScript<BookmarksInput>(readBookmarks);
