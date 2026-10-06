/* nav-footer.js — injected nav and footer HTML, keeps all pages in sync */
(function () {

  const NAV = `
<nav class="nav">
  <div class="nav-inner">
    <a href="/" class="nav-logo">
      CS Executive Services
      <span>Arlington, Virginia</span>
    </a>
    <div class="nav-links">
      <a href="/about.html" class="nav-link">About</a>
      <div class="nav-dropdown">
        <a href="#" class="nav-link">Services</a>
        <div class="nav-dropdown-menu">
          <a href="/services/chauffeur.html">Executive Chauffeur</a>
          <a href="/services/detailing.html">Automotive Detailing</a>
          <a href="/services/brand-strategy.html">Brand Strategy</a>
          <a href="/services/it-security.html">IT Security</a>
        </div>
      </div>
      <a href="/contact.html" class="nav-link">Enquiries</a>
    </div>
    <button class="nav-hamburger" aria-label="Open menu">
      <span></span><span></span><span></span>
    </button>
  </div>
</nav>
<div class="nav-mobile">
  <button class="nav-mobile-close">Close</button>
  <a href="/">Home</a>
  <a href="/about.html">About</a>
  <a href="/services/chauffeur.html">Chauffeur</a>
  <a href="/services/detailing.html">Detailing</a>
  <a href="/services/brand-strategy.html">Brand Strategy</a>
  <a href="/services/it-security.html">IT Security</a>
  <a href="/contact.html">Enquiries</a>
</div>`;

  const FOOTER = `
<footer class="footer">
  <div class="container">
    <div class="footer-amber-rule"></div>
    <div class="footer-top">
      <div>
        <div class="footer-brand-name">CS Executive Services, LLC</div>
        <p class="footer-brand-desc">
          A boutique executive services firm serving discerning clients in the
          Washington, DC metropolitan area. Privacy and discretion in all matters.
        </p>
      </div>
      <div>
        <div class="footer-col-title">Services</div>
        <div class="footer-links">
          <a href="/services/chauffeur.html">Executive Chauffeur</a>
          <a href="/services/detailing.html">Automotive Detailing</a>
          <a href="/services/brand-strategy.html">Brand Strategy</a>
          <a href="/services/it-security.html">IT Security</a>
        </div>
      </div>
      <div>
        <div class="footer-col-title">Correspondence</div>
        <div class="footer-links">
          <a href="mailto:reservations@csexecutiveservices.com">reservations@csexecutiveservices.com</a>
          <a href="tel:+15715402261">(571) 540-2261</a>
          <a href="/contact.html">Online Enquiry</a>
          <a href="https://www.linkedin.com/in/coreysheldon" target="_blank" rel="noopener">LinkedIn<span class="sr-only"> (opens in new tab)</span></a>
        </div>
      </div>
    </div>
    <div class="footer-bottom">
      <p class="footer-legal">
        &copy; 2026 CS Executive Services, LLC &middot; Arlington County, Virginia
      </p>
      <p class="footer-legal">All enquiries treated with complete confidentiality.</p>
    </div>
  </div>
</footer>`;

  // Inject nav before first child of body
  const navTarget = document.getElementById('nav-mount');
  if (navTarget) navTarget.innerHTML = NAV;

  // Inject footer
  const footerTarget = document.getElementById('footer-mount');
  if (footerTarget) footerTarget.innerHTML = FOOTER;

})();
