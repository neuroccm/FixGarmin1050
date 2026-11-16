import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// The pop-up box for an alert. It is requested by the data field itself (RideGuardField.alertBox).
class RgAlertView extends WatchUi.DataFieldAlert {
    hidden var _rule as Number;
    function initialize(rule as Number) { DataFieldAlert.initialize(); _rule = rule; }
    function onUpdate(dc as Graphics.Dc) as Void { RgDraw.alert(dc, _rule); }
}

// The alert tone, at most one per 10 s across all rules. Counts what it played so a ride's log
// can show that alerts were really delivered.
class Alerter {
    var tones as Number = 0;

    hidden var _lastToneAt as Number = -100000;
    hidden var _failed as Boolean = false;

    function initialize() {}

    static function shouldTone(now as Number, lastToneAt as Number, toneOn as Boolean) as Boolean {
        return toneOn && now - lastToneAt >= 10;
    }

    function tone(now as Number, toneOn as Boolean) as Void {
        if (!Alerter.shouldTone(now, _lastToneAt, toneOn)) { return; }
        _lastToneAt = now;
        try {
            Attention.playTone(Attention.TONE_ALARM);
            tones++;
        } catch (e) {
            if (!_failed) { EventLog.write("TONE-ERR " + e.getErrorMessage()); }
            _failed = true;
        }
    }
}
