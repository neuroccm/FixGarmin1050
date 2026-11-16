import Toybox.Lang;
import Toybox.Test;

// Feed `secs` identical samples starting at t0; return every event produced.
function feedDog(w as Watchdog, t0 as Number, secs as Number, speed as Float or Null, dist as Float or Null,
              distStep as Float, timer as Number, hr as Number or Null, power as Number or Null) as Array<Array<Number>> {
    var all = [] as Array<Array<Number>>;
    var d = dist;
    for (var i = 0; i < secs; i++) {
        var ev = w.step(t0 + i, speed, d, timer, hr, power);
        for (var k = 0; k < ev.size(); k++) { all.add(ev[k]); }
        if (d != null) { d = d + distStep; }
    }
    return all;
}

(:test)
function testR31RaisesAfterT1WhenTimerOff(logger as Test.Logger) as Boolean {
    var w = TestUtil.dog();
    var ev30 = feedDog(w, 0, 30, 5.0f, 0.0f, 0.0f, Rg.TIMER_OFF, null, null);
    var ev31 = feedDog(w, 30, 1, 5.0f, 0.0f, 0.0f, Rg.TIMER_OFF, null, null);
    return TestUtil.check(logger, TestUtil.count(ev30, Rg.R_MOVING, Rg.EV_RAISE) == 0, "raised too early")
        && TestUtil.check(logger, TestUtil.count(ev31, Rg.R_MOVING, Rg.EV_RAISE) == 1, "no raise at 31st second")
        && TestUtil.check(logger, w.activeRule() == Rg.R_MOVING, "R3.1 not active");
}

(:test)
function testR31FiresWhenStoppedAndMoving(logger as Test.Logger) as Boolean {
    var ev = feedDog(TestUtil.dog(), 0, 31, 5.0f, 0.0f, 0.0f, Rg.TIMER_STOPPED, null, null);
    return TestUtil.check(logger, TestUtil.count(ev, Rg.R_MOVING, Rg.EV_RAISE) == 1, "STOPPED + moving must raise R3.1");
}

(:test)
function testR31FiresWhenPausedAndMoving(logger as Test.Logger) as Boolean {
    var ev = feedDog(TestUtil.dog(), 0, 31, 5.0f, 0.0f, 0.0f, Rg.TIMER_PAUSED, null, null);
    return TestUtil.check(logger, TestUtil.count(ev, Rg.R_MOVING, Rg.EV_RAISE) == 1, "PAUSED + moving must raise R3.1");
}

(:test)
function testR31SilentWhenPausedAtStandstill(logger as Test.Logger) as Boolean {
    var ev = feedDog(TestUtil.dog(), 0, 300, 0.0f, 0.0f, 0.0f, Rg.TIMER_PAUSED, null, null);
    return TestUtil.check(logger, ev.size() == 0, "auto-pause at a standstill must not alert");
}

(:test)
function testR31SilentWhenTimerOn(logger as Test.Logger) as Boolean {
    var ev = feedDog(TestUtil.dog(), 0, 300, 5.0f, 0.0f, 5.0f, Rg.TIMER_ON, null, null);
    return TestUtil.check(logger, TestUtil.count(ev, Rg.R_MOVING, Rg.EV_RAISE) == 0, "R3.1 raised with timer ON");
}

(:test)
function testR31BelowSpeedThresholdSilent(logger as Test.Logger) as Boolean {
    var ev = feedDog(TestUtil.dog(), 0, 300, 2.7f, 0.0f, 0.0f, Rg.TIMER_OFF, null, null);
    return TestUtil.check(logger, ev.size() == 0, "2.7 m/s is below 10 km/h");
}

(:test)
function testNullSpeedNeverRaisesR31(logger as Test.Logger) as Boolean {
    var ev = feedDog(TestUtil.dog(), 0, 300, null, null, 0.0f, Rg.TIMER_STOPPED, null, null);
    return TestUtil.check(logger, ev.size() == 0, "null speed must not raise");
}

(:test)
function testRepeatEveryR(logger as Test.Logger) as Boolean {
    var w = TestUtil.dog();
    var ev = feedDog(w, 0, 31 + 125, 5.0f, 0.0f, 0.0f, Rg.TIMER_OFF, null, null);
    // raise at t=30, repeats at t=90 and t=150
    return TestUtil.check(logger, TestUtil.count(ev, Rg.R_MOVING, Rg.EV_RAISE) == 1, "one raise")
        && TestUtil.check(logger, TestUtil.count(ev, Rg.R_MOVING, Rg.EV_REPEAT) == 2, "two repeats in 125 s");
}

(:test)
function testClearWhenConditionEnds(logger as Test.Logger) as Boolean {
    var w = TestUtil.dog();
    feedDog(w, 0, 31, 5.0f, 0.0f, 0.0f, Rg.TIMER_OFF, null, null);
    var ev = feedDog(w, 31, 1, 5.0f, 0.0f, 0.0f, Rg.TIMER_ON, null, null);
    return TestUtil.check(logger, TestUtil.count(ev, Rg.R_MOVING, Rg.EV_CLEAR) == 1, "pressing Start clears R3.1")
        && TestUtil.check(logger, w.activeRule() == 0, "nothing active after clear");
}

