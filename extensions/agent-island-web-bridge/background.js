const endpoint = "http://127.0.0.1:27583/v1/events";

chrome.runtime.onMessage.addListener((event) => {
  if (!event || event.type !== "agent-island-status") return;
  chrome.storage.local.get(["pairingToken"], async ({ pairingToken }) => {
    if (!pairingToken) return;
    try {
      await fetch(endpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${pairingToken}`
        },
        body: JSON.stringify(event.payload),
        keepalive: true
      });
    } catch (_) {
      // Agent Island may not be running. The next DOM change will retry.
    }
  });
});
