# CS Executive Services — Hybrid Hosting Runbook

**Architecture:** Pi (primary) → CF Worker → CF Pages (secondary) → GitHub Pages (tertiary)
**Endpoint:** `wrangler.csexecutiveservices.com` — internal CF tunnel origin  
**HA expansion:** `wrangler-002`, `wrangler-iad`, `wrangler-iad-hot` as infrastructure grows

---

## Overview

```
Browser → CF Worker (www.csexecutiveservices.com)
              │
              ├─ Pi up   → wrangler.csexecutiveservices.com (tunnel, outbound only)
              │               └─ nginx :80 + FastAPI contact-api :8002
              │
              ├─ Pi down → csexec-pages.pages.dev (CF Pages, deployed via wrangler)
              │               └─ /api/contact → 503 JSON → main.js shows mailto
              │
              └─ CF down → corporatetraveldc.github.io/csexecutiveservices-website
                              (auto-updated on every git push to main)
```

**All outbound from Pi. Nothing writes inward to Pi.**

---

## Prerequisites

### Node.js / npm check
```bash
node --version   # need 18.0+
npm  --version
```
If Node < 18:
```bash
# On RPi OS / Fedora:
curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
sudo dnf install -y nodejs         # Fedora
# or
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -
sudo apt-get install -y nodejs     # RPi OS
```

### Install wrangler globally
```bash
npm install -g wrangler
wrangler --version   # confirm
```

---

## Step 1 — Cloudflare API Token

You need a token with Workers and Pages permissions.

1. Go to https://dash.cloudflare.com/profile/api-tokens
2. Click **Create Token** → **Create Custom Token**
3. Set the following permissions:

| Resource | Scope | Permission |
|---|---|---|
| Account | Cloudflare Pages | Edit |
| Account | Workers Scripts | Edit |
| Zone | Zone | Read |
| Zone | DNS | Edit |
| Zone | Workers Routes | Edit |

4. Under **Zone Resources** → select `csexecutiveservices.com`
5. Click **Continue to Summary** → **Create Token**
6. Copy the token — it will not be shown again

Store on Pi (mode 0600, never commit):
```bash
sudo tee /etc/corporatetraveldc/cloudflare.env > /dev/null << 'EOF'
CLOUDFLARE_API_TOKEN=<paste-token-here>
EOF
sudo chmod 0600 /etc/corporatetraveldc/cloudflare.env
```

Authenticate wrangler:
```bash
export CLOUDFLARE_API_TOKEN=$(grep CLOUDFLARE_API_TOKEN /etc/corporatetraveldc/cloudflare.env | cut -d= -f2)
wrangler whoami   # confirm auth works
```

Add to your shell or deploy script source:
```bash
# Add to /opt/csexec-website/deploy.sh top (already scaffolded):
source /etc/corporatetraveldc/cloudflare.env
export CLOUDFLARE_API_TOKEN
```

---

## Step 2 — DNS: wrangler endpoint

In Cloudflare dashboard → csexecutiveservices.com → DNS:

| Type | Name | Target | Proxy |
|---|---|---|---|
| CNAME | `wrangler` | `<tunnel-uuid>.cfargotunnel.com` | ✓ Proxied (orange cloud) |

Get your tunnel UUID:
```bash
cloudflared tunnel list
# copy the UUID for the csexec tunnel
```

This is the only DNS record the CF Worker uses to reach the Pi.
**Future nodes:** add `wrangler-002`, `wrangler-iad`, `wrangler-iad-hot` here
pointing at additional tunnel UUIDs or cloud IPs as infrastructure grows.

---

## Step 3 — cloudflared tunnel config

Edit `~/.cloudflared/config.yml` on the Pi.
Add the wrangler ingress rule **before** existing www route:

```yaml
ingress:
  # Wrangler endpoint — CF Worker → Pi web server (internal, CF-proxied)
  - hostname: wrangler.csexecutiveservices.com
    service: http://127.0.0.1:80

  # Existing routes (keep as-is)
  - hostname: www.csexecutiveservices.com
    service: http://127.0.0.1:80
  # ... dispatch, adsb, pihole, etc. ...
  - service: http_status:404
```

Restart tunnel:
```bash
sudo systemctl restart cloudflared
# or if running as user:
systemctl --user restart cloudflared
```

Verify new route is reachable:
```bash
curl -sI https://wrangler.csexecutiveservices.com/healthz
# should return 200 from Pi nginx
```

---

## Step 4 — CF Pages project

