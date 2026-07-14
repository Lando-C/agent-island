const token = document.querySelector("#token");
const status = document.querySelector("#status");

chrome.storage.local.get(["pairingToken"], ({ pairingToken }) => {
  token.value = pairingToken || "";
});

document.querySelector("#save").addEventListener("click", () => {
  const value = token.value.trim();
  if (value.length < 32) {
    status.textContent = "The token is incomplete.";
    return;
  }
  chrome.storage.local.set({ pairingToken: value }, () => {
    status.textContent = "Saved locally in this browser profile.";
  });
});
