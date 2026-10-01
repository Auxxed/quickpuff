import cbor2
import pytest

from quickpuff import saved_lights
from quickpuff.codec import first_cbor_item, hexify
from quickpuff.lights import solid_color_payload
from quickpuff.moods import cycle_payload


def raw(payload):
    return cbor2.dumps(hexify(payload), canonical=True)


def test_capture_drops_the_padding_the_peak_keeps_after_a_light():
    blob = raw(cycle_payload("fade", ["#ff0000", "#0000ff"]))
    assert first_cbor_item(blob + b"\x00" * 64) == blob


def test_save_list_and_replay_exact_bytes():
    blob = raw(cycle_payload("lava", ["#4d0013", "#ff7000", "#ffd000"]))
    entry = saved_lights.save("  Puffcon   2026 ", blob)
    assert entry["name"] == "Puffcon 2026"
    assert entry["style"] == "lava"
    assert entry["colors"] == ["#4d0013", "#ff7000", "#ffd000"]
    assert "raw" not in saved_lights.listing()[0]
    assert saved_lights.get_raw(entry["id"]) == blob


def test_saving_the_same_light_again_renames_it():
    blob = raw(solid_color_payload("#3dd68c"))
    saved_lights.save("Green", blob)
    saved_lights.save("Minty", blob)
    assert [x["name"] for x in saved_lights.listing()] == ["Minty"]
    assert saved_lights.listing()[0]["style"] == "solid"


def test_rename_and_delete():
    ident = saved_lights.save("A", raw(solid_color_payload("#ff0000")))["id"]
    saved_lights.rename(ident, "B")
    assert saved_lights.listing()[0]["name"] == "B"
    saved_lights.delete(ident)
    assert saved_lights.listing() == []
    with pytest.raises(ValueError):
        saved_lights.delete(ident)


def test_a_light_needs_a_name_and_real_bytes():
    with pytest.raises(ValueError):
        saved_lights.save("   ", raw(solid_color_payload("#ff0000")))
    with pytest.raises(ValueError):
        saved_lights.save("Big", b"\x00" * 5000)


def test_memo_gives_back_exact_colours_the_table_would_nudge():
    blob = raw(cycle_payload("fade", ["#ff0000", "#00ff00"], tempo=0.4))
    assert saved_lights.recall_cycle(blob) is None
    saved_lights.remember_cycle(blob, {"style": "fade", "colors": ["#ff0000", "#00ff00"], "tempo": 0.4, "inhale": False})
    assert saved_lights.recall_cycle(blob)["colors"] == ["#ff0000", "#00ff00"]
    assert saved_lights.describe(blob)["colors"] == ["#ff0000", "#00ff00"]
