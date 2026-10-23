"""
LinkedIn -> Notion CRM clipboard monitor.

Copy a person's details from LinkedIn (their profile URL, or select the top of
their profile - name, headline, location - and press Ctrl+C). This script
notices the new clipboard content, pulls out the useful fields and adds a row
to your Notion database. No scraping, no browser automation: you stay in
control of what gets copied, so your LinkedIn account isn't put at risk.

Setup (see README.md for screenshots-free step by step):
    pip install -r requirements.txt
    set NOTION_TOKEN and NOTION_DATABASE_ID (env vars or the CONFIG below)
    python clipboard_to_notion.py

Stop it with Ctrl+C in the terminal.
"""

import argparse
import os
import re
import sys
import time

import pyperclip
import requests

# ---------------------------------------------------------------------------
# CONFIG - either fill these in, or set environment variables of the same name.
# ---------------------------------------------------------------------------
NOTION_TOKEN = os.environ.get("NOTION_TOKEN", "")            # starts with "ntn_" or "secret_"
NOTION_DATABASE_ID = os.environ.get("NOTION_DATABASE_ID", "")  # the database link or its 32-char ID

# Names of the columns in your Notion database. Columns that don't exist in
# your database are skipped automatically, so you only need the ones you want.
# The title column (usually "Name") is detected automatically.
COLUMNS = {
    "linkedin": "LinkedIn",   # URL type
    "headline": "Headline",   # Text type
    "company": "Company",     # Text type
    "location": "Location",   # Text type
    "email": "Email",         # Email type
    "status": "Status",       # Select (or Status) type
    "notes": "Notes",         # Text type - the full copied text goes here
}
DEFAULT_STATUS = "To contact"

POLL_SECONDS = 0.5
NOTION_VERSION = "2022-06-28"
API = "https://api.notion.com/v1"

LINKEDIN_URL_RE = re.compile(r"https?://(?:[a-z]{2,3}\.)?linkedin\.com/in/[A-Za-z0-9\-_%]+/?", re.I)
EMAIL_RE = re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")
# Lines LinkedIn puts around a profile's top card that aren't useful data.
NOISE_RE = re.compile(
    r"^(he/him|she/her|they/them|·?\s*(1st|2nd|3rd\+?)|contact info|message|follow|connect|more|"
    r"\d[\d,+]*\s+(followers|connections)|.*mutual connection.*|open to|view .*|show all.*|"
    r"verified|premium|·)$",
    re.I,
)


# ---------------------------------------------------------------------------
# Parsing the copied text
# ---------------------------------------------------------------------------
def slug_to_name(url):
    """linkedin.com/in/jane-doe-1a2b3c -> 'Jane Doe'."""
    slug = url.rstrip("/").split("/in/")[-1]
    parts = [p for p in slug.split("-") if p and not re.search(r"\d", p)]
    return " ".join(p.capitalize() for p in parts) or slug


def parse_contact(text):
    """Turn whatever was copied into a dict of CRM fields."""
    text = text.strip()
    url_match = LINKEDIN_URL_RE.search(text)
    email_match = EMAIL_RE.search(text)
    contact = {
        "linkedin": url_match.group(0).split("?")[0] if url_match else "",
        "email": email_match.group(0) if email_match else "",
        "name": "", "headline": "", "company": "", "location": "",
        "notes": text,
    }

    lines = []
    for raw in text.splitlines():
        line = raw.strip().strip("·").strip()
        if not line or NOISE_RE.match(line) or line.startswith("http") or EMAIL_RE.fullmatch(line):
            continue
        if line not in lines:  # LinkedIn often repeats the name (e.g. alt text)
            lines.append(line)

    if lines:
        contact["name"] = lines[0]
    if len(lines) > 1:
        contact["headline"] = lines[1]
    # Location: usually a later short line with a comma and no "at"/"|", e.g. "Pune, Maharashtra, India".
    for line in lines[2:]:
        if "," in line and len(line) < 80 and not re.search(r"\bat\b|@|\|", line):
            contact["location"] = line
            break
    # Company: "Software Engineer at Acme" / "Founder @ Acme | ..." in the headline.
    m = re.search(r"(?:\bat\b|@)\s+([^|,·•]+)", contact["headline"])
    if m:
        contact["company"] = m.group(1).strip()

    if not contact["name"] and contact["linkedin"]:
        contact["name"] = slug_to_name(contact["linkedin"])
    return contact


def looks_like_contact(text, accept_all):
    """Decide whether a clipboard change should become a CRM row."""
    text = text.strip()
    if not text or len(text) > 5000:
        return False
    if accept_all:
        return True
    # Profile URL, or a multi-line selection (name + headline + ...).
    return bool(LINKEDIN_URL_RE.search(text)) or len([l for l in text.splitlines() if l.strip()]) >= 2


