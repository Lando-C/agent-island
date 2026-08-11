const token = document.querySelector("#token");
const status = document.querySelector("#status");

chrome.storage.local.get(["pairingToken"], ({ pairingToken }) => {
  token.value = pairingToken || "";
});

document.querySelector("#save").addEventListener("click", () => {
  const value = token.value.trim();
  if (!/^[0-9a-f]{64}$/i.test(value)) {
    status.textContent = "The token must be the 64-character value copied from Agent Island.";
    return;
  }
  chrome.storage.local.set({ pairingToken: value }, () => {
    status.textContent = "Saved locally in this browser profile.";
  });
});
