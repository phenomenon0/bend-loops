#!/usr/bin/env python3
"""bendq — one queryable evidence store for the Bend business. Stdlib only."""
import sqlite3, sys, re
from pathlib import Path
DB = Path.home() / ".local" / "state" / "bendq" / "evidence.db"

def conn():
    DB.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(DB)
    db.execute("CREATE TABLE IF NOT EXISTS docs(path TEXT PRIMARY KEY, repo TEXT, mtime REAL, text TEXT)")
    return db

def index(repo):
    repo = Path(repo).resolve(); db = conn(); n = 0
    for pat in ("docs/omen/**/*.md", "docs/omen/**/*.json", "demos/kernels/*.md", "power/**/*.md"):
        for f in repo.glob(pat):
            if f.is_file():
                db.execute("INSERT OR REPLACE INTO docs VALUES(?,?,?,?)",
                           (str(f.relative_to(repo)), str(repo), f.stat().st_mtime, f.read_text(errors="replace")))
                n += 1
    db.commit(); print(f"indexed {n} docs from {repo}")

def query(q, k=4):
    db = conn(); terms = [t for t in re.split(r"\s+", q) if t][:6]
    if not terms: print("usage: bendq.py query <terms>"); return
    where = " AND ".join(["text LIKE ?"] * len(terms))
    rows = db.execute(f"SELECT path, repo, text FROM docs WHERE {where} LIMIT 40", [f"%{t}%" for t in terms]).fetchall()
    seen = set()
    for path, repo, text in rows:
        if path in seen: continue
        seen.add(path)
        m = re.search(re.escape(terms[0]), text, re.I)
        snip = text[max(0, m.start()-120): m.start()+260].replace("\n", " ") if m else text[:200]
        print(f"[{Path(repo).name}] {path}\n  …{snip}…\n")
        if len(seen) >= k: break
    if not seen: print("(no matches — indexed repos: check `bendq.py stats`)")

def stats():
    db = conn()
    for repo, n in db.execute("SELECT repo, count(*) FROM docs GROUP BY repo"):
        print(f"{n:5d}  {repo}")

if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "index": index(sys.argv[2])
    elif len(sys.argv) >= 3 and sys.argv[1] == "query": query(" ".join(sys.argv[2:]))
    elif len(sys.argv) >= 2 and sys.argv[1] == "stats": stats()
    else: print(__doc__)
