import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

// One short line per event into /Garmin/Apps/LOGS/RIDEGRD.TXT (written only if that file exists).
module EventLog {
    function write(msg as String) as Void {
        var t = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        System.println(Texts.logLine(t.hour as Number, t.min as Number, t.sec as Number, msg));
    }
}
