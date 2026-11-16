import Toybox.Graphics;
import Toybox.Lang;

// All user-visible strings and colours. Pure.
module Texts {
    function status(state as Number, timer as Number, speedBlind as Boolean, timerTimeMs as Number or Null) as String {
        if (state == Rg.ST_STANDBY) { return "RG ready"; }
        if (state == Rg.ST_ENDED) { return ended(); }
        if (timer == Rg.TIMER_OFF) { return "RG timer off"; }       // a ride is open but nothing is recording
        if (speedBlind) { return "RG no speed"; }
        if (timer == Rg.TIMER_PAUSED) { return "RG paused"; }
        if (timer == Rg.TIMER_STOPPED) { return "RG timer stopped"; }
        var mins = (timerTimeMs == null) ? 0 : (timerTimeMs as Number) / 60000;
        return "RG OK " + (mins / 60) + ":" + (mins % 60).format("%02d");
    }

    // Green only when the timer is running or auto-paused and the watchdog can see your speed.
    // Amber is Garmin's COLOR_YELLOW (0xFFAA00); COLOR_ORANGE (0xFF5500) reads as red next to an alert.
    function statusColor(state as Number, timer as Number, speedBlind as Boolean, alertRule as Number) as Number {
        if (alertRule != 0) { return Graphics.COLOR_RED; }
        if (state != Rg.ST_WATCHING) { return Graphics.COLOR_LT_GRAY; }
        if (speedBlind || timer == Rg.TIMER_STOPPED || timer == Rg.TIMER_OFF) { return Graphics.COLOR_YELLOW; }
        return Graphics.COLOR_GREEN;
    }

    // A second line that says what the state means or what to do. Empty when the state needs none.
    function hint(state as Number, timer as Number, speedBlind as Boolean) as String {
        if (state == Rg.ST_STANDBY) { return ""; }
        if (state == Rg.ST_ENDED) { return "Saved or discarded"; }
        if (timer == Rg.TIMER_OFF) { return "Press START to record"; }
        if (speedBlind) { return "No GPS or speed sensor"; }
        if (timer == Rg.TIMER_PAUSED) { return "Resumes when you move"; }
        if (timer == Rg.TIMER_STOPPED) { return "Press START to resume"; }
        return "";
    }

    function ended() as String { return "RG ride ended"; }

    // STANDBY draws a hollow dot; every other state a filled one.
    function dotHollow(state as Number) as Boolean { return state == Rg.ST_STANDBY; }

    function title(rule as Number) as String {
        if (rule == Rg.R_MOVING) { return "TIMER NOT RUNNING"; }
        if (rule == Rg.R_FROZEN) { return "DISTANCE FROZEN"; }
        if (rule == Rg.R_HR) { return "HR LOST"; }
        return "POWER LOST";
    }

    // The same title on two lines, for fields too narrow to show it on one at a readable size.
    function titleWrapped(rule as Number) as String {
        if (rule == Rg.R_MOVING) { return "TIMER NOT\nRUNNING"; }
        if (rule == Rg.R_FROZEN) { return "DISTANCE\nFROZEN"; }
        if (rule == Rg.R_HR) { return "HR\nLOST"; }
        return "POWER\nLOST";
    }

    function action(rule as Number) as String {
        if (rule == Rg.R_MOVING) { return "Press START to record"; }
        if (rule == Rg.R_FROZEN) { return "Check GPS & sensors"; }
        if (rule == Rg.R_HR) { return "Check HR strap / watch"; }
        return "Check power meter";
    }

    function ruleTag(rule as Number) as String {
        if (rule == Rg.R_MOVING) { return "R3.1"; }
        if (rule == Rg.R_FROZEN) { return "R3.2"; }
        if (rule == Rg.R_HR) { return "R3.3hr"; }
        return "R3.3pw";
    }

    function ruleShort(rule as Number) as String {
        if (rule == Rg.R_MOVING) { return "timer"; }
        if (rule == Rg.R_FROZEN) { return "distance"; }
        if (rule == Rg.R_HR) { return "HR"; }
        return "power";
    }

    // "1 alert: timer 10:31" / "3 alerts, last: HR 9:05". Empty when there were none.
    function alertsLine(count as Number, rule as Number, hour as Number, min as Number) as String {
        if (count <= 0 || rule == 0) { return ""; }
        var when = ruleShort(rule) + " " + hour + ":" + min.format("%02d");
        return (count == 1) ? "1 alert: " + when : count + " alerts, last: " + when;
    }

    function helpPage(i as Number) as String {
        if (i == 0) { return "RideGuard warns you\nwhen the Edge\nisn't recording"; }
        if (i == 1) { return "green OK  amber check\nred ALERT  grey ready"; }
        if (i == 2) { return "Red: timer not running,\ndistance frozen,\nHR or power lost"; }
        if (i == 3) { return "Record this ride\non your Epix too"; }
        return "Plug into your Mac\nto archive rides";
    }

    // Logged once each time the Edge loads the field: shows reloads and the memory headroom.
    function initLine(usedBytes as Number, totalBytes as Number) as String {
        return "INIT mem=" + (usedBytes / 1024) + "k/" + (totalBytes / 1024) + "k";
    }

    function logLine(hour as Number, min as Number, sec as Number, msg as String) as String {
        return hour.format("%02d") + ":" + min.format("%02d") + ":" + sec.format("%02d") + " " + msg;
    }
}