(:test)
function testR32DistanceFrozen(logger as Test.Logger) as Boolean {
    var w = TestUtil.dog();
    var ev60 = feedDog(w, 0, 61, 5.0f, 100.0f, 0.0f, Rg.TIMER_ON, null, null);
    var ev61 = feedDog(w, 61, 1, 5.0f, 100.0f, 0.0f, Rg.TIMER_ON, null, null);
    return TestUtil.check(logger, TestUtil.count(ev60, Rg.R_FROZEN, Rg.EV_RAISE) == 0, "R3.2 too early")
        && TestUtil.check(logger, TestUtil.count(ev61, Rg.R_FROZEN, Rg.EV_RAISE) == 1, "R3.2 not raised after 60 s frozen");
}

(:test)
function testR32SilentWhenDistanceAdvances(logger as Test.Logger) as Boolean {
    var ev = feedDog(TestUtil.dog(), 0, 300, 5.0f, 0.0f, 5.0f, Rg.TIMER_ON, null, null);
    return TestUtil.check(logger, ev.size() == 0, "advancing distance must not alert");
}

(:test)
function testR33HrLostOnlyAfterSeen(logger as Test.Logger) as Boolean {
    var neverSeen = feedDog(TestUtil.dog(), 0, 300, 5.0f, 0.0f, 5.0f, Rg.TIMER_ON, null, null);
    var w = TestUtil.dog();
    feedDog(w, 0, 10, 5.0f, 0.0f, 5.0f, Rg.TIMER_ON, 130, null);
    var lost = feedDog(w, 10, 62, 5.0f, 50.0f, 5.0f, Rg.TIMER_ON, null, null);
    return TestUtil.check(logger, neverSeen.size() == 0, "HR never seen must not alert")
        && TestUtil.check(logger, TestUtil.count(lost, Rg.R_HR, Rg.EV_RAISE) == 1, "HR lost not raised")
        && TestUtil.check(logger, w.sawHr, "sawHr not set");
}

(:test)
function testR33PowerLost(logger as Test.Logger) as Boolean {
    var w = TestUtil.dog();
    feedDog(w, 0, 10, 5.0f, 0.0f, 5.0f, Rg.TIMER_ON, null, 200);
    var lost = feedDog(w, 10, 62, 5.0f, 50.0f, 5.0f, Rg.TIMER_ON, null, null);
    return TestUtil.check(logger, TestUtil.count(lost, Rg.R_POWER, Rg.EV_RAISE) == 1, "power lost not raised");
}

(:test)
function testDisabledRuleNeverFires(logger as Test.Logger) as Boolean {
    var w = new Watchdog(10.0f / 3.6f, 30, 60, 60, 60, [false, true, true]);
    var ev = feedDog(w, 0, 300, 5.0f, 0.0f, 0.0f, Rg.TIMER_OFF, null, null);
    return TestUtil.check(logger, ev.size() == 0, "disabled R3.1 fired");
}

(:test)
function testResetRideForgetsSensors(logger as Test.Logger) as Boolean {
    var w = TestUtil.dog();
    feedDog(w, 0, 5, 5.0f, 0.0f, 5.0f, Rg.TIMER_ON, 130, 200);
    w.resetRide();
    var ev = feedDog(w, 5, 120, 5.0f, 25.0f, 5.0f, Rg.TIMER_ON, null, null);
    return TestUtil.check(logger, !w.sawHr && !w.sawPower, "flags not reset")
        && TestUtil.check(logger, ev.size() == 0, "sensor alerts after reset");
}

// --- Design decision: sensor alerts beep three times, then stay silent ---

(:test)
function testSensorAlertBeepsThreeTimesThenStaysSilent(logger as Test.Logger) as Boolean {
    var w = TestUtil.dog();
    feedDog(w, 0, 10, 5.0f, 0.0f, 5.0f, Rg.TIMER_ON, 130, null);
    var ev = feedDog(w, 10, 61 + 900, 5.0f, 50.0f, 5.0f, Rg.TIMER_ON, null, null);     // HR gone for 16 minutes
    var beeps = TestUtil.count(ev, Rg.R_HR, Rg.EV_RAISE) + TestUtil.count(ev, Rg.R_HR, Rg.EV_REPEAT);
    return TestUtil.check(logger, beeps == 3, "a dead HR sensor must beep 3 times in all, got " + beeps)
        && TestUtil.check(logger, w.activeRule() == Rg.R_HR, "the alert stays active (red field) while the sensor is missing");
}

