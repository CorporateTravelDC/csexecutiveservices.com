/* CS Executive Services — main.js */

(function () {
  'use strict';

  /* ── Scroll-aware navigation ─────────────────────────────── */
  const nav = document.querySelector('.nav');
  if (nav) {
    const onScroll = () => {
      nav.classList.toggle('nav-scrolled', window.scrollY > 40);
    };
    window.addEventListener('scroll', onScroll, { passive: true });
    onScroll();
  }

  /* ── Mobile menu ─────────────────────────────────────────── */
  const hamburger  = document.querySelector('.nav-hamburger');
  const mobileMenu = document.querySelector('.nav-mobile');
  const mobileClose = document.querySelector('.nav-mobile-close');

  if (hamburger && mobileMenu) {
    hamburger.addEventListener('click', () => {
      mobileMenu.classList.add('open');
      document.body.style.overflow = 'hidden';
      hamburger.setAttribute('aria-expanded', 'true');
      if (mobileClose) mobileClose.focus();
    });
    const closeMenu = () => {
      mobileMenu.classList.remove('open');
      document.body.style.overflow = '';
      hamburger.setAttribute('aria-expanded', 'false');
      hamburger.focus();
    };
    if (mobileClose) mobileClose.addEventListener('click', closeMenu);
    mobileMenu.querySelectorAll('a').forEach(a => a.addEventListener('click', closeMenu));
    mobileMenu.addEventListener('keydown', e => {
      if (e.key === 'Escape') closeMenu();
    });
  }

  /* ── Services dropdown (click for mobile, hover via CSS) ── */
  document.querySelectorAll('.nav-dropdown').forEach(dd => {
    const trigger = dd.querySelector('.nav-link');
    if (trigger) {
      trigger.setAttribute('aria-haspopup', 'true');
      trigger.setAttribute('aria-expanded', 'false');
      trigger.addEventListener('click', e => {
        if (window.innerWidth <= 768) {
          e.preventDefault();
          const isOpen = dd.classList.toggle('open');
          trigger.setAttribute('aria-expanded', String(isOpen));
        }
      });
      // Desktop: CSS :focus-within already reveals the menu on keyboard
      // focus (see style.css) -- mirror that state into aria-expanded so
      // screen readers announce it correctly too.
      dd.addEventListener('focusin', () => trigger.setAttribute('aria-expanded', 'true'));
      dd.addEventListener('focusout', e => {
        if (!dd.contains(e.relatedTarget)) trigger.setAttribute('aria-expanded', 'false');
      });
    }
  });
  document.addEventListener('click', e => {
    if (!e.target.closest('.nav-dropdown')) {
      document.querySelectorAll('.nav-dropdown.open').forEach(dd => {
        dd.classList.remove('open');
        const trigger = dd.querySelector('.nav-link');
        if (trigger) trigger.setAttribute('aria-expanded', 'false');
      });
    }
  });

  /* ── Fade-up on scroll (IntersectionObserver) ────────────── */
  const fadeObserver = new IntersectionObserver(
    entries => entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible');
        fadeObserver.unobserve(entry.target);
      }
    }),
    { threshold: 0.12, rootMargin: '0px 0px -40px 0px' }
  );
  document.querySelectorAll('.fade-up').forEach(el => fadeObserver.observe(el));

  /* ── Contact form ────────────────────────────────────────── */
  const form      = document.getElementById('contact-form');
  const statusEl  = document.getElementById('form-status');
  const submitBtn = document.getElementById('form-submit');

  const CONTACT_DIRECT =
    'Please correspond with the firm directly at ' +
    '<a href="mailto:reservations@csexecutiveservices.com" class="status-link">' +
    'reservations@csexecutiveservices.com</a> or by telephone at ' +
    '<a href="tel:+15715402261" class="status-link">(571) 540-2261</a>. ' +
    'Your enquiry will receive the same attention by either means.';

  function showSuccess(container, headline, body) {
    const panel = document.createElement('div');
    panel.className = 'form-thankyou fade-up visible';
    panel.innerHTML =
      '<div class="form-thankyou-mark">✓</div>' +
      '<h3>' + headline + '</h3>' +
      '<p>' + body + '</p>';
    container.replaceWith(panel);
  }

  function showUnavailable(container) {
    const panel = document.createElement('div');
    panel.className = 'form-unavailable fade-up visible';
    panel.innerHTML =
      '<span class="eyebrow">Direct Correspondence</span>' +
      '<h3>The Online Enquiry<br>Service Is Temporarily Unavailable</h3>' +
      '<div class="rule"></div>' +
      '<p>' + CONTACT_DIRECT + '</p>';
    container.replaceWith(panel);
  }

  if (form) {
    form.addEventListener('submit', async e => {
      e.preventDefault();

      const data = {
        name:      form.elements['name']?.value?.trim()    || '',
        email:     form.elements['email']?.value?.trim()   || '',
        phone:     form.elements['phone']?.value?.trim()   || '',
        service:   form.elements['service']?.value         || '',
        message:   form.elements['message']?.value?.trim() || '',
        preferred: form.elements['preferred']?.value       || '',
      };

      if (!data.name || !data.email || !data.message) {
        showStatus('error', 'Please complete all required fields before submitting.');
        return;
      }

      submitBtn.disabled = true;
      submitBtn.textContent = 'Sending…';

      try {
        const res  = await fetch('/api/contact', {
          method:  'POST',
          headers: { 'Content-Type': 'application/json' },
          body:    JSON.stringify(data),
        });
        const json = await res.json();

        if (res.ok) {
          showSuccess(
            form,
            'Enquiry Received',
            json.message ||
            'Your enquiry has been received and will be attended to in confidence. ' +
            'A member of the firm will be in contact by your preferred means at the earliest suitable moment.'
          );
        } else if (res.status === 503 || json.status === 'unavailable') {
          showUnavailable(form);
        } else {
          throw new Error(json.detail || 'An unexpected error occurred.');
        }
      } catch (_) {
        showUnavailable(form);
      } finally {
        if (submitBtn) {
          submitBtn.disabled = false;
          submitBtn.textContent = 'Submit Enquiry';
        }
      }
    });
  }

  function showStatus(type, msg) {
    if (!statusEl) return;
    statusEl.innerHTML = msg;
    statusEl.className = 'form-status ' + type;
    statusEl.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }

  /* ── Smooth scroll for anchor links ─────────────────────── */
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  document.querySelectorAll('a[href^="#"]').forEach(a => {
    a.addEventListener('click', e => {
      const target = document.querySelector(a.getAttribute('href'));
      if (target) {
        e.preventDefault();
        const top = target.getBoundingClientRect().top + window.scrollY
                    - parseInt(getComputedStyle(document.documentElement)
                        .getPropertyValue('--nav-h') || '80', 10) - 16;
        window.scrollTo({ top, behavior: reduceMotion ? 'auto' : 'smooth' });
      }
    });
  });

})();
