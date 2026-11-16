import Toybox.Lang;

// Drives a default Watchdog over packed replay segments for seconds [fromS, toS).
module Replay {
    function firstAndCount(data as ByteArray, rule as Number, fromS as Number, toS as Number) as Array<Number> {
        var speeds = [0.0f, 2.5f, 5.0f];
        var w = TestUtil.dog();
        var t = 0;
        var dist = 0.0f;
        var first = -1;
        var count = 0;
        for (var i = 0; i + 2 < data.size() && t < toS; i += 3) {
            var secs = data[i] | (data[i + 1] << 8);
            var f = data[i + 2];
            var speed = speeds[f & 3];
            var timer = (f >> 2) & 3;
            var step = ((f >> 4) & 1) == 1 ? 5.0f : 0.0f;
            var k = 0;
            if (t + secs <= fromS) { t += secs; dist += step * secs; continue; }   // segment wholly before the window
            if (t < fromS) { k = fromS - t; dist += step * k; t = fromS; }
            while (k < secs && t < toS) {
                dist += step;
                var ev = w.step(t, speed, dist, timer, null, null);
                for (var e = 0; e < ev.size(); e++) {
                    if (ev[e][0] == rule && (ev[e][1] == Rg.EV_RAISE || ev[e][1] == Rg.EV_REPEAT)) {
                        if (first < 0) { first = t; }
                        count++;
                    }
                }
                k++;
                t++;
            }
        }
        return [first, count];
    }

    // Rides opened by a fresh Lifecycle over a whole packed ride.
    function lifeStarts(data as ByteArray) as Number {
        var speeds = [0.0f, 2.5f, 5.0f];
        var l = new Lifecycle();
        var t = 0;
        var starts = 0;
        for (var i = 0; i + 2 < data.size(); i += 3) {
            var secs = data[i] | (data[i + 1] << 8);
            var f = data[i + 2];
            var speed = speeds[f & 3];
            var timer = (f >> 2) & 3;
            for (var k = 0; k < secs; k++) {
                if (l.step(t, speed, timer) == Rg.LC_STARTED) { starts++; }
                t++;
            }
        }
        return starts;
    }

    // The same packed ride through the whole field (lifecycle, watchdog, alert delivery).
    // Returns [first second with an alert on record, tones played]; every raise and repeat beeps.
    function fieldFirstAndTones(data as ByteArray, toS as Number) as Array<Number> {
        var speeds = [0.0f, 2.5f, 5.0f];
        var f = TestUtil.field();
        var t = 0;
        var dist = 0.0f;
        var first = -1;
        for (var i = 0; i + 2 < data.size() && t < toS; i += 3) {
            var secs = data[i] | (data[i + 1] << 8);
            var fl = data[i + 2];
            var speed = speeds[fl & 3];
            var timer = (fl >> 2) & 3;
            var step = ((fl >> 4) & 1) == 1 ? 5.0f : 0.0f;
            for (var k = 0; k < secs && t < toS; k++) {
                dist += step;
                f.tick(TestUtil.info(timer, speed, dist, t * 1000), 100000 + t);
                if (first < 0 && f.stats()[0] > 0) { first = t; }
                t++;
            }
        }
        return [first, f.stats()[1]];
    }
}
