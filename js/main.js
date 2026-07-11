document.addEventListener('DOMContentLoaded', function() {
  var panel = document.querySelector('.panel-cover');
  var postList = document.querySelector('.main-post-list');
  var blogButtons = document.querySelectorAll('a.blog-button');

  function collapsePanel() {
    if (panel) {
      panel.classList.add('panel-cover--collapsed');
    }
  }

  function showPostList() {
    if (postList) {
      postList.classList.remove('hidden');
    }
  }

  Array.prototype.forEach.call(blogButtons, function(button) {
    button.addEventListener('click', function() {
      if (window.location.hash === '#blog') {
        return;
      }

      if (panel && panel.classList.contains('panel-cover--collapsed')) {
        return;
      }

      showPostList();
      collapsePanel();
    });
  });

  if (window.location.hash === '#blog') {
    collapsePanel();
    showPostList();
  }

  if (window.location.pathname.indexOf('/tag/') === 0) {
    collapsePanel();
  }
});
