"""What gets installed is exactly what was reviewed: every package pinned and
hash-checked, CI actions pinned to commits, and nothing in install.sh that
splices an unchecked path into a file it generates."""

import re
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
LOCKS = ("requirements.txt", "requirements-dev.txt")


def requirements(name):
    """(name, version, marker, hashes) for each requirement in a lock."""
    text = (ROOT / name).read_text()
    found = []
    for block in re.split(r"\n(?=[A-Za-z0-9])", text):
        match = re.match(r"([A-Za-z0-9_.-]+)==([^\s;\\]+)\s*(?:;([^\\\n]*))?", block)
        if match:
            hashes = re.findall(r"--hash=sha256:([0-9a-f]{64})", block)
            found.append((match.group(1).lower(), match.group(2), (match.group(3) or "").strip(), hashes))
    return found


@pytest.mark.parametrize("lock", LOCKS)
def test_every_requirement_is_pinned_and_hashed(lock):
    entries = requirements(lock)
    assert entries
    lines = [
        line
        for line in (ROOT / lock).read_text().splitlines()
        if line and not line.startswith((" ", "#"))
    ]
    # Nothing that slipped past the parser above: every requirement line is `==` pinned.
    assert len(lines) == len(entries)
    for name, version, _marker, hashes in entries:
        assert re.fullmatch(r"[0-9][0-9A-Za-z.]*", version), name
        assert hashes, f"{name} has no hashes"


def test_the_runtime_lock_covers_every_dependency_on_linux():
    names = {name for name, *_ in requirements("requirements.txt")}
    # pyproject's own, plus what bleak pulls in on Linux for 3.10-3.14.
    assert {"bleak", "cbor2", "dbus-fast", "async-timeout", "typing-extensions"} <= names
    assert not any(name.startswith(("pyobjc", "winrt")) for name in names)


def test_python_310_gets_a_dbus_fast_that_supports_it():
    pins = {(name, marker) for name, _v, marker, _h in requirements("requirements.txt")}
    markers = {marker for name, marker in pins if name == "dbus-fast"}
    assert markers == {"python_full_version < '3.11'", "python_full_version >= '3.11'"}


def test_install_sh_installs_only_from_the_lock_with_hashes():
    script = (ROOT / "install.sh").read_text()
    installs = [line for line in script.splitlines() if re.search(r"\bpip\b.*\binstall\b", line)]
    assert installs, "install.sh no longer installs the Python dependencies"
    for line in installs:
        assert "--require-hashes" in line and "--no-deps" in line, line
        assert '-r "$ROOT/requirements.txt"' in line
    assert "--upgrade pip" not in script


def test_install_sh_and_its_wrapper_use_a_fixed_bash():
    script = (ROOT / "install.sh").read_text()
    assert script.startswith("#!/usr/bin/bash\n")
    assert "#!/usr/bin/env" not in script


def _plain_path(value):
    script = (ROOT / "install.sh").read_text()
    functions = "\n".join(
        # A one-line definition, or one that ends at a lone closing brace.
        re.search(rf"^{name}\(\) \{{[^\n]*\}}$|^{name}\(\) \{{.*?^}}$", script, re.S | re.M).group(0)
        for name in ("die", "plain_path")
    )
    return subprocess.run(
        ["/usr/bin/bash", "-c", functions + '\nplain_path "$1" "a test"', "bash", value],
        capture_output=True,
        text=True,
        timeout=10,
    )


@pytest.mark.parametrize("path", ["/home/u/.local/share/quickpuff/venv", "/home/u/.config/omarchy/plugins/auxxed.quickpuff", "/x/a+b-c_1.2"])
def test_plain_paths_are_accepted(path):
    assert _plain_path(path).returncode == 0


@pytest.mark.parametrize("path", ["/home/u/my dir", "/a|b", "/a&b", "/a%h", "/a'b", '/a"b', "/a\nb", "/a\\b", "/a$b", "/a;b"])
def test_paths_that_could_break_the_generated_files_are_refused(path):
    result = _plain_path(path)
    assert result.returncode != 0
    assert "won't install" in result.stderr


def test_ci_actions_are_pinned_to_commits_and_read_only():
    workflow = (ROOT / ".github" / "workflows" / "tests.yml").read_text()
    uses = re.findall(r"uses:\s*(\S+)", workflow)
    assert uses
    for ref in uses:
        assert re.fullmatch(r"[\w.-]+/[\w.-]+@[0-9a-f]{40}", ref), ref
    assert re.search(r"^permissions:\n  contents: read$", workflow, re.M)
    for line in workflow.splitlines():
        if "pip install" in line:
            assert "--require-hashes" in line and "--no-deps" in line, line
