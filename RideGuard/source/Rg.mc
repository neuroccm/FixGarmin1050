import Toybox.Lang;

module Rg {
    const TIMER_OFF = 0;
    const TIMER_STOPPED = 1;
    const TIMER_PAUSED = 2;
    const TIMER_ON = 3;

    const R_MOVING = 1;
    const R_FROZEN = 2;
    const R_HR = 3;
    const R_POWER = 4;

    const EV_RAISE = 1;
    const EV_REPEAT = 2;
    const EV_CLEAR = 3;

    const ST_STANDBY = 0;
    const ST_WATCHING = 1;
    const ST_ENDED = 2;

    // A lost sensor beeps this many times (raise + repeats), then stays silent until it returns.
    const SENSOR_BEEPS = 3;

    const LC_NONE = 0;
    const LC_STARTED = 1;
    const LC_ENDED = 2;
}
