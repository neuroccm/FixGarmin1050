import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Test;

(:test)
function testStatusStandbyAndWatching(logger as Test.Logger) as Boolean {
    return TestUtil.check(logger, Texts.status(Rg.ST_STANDBY, Rg.TIMER_OFF, false, null).equals("RG ready"), "standby text")
        && TestUtil.check(logger, Texts.status(Rg.ST_WATCHING, Rg.TIMER_ON, false, 4320000).equals("RG OK 1:12"), "watching text with 72 min");
}

(:test)
function testStatusPausedAndStopped(logger as Test.Logger) as Boolean {
    return TestUtil.check(logger, Texts.status(Rg.ST_WATCHING, Rg.TIMER_PAUSED, false, 60000).equals("RG paused"), "paused text")
        && TestUtil.check(logger, Texts.status(Rg.ST_WATCHING, Rg.TIMER_STOPPED, false, 60000).equals("RG timer stopped"), "stopped text")
        && TestUtil.check(logger, Texts.statusColor(Rg.ST_WATCHING, Rg.TIMER_PAUSED, false, 0) == Graphics.COLOR_GREEN, "paused is green")
        && TestUtil.check(logger, Texts.statusColor(Rg.ST_WATCHING, Rg.TIMER_STOPPED, false, 0) == Graphics.COLOR_YELLOW, "stopped is amber");
}

(:test)
function testStatusNoSpeed(logger as Test.Logger) as Boolean {
    return TestUtil.check(logger, Texts.status(Rg.ST_WATCHING, Rg.TIMER_ON, true, 60000).equals("RG no speed"), "blind text")
        && TestUtil.check(logger, Texts.statusColor(Rg.ST_WATCHING, Rg.TIMER_ON, true, 0) == Graphics.COLOR_YELLOW, "blind is amber")
        && TestUtil.check(logger, Texts.statusColor(Rg.ST_WATCHING, Rg.TIMER_ON, true, Rg.R_MOVING) == Graphics.COLOR_RED, "alert beats blind");
}

(:test)
function testAlertTexts(logger as Test.Logger) as Boolean {
    return TestUtil.check(logger, Texts.title(Rg.R_MOVING).equals("TIMER NOT RUNNING") && Texts.action(Rg.R_MOVING).equals("Press START to record"), "R3.1 texts")
        && TestUtil.check(logger, Texts.title(Rg.R_FROZEN).equals("DISTANCE FROZEN"), "R3.2 title")
        && TestUtil.check(logger, Texts.title(Rg.R_HR).equals("HR LOST") && Texts.title(Rg.R_POWER).equals("POWER LOST"), "R3.3 titles");
}

(:test)
function testLogLineAndTags(logger as Test.Logger) as Boolean {
    return TestUtil.check(logger, Texts.logLine(9, 5, 7, "START").equals("09:05:07 START"), "log line format")
        && TestUtil.check(logger, Texts.ruleTag(Rg.R_HR).equals("R3.3hr"), "rule tag")
        && TestUtil.check(logger, Texts.dotHollow(Rg.ST_STANDBY) && !Texts.dotHollow(Rg.ST_WATCHING), "dot style");
}

(:test)
function testHelpPagesExist(logger as Test.Logger) as Boolean {
    var ok = true;
    for (var i = 0; i < 5; i++) { ok = ok && Texts.helpPage(i).length() > 10; }
    return TestUtil.check(logger, ok, "five help pages");
}

// --- Rulings and additions after the real-ride replay ---

(:test)
function testStatusTimerOffWhileRideOpenIsAmber(logger as Test.Logger) as Boolean {
    return TestUtil.check(logger, Texts.status(Rg.ST_WATCHING, Rg.TIMER_OFF, false, null).equals("RG timer off"), "an open ride with the timer OFF must not read OK")
        && TestUtil.check(logger, Texts.statusColor(Rg.ST_WATCHING, Rg.TIMER_OFF, false, 0) == Graphics.COLOR_YELLOW, "timer off is amber, not green");
}

(:test)
function testHintsExplainEveryNonOkState(logger as Test.Logger) as Boolean {
    return TestUtil.check(logger, Texts.hint(Rg.ST_WATCHING, Rg.TIMER_ON, false).equals(""), "OK needs no hint")
        && TestUtil.check(logger, Texts.hint(Rg.ST_WATCHING, Rg.TIMER_PAUSED, false).equals("Resumes when you move"), "paused hint")
        && TestUtil.check(logger, Texts.hint(Rg.ST_WATCHING, Rg.TIMER_STOPPED, false).equals("Press START to resume"), "stopped hint")
        && TestUtil.check(logger, Texts.hint(Rg.ST_WATCHING, Rg.TIMER_OFF, false).equals("Press START to record"), "timer-off hint")
        && TestUtil.check(logger, Texts.hint(Rg.ST_WATCHING, Rg.TIMER_ON, true).equals("No GPS or speed sensor"), "blind hint")
        && TestUtil.check(logger, Texts.hint(Rg.ST_STANDBY, Rg.TIMER_OFF, false).equals(""), "standby has help pages instead")
        && TestUtil.check(logger, Texts.hint(Rg.ST_ENDED, Rg.TIMER_OFF, false).equals("Saved or discarded"), "ended hint");
}

(:test)
function testAlertsLine(logger as Test.Logger) as Boolean {
    return TestUtil.check(logger, Texts.alertsLine(0, 0, 0, 0).equals(""), "no alerts, no line")
        && TestUtil.check(logger, Texts.alertsLine(1, Rg.R_MOVING, 10, 31).equals("1 alert: timer 10:31"), "one alert")
        && TestUtil.check(logger, Texts.alertsLine(3, Rg.R_HR, 9, 5).equals("3 alerts, last: HR 9:05"), "several alerts")
        && TestUtil.check(logger, Texts.ruleShort(Rg.R_FROZEN).equals("distance") && Texts.ruleShort(Rg.R_POWER).equals("power"), "short rule names");
}

(:test)
function testInitLineReportsMemory(logger as Test.Logger) as Boolean {
    return TestUtil.check(logger, Texts.initLine(46080, 131072).equals("INIT mem=45k/128k"), "one line per field load, with memory used/limit");
}
