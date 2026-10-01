from quickpuff.heat_trace import ACTIVE, FADE, MAX_POINTS, PREHEAT, HeatTrace

IDLE = 5


def run(trace, states, start=0.0, step=0.7, temp=100.0, rise=10.0, target=520):
    prev = IDLE
    t = start
    for state in states:
        trace.update(prev, state, temp, t, target)
        prev = state
        t += step
        temp += rise
    return t


def test_nothing_is_recorded_while_idle():
    trace = HeatTrace()
    run(trace, [IDLE] * 5)
    assert trace.as_status() is None


def test_records_a_cycle_about_once_a_second_with_its_phases():
    trace = HeatTrace()
    run(trace, [PREHEAT] * 6 + [ACTIVE] * 4 + [FADE] * 2)
    status = trace.as_status()
    times = [p[0] for p in status["points"]]
    assert times[0] == 0.0
    assert all(b - a >= 1.0 for a, b in zip(times, times[1:]))
    assert status["ready_at"] == 4.2
    assert status["fade_at"] == 7.0
    assert status["target_f"] == 520
    assert status["active"] is True


def test_the_curve_stays_as_last_session_until_the_next_cycle():
    trace = HeatTrace()
    t = run(trace, [PREHEAT] * 4 + [ACTIVE] * 2)
    trace.update(ACTIVE, IDLE, 80, t)
    kept = trace.as_status()
    assert kept["active"] is False and kept["points"]
    trace.update(IDLE, PREHEAT, 90, t + 60, 480)
    fresh = trace.as_status()
    assert fresh["points"] == [[0.0, 90.0]]
    assert fresh["target_f"] == 480 and fresh["ready_at"] is None


def test_a_long_session_is_thinned_not_cut():
    trace = HeatTrace()
    run(trace, [PREHEAT] + [ACTIVE] * 1200, step=1.0)
    points = trace.as_status()["points"]
    assert len(points) <= MAX_POINTS
    assert points[0][0] == 0.0 and points[-1][0] > 1000


def test_missing_temperature_is_skipped():
    trace = HeatTrace()
    trace.update(IDLE, PREHEAT, None, 0.0)
    trace.update(PREHEAT, PREHEAT, 200, 1.5)
    assert trace.as_status()["points"] == [[1.5, 200.0]]
