"""
CS Executive Services — Contact Form API
POST /api/contact → email notification → JSON response.
Runs on port 8002; nginx proxy_pass from /api/contact.
"""
import hashlib, os, smtplib, subprocess, sys, tempfile, logging
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime, timezone
from pathlib import Path
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("contact-api")

_APP_DIR = Path(__file__).resolve().parent
_SELF_MANIFEST_KEY = "contact-api/main.py"


def _verify_self() -> None:
    """Signed-manifest integrity self-check, run before the app object even
    exists. See security/ + scripts/verify-manifest.sh at this repo's root,
    and ctdi-dispatch-internal's docs/COMPLIANCE_SECURITY.md "Signed
    Manifest Integrity" for the full design this mirrors. This service does
    real, credentialed SMTP relay through ProtonMail Bridge on a
    public-facing endpoint (POST /api/contact) -- the same "public trigger +
    real side effect" pattern that made the honeypot's fail2ban actions
    worth protecting the same way.

    Doesn't shell out to scripts/verify-manifest.sh -- that script assumes
    the manifest's path key matches the file's cwd-relative on-disk
    location, but main.py is deliberately flattened to /app/main.py here
    (not /app/contact-api/main.py): "contact-api" has a hyphen and can't be
    a Python package name for uvicorn's "main:app" target. Does the same two
    checks directly instead: GPG-verify MANIFEST.sha256's signature against
    the baked-in public key, then compare this file's own hash against its
    "contact-api/main.py" entry in that manifest.
    """
    manifest = _APP_DIR / "MANIFEST.sha256"
    signature = _APP_DIR / "MANIFEST.sha256.asc"
    pubkey = _APP_DIR / "trusted-signing-key.pub.asc"
    for f in (manifest, signature, pubkey):
        if not f.exists():
            print(f"contact-api: INTEGRITY CHECK FAILED -- missing {f}", file=sys.stderr)
            sys.exit(1)

    with tempfile.TemporaryDirectory() as gnupghome:
        os.chmod(gnupghome, 0o700)
        env = {**os.environ, "GNUPGHOME": gnupghome}
        subprocess.run(["gpg", "--quiet", "--import", str(pubkey)],
                        env=env, capture_output=True)
        verify = subprocess.run(
            ["gpg", "--quiet", "--verify", str(signature), str(manifest)],
            env=env, capture_output=True, text=True,
        )
        if verify.returncode != 0:
            print(f"contact-api: INTEGRITY CHECK FAILED -- signature invalid: {verify.stderr.strip()}",
                  file=sys.stderr)
            sys.exit(1)

    expected_hash = None
    for line in manifest.read_text().splitlines():
        h, _, path = line.partition("  ")
        if path == _SELF_MANIFEST_KEY:
            expected_hash = h
            break
    if expected_hash is None:
        print(f"contact-api: INTEGRITY CHECK FAILED -- {_SELF_MANIFEST_KEY} not in signed manifest",
              file=sys.stderr)
        sys.exit(1)

    actual_hash = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    if actual_hash != expected_hash:
        print(f"contact-api: INTEGRITY CHECK FAILED -- main.py hash mismatch "
              f"(expected {expected_hash}, got {actual_hash})", file=sys.stderr)
        sys.exit(1)


_verify_self()

app = FastAPI(title="csexec-contact", docs_url=None, redoc_url=None)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://www.csexecutiveservices.com",
        "https://csexecutiveservices.com",
    ],
    allow_methods=["POST", "OPTIONS"],
    allow_headers=["Content-Type"],
)

SMTP_HOST   = os.getenv("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT   = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER   = os.getenv("SMTP_USER", "")
SMTP_PASS   = os.getenv("SMTP_PASS", "")
NOTIFY_TO   = os.getenv("NOTIFY_TO", "reservations@csexecutiveservices.com")
NOTIFY_FROM = os.getenv("NOTIFY_FROM", SMTP_USER)


class ContactRequest(BaseModel):
    name:      str
    email:     str
    phone:     str = ""
    service:   str = ""
    message:   str
    preferred: str = ""


@app.get("/healthz")
def healthz():
    return {"status": "ok", "service": "csexec-contact"}


@app.post("/api/contact")
async def contact(req: ContactRequest):
    log.info("Contact form submission — name=%s email=%s service=%s",
             req.name, req.email, req.service)

    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    subject = f"[CS Executive Services] New enquiry from {req.name}"
    body = (
        f"New contact form submission — {ts}\n\n"
        f"Name:      {req.name}\n"
        f"Email:     {req.email}\n"
        f"Phone:     {req.phone or '(not provided)'}\n"
        f"Service:   {req.service or '(not specified)'}\n"
        f"Reply via: {req.preferred or '(not specified)'}\n\n"
        f"Message:\n{req.message}\n"
        f"---\nSubmitted via csexecutiveservices.com"
    )

    if SMTP_USER and SMTP_PASS:
        try:
            msg = MIMEMultipart()
            msg["From"]     = NOTIFY_FROM
            msg["To"]       = NOTIFY_TO
            msg["Subject"]  = subject
            msg["Reply-To"] = req.email
            msg.attach(MIMEText(body, "plain"))
            with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as srv:
                srv.ehlo()
                srv.starttls()
                srv.login(SMTP_USER, SMTP_PASS)
                srv.sendmail(NOTIFY_FROM, [NOTIFY_TO], msg.as_string())
            log.info("Notification sent to %s", NOTIFY_TO)
        except Exception as e:
            log.error("SMTP error (submission still logged): %s", e)
    else:
        log.warning("SMTP not configured — submission logged only")

    return {
        "status": "received",
        "message": (
            "Your enquiry has been received and will be attended to in confidence. "
            "A member of the firm will be in contact by your preferred means "
            "at the earliest suitable moment."
        ),
    }
