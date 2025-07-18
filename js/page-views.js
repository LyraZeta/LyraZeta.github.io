/**
 * 页面浏览量统计
 * 结合百度统计使用
 */
(function() {
    'use strict';
    
    const PageViews = {
        // 初始化
        init: function() {
            this.updatePageViews();
            this.trackBaiduEvent();
        },
        
        // 更新页面浏览量
        updatePageViews: function() {
            const pageUrl = window.location.pathname;
            const viewsKey = 'page_views_' + this.sanitizeKey(pageUrl);
            
            // 获取当前浏览量
            let views = parseInt(localStorage.getItem(viewsKey) || '0');
            
            // 增加浏览量（但要避免刷新时重复计数）
            const lastVisit = localStorage.getItem(viewsKey + '_last');
            const now = Date.now();
            
            // 如果距离上次访问超过1分钟，才增加计数
            if (!lastVisit || (now - parseInt(lastVisit)) > 60000) {
                views++;
                localStorage.setItem(viewsKey, views.toString());
                localStorage.setItem(viewsKey + '_last', now.toString());
            }
            
            // 显示浏览量
            this.displayViews(views);
        },
        
        // 显示浏览量
        displayViews: function(views) {
            const viewsElement = document.getElementById('page-views');
            if (viewsElement) {
                // 添加动画效果
                viewsElement.style.opacity = '0';
                setTimeout(() => {
                    viewsElement.textContent = views;
                    viewsElement.style.opacity = '1';
                }, 200);
            }
        },
        
        // 发送自定义事件到百度统计
        trackBaiduEvent: function() {
            if (typeof _hmt !== 'undefined') {
                const pageUrl = window.location.pathname;
                const pageTitle = document.title;
                
                // 发送页面浏览事件
                _hmt.push(['_trackEvent', 'pageview', 'article_read', pageTitle]);
                
                // 发送页面停留时间事件（5秒后）
                setTimeout(() => {
                    _hmt.push(['_trackEvent', 'engagement', 'article_read_5s', pageTitle]);
                }, 5000);
                
                // 发送页面停留时间事件（30秒后）
                setTimeout(() => {
                    _hmt.push(['_trackEvent', 'engagement', 'article_read_30s', pageTitle]);
                }, 30000);
            }
        },
        
        // 清理key中的特殊字符
        sanitizeKey: function(str) {
            return str.replace(/[^a-zA-Z0-9]/g, '_');
        },
        
        // 获取总访问量
        getTotalViews: function() {
            const keys = Object.keys(localStorage);
            let total = 0;
            
            keys.forEach(key => {
                if (key.startsWith('page_views_') && !key.endsWith('_last')) {
                    total += parseInt(localStorage.getItem(key) || '0');
                }
            });
            
            return total;
        }
    };
    
    // 页面加载完成后初始化
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => PageViews.init());
    } else {
        PageViews.init();
    }
    
    // 暴露到全局，方便其他地方调用
    window.PageViews = PageViews;
    
})();
