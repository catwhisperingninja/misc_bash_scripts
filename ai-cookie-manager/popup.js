// Popup script for settings management

document.addEventListener('DOMContentLoaded', () => {
  const apiKeyInput = document.getElementById('apiKey');
  const enabledCheckbox = document.getElementById('enabled');
  const saveBtn = document.getElementById('saveBtn');
  const statusDiv = document.getElementById('status');

  // Load saved settings
  chrome.storage.sync.get(['apiKey', 'enabled', 'stats'], (result) => {
    if (result.apiKey) {
      apiKeyInput.value = result.apiKey;
    }
    if (result.enabled !== undefined) {
      enabledCheckbox.checked = result.enabled;
    }

    // Update stats
    updateStats(result.stats || {});
  });

  // Get current status from background
  chrome.runtime.sendMessage({ type: 'GET_CONFIG' }, (response) => {
    if (response) {
      const statusSpan = document.getElementById('extensionStatus');
      if (response.hasApiKey && response.enabled) {
        statusSpan.textContent = 'Active';
        statusSpan.style.color = '#4CAF50';
      } else if (!response.hasApiKey) {
        statusSpan.textContent = 'No API key';
        statusSpan.style.color = '#f44336';
      } else {
        statusSpan.textContent = 'Disabled';
        statusSpan.style.color = '#ff9800';
      }
    }
  });

  // Save settings
  saveBtn.addEventListener('click', () => {
    const apiKey = apiKeyInput.value.trim();
    const enabled = enabledCheckbox.checked;

    // Basic validation
    if (apiKey && !apiKey.startsWith('sk-ant-')) {
      showStatus('Invalid API key format. Should start with sk-ant-', 'error');
      return;
    }

    chrome.storage.sync.set({
      apiKey: apiKey,
      enabled: enabled
    }, () => {
      if (chrome.runtime.lastError) {
        showStatus('Error saving settings: ' + chrome.runtime.lastError.message, 'error');
      } else {
        showStatus('Settings saved successfully!', 'success');

        // Update status display
        setTimeout(() => {
          const statusSpan = document.getElementById('extensionStatus');
          if (apiKey && enabled) {
            statusSpan.textContent = 'Active';
            statusSpan.style.color = '#4CAF50';
          } else if (!apiKey) {
            statusSpan.textContent = 'No API key';
            statusSpan.style.color = '#f44336';
          } else {
            statusSpan.textContent = 'Disabled';
            statusSpan.style.color = '#ff9800';
          }
        }, 500);
      }
    });
  });

  function showStatus(message, type) {
    statusDiv.textContent = message;
    statusDiv.className = `status ${type}`;
    statusDiv.style.display = 'block';

    setTimeout(() => {
      statusDiv.style.display = 'none';
    }, 3000);
  }

  function updateStats(stats) {
    document.getElementById('bannersHandled').textContent = stats.bannersHandled || 0;
    document.getElementById('aiCalls').textContent = stats.aiCalls || 0;
  }
});
