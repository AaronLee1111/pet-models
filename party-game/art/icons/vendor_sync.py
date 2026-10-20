"""Copies the approved Kenney sources (atlas_v1.tsv) from extracted pack folders into
art/vendor/kenney/selected/, unmodified, at their original relative paths, plus each pack's
License.txt and the matching SVG of every PNG. Files no longer selected are removed.
Writes art/icons/file_hashes.tsv.

    python3 vendor_sync.py <folder with the extracted kenney_* packs> [--write]

Without --write it is a dry run: prints every destination and the license check, writes nothing.
"""
import csv
import hashlib
import os
import shutil
import sys

ICONS = os.path.dirname(os.path.abspath(__file__))
DEST = os.path.join(os.path.dirname(ICONS), "vendor", "kenney", "selected")
PACKS = {"board-game-icons": "kenney_board-game-icons", "input-prompts": "kenney_input-prompts_1.5", "ui-pack": "kenney_ui-pack"}


def svg_for(pack, png):
    name = os.path.splitext(os.path.basename(png))[0] + ".svg"
    if pack == "board-game-icons":
        return "Vector/Icons/" + name
    if pack == "input-prompts":
        return png.split("/")[0] + "/Vector/" + name
    return None


def main():
    root, write = sys.argv[1], "--write" in sys.argv
    wanted = set()
    for pack in PACKS:
        wanted.add((pack, "License.txt"))
    for row in csv.reader(open(os.path.join(ICONS, "atlas_v1.tsv"), encoding="utf-8"), delimiter="\t"):
        if not row or row[0].startswith("#"):
            continue
        for rel in (row[3], row[4]):
            if rel == "-":
                continue
            wanted.add((row[2], rel))
            if rel.endswith(".png") and svg_for(row[2], rel):
                wanted.add((row[2], svg_for(row[2], rel)))
    for pack, folder in PACKS.items():
        text = open(os.path.join(root, folder, "License.txt"), encoding="utf-8", errors="replace").read()
        assert "Creative Commons Zero, CC0" in text, pack + ": license is not CC0"
        print(f"license {pack}: CC0 verified")
    rows = []
    for pack, rel in sorted(wanted):
        src = os.path.join(root, PACKS[pack], rel)
        assert os.path.exists(src), src
        digest = hashlib.sha256(open(src, "rb").read()).hexdigest()
        rows.append((pack, rel, digest))
        print(("copy " if write else "would copy ") + f"{pack}/{rel}")
        if write:
            dst = os.path.join(DEST, pack, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
    stale = []
    for dirpath, _, files in os.walk(DEST):
        for name in files:
            rel = os.path.relpath(os.path.join(dirpath, name), DEST).split(os.sep)
            if (rel[0], "/".join(rel[1:])) not in wanted:
                stale.append(os.path.join(dirpath, name))
    for path in stale:
        print(("remove " if write else "would remove ") + os.path.relpath(path, DEST))
        if write:
            os.remove(path)
    if write:
        for dirpath, dirs, files in sorted(os.walk(DEST), reverse=True):
            if not dirs and not files:
                os.rmdir(dirpath)
        with open(os.path.join(ICONS, "file_hashes.tsv"), "w") as f:
            f.write("pack\toriginal relative path\tsha256\n")
            for row in rows:
                f.write("\t".join(row) + "\n")
    print(f"{len(rows)} files selected, {len(stale)} to remove" + ("" if write else " (dry run)"))


main()
