// Content script that runs on each page to detect and handle cookie banners

(function() {
  'use strict';

  // Common selectors for cookie banners
  const BANNER_SELECTORS = [
    '[id*="cookie"]',
    '[class*="cookie"]',
    '[id*="consent"]',
    '[class*="consent"]',
    '[class*="gdpr"]',
    '[id*="gdpr"]',
    '[class*="banner"]',
    '[aria-label*="cookie"]',
    '[aria-label*="consent"]'
  ];

  // Common button text patterns for rejection/minimal acceptance
  const REJECT_PATTERNS = [
    /reject\s+all/i,
    /decline\s+all/i,
    /refuse\s+all/i,
    /only\s+necessary/i,
    /essential\s+only/i,
    /necessary\s+cookies/i,
    /required\s+only/i,
    /customize/i,
    /manage\s+cookies/i,
    /cookie\s+settings/i,
    /preferences/i
  ];

  // Common accept all patterns (to avoid these)
  const ACCEPT_ALL_PATTERNS = [
    /accept\s+all/i,
    /allow\s+all/i,
    /agree/i,
    /consent/i,
    /got\s+it/i,
    /ok/i,
    /continue/i
  ];

  let bannerFound = false;
  let processed = false;

  function log(message, data = null) {
    const prefix = '[AI Cookie Manager]';
    if (data) {
      console.log(prefix, message, data);
    } else {
      console.log(prefix, message);
    }
  }

  // Find potential cookie banners
  function findCookieBanners() {
    const banners = [];

    for (const selector of BANNER_SELECTORS) {
      const elements = document.querySelectorAll(selector);
      elements.forEach(el => {
        // Check if element is visible and has reasonable size
        const rect = el.getBoundingClientRect();
        const style = window.getComputedStyle(el);

        if (rect.width > 100 && rect.height > 50 &&
            style.display !== 'none' &&
            style.visibility !== 'hidden' &&
            style.opacity !== '0') {

          // Check if it contains cookie/consent related text
          const text = el.textContent.toLowerCase();
          if (text.includes('cookie') ||
              text.includes('consent') ||
              text.includes('privacy') ||
              text.includes('gdpr')) {
            banners.push(el);
          }
        }
      });
    }

    return banners;
  }

  // Extract page context for AI analysis
  function extractPageContext(banner) {
    const text = banner.textContent.substring(0, 2000); // Limit text size
    const buttons = Array.from(banner.querySelectorAll('button, a, [role="button"]'))
      .map(btn => ({
        text: btn.textContent.trim(),
        id: btn.id,
        class: btn.className,
        ariaLabel: btn.getAttribute('aria-label')
      }));

    return {
      bannerText: text,
      buttons: buttons,
      bannerHTML: banner.outerHTML.substring(0, 1000) // Partial HTML for structure
    };
  }

  // Find reject/essential-only button
  function findRejectButton(banner) {
    const buttons = banner.querySelectorAll('button, a, [role="button"], input[type="button"]');
    let bestMatch = null;
    let bestScore = 0;

    buttons.forEach(button => {
      const text = button.textContent.trim();
      const ariaLabel = button.getAttribute('aria-label') || '';
      const combinedText = `${text} ${ariaLabel}`.toLowerCase();

      // Check for reject/minimal patterns
      let score = 0;
      for (const pattern of REJECT_PATTERNS) {
        if (pattern.test(combinedText)) {
          score += 10;
        }
      }

      // Penalize accept all patterns
      for (const pattern of ACCEPT_ALL_PATTERNS) {
        if (pattern.test(combinedText)) {
          score -= 20;
        }
      }

      // Prefer buttons with "reject", "decline", "necessary", "essential"
      if (combinedText.includes('reject') || combinedText.includes('decline')) {
        score += 15;
      }
      if (combinedText.includes('necessary') || combinedText.includes('essential')) {
        score += 12;
      }

      if (score > bestScore) {
        bestScore = score;
        bestMatch = button;
      }
    });

    return bestScore > 0 ? bestMatch : null;
  }

  // Handle the cookie banner
  async function handleCookieBanner(banner) {
    if (processed) return;
    processed = true;

    log('Cookie banner detected, analyzing...');

    const context = extractPageContext(banner);

    // Try basic pattern matching first
    const rejectButton = findRejectButton(banner);

    if (rejectButton) {
      log('Found reject/essential button:', rejectButton.textContent.trim());

      // Send to background script for AI confirmation
      chrome.runtime.sendMessage({
        type: 'ANALYZE_BANNER',
        url: window.location.href,
        context: context,
        buttonFound: {
          text: rejectButton.textContent.trim(),
          class: rejectButton.className,
          id: rejectButton.id
        }
      }, (response) => {
        if (response && response.shouldClick) {
          log('AI confirmed, clicking button');
          rejectButton.click();

          // Hide banner as backup
          setTimeout(() => {
            if (banner.parentNode) {
              banner.style.display = 'none';
            }
          }, 500);
        } else {
          log('AI rejected the button, manual intervention needed');
        }
      });
    } else {
      log('No suitable button found, requesting AI analysis');

      // No good pattern match, ask AI to analyze
      chrome.runtime.sendMessage({
        type: 'ANALYZE_BANNER',
        url: window.location.href,
        context: context,
        buttonFound: null
      }, (response) => {
        if (response && response.selector) {
          log('AI provided selector:', response.selector);
          const aiButton = banner.querySelector(response.selector);
          if (aiButton) {
            aiButton.click();
          }
        }
      });
    }
  }

  // Main detection function
  function detectAndHandle() {
    if (bannerFound) return;

    const banners = findCookieBanners();

    if (banners.length > 0) {
      bannerFound = true;
      log(`Found ${banners.length} potential cookie banner(s)`);

      // Handle the most prominent banner (largest)
      const largestBanner = banners.reduce((largest, current) => {
        const currentSize = current.getBoundingClientRect().width * current.getBoundingClientRect().height;
        const largestSize = largest.getBoundingClientRect().width * largest.getBoundingClientRect().height;
        return currentSize > largestSize ? current : largest;
      });

      handleCookieBanner(largestBanner);
    }
  }

  // Run detection after page loads
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', detectAndHandle);
  } else {
    detectAndHandle();
  }

  // Also watch for dynamic banners
  const observer = new MutationObserver((mutations) => {
    if (!bannerFound) {
      detectAndHandle();
    }
  });

  observer.observe(document.body, {
    childList: true,
    subtree: true
  });

  // Stop observing after 10 seconds
  setTimeout(() => {
    observer.disconnect();
  }, 10000);

  log('Content script loaded and monitoring for cookie banners');
})();
