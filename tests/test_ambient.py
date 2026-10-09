"""Theme and music lights: palettes from the Omarchy theme and album art, the
rules for fetching art, and the daemon keeping the lantern on them."""

import asyncio
import os

import pytest

from quickpuff import ambient, moods
from quickpuff.daemon import QuickPuffDaemon
from quickpuff.paths import load_config
from quickpuff.proc import run_bounded

THEME = """mode = "dark"
accent = "#e68e0d"
background = "#121212"
foreground = "#bebebe"
blue = "#3b82f6"
magenta = "#d35f5f"
green = "#ffc107"
cyan = "#bebebe"
"""


def write_theme(root, text=THEME):
    theme = root / "omarchy/current/theme"
    theme.mkdir(parents=True, exist_ok=True)
    (theme / "colors.toml").write_text(text)
    return theme


@pytest.fixture
def state(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))
    return tmp_path / "state"


def hue(color):
    return moods._rgb_to_lch(moods._hex_to_triple(color))[2]


# ------------------------------------------------------------- palettes

def test_theme_palette_leads_with_the_accent_and_skips_greys(state):
    write_theme(state)
    palette = ambient.theme_palette()
    assert 1 < len(palette) <= 3
    assert abs(hue(palette[0]) - hue("#e68e0d")) < 6
    for color in palette:
        lightness, chroma, _ = moods._rgb_to_lch(moods._hex_to_triple(color))
        assert lightness >= 55 and chroma >= 30


def test_no_theme_no_palette(state):
    assert ambient.theme_palette() is None


def test_a_symlinked_theme_file_is_refused(state, tmp_path):
    theme = state / "omarchy/current/theme"
    theme.mkdir(parents=True)
    (tmp_path / "elsewhere.toml").write_text(THEME)
    os.symlink(tmp_path / "elsewhere.toml", theme / "colors.toml")
    assert ambient.theme_palette() is None


def test_parse_theme_takes_only_hex_colours():
    assert ambient.parse_theme('accent = "#ABCDEF"\nmode = "dark"\nbad = "#zzzzzz"\n') == {"accent": "#abcdef"}


def pixels(*runs):
    return b"".join(bytes(rgb) * n for rgb, n in runs)


def test_art_palette_most_present_vivid_colour_first():
    art = pixels(((220, 30, 40), 300), ((30, 60, 230), 150), ((128, 128, 128), 126))
    palette = ambient.art_palette(art)
    assert len(palette) == 2
    assert hue(palette[0]) < 45 or hue(palette[0]) > 340   # red
    assert 250 < hue(palette[1]) < 310                     # blue


def test_grey_art_has_no_palette():
    assert ambient.art_palette(pixels(((40, 40, 40), 300), ((200, 200, 200), 276))) is None


# ------------------------------------------------------------- fetching art

@pytest.mark.parametrize("url", [
    "http://i.scdn.co/image/x",                  # not HTTPS
    "https://example.com/cover.jpg",             # not a cover-art host
    "https://user@i.scdn.co/image/x",            # credentials
    "https://i.scdn.co:8443/image/x",            # another port
    "https://i.scdn.co.evil.example/image/x",    # lookalike host
    "ftp://i.scdn.co/x",
    "file://otherhost/tmp/x.jpg",
    "file:relative.jpg",
])
def test_art_from_anywhere_else_is_left_alone(url, monkeypatch):
    monkeypatch.setattr(ambient.urllib.request, "build_opener", lambda *a: pytest.fail("no fetch"))
    assert ambient.fetch_art(url) is None


def test_local_art_is_read_but_not_through_a_symlink(tmp_path):
    cover = tmp_path / "cover.jpg"
    cover.write_bytes(b"jpegbytes")
    assert ambient.fetch_art(cover.as_uri()) == b"jpegbytes"
    os.symlink(cover, tmp_path / "link.jpg")
    assert ambient.fetch_art((tmp_path / "link.jpg").as_uri()) is None


def test_known_hosts_include_suffixes():
    assert ambient._art_host_ok("is3-ssl.mzstatic.com")
    assert not ambient._art_host_ok("mzstatic.com.example")


def test_run_bounded_feeds_stdin_and_returns_bytes():
    assert run_bounded(["/usr/bin/cat"], timeout=5, stdin_bytes=b"\x00\x01abc", text=False) == (0, b"\x00\x01abc")


# ------------------------------------------------------------- the daemon

class LanternPeak:
    is_connected = True

    def __init__(self):
        self.own = b"\xa1\x63own\x01"
        self.lights = []
        self.raw_back = []

    async def get_lantern_light_raw(self):
        return self.own

    async def set_lantern_light(self, colors, *, style="fade", tempo=0.3, show=False):
        self.lights.append(list(colors))

    async def set_lantern_light_raw(self, raw, *, show=False):
        self.raw_back.append(raw)


def daemon(tmp_path, peak):
    d = QuickPuffDaemon(sock=tmp_path / "quickpuff.sock")
    d._desktop_notify = lambda *a, **k: None
    d.device = peak
    return d


def step(d):
    asyncio.run(d._ambient_step())


def test_off_by_default_and_leaves_the_lantern_alone(tmp_path, state):
    write_theme(state)
    peak = LanternPeak()
    d = daemon(tmp_path, peak)
    assert d.status["theme_light"] is False and d.status["music_light"] is False
    step(d)
    assert peak.lights == [] and peak.raw_back == []


def test_theme_light_keeps_the_lantern_light_then_follows_the_theme(tmp_path, state):
    write_theme(state)
    peak = LanternPeak()
    d = daemon(tmp_path, peak)
    asyncio.run(d._set_ambient("theme_light", True))
    step(d)
    assert peak.lights == [ambient.theme_palette()]
    assert load_config()["lantern_before"] == peak.own.hex()
    assert d.status["ambient"]["source"] == "theme"
    step(d)
    assert len(peak.lights) == 1               # unchanged: nothing written again
    write_theme(state, 'accent = "#22c55e"\n')
    step(d)
    assert len(peak.lights) == 2 and abs(hue(peak.lights[-1][0]) - hue("#22c55e")) < 8


def test_turning_both_off_gives_the_lantern_its_own_light_back(tmp_path, state):
    write_theme(state)
    peak = LanternPeak()
    d = daemon(tmp_path, peak)
    asyncio.run(d._set_ambient("theme_light", True))
    step(d)
    asyncio.run(d._set_ambient("theme_light", False))
    step(d)
    assert peak.raw_back == [peak.own]
    assert "lantern_before" not in load_config()
    assert d.status["ambient"] is None


def test_music_overrides_the_theme_while_something_plays(tmp_path, state):
    write_theme(state)
    peak = LanternPeak()
    d = daemon(tmp_path, peak)
    asyncio.run(d._set_ambient("theme_light", True))
    asyncio.run(d._set_ambient("music_light", True))
    playing = {"value": (["#ff0044", "#2244ff"], "Artist — Song")}

    async def music():
        return playing["value"]

    d._music_palette = music
    step(d)
    assert peak.lights[-1] == ["#ff0044", "#2244ff"]
    assert d.status["ambient"] == {"source": "music", "colors": ["#ff0044", "#2244ff"], "track": "Artist — Song"}
    playing["value"] = (None, "")
    step(d)
    assert peak.lights[-1] == ambient.theme_palette()


def test_a_resting_peak_is_never_woken_for_it(tmp_path, state):
    write_theme(state)
    peak = LanternPeak()
    d = daemon(tmp_path, peak)
    asyncio.run(d._set_ambient("theme_light", True))
    d._resting = True
    step(d)
    assert peak.lights == []
