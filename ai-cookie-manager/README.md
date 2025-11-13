# AI Cookie Manager - Chrome Extension

A basic Chromium-based browser extension that uses AI to automatically detect and reject non-essential cookies on websites.

## Features

- Automatically detects cookie consent banners on websites
- Uses Claude AI (Anthropic) to intelligently identify and click the "reject all" or "essential only" button
- Pattern matching fallback for common cookie banner layouts
- Simple popup UI for configuration
- Privacy-focused: Only accepts necessary/functional cookies

## Security Note

**This is a basic prototype for personal testing only.** It includes:
- Basic input validation
- Content Security Policy (CSP) restrictions
- Manifest V3 for improved security
- No external dependencies beyond Anthropic API

**NOT production-ready.** Missing:
- Comprehensive error handling
- Rate limiting
- Extensive testing
- Security audit

## Installation

### 1. Get an Anthropic API Key

1. Go to [https://console.anthropic.com/](https://console.anthropic.com/)
2. Sign up or log in
3. Navigate to API Keys
4. Create a new API key (starts with `sk-ant-`)

### 2. Load Extension in Chrome

1. Open Chrome and go to `chrome://extensions/`
2. Enable "Developer mode" (toggle in top right)
3. Click "Load unpacked"
4. Select the `ai-cookie-manager` folder
5. The extension should now appear in your extensions list

### 3. Configure the Extension

1. Click the extension icon in your toolbar (puzzle piece icon → AI Cookie Manager)
2. Paste your Anthropic API key
3. Make sure "Enable automatic cookie management" is checked
4. Click "Save Settings"

## Testing

### Safe Testing Websites

Test the extension on these cookie-heavy sites:
- https://www.theguardian.com
- https://www.bbc.com
- https://www.cnn.com
- https://www.reddit.com (EU version)

### What to Check

1. **Console Logs**: Open DevTools (F12) and check the Console for `[AI Cookie Manager]` messages
2. **Banner Detection**: The extension should detect and log cookie banners
3. **Button Clicking**: Watch for automatic clicks on reject/essential-only buttons
4. **AI Analysis**: Check background page console for AI API responses

### View Extension Logs

- **Content Script logs**: Open DevTools on the webpage (F12)
- **Background Worker logs**: Go to `chrome://extensions/` → Click "service worker" link under the extension

## How It Works

1. **Content Script** (`content.js`) runs on every webpage
   - Scans for cookie banners using common selectors
   - Extracts button text and banner context
   - Performs pattern matching to identify reject/essential buttons

2. **Background Worker** (`background.js`) coordinates AI analysis
   - Receives banner context from content script
   - Calls Claude API with banner information
   - Returns decision on whether to click the suggested button

3. **AI Decision Making**
   - AI analyzes button text and banner content
   - Only clicks if confidence > 70% that it's a reject/essential button
   - Avoids "Accept All" buttons

## File Structure

```
ai-cookie-manager/
├── manifest.json          # Extension configuration (Manifest V3)
├── content.js            # Runs on webpages, detects banners
├── background.js         # Service worker, AI coordination
├── popup.html            # Settings UI
├── popup.js              # Settings UI logic
└── icons/
    ├── icon16.png        # Extension icon (16x16)
    ├── icon48.png        # Extension icon (48x48)
    ├── icon128.png       # Extension icon (128x128)
    └── icon.svg          # SVG source for icons
```

## Troubleshooting

### Extension Not Working

1. Check that it's enabled in `chrome://extensions/`
2. Verify API key is configured in the popup
3. Check console logs for errors
4. Ensure "Enable automatic cookie management" is checked

### No Banners Detected

- Some sites load banners after delay - wait a few seconds
- Check console for `[AI Cookie Manager]` messages
- The extension monitors for 10 seconds after page load

### API Errors

- Verify API key is correct (starts with `sk-ant-`)
- Check you have credits in your Anthropic account
- View background worker console for specific error messages

### Buttons Not Clicking

- AI may have determined button is unsafe to click
- Check console for "AI rejected the button" message
- Confidence threshold is set to 70%

## API Costs

The extension uses Claude 3 Haiku, which is very affordable:
- ~$0.00025 per cookie banner analyzed
- Most pages only trigger 1 API call
- You can monitor usage in Anthropic console

## Privacy

- API key stored locally in Chrome sync storage
- Only banner context sent to Anthropic API (no personal data)
- No tracking or analytics
- No data collection

## Limitations

- Only works on Chromium-based browsers (Chrome, Edge, Brave, etc.)
- Requires Anthropic API key and internet connection
- May not catch all cookie banners (complex dynamic ones)
- Basic security - not production grade
- No support for Firefox (would need Manifest V2 adaptation)

## Uninstallation

1. Go to `chrome://extensions/`
2. Click "Remove" on AI Cookie Manager
3. Your API key will be removed from Chrome storage

## Development

To modify the extension:

1. Edit the source files
2. Go to `chrome://extensions/`
3. Click the reload icon on the extension card
4. Test your changes

### Key Configuration

In `background.js`, you can modify:
- `model`: Change AI model (default: `claude-3-haiku-20240307`)
- Confidence threshold: Currently 70% (line ~118)

In `content.js`, you can adjust:
- `BANNER_SELECTORS`: Add more CSS selectors for banners
- `REJECT_PATTERNS`: Add patterns for reject buttons
- Observer timeout: Currently 10 seconds (line ~175)

## License

MIT License - See LICENSE file

## Disclaimer

This extension is provided as-is for personal testing purposes. Use at your own risk. The author is not responsible for any issues arising from its use, including but not limited to: unwanted cookies being accepted, websites breaking, or API costs incurred.

**Always review cookie decisions on sensitive sites (banking, healthcare, etc.).**
