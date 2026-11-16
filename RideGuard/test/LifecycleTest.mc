import Toybox.Lang;
import Toybox.Test;

function runLife(l as Lifecycle, t0 as Number, secs as Number, speed as Float or Null, timer as Number) as Array<Number> {
    var evs = [] as Array<Number>;
    for (var i = 0; i < secs; i++) {
        var e = l.step(t0 + i, speed, timer);
        if (e != Rg.LC_NONE) { evs.add(e); }
    }
    return evs;
}

(:test)
function testStandbyUntilStart(logger as Test.Logger) as Boolean {
    var l = new Lifecycle();
    runLife(l, 0, 100, 0.0f, Rg.TIMER_OFF);
    var ev = runLife(l, 100, 1, 0.0f, Rg.TIMER_ON);
    return TestUtil.check(logger, ev.size() == 1 && ev[0] == Rg.LC_STARTED, "Start must open the ride")
        && TestUtil.check(logger, l.state == Rg.ST_WATCHING && l.rideStart == 100 && l.timerSeen, "watching from t=100");
}

(:test)
function testForgottenStartOpensOnMovement(logger as Test.Logger) as Boolean {
    var l = new Lifecycle();
    var four = runLife(l, 0, 4, 3.0f, Rg.TIMER_OFF);
    var fifth = runLife(l, 4, 1, 3.0f, Rg.TIMER_OFF);
    return TestUtil.check(logger, four.size() == 0, "opened before 5 s")
        && TestUtil.check(logger, fifth.size() == 1 && l.state == Rg.ST_WATCHING && !l.timerSeen, "5 s above 2 m/s must open");
}

(:test)
function testSaveOrDiscardEndsRide(logger as Test.Logger) as Boolean {
    var l = new Lifecycle();
    runLife(l, 0, 10, 0.0f, Rg.TIMER_ON);
    runLife(l, 10, 10, 0.0f, Rg.TIMER_STOPPED);
    var ev = runLife(l, 20, 1, 0.0f, Rg.TIMER_OFF);
    return TestUtil.check(logger, ev.size() == 1 && ev[0] == Rg.LC_ENDED && l.state == Rg.ST_ENDED, "timer back to OFF must end the ride");
}

(:test)
function testEndedShowsSixtySecondsThenStandby(logger as Test.Logger) as Boolean {
    var l = new Lifecycle();
    runLife(l, 0, 10, 0.0f, Rg.TIMER_ON);
    runLife(l, 10, 1, 0.0f, Rg.TIMER_OFF);
    runLife(l, 11, 59, 0.0f, Rg.TIMER_OFF);
    var stillEnded = l.state == Rg.ST_ENDED;
    runLife(l, 70, 1, 0.0f, Rg.TIMER_OFF);
    return TestUtil.check(logger, stillEnded, "ENDED left too early")
        && TestUtil.check(logger, l.state == Rg.ST_STANDBY && l.rideStart == null, "not back to STANDBY after 60 s");
}

(:test)
function testStoppedTimerNeverEndsRide(logger as Test.Logger) as Boolean {
    var l = new Lifecycle();
    runLife(l, 0, 10, 0.0f, Rg.TIMER_ON);
    var ev = runLife(l, 10, 2400, 0.0f, Rg.TIMER_STOPPED);
    return TestUtil.check(logger, ev.size() == 0 && l.state == Rg.ST_WATCHING, "a STOPPED timer (cafe) must keep the ride open");
}

(:test)
function testForgottenStartEndsAfterThirtyMinutesStill(logger as Test.Logger) as Boolean {
    var l = new Lifecycle();
    runLife(l, 0, 600, 5.0f, Rg.TIMER_OFF);
    var early = runLife(l, 600, 1799, 0.0f, Rg.TIMER_OFF);
    var ev = runLife(l, 2399, 2, 0.0f, Rg.TIMER_OFF);
    return TestUtil.check(logger, early.size() == 0, "ended before 30 min")
        && TestUtil.check(logger, ev.size() == 1 && ev[0] == Rg.LC_ENDED, "30 min still with timer OFF must end");
}

(:test)
function testOnResetEndsRide(logger as Test.Logger) as Boolean {
    var l = new Lifecycle();
    runLife(l, 0, 10, 0.0f, Rg.TIMER_ON);
    return TestUtil.check(logger, l.onReset(10) == Rg.LC_ENDED && l.state == Rg.ST_ENDED, "onTimerReset must end the ride");
}

