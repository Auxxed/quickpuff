"""The shell-side rules the plugin keeps, checked against the QML itself.

omarchy-shell hosts every widget in one process, so the QML never collects a
child's whole output, never runs a login shell, never reads a file, and hands
the shell's own components only plain text. These tests fail the build when
one of those slips back in.
"""

import re
import subprocess
from pathlib import Path

from quickpuff.constants import READY_ANIMATIONS

ROOT = Path(__file__).resolve().parents[1]
QML = sorted(p for p in ROOT.rglob("*.qml") if ".git" not in p.parts)


def _blocks(src: str, type_pattern: str):
    """Each `Type { ... }` block in src, with its line number."""
    for match in re.finditer(rf"\b({type_pattern})\s*\{{", src):
        i, depth = match.end(), 1
        while i < len(src) and depth:
            depth += (src[i] == "{") - (src[i] == "}")
            i += 1
        yield src[: match.start()].count("\n") + 1, src[match.end() : i]


def test_there_is_qml_to_check():
    assert any(p.name == "Panel.qml" for p in QML)


def test_every_text_is_plain_text():
    # Text.AutoText draws markup-looking strings as rich text, which can load
    # images; every Text pins PlainText, literal ones included.
    missing = [
        f"{p.relative_to(ROOT)}:{line}"
        for p in QML
        for line, body in _blocks(p.read_text(), "Text|Label|TextEdit")
        if "textFormat:" not in body
    ]
    assert missing == []


def test_no_whole_output_collectors_or_shells():
    banned = {
        "StdioCollector": "collects a child's whole output",
        '"bash"': "runs a shell",
        '"sh"': "runs a shell",
        "bar.run(": "runs a login shell",
        "Util.execDetached": "runs a login shell",
        "Util.execArgv": "runs a login shell",
        'Quickshell.execDetached(["pw-play"': "PATH lookup",
    }
    found = [
        f"{p.relative_to(ROOT)}: {needle} ({why})"
        for p in QML
        for needle, why in banned.items()
        if needle in p.read_text()
    ]
    assert found == []


def test_processes_are_bounded():
    # Only BoundedProcess itself may declare a bare Process.
    for p in QML:
        if p.name == "BoundedProcess.qml":
            continue
        assert not re.search(r"\bProcess\s*\{", p.read_text()), p.relative_to(ROOT)


def test_file_views_only_watch():
    views = [(p, body) for p in QML for _, body in _blocks(p.read_text(), "FileView")]
    assert views
    for p, body in views:
        assert re.search(r"preload:\s*false", body), p.relative_to(ROOT)
        assert re.search(r"blockAllReads:\s*true", body), p.relative_to(ROOT)
        assert "text()" not in body and "data()" not in body, p.relative_to(ROOT)


def test_host_drawn_text_goes_through_plain():
    bar = (ROOT / "BarWidget.qml").read_text()
    assert "Plain.plain(data.text" in bar and "Plain.plain(data.tooltip" in bar
    assert "Plain.plain(out" in bar
    panel = (ROOT / "Panel.qml").read_text()
    assert re.search(r'message:\s*"Power off " \+ Plain\.plain\(', panel)
    section = (ROOT / "components" / "Section.qml").read_text()
    assert "text: Plain.plain(section.title" in section


def test_plain_helper_is_ascii():
    # Escapes stay escapes; QML's lexer reads a raw U+2028 as a line break.
    data = (ROOT / "components" / "plain.js").read_bytes()
    assert all(b < 128 for b in data)


def test_bar_widget_plays_only_known_animations():
    bar = (ROOT / "BarWidget.qml").read_text()
    listed = re.search(r"readonly property var readyAnimations: \[([^\]]*)\]", bar).group(1)
    names = set(re.findall(r'"([a-z]+)"', listed))
    assert names == set(READY_ANIMATIONS) - {"off"}


def test_no_file_too_big_for_the_marketplace_scanner():
    # The marketplace's baseline scanner stops at 512 KiB per file.
    tracked = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "-z"], capture_output=True, check=True
    ).stdout.split(b"\0")
    big = [
        name.decode()
        for name in tracked
        if name and (ROOT / name.decode()).is_file() and (ROOT / name.decode()).stat().st_size > 512 * 1024
    ]
    assert big == []
