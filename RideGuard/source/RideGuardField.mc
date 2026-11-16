import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// The data field: once a second the Edge calls compute(); it feeds the lifecycle and the watchdog,
// delivers alerts, and saves a small record so a reload mid-ride changes nothing.
class RideGuardField extends WatchUi.DataField {
    hidden var _cfg as RgSettings;
    hidden var _life as Lifecycle;
    hidden var _dog as Watchdog;
    hidden var _alerter as Alerter;
    hidden var _timer as Number = Rg.TIMER_OFF;
    hidden var _timerMs as Number or Null = null;
    hidden var _blindRun as Number = 0;
    hidden var _alerts as Number = 0;
    hidden var _lastRule as Number = 0;
    hidden var _lastAlertAt as Number = 0;
    hidden var _lastSave as Number = 0;
    hidden var _dirty as Boolean = false;
    hidden var _fault as Boolean = false;
    hidden var _boxes as Number = 0;
    hidden var _boxFailed as Boolean = false;

    function initialize() {
        DataField.initialize();
        _cfg = new RgSettings();
        _life = new Lifecycle();
        _dog = new Watchdog(_cfg.speedMs, _cfg.t1, _cfg.t2, _cfg.t3, _cfg.repeatS, _cfg.on);
        _alerter = new Alerter();
        var rec = StateStore.load();          // read only; compute() is the only writer
        _life.restore(rec);
        if (rec != null && _life.isOpen()) {
            _dog.sawHr = rec.get("sawHr") == true;
            _dog.sawPower = rec.get("sawPower") == true;
            _alerts = RideGuardField.count(rec.get("alerts"));
            _lastRule = RideGuardField.count(rec.get("lastAlert"));
            _lastAlertAt = RideGuardField.count(rec.get("lastAlertAt"));
        }
        var mem = System.getSystemStats();
        EventLog.write(Texts.initLine(mem.usedMemory as Number, mem.totalMemory as Number));
    }

    // A stored value as a non-negative whole number; anything else is 0.
    static function count(v as Object or Null) as Number {
        return (v instanceof Number && (v as Number) > 0) ? v as Number : 0;
    }

    static function record(life as Lifecycle, dog as Watchdog, alerts as Number, lastRule as Number, lastAlertAt as Number) as Dictionary {
        return {"v" => 1, "rideOpen" => life.isOpen(), "rideStart" => life.rideStart, "timerSeen" => life.timerSeen,
                "sawHr" => dog.sawHr, "sawPower" => dog.sawPower, "alerts" => alerts,
                "lastAlert" => lastRule, "lastAlertAt" => lastAlertAt};
    }

    // Called by the Edge about once a second, on every page and in every timer state.
    // A sample that can't be processed must not kill the watchdog for the rest of the ride:
    // the field shows "RG error" and tries again on the next sample.
    function compute(info as Activity.Info) as Void {
        try {
            tick(info, Time.now().value());
            _fault = false;
        } catch (e) {
            if (!_fault) { EventLog.write("ERR " + e.getErrorMessage()); }
            _fault = true;
        }
    }

