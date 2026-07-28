(() => {
  const hostname = location.hostname.toLowerCase();
  const source = hostname.includes("claude") ? "claude" :
    (hostname.includes("codex") ? "codex" : "chatgpt");
  const selectors = {
    chatgpt: {
      profile: "chatgpt-web-2026-07",
      anchors: [
        ['main'],
        [
          '#prompt-textarea',
          'textarea[data-testid*="prompt" i]',
          '[contenteditable="true"][data-testid*="composer" i]',
          'main [contenteditable="true"]'
        ]
      ],
      working: [
        'button[data-testid="stop-button"]',
        '[data-testid*="stop-generation"]',
        'button[aria-label*="Stop generating" i]',
        'button[aria-label*="Stop streaming" i]'
      ],
      approval: [
        '[role="dialog"] button[data-testid*="approve" i]',
        '[role="dialog"] button[aria-label*="allow" i]',
        'button[data-testid*="permission" i]'
      ],
      title: ['[data-testid="conversation-title"]', 'main h1', 'h1']
    },
    claude: {
      profile: "claude-web-2026-07",
      anchors: [
        ['main'],
        ['[contenteditable="true"]', 'fieldset textarea']
      ],
      working: [
        'button[aria-label*="Stop" i]',
        'button[title*="Stop" i]',
        '[data-testid*="stop" i]'
      ],
      approval: [
        '[role="dialog"] button[aria-label*="allow" i]',
        '[role="dialog"] button[aria-label*="approve" i]',
        '[role="dialog"] button[aria-label*="deny" i]'
      ],
      title: ['main h1', 'h1']
    },
    codex: {
      profile: "codex-web-2026-07",
      anchors: [
        ['main'],
        ['[contenteditable="true"]', 'textarea']
      ],
      working: [
        'button[aria-label*="Stop" i]',
        'button[title*="Stop" i]',
        '[data-testid*="stop" i]'
      ],
      approval: [
        '[role="dialog"] button[aria-label*="allow" i]',
        '[role="dialog"] button[aria-label*="approve" i]',
        '[role="dialog"] button[aria-label*="deny" i]'
      ],
      title: ['main h1', 'h1']
    }
  };

  const provider = selectors[source];
  const detectorVersion = "0.3.0";
  let lastKey = "";
  let timer;

  function hasAny(selectorList) {
    return selectorList.some((selector) => document.querySelector(selector));
  }

  function hasEveryAnchorGroup(selectorGroups) {
    return selectorGroups.every((group) => hasAny(group));
  }

  function firstText(selectorList) {
    for (const selector of selectorList) {
      const text = document.querySelector(selector)?.textContent?.trim();
      if (text) return text;
    }
    return "";
  }

  function status() {
    // Never inspect arbitrary conversation text for approval words. A prompt or
    // assistant reply can contain "allow" and must not create a false human
    // handoff state. Only an actual control or modal qualifies.
    if (hasAny(provider.approval)) {
      return { phase: "needs_attention", detail: "Browser approval control is visible" };
    }
    if (hasAny(provider.working)) {
      return { phase: "working", detail: "Browser generation control is visible" };
    }
    return { phase: "idle", detail: "No browser generation control is visible" };
  }

  function selectorState() {
    // Anchors establish that the known provider UI contract is present before
    // absence of a working/approval control can be interpreted as idle.
    return hasEveryAnchorGroup(provider.anchors) ? "verified" : "degraded";
  }

  function conversationPath() {
    // Search parameters can contain shared content or tracking data. The bridge
    // needs a stable tab/session key, not the query string.
    return location.pathname || "/";
  }

  function title() {
    return firstText(provider.title) || document.title.replace(/\s*[-|].*$/, "") || source;
  }

  function publish() {
    const state = selectorState();
    const next = state === "verified"
      ? status()
      : { phase: "idle", detail: "Provider page does not match the bundled selector profile" };
    const path = conversationPath();
    const payload = {
      version: 3,
      source,
      session_id: path,
      title: title().slice(0, 120),
      phase: next.phase,
      detail: next.detail,
      url: location.origin + path,
      detector_version: detectorVersion,
      selector_profile: provider.profile,
      selector_state: state
    };
    const key = `${payload.session_id}|${payload.phase}|${payload.title}|${state}`;
    if (key === lastKey) return;
    lastKey = key;
    chrome.runtime.sendMessage({ type: "agent-island-status", payload });
  }

  function schedule() {
    clearTimeout(timer);
    timer = setTimeout(publish, 300);
  }

  new MutationObserver(schedule).observe(document.documentElement, {
    childList: true,
    subtree: true,
    attributes: true
  });
  window.addEventListener("popstate", schedule);
  window.addEventListener("hashchange", schedule);
  setInterval(publish, 8000);
  publish();
})();
