#!/usr/bin/env python3
"""Read-only folder scanner for the windows-pc-cleanup skill.

Works on Windows paths and on folders mounted into a Linux sandbox.
Never modifies anything.

  python scan_folder.py large <folder> [--top 50] [--min-mb 200] [--json out.json]
  python scan_folder.py dupes <folder> [--min-mb 1] [--json out.json]
  python scan_folder.py tree  <folder> [--depth 2] [--top 30] [--json out.json]
"""
import argparse
import hashlib
import json
import os
import sys
import time
from collections import defaultdict

SKIP_DIRS = {"$recycle.bin", "system volume information", "windows", "winsxs", "node_modules_cache"}


def walk_files(root):
    """Yield (path, size, mtime) for every regular file, ignoring unreadable entries and symlinks."""
    stack = [root]
    while stack:
        d = stack.pop()
        try:
            with os.scandir(d) as it:
                for e in it:
                    try:
                        if e.is_symlink():
                            continue
                        if e.is_dir(follow_symlinks=False):
                            if e.name.lower() not in SKIP_DIRS:
                                stack.append(e.path)
                        elif e.is_file(follow_symlinks=False):
                            st = e.stat(follow_symlinks=False)
                            yield e.path, st.st_size, st.st_mtime
                    except OSError:
                        continue
        except OSError:
            continue


def fmt_mb(n):
    return round(n / (1024 * 1024), 1)


def cmd_large(a):
    min_bytes = int(a.min_mb * 1024 * 1024)
    found = [(p, s, m) for p, s, m in walk_files(a.folder) if s >= min_bytes]
    found.sort(key=lambda x: x[1], reverse=True)
    rows = [{"path": p, "sizeMB": fmt_mb(s), "modified": time.strftime("%Y-%m-%d", time.localtime(m))}
            for p, s, m in found[: a.top]]
    for r in rows:
        print(f"{r['sizeMB']:>10} MB  {r['modified']}  {r['path']}")
    print(f"\n{len(found)} file(s) >= {a.min_mb} MB; showing {len(rows)}.")
    return rows


def file_hash(path, first_only=False):
    h = hashlib.sha256()
    try:
        with open(path, "rb") as f:
            if first_only:
                h.update(f.read(64 * 1024))
            else:
                for chunk in iter(lambda: f.read(1024 * 1024), b""):
                    h.update(chunk)
    except OSError:
        return None
    return h.hexdigest()


def cmd_dupes(a):
    min_bytes = int(a.min_mb * 1024 * 1024)
    by_size = defaultdict(list)
    for p, s, m in walk_files(a.folder):
        if s >= min_bytes:
            by_size[s].append(p)
    groups = []
    for size, paths in by_size.items():
        if len(paths) < 2:
            continue
        # cheap pass on the first 64 KB, then full hash only where needed
        by_head = defaultdict(list)
        for p in paths:
            hh = file_hash(p, first_only=True)
            if hh:
                by_head[hh].append(p)
        for same_head in by_head.values():
            if len(same_head) < 2:
                continue
            by_full = defaultdict(list)
            for p in same_head:
                fh = file_hash(p)
                if fh:
                    by_full[fh].append(p)
            for fh, same in by_full.items():
                if len(same) > 1:
                    groups.append({"sizeMB": fmt_mb(size), "wastedMB": fmt_mb(size * (len(same) - 1)),
                                   "sha256": fh, "files": sorted(same)})
    groups.sort(key=lambda g: g["wastedMB"], reverse=True)
    total = 0.0
    for i, g in enumerate(groups, 1):
        total += g["wastedMB"]
        print(f"[{i}] {g['sizeMB']} MB x {len(g['files'])} copies (extra copies use {g['wastedMB']} MB)")
        for f in g["files"]:
            print(f"     {f}")
    print(f"\n{len(groups)} duplicate group(s); removing extra copies would free about {round(total, 1)} MB.")
    return groups


def cmd_tree(a):
    root = os.path.abspath(a.folder)
    base_depth = root.rstrip(os.sep).count(os.sep)
    sizes = defaultdict(int)
    for p, s, m in walk_files(root):
        d = os.path.dirname(p)
        # attribute size to every ancestor up to the requested depth
        while True:
            depth = d.rstrip(os.sep).count(os.sep) - base_depth
            if depth <= a.depth:
                sizes[d] += s
            if os.path.abspath(d) == root or len(d) <= len(root):
                break
            d = os.path.dirname(d)
    rows = [{"path": p, "sizeMB": fmt_mb(s),
             "depth": p.rstrip(os.sep).count(os.sep) - base_depth}
            for p, s in sizes.items() if os.path.abspath(p) != root]
    rows.sort(key=lambda r: r["sizeMB"], reverse=True)
    rows = rows[: a.top]
    print(f"{fmt_mb(sizes.get(root, 0)):>10} MB  {root}  (total)")
    for r in rows:
        print(f"{r['sizeMB']:>10} MB  {'  ' * (r['depth'] - 1)}{r['path']}")
    return {"root": root, "totalMB": fmt_mb(sizes.get(root, 0)), "folders": rows}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("large"); p.add_argument("folder"); p.add_argument("--top", type=int, default=50)
    p.add_argument("--min-mb", type=float, default=200); p.add_argument("--json")
    p = sub.add_parser("dupes"); p.add_argument("folder"); p.add_argument("--min-mb", type=float, default=1)
    p.add_argument("--json")
    p = sub.add_parser("tree"); p.add_argument("folder"); p.add_argument("--depth", type=int, default=2)
    p.add_argument("--top", type=int, default=30); p.add_argument("--json")
    a = ap.parse_args()
    if not os.path.isdir(a.folder):
        sys.exit(f"Not a folder: {a.folder}")
    result = {"large": cmd_large, "dupes": cmd_dupes, "tree": cmd_tree}[a.cmd](a)
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
