// Background service worker for AI coordination

const CONFIG = {
  // User should set their API key via the popup
  apiKey: '',
  apiEndpoint: 'https://api.anthropic.com/v1/messages',
  model: 'claude-3-haiku-20240307', // Fast and cheap for this use case
  enabled: true
};

// Load config from storage
chrome.storage.sync.get(['apiKey', 'enabled'], (result) => {
  if (result.apiKey) {
    CONFIG.apiKey = result.apiKey;
  }
  if (result.enabled !== undefined) {
    CONFIG.enabled = result.enabled;
  }
});

// Listen for config changes
chrome.storage.onChanged.addListener((changes, namespace) => {
  if (namespace === 'sync') {
    if (changes.apiKey) {
      CONFIG.apiKey = changes.apiKey.newValue;
    }
    if (changes.enabled !== undefined) {
      CONFIG.enabled = changes.enabled.newValue;
    }
  }
});

function log(message, data = null) {
  const prefix = '[AI Cookie Manager BG]';
  if (data) {
    console.log(prefix, message, data);
  } else {
    console.log(prefix, message);
  }
}

// Call Claude API to analyze cookie banner
async function analyzeWithAI(context) {
  if (!CONFIG.apiKey) {
    log('No API key configured');
    return { shouldClick: false, error: 'No API key' };
  }

  const prompt = `You are analyzing a cookie consent banner. Your goal is to determine if the button found is safe to click to REJECT or accept ONLY ESSENTIAL/NECESSARY cookies.

Banner context:
Text: ${context.bannerText}

Available buttons:
${context.buttons.map((b, i) => `${i + 1}. "${b.text}" (id: ${b.id}, class: ${b.class})`).join('\n')}

${context.buttonFound ? `Suggested button: "${context.buttonFound.text}"` : 'No button suggested by pattern matching.'}

Respond with ONLY a JSON object with this structure:
{
  "shouldClick": true/false,
  "confidence": 0-100,
  "reasoning": "brief explanation",
  "alternativeSelector": "CSS selector if suggested button is wrong (or null)"
}

Rules:
- shouldClick=true ONLY if the button will reject non-essential cookies or accept only necessary cookies
- shouldClick=false if the button accepts all cookies or is unclear
- confidence should reflect your certainty
- If you find a better button, provide its CSS selector in alternativeSelector`;

  try {
    const response = await fetch(CONFIG.apiEndpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': CONFIG.apiKey,
        'anthropic-version': '2023-06-01'
      },
      body: JSON.stringify({
        model: CONFIG.model,
        max_tokens: 500,
        messages: [{
          role: 'user',
          content: prompt
        }]
      })
    });

    if (!response.ok) {
      const error = await response.text();
      log('API error:', error);
      return { shouldClick: false, error: `API error: ${response.status}` };
    }

    const data = await response.json();
    const content = data.content[0].text;

    // Extract JSON from response
    const jsonMatch = content.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
      log('No JSON in response:', content);
      return { shouldClick: false, error: 'Invalid AI response' };
    }

    const result = JSON.parse(jsonMatch[0]);
    log('AI analysis result:', result);

    return result;
  } catch (error) {
    log('AI analysis error:', error);
    return { shouldClick: false, error: error.message };
  }
}

// Message handler
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.type === 'ANALYZE_BANNER') {
    if (!CONFIG.enabled) {
      sendResponse({ shouldClick: false, error: 'Extension disabled' });
      return;
    }

    log('Received banner analysis request from:', request.url);

    // If we have a button found by pattern matching, analyze it
    if (request.buttonFound) {
      analyzeWithAI(request.context)
        .then(result => {
          // Only click if high confidence
          const shouldClick = result.shouldClick && result.confidence > 70;

          sendResponse({
            shouldClick: shouldClick,
            selector: result.alternativeSelector,
            confidence: result.confidence,
            reasoning: result.reasoning
          });
        })
        .catch(error => {
          log('Error in AI analysis:', error);
          sendResponse({ shouldClick: false, error: error.message });
        });
    } else {
      // No pattern match, need AI to find the right button
      analyzeWithAI(request.context)
        .then(result => {
          sendResponse({
            shouldClick: false, // Don't auto-click without pattern match
            selector: result.alternativeSelector,
            confidence: result.confidence,
            reasoning: result.reasoning
          });
        })
        .catch(error => {
          log('Error in AI analysis:', error);
          sendResponse({ shouldClick: false, error: error.message });
        });
    }

    return true; // Keep message channel open for async response
  }

  if (request.type === 'GET_CONFIG') {
    sendResponse({
      apiKey: CONFIG.apiKey ? '***' + CONFIG.apiKey.slice(-4) : '',
      enabled: CONFIG.enabled,
      hasApiKey: !!CONFIG.apiKey
    });
    return true;
  }
});

log('Background service worker initialized');
