import QtQuick
import QtTest
import "../../components"

// Hold to heat: only a full hold may fire. Run:
//   QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml
TestCase {
  id: testCase
  name: "HoldToFire"

  Component {
    id: holdComponent
    HoldToFire { duration: 200 }
  }

  Component {
    id: spyComponent
    SignalSpy {}
  }

  function makeHold() {
    var hold = createTemporaryObject(holdComponent, testCase)
    var fired = createTemporaryObject(spyComponent, testCase, { target: hold, signalName: "fired" })
    var cancelled = createTemporaryObject(spyComponent, testCase, { target: hold, signalName: "cancelled" })
    return { hold: hold, fired: fired, cancelled: cancelled }
  }

  function test_a_full_hold_fires_once() {
    var t = makeHold()
    t.hold.start()
    verify(t.hold.holding)
    t.fired.wait(1000)
    compare(t.fired.count, 1)
    compare(t.cancelled.count, 0)
    // Letting go after it fired is not a cancel, and fires nothing more.
    t.hold.end()
    wait(300)
    compare(t.fired.count, 1)
    compare(t.cancelled.count, 0)
    compare(t.hold.progress, 0)
  }

  function test_letting_go_early_cancels_and_never_fires() {
    var t = makeHold()
    t.hold.start()
    wait(80)
    verify(t.hold.progress > 0 && t.hold.progress < 1)
    t.hold.end()
    compare(t.cancelled.count, 1)
    verify(!t.hold.holding)
    wait(400)
    compare(t.fired.count, 0)
    compare(t.hold.progress, 0)
  }

  function test_ending_without_a_hold_is_quiet() {
    var t = makeHold()
    t.hold.end()
    compare(t.cancelled.count, 0)
    compare(t.fired.count, 0)
  }

  function test_a_second_press_starts_over() {
    var t = makeHold()
    t.hold.start()
    wait(120)
    t.hold.start()
    wait(120)
    compare(t.fired.count, 0)  // 240 ms in total, but no single 200 ms hold
    t.fired.wait(1000)
    compare(t.fired.count, 1)
  }
}
