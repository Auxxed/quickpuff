"""Starting the daemon: systemd starts an installed one, the detached
fallback is only for a checkout with no unit, and its log is opened safely.
Plus the bounded runner the helpers use instead of collecting output whole."""

import os
import stat
import subprocess
import threading
import time

import pytest

from quickpuff import doctor, paths, service
from quickpuff.proc import run_bounded


# ---- the daemon's log ------------------------------------------------------------


def test_log_is_created_private_and_appended(tmp_path):
    fd = service.open_daemon_log()
    try:
        os.write(fd, b"one\n")
    finally:
        os.close(fd)
    fd = service.open_daemon_log()
    try:
        os.write(fd, b"two\n")
    finally:
        os.close(fd)
    log = paths.log_path()
    assert log.read_bytes() == b"one\ntwo\n"
    assert stat.S_IMODE(log.stat().st_mode) == 0o600


def test_a_wide_log_from_an_older_version_is_tightened():
    log = paths.log_path()
    log.write_text("old\n")
    log.chmod(0o644)
    os.close(service.open_daemon_log())
    assert stat.S_IMODE(log.stat().st_mode) == 0o600


def test_symlinked_log_is_refused_and_its_target_untouched(tmp_path):
    victim = tmp_path / "victim.txt"
    victim.write_text("must survive\n")
    paths.log_path().symlink_to(victim)
    with pytest.raises(paths.RefusedFile):
        service.open_daemon_log()
    assert victim.read_text() == "must survive\n"


def test_fifo_log_is_refused_without_blocking():
    os.mkfifo(paths.log_path())
    done = {}
    worker = threading.Thread(target=lambda: done.update(r=_refused(service.open_daemon_log)), daemon=True)
    worker.start()
    worker.join(5)
    assert not worker.is_alive(), "blocked opening a FIFO"
    assert done["r"] is True


def test_another_accounts_log_is_refused(monkeypatch):
    paths.log_path().write_text("theirs\n")
    real = os.geteuid()
    monkeypatch.setattr(os, "geteuid", lambda: real + 1)
    with pytest.raises(paths.RefusedFile):
        service.open_daemon_log()


def _refused(fn):
    try:
        os.close(fn())
    except paths.RefusedFile:
        return True
    return False


# ---- who starts the daemon --------------------------------------------------------


@pytest.fixture
def no_daemon_yet(monkeypatch):
    """daemon_running() says no until something has started it."""
    state = {"up": False}
    monkeypatch.setattr(service, "daemon_running", lambda: state["up"])
    monkeypatch.setattr(
        service.subprocess, "Popen", lambda *a, **k: pytest.fail("spawned a detached daemon with a unit installed")
    )
    return state


def test_an_installed_but_stopped_unit_is_started_by_systemd(monkeypatch, no_daemon_yet):
    calls = []

    def fake_run(argv, **kwargs):
        calls.append(argv)
        if argv[2] == "show":
            return 0, "LoadState=loaded\nActiveState=inactive\nUnitFileState=disabled"
        if argv[2] == "start":
            no_daemon_yet["up"] = True
            return 0, ""
        raise AssertionError(argv)

    monkeypatch.setattr(service, "run_bounded", fake_run)
    service.ensure_daemon(timeout=2)
    assert calls[-1] == ["/usr/bin/systemctl", "--user", "start", "quickpuff-daemon.service"]


def test_a_failed_unit_is_started_again(monkeypatch, no_daemon_yet):
    started = []

    def fake_run(argv, **kwargs):
        if argv[2] == "start":
            started.append(True)
            no_daemon_yet["up"] = True
            return 0, ""
        return 0, "LoadState=loaded\nActiveState=failed\nUnitFileState=enabled"

    monkeypatch.setattr(service, "run_bounded", fake_run)
    service.ensure_daemon(timeout=2)
    assert started == [True]


def test_a_unit_systemd_is_already_starting_is_waited_for_not_started(monkeypatch, no_daemon_yet):
    def fake_run(argv, **kwargs):
        assert argv[2] == "show", "started a unit that was already activating"
        no_daemon_yet["up"] = True
        return 0, "LoadState=loaded\nActiveState=activating\nUnitFileState=enabled"

    monkeypatch.setattr(service, "run_bounded", fake_run)
    service.ensure_daemon(timeout=2)


def test_a_unit_that_wont_start_is_an_error_not_a_detached_daemon(monkeypatch, no_daemon_yet):
    def fake_run(argv, **kwargs):
        if argv[2] == "start":
            return 1, ""
        return 0, "LoadState=loaded\nActiveState=inactive\nUnitFileState=enabled"

    monkeypatch.setattr(service, "run_bounded", fake_run)
    with pytest.raises(RuntimeError, match="Couldn't start quickpuff-daemon.service"):
        service.ensure_daemon(timeout=0.2)