Create the project (one-time setup):
```bash
cd /opt/csexec-website
source /etc/corporatetraveldc/cloudflare.env
export CLOUDFLARE_API_TOKEN

wrangler pages project create csexec-pages --production-branch main
```

First deploy:
```bash
wrangler pages deploy www/ --project-name csexec-pages
# note the pages.dev URL shown — update CF_PAGES in cloudflare/worker.js if different
```

Default URL: `https://csexec-pages.pages.dev`
If Cloudflare assigns a different slug, update `CF_PAGES` in `cloudflare/worker.js`.

---

## Step 5 — Deploy the CF Worker

```bash
cd /opt/csexec-website
source /etc/corporatetraveldc/cloudflare.env
export CLOUDFLARE_API_TOKEN

wrangler deploy
```

Verify the Worker is routing correctly:
```bash
# Pi up — should serve live Pi content
curl -sI https://www.csexecutiveservices.com/

# Contact form — Pi up
curl -s -X POST https://www.csexecutiveservices.com/api/contact \
  -H "Content-Type: application/json" \
  -d '{"name":"Test","email":"test@test.com","message":"Test"}'
# should return {"status":"received"}
```

---

## Step 6 — GitHub Pages (tertiary failsafe)

**Requires PAT with `workflow` scope** — the deploy PAT (Contents only) cannot
write to `.github/workflows/`.

**Option A — GitHub web UI (easiest):**
1. Go to https://github.com/CorporateTravelDC/csexecutiveservices-website
2. Click **Add file → Create new file**
3. Filename: `.github/workflows/pages.yml`
4. Paste contents from `cloudflare/github-pages-workflow.yml` in this repo
5. Commit directly to main

**Option B — update PAT and push from Pi:**
1. Go to https://github.com/settings/tokens → edit the deploy PAT
2. Add the `workflow` scope
3. On Pi:
```bash
cp cloudflare/github-pages-workflow.yml .github/workflows/pages.yml
git add .github/workflows/pages.yml
git commit -m "feat: GitHub Pages tertiary failsafe workflow"
git push origin main
```

After the workflow is in place, verify at:
https://github.com/CorporateTravelDC/csexecutiveservices-website/actions

---

## Step 7 — First full deploy

```bash
cd /opt/csexec-website
chmod +x deploy.sh
./deploy.sh
```

Expected output:
```
=== CS Executive Services — deploy ===
[1/3] git push → GitHub Pages (tertiary failsafe)
[2/3] wrangler pages deploy → CF Pages (secondary fallback)
[3/3] wrangler deploy → CF Worker (smart router)
=== deploy complete ===
```

---

## Verification — all three layers

```bash
# Layer 1: Pi primary (tunnel up)
curl -sI https://www.csexecutiveservices.com/
# expect: 200, served from Pi nginx

# Layer 2: CF Pages direct (bypass Worker)
curl -sI https://csexec-pages.pages.dev/
# expect: 200, static site

# Layer 3: GitHub Pages direct (bypass everything)
curl -sI https://corporatetraveldc.github.io/csexecutiveservices-website/
# expect: 200, static site
```

Simulate Pi down (temporarily stop cloudflared on Pi):
```bash
sudo systemctl stop cloudflared
# wait ~5s, then from a browser:
# https://www.csexecutiveservices.com/ — should serve CF Pages
# https://www.csexecutiveservices.com/contact.html — form hidden, mailto shown
sudo systemctl start cloudflared
```

---

## HA Expansion (future)

When adding `wrangler-002`, `wrangler-iad`, or `wrangler-iad-hot`:

1. Add DNS CNAME in Cloudflare → new tunnel UUID or cloud IP
2. Add ingress rule in cloudflared config on new node
3. Update `cloudflare/worker.js` — add fallback logic after primary wrangler endpoint:
   ```js
   const WRANGLER_002 = "https://wrangler-002.csexecutiveservices.com";
   const WRANGLER_IAD = "https://wrangler-iad.csexecutiveservices.com";
   ```
4. Redeploy Worker: `wrangler deploy`

No other changes needed — the endpoint chain extends naturally.

---

## File inventory (this repo)

| File | Purpose |
|---|---|
| `cloudflare/worker.js` | CF Worker smart router |
| `wrangler.toml` | Wrangler config — Worker routes |
| `deploy.sh` | Pi deploy script — git + pages + worker |
| `cloudflare/cloudflared-config-patch.yaml` | Tunnel ingress rule for wrangler endpoint |
| `cloudflare/github-pages-workflow.yml` | GH Actions workflow (manual placement) |
| `www/js/main.js` | 503 handling — hides form, shows mailto |
| `docs/DEPLOY-HYBRID.md` | This document |
