import Toybox.Lang;

// Ride lifecycle: STANDBY -> WATCHING -> ENDED (60 s) -> STANDBY. Pure; step() once per second.
class Lifecycle {
    var state as Number = Rg.ST_STANDBY;
    var rideStart as Number or Null = null;
    var timerSeen as Boolean = false;

    hidden var _moveRun as Number = 0;
    hidden var _stillRun as Number = 0;
    hidden var _endedAt as Number = 0;
    hidden var _restored as Boolean = false;

    function initialize() {}

    function isOpen() as Boolean { return state == Rg.ST_WATCHING; }

    function restore(rec as Dictionary or Null) as Void {
        if (rec != null && rec.get("rideOpen") == true && rec.get("rideStart") != null) {
            state = Rg.ST_WATCHING;
            rideStart = rec.get("rideStart") as Number;
            timerSeen = rec.get("timerSeen") == true;
            _restored = true;
        }
    }

    hidden function open(now as Number, byTimer as Boolean) as Number {
        state = Rg.ST_WATCHING;
        rideStart = now;
        timerSeen = byTimer;
        _moveRun = 0;
        _stillRun = 0;
        return Rg.LC_STARTED;
    }

    hidden function end(now as Number) as Number {
        state = Rg.ST_ENDED;
        _endedAt = now;
        return Rg.LC_ENDED;
    }

    function onReset(now as Number) as Number {
        return state == Rg.ST_WATCHING ? end(now) : Rg.LC_NONE;
    }

    function step(now as Number, speed as Float or Null, timer as Number) as Number {
        var moving = speed != null && speed > 2.0f;
        var still = speed == null || speed < 1.0f;
        _moveRun = moving ? _moveRun + 1 : 0;
        var justRestored = _restored;
        _restored = false;

        if (state == Rg.ST_WATCHING) {
            if (timer != Rg.TIMER_OFF) { timerSeen = true; }
            // The timer is back to OFF: saved or discarded. A ride restored after a reload also ends
            // when the timer is OFF and nothing is moving (it was closed while the field was unloaded).
            if (timer == Rg.TIMER_OFF && (timerSeen || (justRestored && !moving))) { return end(now); }
            _stillRun = (!timerSeen && timer == Rg.TIMER_OFF && still) ? _stillRun + 1 : 0;
            if (_stillRun >= 1800) { return end(now); }
            return Rg.LC_NONE;
        }
        // STANDBY or ENDED
        if (timer != Rg.TIMER_OFF) { return open(now, true); }
        if (state == Rg.ST_ENDED) {
            // "ride ended" stays for 60 s. Rolling on after a save must not open a new ride during it.
            if (now - _endedAt < 60) { return Rg.LC_NONE; }
            state = Rg.ST_STANDBY;
            rideStart = null;
            timerSeen = false;
        }
        if (_moveRun >= 5) { return open(now, false); }
        return Rg.LC_NONE;
    }
}
