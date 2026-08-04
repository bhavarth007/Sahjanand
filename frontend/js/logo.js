/**
 * logo.js — sets logo on all pages immediately, no async needed.
 * Looks for elements with data-logo attribute and sets src.
 */
(function() {
  const LOGO = '/assets/images/logo.png';

  function applyLogo() {
    // Set all logo images
    document.querySelectorAll('[data-logo]').forEach(function(el) {
      el.src = LOGO;
      el.onerror = null; // no broken icon if file missing
    });
    // Set favicon
    var favicon = document.querySelector('link[rel="icon"]');
    if (favicon) favicon.href = LOGO;
  }

  // Run immediately if DOM ready, else wait
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', applyLogo);
  } else {
    applyLogo();
  }
})();
