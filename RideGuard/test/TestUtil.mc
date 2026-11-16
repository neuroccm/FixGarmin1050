import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Test;

module TestUtil {
    function check(logger as Test.Logger, ok as Boolean, msg as String) as Boolean {
        if (!ok) { logger.error(msg); }
        return ok;
    }

    // Count events of one rule and kind in a list of [rule, kind] events.
    function count(events as Array<Array<Number>>, rule as Number, kind as Number) as Number {
        var n = 0;
        for (var i = 0; i < events.size(); i++) {
            if (events[i][0] == rule && events[i][1] == kind) { n++; }
        }
        return n;
    }

    function dog() as Watchdog {
        return new Watchdog(10.0f / 3.6f, 30, 60, 60, 60, [true, true, true]);
    }

    // An off-screen drawing context the size of a data field, for layout tests.
    function dc(w as Number, h as Number) as Graphics.Dc {
        var ref = Graphics.createBufferedBitmap({:width => w, :height => h});
        return (ref.get() as Graphics.BufferedBitmap).getDc();
    }

    // A field with no saved ride behind it.
    function field() as RideGuardField {
        Application.Storage.deleteValue(StateStore.KEY);
        return new RideGuardField();
    }

    function info(timer as Number, speed as Float or Null, dist as Float or Null, timerMs as Number or Null) as Activity.Info {
        var i = new Activity.Info();
        i.timerState = timer as Activity.TimerState;
        i.currentSpeed = speed;
        i.elapsedDistance = dist;
        i.timerTime = timerMs;
        return i;
    }
}
