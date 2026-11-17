#!/usr/bin/env python3
"""Rank source files by size x recent churn and check them against line budgets.

  hotspots.py --repo . [--top 25]        ranking (audit)
  hotspots.py --repo . --changed BASE    files a diff touches: before/after lines, budget crossings
  hotspots.py --repo . --check           exit 1 if a file is over --error and not exempt (CI gate)

Lines are non-blank lines. Outside a git repo, files are walked and churn is 0.
Exemptions are the backticked paths in the
"## Exemptions" section of docs/architecture.md.
"""
import argparse, os, re, subprocess, sys
from collections import Counter

SOURCE_EXT = {".ts", ".tsx", ".js", ".jsx", ".mjs", ".kt", ".kts", ".java", ".swift",
              ".py", ".go", ".rs", ".dart", ".cs", ".rb", ".m", ".mm", ".c", ".cc", ".cpp", ".h"}
DEFAULT_EXCLUDE = [r"(^|/)(__tests__|tests?|androidTest|testFixtures|Tests)/", r"\.(test|spec)\.",
                   r"Test\.(kt|java|swift)$", r"(^|/)(build|dist|generated|node_modules|Pods|vendor)/",
                   r"\.d\.ts$", r"\.min\.js$", r"(^|/)jest\.setup\."]


def git(repo, *args, check=True):
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    if check and r.returncode != 0:
        sys.exit(f"git {' '.join(args)}: {r.stderr.strip()}")
    return r.stdout if r.returncode == 0 else None


def is_git(repo):
    return git(repo, "rev-parse", "--git-dir", check=False) is not None


def is_source(path, exclude):
    return os.path.splitext(path)[1] in SOURCE_EXT and not any(re.search(p, path) for p in exclude)


def count_lines(text):
    return sum(1 for line in text.splitlines() if line.strip())


def file_lines(repo, path):
    try:
        with open(os.path.join(repo, path), encoding="utf-8", errors="replace") as f:
            return count_lines(f.read())
    except OSError:
        return 0


def walk(repo):
    for root, dirs, names in os.walk(repo):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d not in ("node_modules", "build", "dist", "Pods")]
        for n in names:
            yield os.path.relpath(os.path.join(root, n), repo)


def churn(repo, days):
    if not is_git(repo):
        return Counter()
    out = git(repo, "log", f"--since={days}.days", "--name-only", "--format=")
    return Counter(line for line in out.splitlines() if line)


def exemptions(repo):
    try:
        doc = open(os.path.join(repo, "docs", "architecture.md"), encoding="utf-8").read()
    except OSError:
        return set()
    m = re.search(r"^## Exemptions\s*$(.*?)(?=^## |\Z)", doc, re.M | re.S)
    return set(re.findall(r"`([^`\s]+)`", m.group(1))) if m else set()


def level(n, a):
    return "ERROR" if n > a.error else "warn" if n > a.warn else ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".")
    ap.add_argument("--top", type=int, default=25)
    ap.add_argument("--days", type=int, default=90, help="churn window")
    ap.add_argument("--warn", type=int, default=300)
    ap.add_argument("--error", type=int, default=500)
    ap.add_argument("--exclude", action="append", default=[], help="extra path regex to skip")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--changed", metavar="BASE")
    mode.add_argument("--check", action="store_true")
    a = ap.parse_args()
    exclude = DEFAULT_EXCLUDE + a.exclude
    top = git(a.repo, "rev-parse", "--show-toplevel", check=False)
    repo = top.strip() if top else os.path.abspath(a.repo)

    if a.changed:
        if not top:
            sys.exit("--changed needs a git repo")
        names = git(repo, "diff", "--name-only", "--diff-filter=AM", f"{a.changed}...HEAD").split()
        rows = []
        for p in filter(lambda p: is_source(p, exclude), names):
            old = git(repo, "show", f"{a.changed}:{p}", check=False)
            before, after = (count_lines(old) if old is not None else 0), file_lines(repo, p)
            crossed = level(after, a) and level(after, a) != level(before, a)
            rows.append((after, before, p, level(after, a), "crossed" if crossed else ""))
        print(f"{'after':>6} {'before':>6}  level  note     file")
        for after, before, p, lv, note in sorted(rows, reverse=True):
            print(f"{after:>6} {before:>6}  {lv:<5}  {note:<7}  {p}")
        return 0

    listing = git(repo, "ls-files").splitlines() if top else walk(repo)
    files = [p for p in listing if is_source(p, exclude)]
    sizes = {p: file_lines(repo, p) for p in files}

    if a.check:
        exempt = exemptions(repo)
        over = sorted((n, p) for p, n in sizes.items() if n > a.error and p not in exempt)
        for n, p in reversed(over):
            print(f"{p}: {n} lines > {a.error} (split it, or add to docs/architecture.md Exemptions with a ticket)")
        stale = sorted(p for p in exempt if p in sizes and sizes[p] <= a.error)
        for p in stale:
            print(f"note: {p} is back under budget — remove it from Exemptions")
        return 1 if over else 0

    ch = churn(repo, a.days)
    rows = sorted(((n * (1 + ch.get(p, 0)), n, ch.get(p, 0), p) for p, n in sizes.items()), reverse=True)
    over_w = sum(1 for n in sizes.values() if n > a.warn)
    over_e = sum(1 for n in sizes.values() if n > a.error)
    print(f"{len(files)} source files · {over_w} over {a.warn} lines · {over_e} over {a.error} · churn = commits in {a.days} days\n")
    print(f"{'lines':>6} {'churn':>5}  level  file")
    for _, n, c, p in rows[: a.top]:
        print(f"{n:>6} {c:>5}  {level(n, a):<5}  {p}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
