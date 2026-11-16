import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Test;

// The field end to end: samples in through tick(), what the rider sees out through view().
// view() returns [alertRule, statusText, dotColour, dotHollow, secondLine].

// Feed `secs` seconds; distance advances by `step` metres a second. Returns the next distance.
function rideFor(f as RideGuardField, t0 as Number, secs as Number, timer as Number, speed as Float or Null, dist as Float, step as Float) as Float {
    var d = dist;
    for (var i = 0; i < secs; i++) {
        d += step;
        f.tick(TestUtil.info(timer, speed, d, (t0 + i) * 1000), t0 + i);
    }
    return d;
}

(:test)
function testRecordShape(logger as Test.Logger) as Boolean {
    var l = new Lifecycle();
    l.step(100, 0.0f, Rg.TIMER_ON);
    var w = TestUtil.dog();
    var rec = RideGuardField.record(l, w, 3, Rg.R_MOVING, 120);
    return TestUtil.check(logger, rec.get("rideOpen") == true && rec.get("rideStart") == 100, "ride fields")
        && TestUtil.check(logger, rec.get("alerts") == 3 && rec.get("lastAlert") == Rg.R_MOVING && rec.get("lastAlertAt") == 120, "alert fields")
        && TestUtil.check(logger, rec.get("v") == 1, "version");
}

(:test)
function testAutoPauseAtStandstillStaysGreenAndSilent(logger as Test.Logger) as Boolean {
    var f = TestUtil.field();
    var d = rideFor(f, 1000, 60, Rg.TIMER_ON, 6.0f, 0.0f, 6.0f);
    rideFor(f, 1060, 600, Rg.TIMER_PAUSED, 0.0f, d, 0.0f);          // ten minutes at a red light
    var v = f.view(1660);
    return TestUtil.check(logger, v[0] == 0, "auto-pause at a standstill must not alert")
        && TestUtil.check(logger, (v[1] as String).equals("RG paused") && v[2] == Graphics.COLOR_GREEN, "paused is green")
        && TestUtil.check(logger, (v[4] as String).equals("Resumes when you move"), "paused says it is normal, with no alert count");
}

(:test)
function testMovingWithTimerStoppedAlertsThenClears(logger as Test.Logger) as Boolean {
    var f = TestUtil.field();
    var d = rideFor(f, 1000, 60, Rg.TIMER_ON, 6.0f, 0.0f, 6.0f);
    rideFor(f, 1060, 30, Rg.TIMER_STOPPED, 6.0f, d, 0.0f);          // the 3 Oct failure: riding on, timer stopped
    var quiet = f.view(1090);
    rideFor(f, 1090, 1, Rg.TIMER_STOPPED, 6.0f, d, 0.0f);
    var alert = f.view(1091);
    rideFor(f, 1091, 5, Rg.TIMER_ON, 6.0f, d, 6.0f);                // Start pressed
    var after = f.view(1096);
    return TestUtil.check(logger, quiet[0] == 0 && (quiet[1] as String).equals("RG timer stopped") && quiet[2] == Graphics.COLOR_YELLOW, "amber before the delay runs out")
        && TestUtil.check(logger, alert[0] == Rg.R_MOVING, "31 s moving with the timer stopped must alert")
        && TestUtil.check(logger, after[0] == 0 && after[2] == Graphics.COLOR_GREEN, "pressing Start clears the alert")
        && TestUtil.check(logger, (after[4] as String).find("1 alert: timer ") == 0, "the alert stays on record for the ride");
}

(:test)
function testForgottenStartShowsTimerOffNotOk(logger as Test.Logger) as Boolean {
    var f = TestUtil.field();
    rideFor(f, 1000, 6, Rg.TIMER_OFF, 2.5f, 0.0f, 0.0f);            // rolling slowly, Start never pressed
    var v = f.view(1006);
    return TestUtil.check(logger, (v[1] as String).equals("RG timer off") && v[2] == Graphics.COLOR_YELLOW, "an open ride with the timer OFF is amber")
        && TestUtil.check(logger, (v[4] as String).equals("Press START to record"), "and says what to do");
}

