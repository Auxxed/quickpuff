from quickpuff import history, wear

DAY = 86400.0
T0 = 1_780_000_000.0


def sessions(preheats, temp_c=272, gap=DAY / 2, start=T0):
    return [
        {"index": i, "ts": start + i * gap, "preheat_s": p, "temp_c": temp_c}
        for i, p in enumerate(preheats)
    ]


# ------------------------------------------------------------- heat-up

def test_heatup_learns_until_it_has_enough_sessions():
    out = wear.heatup(sessions([27.0] * 10))
    assert out["state"] == "learning"
    assert out["recent"] == 27.0
    assert out["samples"] == 10 and out["needed"] == 35


def test_steady_heatup():
    out = wear.heatup(sessions([27.0, 27.5, 26.5] * 15))
    assert out["state"] == "steady"
    assert abs(out["change_pct"]) < 5
    assert out["ref_temp_f"] == 522


def test_heatup_creeping_up_is_flagged():
    out = wear.heatup(sessions([26.0] * 20 + [27.0] * 10 + [31.0] * 15))
    assert out["state"] == "up"
    assert out["change_pct"] == 19


def test_warm_chamber_starts_are_left_out():
    cold = sessions([27.0] * 40)
    # A quick second dab two minutes after each cold one heats in half the time.
    warm = [{"index": 1000 + i, "ts": s["ts"] + 120, "preheat_s": 13.0, "temp_c": 272} for i, s in enumerate(cold)]
    out = wear.heatup(cold + warm)
    assert out["samples"] == 40
    assert out["recent"] == 27.0


def test_a_hotter_profile_is_not_mistaken_for_wear():
    # Same heater, hotter target: proportionally longer, so steady once scaled.
    early = sessions([25.0] * 20, temp_c=250)
    later = sessions([25.0 * (290 - 22) / (250 - 22)] * 20, temp_c=290, start=T0 + 30 * DAY)
    out = wear.heatup(early + later)
    assert out["state"] == "steady"
    assert out["ref_temp_f"] == 554


def test_months_are_medians_per_month():
    out = wear.heatup(sessions([27.0] * 120, gap=DAY))
    assert 3 <= len(out["months"]) <= wear.MONTHS_SHOWN
    assert all(m["value"] == 27.0 for m in out["months"])


# ------------------------------------------------------------- battery

def test_battery_per_dab_from_start_and_end_readings():
    events = [{"ts": T0 + i * DAY, "delta": 1, "battery_start": 90, "battery": 84} for i in range(5)]
    out = wear.battery_per_dab(events, [])
    assert out["recent"] == 6.0 and out["samples"] == 5


def test_battery_trend_up_as_the_pack_wears():
    events = [{"ts": T0 + i * DAY, "delta": 1, "battery_start": 90, "battery": 85} for i in range(10)]
    events += [{"ts": T0 + (10 + i) * DAY, "delta": 1, "battery_start": 90, "battery": 83} for i in range(10)]
    out = wear.battery_per_dab(events, [])
    assert out["state"] == "up" and out["change_pct"] == 40


def test_old_readings_pair_only_across_one_dab_without_charging():
    events = [
        {"ts": T0, "battery": 80},
        {"ts": T0 + 1800, "battery": 73},          # 30 min, one dab: counts (7)
        {"ts": T0 + 3600, "battery": 95},          # charged: skipped
        {"ts": T0 + 3 * 3600, "battery": 80},      # too long after: skipped
        {"ts": T0 + 3 * 3600 + 900, "battery": 70},  # two dabs between: skipped
    ]
    device = [{"ts": T0 + 1700}, {"ts": T0 + 3500}, {"ts": T0 + 3 * 3600 - 60}, {"ts": T0 + 3 * 3600 + 300}, {"ts": T0 + 3 * 3600 + 600}]
    out = wear.battery_per_dab(events, device)
    assert out["samples"] == 1 and out["recent"] == 7.0


def test_record_cycle_keeps_the_charge_it_started_with():
    event = history.record_cycle(temp_f=520, battery_start=88)
    history.record_battery(event["ts"], 81)
    wear_stats = history.get_stats()["wear"]["battery"]
    assert wear_stats["recent"] == 7.0


def test_record_cycle_ignores_a_reading_never_taken():
    assert "battery_start" not in history.record_cycle(battery_start=0)
    assert "battery_start" not in history.record_cycle(battery_start=None)
