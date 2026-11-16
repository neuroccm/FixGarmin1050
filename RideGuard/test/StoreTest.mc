import Toybox.Lang;
import Toybox.Test;

(:test)
function testMergeKeepsEarlierRideStart(logger as Test.Logger) as Boolean {
    var stored = {"v" => 1, "rideOpen" => true, "rideStart" => 1000, "timerSeen" => true};
    var observed = {"v" => 1, "rideOpen" => true, "rideStart" => 1500, "timerSeen" => true, "alerts" => 2};
    var m = StateStore.merge(stored, observed);
    return TestUtil.check(logger, m.get("rideStart") == 1000, "earlier rideStart must win")
        && TestUtil.check(logger, m.get("alerts") == 2, "other observed fields kept");
}

(:test)
function testMergeClosedRideTakesObserved(logger as Test.Logger) as Boolean {
    var stored = {"v" => 1, "rideOpen" => true, "rideStart" => 1000};
    var observed = {"v" => 1, "rideOpen" => false, "rideStart" => null};
    var m = StateStore.merge(stored, observed);
    return TestUtil.check(logger, m.get("rideOpen") == false && m.get("rideStart") == null, "a closed ride replaces the stored one");
}

(:test)
function testMergeWithNothingStored(logger as Test.Logger) as Boolean {
    var observed = {"v" => 1, "rideOpen" => true, "rideStart" => 1500};
    return TestUtil.check(logger, StateStore.merge(null, observed).get("rideStart") == 1500, "null stored");
}

(:test)
function testToneRateLimit(logger as Test.Logger) as Boolean {
    return TestUtil.check(logger, Alerter.shouldTone(100, 95, true) == false, "5 s after a tone must be silent")
        && TestUtil.check(logger, Alerter.shouldTone(105, 95, true) == true, "10 s after a tone may beep")
        && TestUtil.check(logger, Alerter.shouldTone(200, 0, false) == false, "tones off");
}

(:test)
function testSettingsClampRejectsOutOfRange(logger as Test.Logger) as Boolean {
    return TestUtil.check(logger, RgSettings.clamp(12, 5, 40, 10) == 12, "in range kept")
        && TestUtil.check(logger, RgSettings.clamp(0, 5, 40, 10) == 10, "0 km/h would alarm at a standstill: use the default")
        && TestUtil.check(logger, RgSettings.clamp(-3, 10, 300, 30) == 30, "negative delay: default")
        && TestUtil.check(logger, RgSettings.clamp(9999, 20, 600, 60) == 60, "absurd value: default")
        && TestUtil.check(logger, RgSettings.clamp(null, 20, 600, 60) == 60, "missing: default")
        && TestUtil.check(logger, RgSettings.clamp("12", 5, 40, 10) == 10, "wrong type: default");
}
