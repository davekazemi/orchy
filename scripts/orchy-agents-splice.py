#!/usr/bin/env python3
"""Splice the Orchy block into AGENTS.md; only the marker-delimited region is ever changed.

Cases:
  a) target missing                 -> create it containing only the block
  b) target has no markers          -> append the block after one blank-line separator
  c) exactly one start, one end,
     start before end               -> replace start..end inclusive; rest byte-identical
  d) anything else                  -> MALFORMED on stderr, exit 3, nothing written

Exit: 0 ok, 1 usage or I/O error, 3 malformed target.
"""
import argparse
import difflib
import os
import sys
import tempfile

START = "<!-- orchy:start -->"
END = "<!-- orchy:end -->"


class Parser(argparse.ArgumentParser):
    def error(self, message):
        self.print_usage(sys.stderr)
        sys.exit(f"error: {message}")


def find_all(text, needle):
    out, i = [], text.find(needle)
    while i != -1:
        out.append(i)
        i = text.find(needle, i + len(needle))
    return out


def line_of(text, idx):
    return text.count("\n", 0, idx) + 1


def read_block(args):
    if args.block == "-":
        text = sys.stdin.read()
    else:
        with open(args.block_file, encoding="utf-8") as f:
            text = f.read()
    text = text.strip()
    if not text.startswith(START):
        text = START + "\n" + text
    if not text.endswith(END):
        text = text + "\n" + END
    return text


def remove_block(orig, s, e, nl):
    before, after = orig[:s], orig[e:]
    if after.startswith(nl):
        after = after[len(nl):]
    if before.endswith(nl + nl):
        before = before[:-len(nl)]
    elif not before and after.startswith(nl):
        after = after[len(nl):]
    return before + after


def write_atomic(target, text):
    parent = os.path.dirname(os.path.abspath(target))
    os.makedirs(parent, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=parent, prefix=".orchy-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        if os.path.exists(target):
            os.chmod(tmp, os.stat(target).st_mode)
        os.replace(tmp, target)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def run(args):
    target, block, orig = args.target, read_block(args), None
    if os.path.exists(target):
        with open(target, encoding="utf-8", newline="") as f:
            orig = f.read()
    nl = "\n"
    if orig and "\r\n" in orig and "\n" not in orig.replace("\r\n", ""):
        nl = "\r\n"
        block = block.replace("\n", nl)
    starts, ends = find_all(orig or "", START), find_all(orig or "", END)

    if orig is None or not orig:
        if args.remove:
            print(f"nothing to remove: {target}")
            return 0
        action, new = "create", block + nl
    elif not starts and not ends:
        if args.remove:
            print(f"nothing to remove: no orchy block in {target}")
            return 0
        new = orig if orig.endswith(nl) else orig + nl
        if not new.endswith(nl + nl):
            new += nl
        action, new = "append", new + block + nl
    elif len(starts) == 1 and len(ends) == 1 and starts[0] < ends[0]:
        s, e = starts[0], ends[0] + len(END)
        if args.remove:
            action, new = "remove", remove_block(orig, s, e, nl)
        else:
            action, new = "replace", orig[:s] + block + orig[e:]
        if new == orig:
            action = "unchanged"
    else:
        if len(starts) == 1 and len(ends) == 1:
            reason = "end marker precedes start marker"
        else:
            reason = f"expected one start and one end marker, found {len(starts)} start, {len(ends)} end"
        print(f"MALFORMED: {reason}", file=sys.stderr)
        for i in starts:
            print(f"  {START} at line {line_of(orig, i)}", file=sys.stderr)
        for i in ends:
            print(f"  {END} at line {line_of(orig, i)}", file=sys.stderr)
        return 3

    if action == "unchanged":
        print(f"unchanged {target}")
        return 0
    if args.dry_run:
        print(f"{action} {target}")
        sys.stdout.writelines(difflib.unified_diff(
            (orig or "").splitlines(True), new.splitlines(True), fromfile=target, tofile=target))
        return 0
    write_atomic(target, new)
    print(f"{action} {target}")
    return 0


def main():
    p = Parser(description=__doc__.splitlines()[0])
    p.add_argument("--target", required=True, help="path to AGENTS.md")
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--block-file", help="rendered block file")
    g.add_argument("--block", choices=["-"], help="read the rendered block from stdin")
    p.add_argument("--dry-run", action="store_true", help="print action and diff; write nothing")
    p.add_argument("--remove", action="store_true", help="remove the block instead of inserting it")
    try:
        return run(p.parse_args())
    except (OSError, UnicodeDecodeError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
