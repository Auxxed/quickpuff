import cbor2
import pytest

from quickpuff.codec import decode_puffco_json, hexify
from quickpuff.lights import solid_color_payload
from quickpuff.moods import (
    CONFETTI_PATHS,
    DISCO_OFFSETS,
    FILL_OFFSETS,
    LAVA_PATHS,
    SPLIT_OFFSETS_2,
    SPLIT_OFFSETS_4,
    STYLES,
    cycle_payload,
    decode_cycle,
    lchycle,
    normalize_style,
)


def param(style, colors, **kw):
    return cycle_payload(style, colors, **kw)["lamp"]["param"]


def wire(payload):
    """Round-trip through the CBOR the Peak stores and hands back."""
    return decode_puffco_json(cbor2.loads(cbor2.dumps(hexify(payload), canonical=True)))


# Produced by the Puffco app's own lchycle (app bundle run under node).
APP_FADE_RED_GREEN = ["#fd0d0d", "#fd1c0d", "#ee790c", "#b4cb06", "#2efc00", "#00ff00", "#2efc00", "#b4cb06", "#ee790c", "#fd1c0d"]
APP_LAVA_DEFAULTS = ["#4d0013", "#5c0f13", "#842b14", "#ba4a11", "#ea6508", "#ff7000", "#ff7c11", "#ff9525", "#ffb12f", "#ffc724", "#ffd000", "#eaba0b", "#b98816", "#824f17", "#5a1f14"]


class TestLchycle:
    def test_matches_the_app_with_steady_holds(self):
        assert lchycle(["#ff0000", "#00ff00"], 10, 0.3) == APP_FADE_RED_GREEN

    def test_matches_the_app_without_holds(self):
        assert lchycle(["#4d0013", "#ff7000", "#ffd000"], 15) == APP_LAVA_DEFAULTS

    def test_one_colour_stays_that_colour(self):
        assert set(lchycle(["#123456"], 5, 0.3)) == {"#123456"}


class TestPikaled2Styles:
    def test_fade_is_the_apps_table_with_no_padding(self):
        p = param("fade", ["#ff0000", "#00ff00"])
        assert p["color"] == APP_FADE_RED_GREEN
        assert (p["anim"], p["plNum"], p["plDenom"], p["colorLen"]) == (1, 0, 0, 10)
        assert p["offset"] == [0] * 20

    def test_animation_codes_and_offsets(self):
        assert param("breathe", ["#ff0000", "#0000ff"])["anim"] == 5
        spin = param("spin", ["#ff4fa3", "#3b9eff"])
        assert (spin["anim"], spin["plNum"], spin["plDenom"]) == (7, 1, 2)
        assert param("disco", ["#ff0000", "#00ff00", "#0000ff"])["offset"] == [int(v * 3 + 0.5) for v in DISCO_OFFSETS]
        assert param("split", ["#ff0000", "#00ff00"])["offset"] == SPLIT_OFFSETS_2
        assert param("split", ["#ff0000", "#00ff00", "#0000ff"])["offset"] == SPLIT_OFFSETS_4
        assert param("fill", ["#ff0000", "#00ff00"])["offset"] == FILL_OFFSETS

    def test_disco_split_fill_blend_without_holds(self):
        colors = ["#4d0013", "#ff7000", "#ffd000"]
        for style in ("disco", "split", "fill"):
            assert param(style, colors)["color"] == APP_LAVA_DEFAULTS

    def test_one_colour_cycles_against_black_except_spin(self):
        assert param("fade", ["#ff6a1a"])["colorLen"] == 10
        assert param("spin", ["#ff6a1a"])["colorLen"] == 5

    def test_tempo_never_freezes_and_faster_is_faster(self):
        assert param("fade", ["#ff0000", "#0000ff"], tempo=0)["speed"] > 0
        assert param("fade", ["#ff0000", "#0000ff"], tempo=0.9)["speed"] > param("fade", ["#ff0000", "#0000ff"], tempo=0.3)["speed"]

    def test_dynamic_inhale(self):
        assert param("fade", ["#ff0000", "#0000ff"], inhale=True)["diFrac"] == 1
        assert param("fade", ["#ff0000", "#0000ff"])["diFrac"] == 0


class TestMigrationStyles:
    def test_lava_lamp_matches_the_apps_defaults(self):
        lamp = cycle_payload("lava", ["#4D0013", "#FF7000", "#FFD000"], tempo=0.5)["lamp"]
        p = lamp["param"]
        assert lamp["name"] == "migrtn1"
        assert p["colors"] == ["#4d0013", "#ff7000", "#ffd000"]
        assert p["speed"] == pytest.approx((0.5 * 0.9 + 0.1) ** 2 * 4)
        assert p["speedDi1"] == pytest.approx(p["speed"] * 3)
        assert (p["minLength"], p["maxLength"], p["minQty"], p["maxQty"]) == (4, 8, 2, 4)
        assert p["preRunTick"] == pytest.approx(0.2 / p["speed"])
        assert p["paths"] == LAVA_PATHS

    def test_confetti_matches_the_apps_defaults(self):
        p = param("confetti", ["#660000", "#ffff00", "#00ff00"])
        assert p["speed"] == pytest.approx((0.5 * 0.9 + 0.1) ** 2 * 20)
        assert (p["minLength"], p["maxLength"], p["minQty"], p["maxQty"], p["spawnFreq"]) == (2, 4, 6, 10, 5)
        assert p["paths"] == CONFETTI_PATHS

    def test_colours_go_over_the_wire_as_one_packed_rgb_string(self):
        blob = cbor2.dumps(hexify(cycle_payload("lava", ["#4d0013", "#ff7000"])), canonical=True)
        assert cbor2.loads(blob)["lamp"]["param"]["colors"] == bytes.fromhex("4d0013ff7000")


@pytest.mark.parametrize("style", STYLES)
def test_decode_reads_back_what_was_written(style):
    colors = ["#4d0013", "#ff7000", "#ffd000"]
    got = decode_cycle(wire(cycle_payload(style, colors, tempo=0.6, inhale=True)))
    assert got["style"] == style
    assert got["tempo"] == pytest.approx(0.6, abs=0.05)
    assert got["inhale"] is True
    # Exact on these colours; the memo covers the ones LUV's gamut nudges.
    assert got["colors"] == colors


def test_a_foreign_lamp_decodes_as_custom():
    foreign = {"lamp": {"name": "pikaled2", "param": {"anim": 3, "speed": 10, "colorLen": 10, "color": ["#ff0000"] * 10, "offset": [1] * 20}}}
    assert decode_cycle(foreign)["style"] == "custom"


def test_a_steady_colour_is_not_a_cycle():
    assert decode_cycle(solid_color_payload("#3dd68c")) is None
    assert decode_cycle(None) is None


def test_style_aliases():
    assert normalize_style("Lava Lamp") == "lava"
    assert normalize_style("vertical-slideshow") == "fill"
    with pytest.raises(ValueError, match="sparkle"):
        normalize_style("sparkle")


@pytest.mark.parametrize("bad", [[], ["red"]])
def test_rejects_bad_colours(bad):
    with pytest.raises(ValueError):
        cycle_payload("fade", bad)
