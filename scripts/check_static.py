#!/usr/bin/env python3
"""Static checks for the Windows-parity port (no cargo/flutter needed).

Verifies brace balance of the changed Rust/Dart files and that the new
CLI/GUI wiring is present. Exits 1 on the first failure so `make check`
(and CI) can gate on it. Run the real compilers on a Linux box:
    cargo check --workspace && flutter analyze
"""
import io
import re
import sys

ROOT = "."
FILES = [
    "crates/unblocker-core/src/adapt/mod.rs",
    "crates/unblocker-core/src/routing/mod.rs",
    "crates/unblocker-core/src/lib.rs",
    "crates/unblocker/src/main.rs",
    "unblocker_gui/lib/src/adapt_page.dart",
    "unblocker_gui/lib/src/home_page.dart",
    "unblocker_gui/lib/src/localization.dart",
]

REQUIRED = [
    ("crates/unblocker/src/main.rs", "Cmd::Adapt"),
    ("crates/unblocker/src/main.rs", "Cmd::AdaptSites"),
    ("crates/unblocker/src/main.rs", "Cmd::HybridBuild"),
    ("crates/unblocker/src/main.rs", "Cmd::RoutingSet"),
    ("crates/unblocker/src/main.rs", "Cmd::AdaptProgress"),
    ("crates/unblocker/src/main.rs", "per_site_args"),
    ("crates/unblocker-core/src/lib.rs", "pub mod adapt;"),
    ("crates/unblocker-core/src/lib.rs", "pub mod routing;"),
    ("unblocker_gui/lib/src/home_page.dart", "adapt_page.dart"),
    ("unblocker_gui/lib/src/home_page.dart", "Icons.tune"),
    ("unblocker_gui/lib/src/localization.dart", "routingSaved"),
    ("packaging/polkit/50-unblocker.rules", "/usr/lib/nukera/unblocker"),
    ("packaging/polkit/50-unblocker.rules", "/usr/bin/unblocker"),
]

FORBIDDEN = ["__PART", "omitted here", "TODO-PATCH"]


def brace_depth(path):
    depth = 0
    for line in io.open(path, encoding="utf-8"):
        s = re.sub(r'"(?:\\.|[^"\\])*"', '""', line)
        s = re.sub(r"'(?:\\.|[^'\\])*'", "''", s)
        s = re.sub(r"//[^\n]*", "", s)
        depth += s.count("{") - s.count("}")
    return depth


def main():
    ok = True
    for f in FILES:
        d = brace_depth(f)
        status = "ok" if d == 0 else f"FAIL (depth {d})"
        if d != 0:
            ok = False
        print(f"{f}: braces {status}")
    for f, needle in REQUIRED:
        text = io.open(f, encoding="utf-8").read()
        if needle in text:
            print(f"{f}: has '{needle}' ok")
        else:
            print(f"{f}: MISSING '{needle}'")
            ok = False
    for f in FILES:
        text = io.open(f, encoding="utf-8").read()
        for bad in FORBIDDEN:
            if bad in text:
                print(f"{f}: FORBIDDEN marker '{bad}'")
                ok = False
    print("RESULT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