# ---------------------------------------------------------------------------
# Notion
# ---------------------------------------------------------------------------
class Notion:
    def __init__(self, token, database):
        # Accepts the full database link, a plain 32-char ID, or a dashed UUID.
        m = re.search(r"(?<![0-9a-f])([0-9a-f]{32}|[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})(?![0-9a-f])",
                      database, re.I)
        if not m:
            sys.exit("NOTION_DATABASE_ID doesn't look right - paste the database link or its 32-character ID.")
        self.db_id = m.group(1).replace("-", "")
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Bearer {token}",
            "Notion-Version": NOTION_VERSION,
            "Content-Type": "application/json",
        })
        self.schema = self._load_schema()
        self.title_prop = next(n for n, p in self.schema.items() if p["type"] == "title")

    def _request(self, method, path, **kwargs):
        r = self.session.request(method, f"{API}{path}", timeout=20, **kwargs)
        if r.status_code >= 400:
            try:
                msg = r.json().get("message", r.text)
            except ValueError:
                msg = r.text
            raise RuntimeError(f"Notion API {r.status_code}: {msg}")
        return r.json()

    def _load_schema(self):
        try:
            db = self._request("GET", f"/databases/{self.db_id}")
        except RuntimeError as e:
            sys.exit(f"{e}\nCheck your token, the database ID, and that the database is shared with your "
                     "integration (database ... menu -> Connections -> add your integration).")
        return db["properties"]

    def find_by_linkedin(self, url):
        col = COLUMNS["linkedin"]
        if not url or self.schema.get(col, {}).get("type") != "url":
            return None
        body = {"filter": {"property": col, "url": {"equals": url}}, "page_size": 1}
        results = self._request("POST", f"/databases/{self.db_id}/query", json=body)["results"]
        return results[0] if results else None

    def _value(self, prop_type, value):
        if prop_type == "title":
            return {"title": _rich_text(value)}
        if prop_type == "rich_text":
            return {"rich_text": _rich_text(value)}
        if prop_type == "url":
            return {"url": value}
        if prop_type == "email":
            return {"email": value}
        if prop_type == "select":
            return {"select": {"name": value}}
        if prop_type == "status":
            return {"status": {"name": value}}
        return None  # column type we don't fill in

    def add_contact(self, contact):
        props = {self.title_prop: {"title": _rich_text(contact["name"] or "Unknown")}}
        values = dict(contact, status=DEFAULT_STATUS)
        for field, col in COLUMNS.items():
            value = values.get(field)
            if not value or col not in self.schema or col == self.title_prop:
                continue
            prop = self._value(self.schema[col]["type"], value)
            if prop:
                props[col] = prop
        body = {"parent": {"database_id": self.db_id}, "properties": props}
        return self._request("POST", "/pages", json=body)


def _rich_text(value):
    # Notion caps each text chunk at 2000 characters.
    return [{"type": "text", "text": {"content": value[i:i + 2000]}} for i in range(0, len(value), 2000)][:100]


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Send copied LinkedIn details to a Notion CRM.")
    parser.add_argument("--all", action="store_true",
                        help="send every clipboard copy (default: only LinkedIn URLs or multi-line selections)")
    parser.add_argument("--dry-run", action="store_true", help="print what would be sent, don't touch Notion")
    args = parser.parse_args()

    notion = None
    if not args.dry_run:
        if not NOTION_TOKEN or not NOTION_DATABASE_ID:
            sys.exit("Set NOTION_TOKEN and NOTION_DATABASE_ID first (see README.md).")
        notion = Notion(NOTION_TOKEN, NOTION_DATABASE_ID)
        skipped = [c for c in COLUMNS.values() if c not in notion.schema]
        print(f"Connected to Notion. Title column: '{notion.title_prop}'.")
        if skipped:
            print(f"Columns not in your database (will be skipped): {', '.join(skipped)}")

    print("Watching the clipboard. Copy a LinkedIn profile URL or its name/headline block. Ctrl+C to stop.\n")
    last = pyperclip.paste()  # ignore whatever was already copied before starting
    try:
        while True:
            time.sleep(POLL_SECONDS)
            try:
                current = pyperclip.paste()
            except pyperclip.PyperclipException:
                continue
            if current == last:
                continue
            last = current
            if not looks_like_contact(current, args.all):
                continue

            contact = parse_contact(current)
            summary = " | ".join(v for v in (contact["name"], contact["headline"], contact["location"]) if v)
            if args.dry_run:
                print(f"[dry run] {contact}")
                continue
            try:
                if notion.find_by_linkedin(contact["linkedin"]):
                    print(f"Already in CRM, skipped: {summary}")
                    continue
                notion.add_contact(contact)
                print(f"Added: {summary}")
            except (RuntimeError, requests.RequestException) as e:
                print(f"Failed to add {contact['name'] or 'contact'}: {e}")
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
