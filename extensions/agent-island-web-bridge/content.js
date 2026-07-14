(() => {
  const hostname = location.hostname;
  const source = hostname.includes("claude") ? "claude" :
    (hostname.includes("codex") ? "codex" : "chatgpt");
  let lastKey = "";
  let timer;

  function firstText(selector) {
    return document.querySelector(selector)?.textContent?.trim() || "";
  }

  function phase() {
    const text = document.body?.innerText || "";
    if (/\b(Allow|Approve|Deny|Permission required)\b/i.test(text)) return "needs_attention";
    const stopSelectors = [
      '[data-testid*="stop"]',
      'button[aria-label*="Stop"]',
      'button[title*="Stop"]',
      'button[data-state="generating"]'
    ];
    if (stopSelectors.some((selector) => document.querySelector(selector))) return "working";
    return "idle";
  }

  function title() {
    return firstText("h1") || document.title.replace(/\s*[-|].*$/, "") || source;
  }

  function publish() {
    const nextPhase = phase();
    const payload = {
      version: 1,
      source,
      session_id: location.pathname + location.search,
      title: title().slice(0, 120),
      phase: nextPhase,
      detail: "Browser DOM signal (heuristic)",
      url: location.origin + location.pathname
    };
    const key = `${payload.session_id}|${payload.phase}|${payload.title}`;
    if (key === lastKey) return;
    lastKey = key;
    chrome.runtime.sendMessage({ type: "agent-island-status", payload });
  }

  function schedule() {
    clearTimeout(timer);
    timer = setTimeout(publish, 450);
  }

  new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true, attributes: true });
  window.addEventListener("popstate", schedule);
  setInterval(publish, 8000);
  publish();
})();