(:test)
function testRestoreMidRideKeepsWatching(logger as Test.Logger) as Boolean {
    var l = new Lifecycle();
    l.restore({"rideOpen" => true, "rideStart" => 1000, "timerSeen" => true});
    var ev = runLife(l, 5000, 1, 6.0f, Rg.TIMER_ON);
    return TestUtil.check(logger, ev.size() == 0 && l.state == Rg.ST_WATCHING && l.rideStart == 1000, "reload mid-ride must keep the ride");
}

(:test)
function testRestoreAfterSaveEnds(logger as Test.Logger) as Boolean {
    var l = new Lifecycle();
    l.restore({"rideOpen" => true, "rideStart" => 1000, "timerSeen" => true});
    var ev = runLife(l, 5000, 1, 0.0f, Rg.TIMER_OFF);
    return TestUtil.check(logger, ev.size() == 1 && ev[0] == Rg.LC_ENDED, "reload after save must show ENDED");
}

(:test)
function testRestoreNullIsStandby(logger as Test.Logger) as Boolean {
    var l = new Lifecycle();
    l.restore(null);
    return TestUtil.check(logger, l.state == Rg.ST_STANDBY && l.rideStart == null, "no record must mean STANDBY");
}

(:test)
function testNewRideDuringEnded(logger as Test.Logger) as Boolean {
    var l = new Lifecycle();
    runLife(l, 0, 10, 0.0f, Rg.TIMER_ON);
    runLife(l, 10, 1, 0.0f, Rg.TIMER_OFF);
    var ev = runLife(l, 20, 1, 0.0f, Rg.TIMER_ON);
    return TestUtil.check(logger, ev.size() == 1 && ev[0] == Rg.LC_STARTED && l.rideStart == 20, "Start during ENDED must open a new ride");
}

// --- From replaying real rides: one was saved while still rolling at 16.8 km/h ---

(:test)
function testMovementDuringEndedDoesNotOpenRide(logger as Test.Logger) as Boolean {
    var l = new Lifecycle();
    runLife(l, 0, 10, 5.0f, Rg.TIMER_ON);
    runLife(l, 10, 1, 5.0f, Rg.TIMER_OFF);              // saved while rolling
    var ev = runLife(l, 11, 30, 5.0f, Rg.TIMER_OFF);    // still rolling during "ride ended"
    return TestUtil.check(logger, ev.size() == 0 && l.state == Rg.ST_ENDED, "rolling on after a save must not open a phantom ride");
}

(:test)
function testMovementAfterEndedDisplayOpensRide(logger as Test.Logger) as Boolean {
    var l = new Lifecycle();
    runLife(l, 0, 10, 5.0f, Rg.TIMER_ON);
    runLife(l, 10, 1, 5.0f, Rg.TIMER_OFF);
    var ev = runLife(l, 11, 65, 5.0f, Rg.TIMER_OFF);    // still riding a minute after the save
    return TestUtil.check(logger, ev.size() == 1 && ev[0] == Rg.LC_STARTED, "riding on after the 60 s display must open a ride")
        && TestUtil.check(logger, l.rideStart == 70 && !l.timerSeen, "opened by movement at t=70");
}

(:test)
function testRestoreMovementRideEndsWhenStill(logger as Test.Logger) as Boolean {
    var l = new Lifecycle();
    l.restore({"rideOpen" => true, "rideStart" => 1000, "timerSeen" => false});
    var ev = runLife(l, 5000, 1, 0.0f, Rg.TIMER_OFF);
    return TestUtil.check(logger, ev.size() == 1 && ev[0] == Rg.LC_ENDED, "a stale movement-opened ride must end on reload when the timer is OFF and you're still");
}

(:test)
function testRestoreWithNoSpeedAndTimerOffEnds(logger as Test.Logger) as Boolean {
    var l = new Lifecycle();
    l.restore({"rideOpen" => true, "rideStart" => 1000, "timerSeen" => false});
    var ev = runLife(l, 5000, 1, null, Rg.TIMER_OFF);
    return TestUtil.check(logger, ev.size() == 1 && ev[0] == Rg.LC_ENDED, "no speed counts as not moving on reload");
}

(:test)
function testRestoreMovementRideStaysOpenWhileMoving(logger as Test.Logger) as Boolean {
    var l = new Lifecycle();
    l.restore({"rideOpen" => true, "rideStart" => 1000, "timerSeen" => false});
    var ev = runLife(l, 5000, 10, 6.0f, Rg.TIMER_OFF);
    return TestUtil.check(logger, ev.size() == 0 && l.state == Rg.ST_WATCHING && l.rideStart == 1000, "a forgotten-Start ride that reloads while moving must stay open");
}
