(function() {
  'use strict';

  var storageKey = 'dark-mode';

  function storedPreference() {
    try {
      return localStorage.getItem(storageKey);
    } catch (error) {
      return null;
    }
  }

  function savePreference(isDark) {
    try {
      localStorage.setItem(storageKey, String(isDark));
    } catch (error) {
      // Keep the active theme even when browser storage is unavailable.
    }
  }

  function updateToggle(toggle, isDark) {
    if (!toggle) {
      return;
    }

    var label = isDark ? '切换到日间模式' : '切换到夜间模式';
    var icon = toggle.querySelector('.fa');

    toggle.setAttribute('aria-label', label);
    toggle.setAttribute('aria-pressed', String(isDark));
    toggle.setAttribute('title', label);

    if (icon) {
      icon.classList.toggle('fa-sun-o', isDark);
      icon.classList.toggle('fa-moon-o', !isDark);
    }
  }

  function applyTheme(isDark, toggle) {
    document.documentElement.classList.toggle('dark-mode', isDark);
    document.body.classList.toggle('dark-mode', isDark);
    document.documentElement.style.colorScheme = isDark ? 'dark' : 'light';
    updateToggle(toggle, isDark);
  }

  function onReady() {
    var toggle = document.getElementById('dark-mode-toggle');
    var isDark = document.documentElement.classList.contains('dark-mode');

    applyTheme(isDark, toggle);

    if (toggle) {
      toggle.addEventListener('click', function() {
        isDark = !document.body.classList.contains('dark-mode');
        applyTheme(isDark, toggle);
        savePreference(isDark);
      });
    }

    if (window.matchMedia) {
      var colorScheme = window.matchMedia('(prefers-color-scheme: dark)');
      var followSystemTheme = function(event) {
        if (storedPreference() === null) {
          applyTheme(event.matches, toggle);
        }
      };

      if (colorScheme.addEventListener) {
        colorScheme.addEventListener('change', followSystemTheme);
      } else if (colorScheme.addListener) {
        colorScheme.addListener(followSystemTheme);
      }
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', onReady);
  } else {
    onReady();
  }
})();
