"use strict";

(() => {
  const storageKey = "lyra-admin-theme";
  const systemTheme = window.matchMedia("(prefers-color-scheme: dark)");
  const normalize = (value) => ["light", "dark"].includes(value) ? value : "system";
  let preference = "system";

  try {
    preference = normalize(window.localStorage.getItem(storageKey));
  } catch (_) {
    // Restricted storage must not prevent login or theme switching.
  }

  const applyTheme = () => {
    document.documentElement.dataset.theme = preference === "system"
      ? (systemTheme.matches ? "dark" : "light")
      : preference;
    document.querySelectorAll('input[name="admin-theme"]').forEach((input) => {
      input.checked = input.value === preference;
    });
  };

  // Run in the head before the stylesheet to avoid a light flash at night.
  applyTheme();
  document.addEventListener("DOMContentLoaded", applyTheme);
  systemTheme.addEventListener("change", () => {
    if (preference === "system") applyTheme();
  });
  window.addEventListener("storage", (event) => {
    if (event.key === storageKey || event.key === null) {
      preference = normalize(event.newValue);
      applyTheme();
    }
  });
  document.addEventListener("change", (event) => {
    if (!event.target.matches('input[name="admin-theme"]')) return;

    preference = normalize(event.target.value);
    try {
      window.localStorage.setItem(storageKey, preference);
    } catch (_) {
      // Keep the selected theme for this page even when persistence is unavailable.
    }
    applyTheme();
  });
})();

document.addEventListener("click", (event) => {
  const toggle = event.target.closest("[data-password]");
  if (toggle) {
    const input = document.getElementById(toggle.dataset.password);
    const visible = input.type === "password";
    input.type = visible ? "text" : "password";
    toggle.setAttribute("aria-pressed", String(visible));
    toggle.setAttribute("aria-label", visible ? "隐藏密码" : "显示密码");
    toggle.title = toggle.getAttribute("aria-label");
    toggle.querySelector("use").setAttribute("href", `/admin/assets/icons.svg#${visible ? "eye-off" : "eye"}`);
  }
});

document.addEventListener("submit", (event) => {
  const message = event.submitter?.dataset.confirm;
  if (message && !window.confirm(message)) event.preventDefault();
});
