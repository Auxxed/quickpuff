"""The demo's pretend heat cycle: believable curves, on time, the same every take."""

from quickpuff import demo
from quickpuff.demo import ACTIVE, FADE, IDLE, PREHEAT, DemoRun

RUN = DemoRun(preheat_s=12, session_s=20, cooldown_s=6, target_f=530, start_f=80)


def samples(run, step=0.05):
    out, i = [], 0
    while (now := demo.sample(run, i * step)) is not None:
        out.append((round(i * step, 3), now))
        i += 1
    return out


def temps(run, lo, hi, step=0.05):
    return [now["heater_temp_f"] for t, now in samples(run, step) if lo <= t < hi]


def runs(values):
    return [v for i, v in enumerate(values) if i == 0 or values[i - 1] != v]


def test_preheat_then_ready_then_fade_then_idle_then_over():
    assert runs([now["operating_state_id"] for _, now in samples(RUN)]) == [PREHEAT, ACTIVE, FADE, IDLE]
    assert runs([now["phase"] for _, now in samples(RUN)]) == ["preheat", "session", "fade", "idle"]


def test_each_phase_begins_on_the_second():
    assert demo.sample(RUN, 0)["operating_state_id"] == PREHEAT
    assert demo.sample(RUN, 11.99)["operating_state_id"] == PREHEAT
    assert demo.sample(RUN, 12)["operating_state_id"] == ACTIVE
    assert demo.sample(RUN, 31.99)["operating_state_id"] == ACTIVE
    assert demo.sample(RUN, 32)["operating_state_id"] == FADE
    assert demo.sample(RUN, 37.99)["operating_state_id"] == FADE
    assert demo.sample(RUN, 38)["operating_state_id"] == IDLE
    assert RUN.length_s == 12 + 20 + 6 + demo.IDLE_S
    assert demo.sample(RUN, RUN.length_s - 0.01)["operating_state_id"] == IDLE
    assert demo.sample(RUN, RUN.length_s) is None


def test_states_carry_the_peaks_own_names():
    names = [demo.sample(RUN, t)["operating_state"] for t in (1, 15, 34, 40)]
    assert names == ["Preheating", "Ready", "Cooling", "Idle"]


def test_the_timer_counts_through_each_heat_state_like_the_peaks():
    now = demo.sample(RUN, 5)
    assert (now["state_elapsed_s"], now["state_total_s"]) == (5.0, 12)
    now = demo.sample(RUN, 20)
    assert (now["state_elapsed_s"], now["state_total_s"]) == (8.0, 20)
    now = demo.sample(RUN, 33)
    assert (now["state_elapsed_s"], now["state_total_s"]) == (1.0, 6)
    now = demo.sample(RUN, 39)
    assert (now["state_elapsed_s"], now["state_total_s"]) == (None, None)


def test_preheat_climbs_all_the_way_and_arrives_just_as_it_ends():
    climb = temps(RUN, 0, 12)
    assert climb[0] == 80.0
    assert all(b >= a for a, b in zip(climb, climb[1:]))
    # Within ~2°F right at the end, but not sitting there long before it:
    # a Peak that looks ready and isn't reads as broken.
    assert abs(demo.sample(RUN, 11.95)["heater_temp_f"] - 530) <= 2
    assert demo.sample(RUN, 10.5)["heater_temp_f"] < 528
    assert max(climb) <= 531


def test_at_temperature_it_hovers_with_a_slow_wobble():
    hover = temps(RUN, 12, 32)
    assert all(abs(t - 530) <= 5 for t in hover)
    assert max(hover) >= 533 and min(hover) <= 527
    # Slow: a few degrees a second at most, never a jitter.
    assert all(abs(b - a) <= 0.5 for a, b in zip(hover, hover[1:]))


def test_no_jumps_where_one_phase_hands_to_the_next():
    for edge in (RUN.ready_at, RUN.fade_at, RUN.idle_at):
        before = demo.sample(RUN, edge - 0.001)["heater_temp_f"]
        after = demo.sample(RUN, edge)["heater_temp_f"]
        assert abs(after - before) < 1


def test_fade_and_idle_keep_cooling():
    cooling = temps(RUN, 32, RUN.length_s)
    assert all(b < a for a, b in zip(cooling, cooling[1:]))
    assert demo.ROOM_F < cooling[-1] < 450


def test_other_lengths_and_targets_keep_the_same_shape():
    run = DemoRun(preheat_s=30, session_s=45, cooldown_s=0, target_f=600)
    assert demo.sample(run, 29.99)["operating_state_id"] == PREHEAT
    assert abs(demo.sample(run, 29.99)["heater_temp_f"] - 600) <= 2
    assert abs(demo.sample(run, 50)["heater_temp_f"] - 600) <= 5
    # No cooldown: straight from the session to idle.
    assert demo.sample(run, 75)["operating_state_id"] == IDLE


def test_every_take_is_the_same():
    assert samples(RUN) == samples(DemoRun(12, 20, 6, 530, 80))


def test_the_heat_graph_comes_from_a_real_heat_trace():
    trace = demo.heat_trace(RUN, 20.3)
    assert trace["active"] is True and trace["target_f"] == 530
    assert trace["ready_at"] == 12.0 and trace["fade_at"] is None
    times = [p[0] for p in trace["points"]]
    assert times[0] == 0.0 and times[-1] == 20.0
    assert all(b - a >= 1.0 for a, b in zip(times, times[1:]))
    assert trace["points"][0] == [0.0, 80.0]


def test_the_heat_graph_is_the_same_however_late_a_tick_lands():
    assert demo.heat_trace(RUN, 20.0) == demo.heat_trace(RUN, 20.9)


def test_once_idle_the_graph_stays_up_as_the_last_session():
    trace = demo.heat_trace(RUN, RUN.length_s + 5)
    assert trace["active"] is False
    assert (trace["ready_at"], trace["fade_at"]) == (12.0, 32.0)
    assert trace["points"][-1][0] < RUN.idle_at


def test_battery_dips_a_few_percent_while_heating_then_holds():
    levels = [demo.battery_at(RUN, 87, t) for t in range(int(RUN.length_s) + 1)]
    assert levels[0] == 87
    assert all(b <= a for a, b in zip(levels, levels[1:]))
    assert 3 <= 87 - levels[int(RUN.fade_at)] <= 4
    assert levels[-1] == levels[int(RUN.fade_at)]
    assert demo.battery_at(RUN, 2, RUN.length_s) == 1


def test_the_stock_peak_reads_like_a_real_one():
    peak = demo.stock_peak()
    assert peak["connected"] is True and peak["device_name"] == "QuickPuff"
    assert peak["product"]["label"] == "Peak Pro Onyx"
    assert peak["product"]["marketing_name"] == "Onyx"
    assert 85 <= peak["battery"] <= 90
    assert peak["current_profile"] == 2
    profiles = peak["profiles"]
    assert [p["index"] for p in profiles] == [0, 1, 2, 3]
    assert [p["temp_f"] for p in profiles] == [490, 510, 530, 545]
    assert [p["color"] for p in profiles] == ["#3b9eff", "#3dd68c", "#ff4d4d", "#ffffff"]
    assert all(p["name"] and p["time"] > 0 for p in profiles)