(:test)
function testSensorAlertStartsOverWhenTheSensorComesBackAndDropsAgain(logger as Test.Logger) as Boolean {
    var w = TestUtil.dog();
    feedDog(w, 0, 10, 5.0f, 0.0f, 5.0f, Rg.TIMER_ON, null, 200);
    feedDog(w, 10, 61 + 600, 5.0f, 50.0f, 5.0f, Rg.TIMER_ON, null, null);              // power lost, 3 beeps, then silence
    var back = feedDog(w, 700, 5, 5.0f, 4000.0f, 5.0f, Rg.TIMER_ON, null, 210);
    var again = feedDog(w, 705, 61 + 60, 5.0f, 4100.0f, 5.0f, Rg.TIMER_ON, null, null);
    return TestUtil.check(logger, TestUtil.count(back, Rg.R_POWER, Rg.EV_CLEAR) == 1, "the alert clears when power returns")
        && TestUtil.check(logger, TestUtil.count(again, Rg.R_POWER, Rg.EV_RAISE) == 1 && TestUtil.count(again, Rg.R_POWER, Rg.EV_REPEAT) == 1, "a second dropout alerts and repeats again");
}

(:test)
function testTimerAndDistanceAlertsKeepRepeating(logger as Test.Logger) as Boolean {
    var moving = feedDog(TestUtil.dog(), 0, 31 + 900, 5.0f, 0.0f, 0.0f, Rg.TIMER_STOPPED, null, null);
    var frozen = feedDog(TestUtil.dog(), 0, 62 + 900, 5.0f, 100.0f, 0.0f, Rg.TIMER_ON, null, null);
    return TestUtil.check(logger, TestUtil.count(moving, Rg.R_MOVING, Rg.EV_REPEAT) == 15, "timer-not-running repeats every 60 s for as long as it lasts, got " + TestUtil.count(moving, Rg.R_MOVING, Rg.EV_REPEAT))
        && TestUtil.check(logger, TestUtil.count(frozen, Rg.R_FROZEN, Rg.EV_REPEAT) == 15, "distance-frozen repeats every 60 s for as long as it lasts, got " + TestUtil.count(frozen, Rg.R_FROZEN, Rg.EV_REPEAT));
}

// The cap is on the sensor being gone, not on the timer: an auto-pause must not re-arm it.

function beeps(ev as Array<Array<Number>>, rule as Number) as Number {
    return TestUtil.count(ev, rule, Rg.EV_RAISE) + TestUtil.count(ev, rule, Rg.EV_REPEAT);
}

(:test)
function testSensorCapSurvivesAutoPause(logger as Test.Logger) as Boolean {
    var w = TestUtil.dog();
    feedDog(w, 0, 10, 5.0f, 0.0f, 5.0f, Rg.TIMER_ON, 130, null);
    var before = feedDog(w, 10, 260, 5.0f, 50.0f, 5.0f, Rg.TIMER_ON, null, null);        // HR dies: 3 beeps
    var paused = feedDog(w, 270, 30, 0.0f, 1350.0f, 0.0f, Rg.TIMER_PAUSED, null, null);  // a red light
    var after = feedDog(w, 300, 600, 5.0f, 1350.0f, 5.0f, Rg.TIMER_ON, null, null);      // ride on, HR still dead
    return TestUtil.check(logger, beeps(before, Rg.R_HR) == 3, "three beeps before the pause, got " + beeps(before, Rg.R_HR))
        && TestUtil.check(logger, paused.size() == 0, "nothing happens during the pause, got " + paused.size() + " events")
        && TestUtil.check(logger, beeps(after, Rg.R_HR) == 0, "no more beeps after the pause, got " + beeps(after, Rg.R_HR))
        && TestUtil.check(logger, w.activeRule() == Rg.R_HR, "still on record as lost");
}

(:test)
function testSensorAlertIsSilentWhilePausedAndFinishesItsBeepsAfter(logger as Test.Logger) as Boolean {
    var w = TestUtil.dog();
    feedDog(w, 0, 10, 5.0f, 0.0f, 5.0f, Rg.TIMER_ON, null, 200);
    var before = feedDog(w, 10, 70, 5.0f, 50.0f, 5.0f, Rg.TIMER_ON, null, null);         // power dies: first beep
    var paused = feedDog(w, 80, 300, 0.0f, 400.0f, 0.0f, Rg.TIMER_PAUSED, null, null);   // five minutes at a cafe
    var after = feedDog(w, 380, 600, 5.0f, 400.0f, 5.0f, Rg.TIMER_ON, null, null);
    return TestUtil.check(logger, beeps(before, Rg.R_POWER) == 1, "one beep before the pause")
        && TestUtil.check(logger, paused.size() == 0, "a pause at a standstill never beeps, got " + paused.size() + " events")
        && TestUtil.check(logger, beeps(after, Rg.R_POWER) == 2, "the remaining two beeps come after the pause, got " + beeps(after, Rg.R_POWER));
}

(:test)
function testSensorAlertClearsWhenSensorReturnsDuringPause(logger as Test.Logger) as Boolean {
    var w = TestUtil.dog();
    feedDog(w, 0, 10, 5.0f, 0.0f, 5.0f, Rg.TIMER_ON, 130, null);
    feedDog(w, 10, 70, 5.0f, 50.0f, 5.0f, Rg.TIMER_ON, null, null);
    var back = feedDog(w, 80, 5, 0.0f, 400.0f, 0.0f, Rg.TIMER_PAUSED, 128, null);
    return TestUtil.check(logger, TestUtil.count(back, Rg.R_HR, Rg.EV_CLEAR) == 1 && w.activeRule() == 0, "HR back during a pause clears the alert");
}