def test_a_masked_unit_is_left_masked(monkeypatch, no_daemon_yet):
    monkeypatch.setattr(service, "run_bounded", lambda argv, **k: (0, "LoadState=masked\nActiveState=inactive"))
    with pytest.raises(RuntimeError, match="masked"):
        service.ensure_daemon(timeout=0.2)


def test_only_a_checkout_without_a_unit_runs_it_detached(monkeypatch):
    state = {"up": False}
    spawned = []
    monkeypatch.setattr(service, "daemon_running", lambda: state["up"])
    monkeypatch.setattr(service, "run_bounded", lambda argv, **k: (0, "LoadState=not-found\nActiveState=inactive"))

    class Proc:
        def __init__(self, argv, **kwargs):
            spawned.append((argv, kwargs))
            # The log descriptor is open while the child is made.
            os.fstat(kwargs["stdout"])
            state["up"] = True

    monkeypatch.setattr(service.subprocess, "Popen", Proc)
    service.ensure_daemon(timeout=2)
    (argv, kwargs), = spawned
    assert argv[1:] == ["-m", "quickpuff.daemon"]
    assert kwargs["stdin"] is subprocess.DEVNULL and kwargs["start_new_session"]
    with pytest.raises(OSError):
        os.fstat(kwargs["stdout"])  # and closed again in the parent


def test_no_runtime_dir_means_no_daemon_and_says_why(monkeypatch):
    monkeypatch.delenv("XDG_RUNTIME_DIR")
    with pytest.raises(paths.RuntimeDirMissing):
        service.ensure_daemon(timeout=0.2)


# ---- run_bounded --------------------------------------------------------------------


def test_runs_a_short_command():
    assert run_bounded(["/usr/bin/printf", "hello\n"], timeout=5) == (0, "hello")


def test_exit_code_comes_back():
    assert run_bounded(["/usr/bin/false"], timeout=5)[0] == 1


def test_missing_command_is_127():
    assert run_bounded(["/nonexistent/quickpuff-test"], timeout=5) == (127, "")


def test_a_command_that_prints_too_much_is_killed_at_the_cap():
    started = time.monotonic()
    assert run_bounded(["/usr/bin/yes"], timeout=10, max_bytes=4096) == (127, "")
    assert time.monotonic() - started < 5


def test_a_command_that_outlives_its_deadline_is_killed_with_what_it_started(tmp_path):
    marker = tmp_path / "grandchild.pid"
    script = f"/usr/bin/sleep 30 & echo $! > {marker}; wait"
    started = time.monotonic()
    assert run_bounded(["/usr/bin/sh", "-c", script], timeout=0.5) == (127, "")
    assert time.monotonic() - started < 5
    pid = int(marker.read_text())
    for _ in range(50):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            break
        time.sleep(0.05)
    else:
        os.kill(pid, 9)
        pytest.fail("the deadline left a grandchild running")


# ---- doctor uses fixed paths and the bounded runner -------------------------------


def test_doctor_runs_helpers_bounded_and_by_full_path(monkeypatch):
    seen = []
    monkeypatch.setattr(doctor, "run_bounded", lambda argv, **k: seen.append((argv, k)) or (0, "active"))
    assert doctor._run([doctor.SYSTEMCTL, "is-active", "bluetooth"]) == (0, "active")
    argv, kwargs = seen[0]
    assert argv[0] == "/usr/bin/systemctl"
    assert kwargs["max_bytes"] == doctor.MAX_OUTPUT_BYTES and kwargs["timeout"] > 0


def test_doctor_says_what_a_missing_runtime_dir_means():
    check = doctor.check_runtime_dir()
    assert check.ok is False and "XDG_RUNTIME_DIR" in check.detail


# ---- the lock helper's process group ------------------------------------------------


def test_a_wedged_lock_helper_is_killed_with_what_it_started(tmp_path, monkeypatch):
    import asyncio

    from quickpuff import presence

    marker = tmp_path / "grandchild.pid"
    helper = tmp_path / "locked-helper"
    helper.write_text(f"#!/usr/bin/bash\n/usr/bin/sleep 30 &\necho $! > {marker}\nwait\n")
    helper.chmod(0o700)
    monkeypatch.setattr(presence, "LOCK_PROBE_TIMEOUT_S", 0.5)
    seat = presence.SeatPresence()
    seat._helper = str(helper)
    assert asyncio.run(seat._read_screen_lock()) is False
    pid = int(marker.read_text())
    for _ in range(50):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            break
        time.sleep(0.05)
    else:
        os.kill(pid, 9)
        pytest.fail("the helper's child outlived the kill")
