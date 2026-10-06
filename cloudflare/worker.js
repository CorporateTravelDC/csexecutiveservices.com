/**
 * CS Executive Services — Cloudflare Worker Smart Router
 * Deployed at: www.csexecutiveservices.com + csexecutiveservices.com
 *
 * Endpoint chain:
 *   wrangler.csexecutiveservices.com  → Pi (primary, outbound CF tunnel)
 *   csexec-pages.pages.dev             → CF Pages (secondary fallback)
 *   corporatetraveldc.github.io/...   → GitHub Pages (tertiary failsafe)
 *
 * HA expansion convention (future nodes):
 *   wrangler-002.csexecutiveservices.com   second Pi node
 *   wrangler-iad.csexecutiveservices.com   IAD-region cache / cloud node
 *   wrangler-iad-hot.csexecutiveservices.com  hot standby
 *
 * Contact form (/api/contact POST):
 *   Pi up   → proxied through tunnel
 *   Pi down → 503 JSON, main.js renders mailto fallback
 *
 * 2026-09-03: CF_PAGES was pointing at csexec-site.pages.dev, a project
 * that was never actually deployed under that name -- the real Pages
 * project (confirmed live via the Cloudflare API) is csexec-pages, so
 * the secondary-fallback tier had silently been a dead URL. Fixed to
 * csexec-pages.pages.dev, found while re-minting the consolidated
 * management API token.
 */

const WRANGLER   = "https://wrangler.csexecutiveservices.com";
const CF_PAGES   = "https://csexec-pages.pages.dev";
const GH_PAGES   = "https://corporatetraveldc.github.io/csexecutiveservices-website";
const PI_TIMEOUT = 3000; // ms — adjust upward for slower Pi cold-starts

export default {
  async fetch(request, env, ctx) {
    const url    = new URL(request.url);
    const isPost = request.method === "POST";
    const isAPI  = url.pathname.startsWith("/api/");

    // ── Primary: Pi via wrangler tunnel endpoint ──────────────────────
    try {
      const upstream = new Request(
        WRANGLER + url.pathname + url.search,
        {
          method:  request.method,
          headers: request.headers,
          body:    isPost ? request.body : undefined,
        }
      );

      const resp = await Promise.race([
        fetch(upstream),
        new Promise((_, reject) =>
          setTimeout(() => reject(new Error("timeout")), PI_TIMEOUT)
        ),
      ]);

      if (resp.ok || (isAPI && resp.status < 500)) {
        const out = new Response(resp.body, resp);
        out.headers.delete("x-workers-subrequest-id");
        return out;
      }
    } catch (_) {
      // Pi unreachable — fall through
    }

    // ── Contact form: Pi is down ──────────────────────────────────────
    // Returns structured 503; main.js hides form and shows mailto
    if (isAPI && isPost) {
      return new Response(
        JSON.stringify({ status: "unavailable" }),
        {
          status:  503,
          headers: { "Content-Type": "application/json",
                     "Cache-Control": "no-store" },
        }
      );
    }

    // ── Secondary: CF Pages static fallback ──────────────────────────
    try {
      const cfPath = url.pathname === "/" ? "/index.html" : url.pathname;
      const cfResp = await fetch(CF_PAGES + cfPath);
      if (cfResp.ok) return cfResp;
    } catch (_) {}

    // ── Tertiary: GitHub Pages failsafe ──────────────────────────────
    return Response.redirect(
      GH_PAGES + (url.pathname === "/" ? "" : url.pathname),
      302
    );
  },
};
