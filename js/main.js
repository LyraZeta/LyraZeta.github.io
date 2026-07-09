$(document).ready(function() {


  $('a.blog-button').click(function() {
    if (location.hash && location.hash == "#blog") return;
    if ($('.panel-cover').hasClass('panel-cover--collapsed')) return;
    $('.main-post-list').removeClass('hidden');
    $('.panel-cover').addClass('panel-cover--collapsed');
  });

  if (window.location.hash && window.location.hash == "#blog") {
    $('.panel-cover').addClass('panel-cover--collapsed');
    $('.main-post-list').removeClass('hidden');
  }

  if (window.location.pathname.substring(0, 5) == "/tag/") {
    $('.panel-cover').addClass('panel-cover--collapsed');
  }

  $('.btn-mobile-menu__icon').click(function() {
    // 导航按钮被点击
    // this.style.backgroundColor = '#fff'; 设置颜色后会自动消失
  });  
});
