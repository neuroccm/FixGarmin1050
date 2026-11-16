import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

// Simulator-only: draws every RideGuard state with the real drawing code, each in a tile the size of
// a real Edge 1050 data field. Use the "1 Field" layout. The page changes every 6 seconds:
// half-width fields (239x158), then full-width fields (480x158).
class GalleryApp extends Application.AppBase {
    function initialize() { AppBase.initialize(); }
    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new GalleryField()];
    }
}

class GalleryField extends WatchUi.DataField {
    function initialize() { DataField.initialize(); }

    // One tile: [alertRule, statusText, dotColour, dotHollow, secondLine], as RideGuardField.view() returns it.
    hidden function tile(dc as Graphics.Dc, x as Number, y as Number, w as Number, h as Number, v as Array) as Void {
        var ref = Graphics.createBufferedBitmap({:width => w, :height => h});
        var bmp = ref.get() as Graphics.BufferedBitmap;
        var t = bmp.getDc();
        if (v[0] != 0) {
            RgDraw.alert(t, v[0] as Number);
        } else {
            RgDraw.status(t, Graphics.COLOR_WHITE, Graphics.COLOR_BLACK, v[2] as Number, v[3] as Boolean, v[1] as String, v[4] as String);
        }
        dc.drawBitmap(x, y, bmp);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(x, y, w, h);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var on = Rg.TIMER_ON;
        var w = Rg.ST_WATCHING;
        var views = [
            [0, Texts.status(Rg.ST_STANDBY, Rg.TIMER_OFF, false, null), Texts.statusColor(Rg.ST_STANDBY, Rg.TIMER_OFF, false, 0), true, Texts.helpPage(0)],
            [0, Texts.status(w, on, false, 4320000), Texts.statusColor(w, on, false, 0), false, ""],
            [0, Texts.status(w, Rg.TIMER_PAUSED, false, 0), Texts.statusColor(w, Rg.TIMER_PAUSED, false, 0), false, Texts.hint(w, Rg.TIMER_PAUSED, false)],
            [0, Texts.status(w, Rg.TIMER_STOPPED, false, 0), Texts.statusColor(w, Rg.TIMER_STOPPED, false, 0), false, Texts.hint(w, Rg.TIMER_STOPPED, false)],
            [0, Texts.status(w, Rg.TIMER_OFF, false, 0), Texts.statusColor(w, Rg.TIMER_OFF, false, 0), false, Texts.hint(w, Rg.TIMER_OFF, false)],
            [0, Texts.status(w, on, true, 0), Texts.statusColor(w, on, true, 0), false, Texts.hint(w, on, true)],
            [Rg.R_MOVING, "", 0, false, ""],
            [Rg.R_FROZEN, "", 0, false, ""],
            [0, Texts.status(w, on, false, 4320000), Texts.statusColor(w, on, false, 0), false, Texts.alertsLine(1, Rg.R_MOVING, 10, 31)],
            [0, Texts.status(Rg.ST_ENDED, Rg.TIMER_OFF, false, 0), Texts.statusColor(Rg.ST_ENDED, Rg.TIMER_OFF, false, 0), false, Texts.hint(Rg.ST_ENDED, Rg.TIMER_OFF, false)]
        ];
        if ((Time.now().value() / 6) % 2 == 0) {
            for (var i = 0; i < 10; i++) { tile(dc, (i % 2) * 241, (i / 2) * 160, 239, 158, views[i] as Array); }
        } else {
            var wide = [0, 1, 3, 6, 8];
            for (var i = 0; i < 5; i++) { tile(dc, 0, i * 160, 480, 158, views[wide[i]] as Array); }
        }
    }
}
