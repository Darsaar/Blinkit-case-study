# LinkedIn → Notion CRM (clipboard monitor)

A free alternative to paid outreach tools. You copy someone's details on LinkedIn
the way you normally would (Ctrl+C / Cmd+C). The script sees what you copied and adds a row to your
Notion CRM database.

It doesn't scrape anything or control your browser. You decide what gets copied, so
LinkedIn has nothing to flag.

## What you can copy

| You copy | What gets saved |
|---|---|
| A profile URL, e.g. `https://www.linkedin.com/in/jane-doe-12ab/` | Name (taken from the URL), LinkedIn link |
| The top of a profile (select from the name down to the location) | Name, headline, company, location, plus the link/email if your selection includes them |

The full text you copied is also saved in a **Notes** column. A profile that's already in the
CRM (same LinkedIn URL) is skipped.

Single-line copies that aren't LinkedIn links, like a word or a password, are ignored. Run with `--all` if you
want every copy sent.

## Setup (about 10 minutes, one time only)

### 1. Install Python
Download it from <https://www.python.org/downloads/>. On Windows, tick **"Add Python to PATH"**
during install.

### 2. Install the two libraries
Open a terminal (Windows: Command Prompt, Mac: Terminal) in this folder and run:
```
pip install -r requirements.txt
```
(On Linux, pyperclip also needs `xclip` or `xsel`: `sudo apt install xclip`.)

### 3. Create the Notion database
Create a full-page **Database → Table** in Notion with these columns. The names must match
exactly. Leave out any column you don't want and the script will skip it.

| Column | Type |
|---|---|
| Name | Title (exists by default) |
| LinkedIn | URL |
| Headline | Text |
| Company | Text |
| Location | Text |
| Email | Email |
| Status | Select (or Status), with an option called `To contact` |
| Notes | Text |

You can use other column names by changing the `COLUMNS` section at the top of the script.

### 4. Create a Notion integration (the "token")
1. Go to <https://www.notion.so/profile/integrations> → **New integration**.
2. Give it a name like "LinkedIn CRM", choose your workspace, and save.
3. Copy the **Internal Integration Secret**. That's your `NOTION_TOKEN`.
4. Open your database in Notion → **•••** menu (top right) → **Connections** → add your
   integration. **If you skip this step you'll get a 404 error.**

### 5. Get the database ID
Open the database as a full page and copy the link from the browser. It looks like
`https://www.notion.so/yourname/0123456789abcdef0123456789abcdef?v=...`.
You can paste the whole link. The script finds the ID inside it.

### 6. Add your token and database ID
Option A: open `clipboard_to_notion.py` and fill in the two lines near the top:
```python
NOTION_TOKEN = os.environ.get("NOTION_TOKEN", "ntn_your_secret_here")
NOTION_DATABASE_ID = os.environ.get("NOTION_DATABASE_ID", "https://www.notion.so/...")
```
Option B: set them as environment variables:
```
# Mac / Linux
export NOTION_TOKEN="ntn_..."
export NOTION_DATABASE_ID="https://www.notion.so/..."

# Windows (Command Prompt)
set NOTION_TOKEN=ntn_...
set NOTION_DATABASE_ID=https://www.notion.so/...
```
Don't share the token or commit it to GitHub.

## Run it
```
python clipboard_to_notion.py
```
Leave the terminal open and go copy profiles on LinkedIn. Each one you add shows up as a line:
```
Added: Priya Sharma | Senior Data Analyst at Blinkit | Gurugram, Haryana, India
```
Press **Ctrl+C** in the terminal to stop.

To check what would be saved without touching Notion:
```
python clipboard_to_notion.py --dry-run
```

## Troubleshooting
- **`Notion API 401`**: the token is wrong or incomplete.
- **`Notion API 404`**: the database isn't connected to your integration (step 4.4), or the ID is wrong.
- **`Notion API 400 ... is not a property`** or a Status error: a column type doesn't match the table
  above, or the `To contact` option doesn't exist in your Status column.
- **Nothing happens when I copy**: single-line copies are ignored unless they're a LinkedIn
  link. Copy at least the name plus headline, or run with `--all`.
- **Name/company looks off**: LinkedIn's page layout varies. The full copied text is always
  in Notes, so you can fix the row by hand.

## Finding emails
This script saves the person and their company. For the email, use the same approach as the
Reddit thread: find the company's email pattern (e.g. `first.last@company.com`) on Hunter.io or
Apollo.io, then verify it there and paste it into the Email column.
