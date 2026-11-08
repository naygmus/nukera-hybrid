"""Static checks for the Windows-parity port, as a pytest suite.

Runs anywhere Python runs (no cargo/flutter needed). The real compilers
stay the source of truth on a Linux build box:
    cargo check --workspace && flutter analyze
"""
import io
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

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


def text(rel):
    return io.open(ROOT / rel, encoding="utf-8").read()


def brace_depth(rel):
    depth = 0
    for line in io.open(ROOT / rel, encoding="utf-8"):
        s = re.sub(r'"(?:\\.|[^"\\])*"', '""', line)
        s = re.sub(r"'(?:\\.|[^'\\])*'", "''", s)
        s = re.sub(r"//[^\n]*", "", s)
        depth += s.count("{") - s.count("}")
    return depth


def test_braces_balanced():
    for f in FILES:
        assert brace_depth(f) == 0, f"{f}: unbalanced braces (depth {brace_depth(f)})"


def test_required_wiring_present():
    for f, needle in REQUIRED:
        assert needle in text(f), f"{f}: missing '{needle}'"


def test_no_placeholder_markers():
    for f in FILES:
        for bad in FORBIDDEN:
            assert bad not in text(f), f"{f}: contains placeholder '{bad}'"