(:test)
function testStandbyShowsHelpPages(logger as Test.Logger) as Boolean {
    var f = TestUtil.field();
    rideFor(f, 1000, 3, Rg.TIMER_OFF, 0.0f, 0.0f, 0.0f);
    var v = f.view(1003);
    return TestUtil.check(logger, (v[1] as String).equals("RG ready") && v[3] == true && v[2] == Graphics.COLOR_LT_GRAY, "standby: hollow grey dot")
        && TestUtil.check(logger, (v[4] as String).equals(Texts.helpPage((1003 / 4) % 5)), "standby rotates the help pages");
}

(:test)
function testNoSpeedForTenSecondsIsAmber(logger as Test.Logger) as Boolean {
    var f = TestUtil.field();
    rideFor(f, 1000, 10, Rg.TIMER_ON, null, 0.0f, 0.0f);
    var early = f.view(1010);
    rideFor(f, 1010, 1, Rg.TIMER_ON, null, 0.0f, 0.0f);
    var v = f.view(1011);
    return TestUtil.check(logger, (early[1] as String).find("RG OK") == 0, "ten seconds without speed is still OK")
        && TestUtil.check(logger, (v[1] as String).equals("RG no speed") && v[2] == Graphics.COLOR_YELLOW, "longer than that is amber, not green");
}

(:test)
function testReloadMidRideKeepsRideAndAlertRecord(logger as Test.Logger) as Boolean {
    var f = TestUtil.field();
    var d = rideFor(f, 1000, 60, Rg.TIMER_ON, 6.0f, 0.0f, 6.0f);
    rideFor(f, 1060, 31, Rg.TIMER_STOPPED, 6.0f, d, 0.0f);          // one alert, saved at once
    var again = new RideGuardField();                                // the Edge reloads the field
    rideFor(again, 1091, 2, Rg.TIMER_ON, 6.0f, d, 6.0f);
    var v = again.view(1093);
    return TestUtil.check(logger, (v[1] as String).find("RG OK") == 0, "still watching after a reload")
        && TestUtil.check(logger, (v[4] as String).find("1 alert: timer ") == 0, "the alert record survives a reload");
}

(:test)
function testBadSampleShowsErrorInsteadOfCrashing(logger as Test.Logger) as Boolean {
    var f = TestUtil.field();
    rideFor(f, 1000, 5, Rg.TIMER_ON, 6.0f, 0.0f, 6.0f);
    var bad = TestUtil.info(Rg.TIMER_ON, 6.0f, 30.0f, 0);
    bad.currentSpeed = "oops" as Float;                              // a value of the wrong type from the Edge
    f.compute(bad);
    var v = f.view(1006);
    f.compute(TestUtil.info(Rg.TIMER_ON, 6.0f, 36.0f, 0));
    var healed = f.view(1007);
    return TestUtil.check(logger, (v[1] as String).equals("RG error") && v[2] == Graphics.COLOR_YELLOW, "a fault must be visible, never a stale green")
        && TestUtil.check(logger, (healed[1] as String).find("RG OK") == 0, "and the field recovers on the next good sample");
}

// --- Final review fixes ---

(:test)
function testAlertIsDeliveredAsToneAndBoxAndRepeats(logger as Test.Logger) as Boolean {
    var f = TestUtil.field();
    var d = rideFor(f, 1000, 60, Rg.TIMER_ON, 6.0f, 0.0f, 6.0f);
    rideFor(f, 1060, 31, Rg.TIMER_STOPPED, 6.0f, d, 0.0f);          // raise at t=1090
    var raised = f.stats();                                          // [alerts, tones, boxes]
    rideFor(f, 1091, 60, Rg.TIMER_STOPPED, 6.0f, d, 0.0f);          // repeat at t=1150
    var repeated = f.stats();
    return TestUtil.check(logger, raised[0] == 1 && raised[1] == 1 && raised[2] == 1, "a raise must beep once and ask for one box, got " + raised)
        && TestUtil.check(logger, repeated[0] == 1 && repeated[1] == 2 && repeated[2] == 2, "a repeat must beep and ask for the box again, got " + repeated);
}

(:test)
function testQuietRideDeliversNothing(logger as Test.Logger) as Boolean {
    var f = TestUtil.field();
    var d = rideFor(f, 1000, 120, Rg.TIMER_ON, 6.0f, 0.0f, 6.0f);
    rideFor(f, 1120, 300, Rg.TIMER_PAUSED, 0.0f, d, 0.0f);
    var s = f.stats();
    return TestUtil.check(logger, s[0] == 0 && s[1] == 0 && s[2] == 0, "no alert, tone or box on a normal ride with an auto-pause, got " + s);
}