    function tick(info as Activity.Info, now as Number) as Void {
        _timer = (info.timerState == null) ? Rg.TIMER_OFF : info.timerState as Number;
        _timerMs = info.timerTime;
        var speed = info.currentSpeed;
        _blindRun = (speed == null) ? _blindRun + 1 : 0;

        var lc = _life.step(now, speed, _timer);
        if (lc == Rg.LC_STARTED) {
            _dog.resetRide();
            _alerts = 0;
            _lastRule = 0;
            _lastAlertAt = 0;
            _boxes = 0;
            _alerter.tones = 0;
            EventLog.write("START " + RideGuardField.date(now));
            _dirty = true;
        }
        if (lc == Rg.LC_ENDED) { EventLog.write(endLine()); _dirty = true; }

        if (_life.isOpen()) {
            var ev = _dog.step(now, speed, info.elapsedDistance, _timer, info.currentHeartRate, info.currentPower);
            for (var i = 0; i < ev.size(); i++) {
                var rule = ev[i][0];
                var kind = ev[i][1];
                if (kind == Rg.EV_RAISE || kind == Rg.EV_REPEAT) {
                    _alerter.tone(now, _cfg.toneOn);
                    alertBox(rule);
                    if (kind == Rg.EV_RAISE) {
                        _alerts++;
                        _lastRule = rule;
                        _lastAlertAt = now;
                        EventLog.write(Texts.ruleTag(rule) + "+");
                        _dirty = true;
                    }
                } else {
                    EventLog.write(Texts.ruleTag(rule) + "-");
                }
            }
        }
        if (_dirty || (_life.isOpen() && now - _lastSave >= 60)) {
            StateStore.save(RideGuardField.record(_life, _dog, _alerts, _lastRule, _lastAlertAt));
            _lastSave = now;
            _dirty = false;
        }
    }

    function onTimerReset() as Void {
        if (_life.onReset(Time.now().value()) == Rg.LC_ENDED) {
            EventLog.write(endLine());
            StateStore.save(RideGuardField.record(_life, _dog, _alerts, _lastRule, _lastAlertAt));
        }
    }

    // Ask the Edge for the red pop-up box. showAlert is a method of the data field, so it is called
    // here, the way an earlier test build called it when the box was seen on real rides. The Edge may still
    // suppress the box in some timer states without saying so.
    hidden function alertBox(rule as Number) as Void {
        try {
            WatchUi.DataField.showAlert(new RgAlertView(rule));
            _boxes++;
        } catch (e) {
            if (!_boxFailed) { EventLog.write("BOX-ERR " + e.getErrorMessage()); }
            _boxFailed = true;
        }
    }

    // [alerts raised, tones played, alert boxes requested] for the current ride.
    function stats() as Array<Number> { return [_alerts, _alerter.tones, _boxes]; }

    hidden function endLine() as String {
        return "END alerts=" + _alerts + " tones=" + _alerter.tones + " boxes=" + _boxes;
    }

    static function date(now as Number) as String {
        var d = Gregorian.info(new Time.Moment(now), Time.FORMAT_SHORT);
        return (d.year as Number) + "-" + (d.month as Number).format("%02d") + "-" + (d.day as Number).format("%02d");
    }

    // What the rider sees: [alertRule, statusText, dotColour, dotHollow, secondLine].
    function view(now as Number) as Array {
        if (_fault) { return [0, "RG error", Graphics.COLOR_YELLOW, false, "Not watching: see log"]; }
        var open = _life.isOpen();
        var rule = open ? _dog.activeRule() : 0;
        var blind = open && _blindRun > 10;
        var sub = Texts.hint(_life.state, _timer, blind);
        if (_life.state == Rg.ST_STANDBY) {
            sub = _cfg.helpOn ? Texts.helpPage((now / 4) % 5) : "";
        } else if (_alerts > 0 && (sub.length() == 0 || _life.state == Rg.ST_ENDED)) {
            var t = Gregorian.info(new Time.Moment(_lastAlertAt), Time.FORMAT_SHORT);
            sub = Texts.alertsLine(_alerts, _lastRule, t.hour as Number, t.min as Number);
        }
        return [rule, Texts.status(_life.state, _timer, blind, _timerMs),
                Texts.statusColor(_life.state, _timer, blind, rule), Texts.dotHollow(_life.state), sub];
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var v = view(Time.now().value());
        if (v[0] != 0) {
            RgDraw.alert(dc, v[0] as Number);
            return;
        }
        var bg = getBackgroundColor();
        var fg = (bg == Graphics.COLOR_BLACK) ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        RgDraw.status(dc, bg, fg, v[2] as Number, v[3] as Boolean, v[1] as String, v[4] as String);
    }
}
