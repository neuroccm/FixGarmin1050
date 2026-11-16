import Toybox.Application;
import Toybox.Lang;

// Settings with safe fallbacks: a missing, mistyped or out-of-range value becomes the default,
// so a bad setting can never turn the watchdog into a constant alarm or switch it off silently.
class RgSettings {
    var speedMs as Float = 10.0f / 3.6f;
    var t1 as Number = 30;
    var t2 as Number = 60;
    var t3 as Number = 60;
    var repeatS as Number = 60;
    var on as Array<Boolean> = [true, true, true];
    var toneOn as Boolean = true;
    var helpOn as Boolean = true;

    function initialize() {
        speedMs = RgSettings.clamp(prop("speedKmh"), 5, 40, 10).toFloat() / 3.6f;
        t1 = RgSettings.clamp(prop("t1"), 10, 300, 30);
        t2 = RgSettings.clamp(prop("t2"), 20, 600, 60);
        t3 = RgSettings.clamp(prop("t3"), 20, 600, 60);
        repeatS = RgSettings.clamp(prop("repeatS"), 20, 600, 60);
        on = [flag("r31On"), flag("r32On"), flag("r33On")];
        toneOn = flag("toneOn");
        helpOn = flag("helpOn");
    }

    // `v` when it is a whole number within [lo, hi]; otherwise `dflt`. The ranges match settings.xml.
    static function clamp(v as Object or Null, lo as Number, hi as Number, dflt as Number) as Number {
        if (v instanceof Number && (v as Number) >= lo && (v as Number) <= hi) { return v as Number; }
        return dflt;
    }

    hidden function prop(key as String) as Object or Null {
        try { return Application.Properties.getValue(key); } catch (e) { return null; }
    }

    // On unless explicitly switched off.
    hidden function flag(key as String) as Boolean {
        return prop(key) != false;
    }
}
