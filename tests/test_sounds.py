"""The sound cues: every one the overlays play is bundled, and each is made by
tools/make-sounds.py, so the repository holds the source of its audio."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOUNDS = ROOT / "sounds"
GENERATOR = (ROOT / "tools" / "make-sounds.py").read_text()


def played_cues():
    names = set()
    for qml in ROOT.glob("**/*.qml"):
        names |= set(re.findall(r'\bcue\("([a-z]+)"\)', qml.read_text()))
    return names


def test_every_cue_the_overlays_play_is_bundled():
    cues = played_cues()
    assert len(cues) == 11
    for name in cues:
        assert (SOUNDS / f"{name}.ogg").read_bytes()[:4] == b"OggS", name


def test_no_stray_sound_files():
    assert {p.name for p in SOUNDS.iterdir()} == {f"{name}.ogg" for name in played_cues()}


def test_every_sound_is_synthesised_in_the_repo():
    made = set(re.findall(r"^@cue\(.*\)\ndef ([a-z]+)\(rng\):", GENERATOR, re.M))
    assert made == played_cues()


def test_sounds_stay_small():
    for path in SOUNDS.glob("*.ogg"):
        assert path.stat().st_size < 256 * 1024, path.name


def test_every_source_recording_is_listed_and_used():
    sources = ROOT / "tools" / "sources"
    clips = {p.stem for p in sources.glob("*.ogg")}
    listing = (sources / "SOURCES.md").read_text()
    assert clips
    for clip in clips:
        assert f"`{clip}.ogg`" in listing, clip
        assert f'recording("{clip}")' in GENERATOR, clip
    assert "Creative Commons 0" in listing
