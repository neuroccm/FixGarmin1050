import Toybox.Lang;

// R3 recording watchdog. Pure: no Toybox side effects; call step() once per second.
class Watchdog {
    var sawHr as Boolean = false;
    var sawPower as Boolean = false;

    hidden var _s as Float;
    hidden var _t as Array<Number>;          // index by rule: [_, T1, T2, T3, T3]
    hidden var _r as Number;
    hidden var _on as Array<Boolean>;        // index by rule
    hidden var _run as Array<Number>;        // consecutive qualifying seconds, by rule
    hidden var _active as Array<Boolean>;
    hidden var _lastAlert as Array<Number>;
    hidden var _repeats as Array<Number>;    // repeats since the raise, by rule
    hidden var _lastDist as Float or Null = null;

    function initialize(speedMs as Float, t1 as Number, t2 as Number, t3 as Number, repeatS as Number, on as Array<Boolean>) {
        _s = speedMs;
        _t = [0, t1, t2, t3, t3];
        _r = repeatS;
        _on = [false, on[0], on[1], on[2], on[2]];
        _run = [0, 0, 0, 0, 0];
        _active = [false, false, false, false, false];
        _lastAlert = [0, 0, 0, 0, 0];
        _repeats = [0, 0, 0, 0, 0];
    }

    function resetRide() as Void {
        sawHr = false;
        sawPower = false;
        _lastDist = null;
        for (var i = 1; i <= 4; i++) { _run[i] = 0; _active[i] = false; }
    }

    function step(now as Number, speed as Float or Null, dist as Float or Null, timer as Number,
                  hr as Number or Null, power as Number or Null) as Array<Array<Number>> {
        var fast = speed != null && speed > _s;
        var on = timer == Rg.TIMER_ON;
        if (hr != null) { sawHr = true; }
        if (power != null) { sawPower = true; }
        var frozen = on && fast && dist != null && _lastDist != null && dist == _lastDist;
        if (dist != null) { _lastDist = dist; }

        // A sensor alert starts only with the timer running. Once raised it holds through pauses and
        // stops until the sensor is back, so a pause can neither clear it nor start its beeps again.
        var hrLost = sawHr && hr == null && (on || _active[Rg.R_HR]);
        var powerLost = sawPower && power == null && (on || _active[Rg.R_POWER]);
        var q = [false, fast && !on, frozen, hrLost, powerLost];
        var events = [] as Array<Array<Number>>;
        for (var i = 1; i <= 4; i++) {
            _run[i] = (q[i] && _on[i]) ? _run[i] + 1 : 0;
            var cond = _run[i] > _t[i];
            if (cond && !_active[i]) {
                _active[i] = true;
                _lastAlert[i] = now;
                _repeats[i] = 0;
                events.add([i, Rg.EV_RAISE]);
            } else if (cond && now - _lastAlert[i] >= _r && (i < Rg.R_HR || (on && _repeats[i] < Rg.SENSOR_BEEPS - 1))) {
                // Timer and distance alerts repeat for as long as they last: the ride isn't being
                // recorded. A lost sensor may be beyond fixing on the road, so it stops beeping after
                // Rg.SENSOR_BEEPS, and it never beeps while the timer is paused or stopped.
                _lastAlert[i] = now;
                _repeats[i]++;
                events.add([i, Rg.EV_REPEAT]);
            } else if (!cond && _active[i]) {
                _active[i] = false;
                events.add([i, Rg.EV_CLEAR]);
            }
        }
        return events;
    }

    function activeRule() as Number {
        for (var i = 1; i <= 4; i++) {
            if (_active[i]) { return i; }
        }
        return 0;
    }
}
