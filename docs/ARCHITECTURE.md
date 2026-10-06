# CS Executive Services — Infrastructure Architecture

> Canonical reference for all endpoint naming, network topology, and scaling conventions.
> All infrastructure decisions derive from the principles below.

---

## Core Principles

1. **Self-hosted root of trust.** The Pi is the authoritative origin for all services.
   External platforms (Cloudflare, GitHub) are delivery and fallback layers only —
   never the source of truth.

2. **Outbound-only external integrations.** No external platform may write to, call into,
   or trigger actions on Pi infrastructure. All external updates originate from the Pi.

3. **No vendor lock-in by design.** Every external dependency is replaceable.
   Cloudflare is a proxy, not a platform. GitHub is a remote, not a host.

4. **Privacy and discretion at every layer.** No contact data, client data, or operational
   data touches third-party storage. Fallback paths fail gracefully to direct correspondence.

---

## Endpoint Naming Convention

### Pattern

```
[oneword][-xxx|regional].csexecutiveservices.com
```

- **`oneword`** — single lowercase word describing the service function. No hyphens.
- **`-xxx`** — optional numeric suffix for additional nodes: `-002`, `-003`
- **`-regional`** — optional 2–3 char regional identifier: `-iad`, `-bwi`, `-dca`, `-va`, `-dc`
- Suffixes may be combined: `wrangler-iad-hot`, `dispatch-002`

### Why this convention

- Operationally self-documenting: the principal knows exactly what every endpoint does
- Scales naturally: new nodes follow the same pattern without retrofitting
- Signals mature, intentional infrastructure to informed observers
- Avoids generic names (`origin`, `backend`, `api`) that reveal architecture to scrapers
  without adding operational clarity

### Current endpoints

| Endpoint | Service | Node |
|---|---|---|
| `dispatch.csexecutiveservices.com` | CorporateTravelDC dispatch platform | Pi-001 |
| `dispatch-runner.csexecutiveservices.com` | Dispatch PWA (FastAPI, port 8001) | Pi-001 |
| `adsb.csexecutiveservices.com` | UltraFeeder ADS-B receiver | Pi-001 |
| `pihole.csexecutiveservices.com` | Pi-hole DNS + ad-block admin | Pi-001 |
| `cloud.csexecutiveservices.com` | Nextcloud | Pi-001 |
| `wrangler.csexecutiveservices.com` | CF tunnel origin — CF Worker hot path | Pi-001 |
| `www.csexecutiveservices.com` | Public website (served via CF Worker) | CF + Pi-001 |

### HA expansion path

| Future endpoint | Purpose |
|---|---|
| `wrangler-002.csexecutiveservices.com` | Second Pi node |
| `wrangler-iad.csexecutiveservices.com` | IAD-region cache or cloud node |
| `wrangler-iad-hot.csexecutiveservices.com` | Hot standby at IAD |
| `dispatch-002.csexecutiveservices.com` | Dispatch failover node |
| `adsb-bwi.csexecutiveservices.com` | BWI-area ADS-B receiver |

When a new node comes online:
1. Add DNS CNAME in Cloudflare → new tunnel UUID or cloud IP
2. Add ingress rule in cloudflared config on the new node
3. Reference the new endpoint in the relevant Worker or service config
4. Document here

---

## Network Topology

```
                        ┌─────────────────────────────┐
                        │   csexecutiveservices.com    │
                        │   Cloudflare DNS + Proxy     │
                        └──────────────┬──────────────┘
                                       │
                    ┌──────────────────┼──────────────────┐
                    │                  │                   │
            www / wrangler         dispatch            adsb / pihole / cloud
            CF Worker routes       CF tunnel           CF tunnel
                    │                  │                   │
                    ▼                  ▼                   ▼
         ┌──────────────────────────────────────────────────────┐
         │                  Pi-001 (BCM2712)                    │
         │              Arlington County, VA                    │
         │                                                      │
         │  nginx :80          dispatch FastAPI :8000           │
         │  contact-api :8002  dispatch-runner :8001            │
         │  Nextcloud          Pi-hole                          │
         │  UltraFeeder        cloudflared (outbound tunnel)    │
         └──────────────────────────────────────────────────────┘
```

### Cloudflare tunnel (cloudflared)

- Single outbound persistent connection: Pi → Cloudflare edge
- All traffic to CF-proxied hostnames routes inbound through this tunnel
- Pi initiates; CF never initiates connections to Pi
- Tailscale provides secondary authenticated access path (`csexecutiveservices.ts.net`)

### Honeypot / fail2ban (shared with the dispatch platform)

- `nginx/snippets/honeypot-website.conf` (this repo) logs to the SAME shared
  `/var/log/nginx/honeypot.log` the dispatch platform's honeypot uses, so
  hits here are banned by the same `nginx-honeypot-corporatetraveldc`
  fail2ban jail -- no separate jail, action, or Cloudflare wiring for this
  site; it inherits everything (local firewalld ban + Cloudflare-edge IP
  Access Rule ban) automatically.
- The ban/unban scripts, the SELinux modules they need, and the standing
  "verify response body, verify identity before delete" convention for any
  external-API action live in `ctdi-dispatch-internal`
  (`docs/COMPLIANCE_SECURITY.md`'s "External API Action Safety Pattern",
  `docs/HONEYPOT_FAIL2BAN.md`) -- not duplicated here. A fix there is live
  for both properties immediately (the fail2ban action calls the script by
  its absolute repo path, not a copy), which is why this repo has no
  fail2ban/SELinux files of its own beyond the one nginx snippet.

### Fallback chain (website)

```
Browser → CF Worker (www.)
    1. wrangler.        Pi via tunnel (primary, 3s timeout)
    2. csexec-site.     CF Pages via wrangler deploy (secondary)
    3. github.io/...    GitHub Pages via git push (tertiary)
```

---

## Credentials and Secrets

| Credential | Location | Scope |
|---|---|---|
| Cloudflare API token | `/etc/corporatetraveldc/cloudflare.env` (0600) | Workers:Edit, Pages:Edit, DNS:Edit |
| GitHub deploy PAT | `/etc/corporatetraveldc/github.env` (0600) | Contents:Write |
| FAA SWIM / SCDS | `/etc/corporatetraveldc/dispatch-secrets.env` (0600) | SWIM feeds |
| SMTP (contact form) | `/etc/corporatetraveldc/contact.env` (0600) | ProtonMail SMTP |

All secrets: mode 0600, never committed to any repository.

---

*Maintained in `csexecutiveservices-website`. All updates require principal approval.*
*Standing directive: applies to all CS Executive Services infrastructure, present and future.*
