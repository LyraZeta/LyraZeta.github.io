(function() {
  "use strict";

  function onReady(callback) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", callback);
    } else {
      callback();
    }
  }

  function updatePostCount(count) {
    var element = document.getElementById("dynamic-post-count");
    if (!element || typeof count !== "number") {
      return;
    }

    element.textContent = "文章 " + count + " 篇";
    element.setAttribute("data-source", "api");
  }

  function loadPostCount() {
    if (!window.fetch) {
      return;
    }

    fetch("/api/posts?limit=0", {
      credentials: "same-origin",
      headers: {
        "Accept": "application/json"
      }
    })
      .then(function(response) {
        if (!response.ok) {
          throw new Error("Unexpected API response");
        }

        return response.json();
      })
      .then(function(payload) {
        updatePostCount(payload.count);
      })
      .catch(function() {
        // The static GitHub Pages deployment has no backend; keep the Jekyll-rendered fallback.
      });
  }

  onReady(loadPostCount);
})();
