document.addEventListener('DOMContentLoaded', function() {
  var toggle = document.getElementById('dark-mode-toggle');
  var body = document.body;

  if (toggle) {
    toggle.addEventListener('click', function(e) {
      e.preventDefault();
      body.classList.toggle('dark-mode');
      var isDark = body.classList.contains('dark-mode');
      localStorage.setItem('dark-mode', isDark);
      
      // Update button text or icon if needed
      // toggle.textContent = isDark ? "Light Mode" : "Dark Mode";
    });
  }
});
