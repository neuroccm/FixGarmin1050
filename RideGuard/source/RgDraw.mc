import Toybox.Graphics;
import Toybox.Lang;

// Layout and drawing shared by the data field and the alert box. Layouts are computed from measured
// text, so the same code serves a half-width field and a full-screen one.
module RgDraw {
    const CENTER = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

    function pad(w as Number) as Number { return (w / 30 < 6) ? 6 : w / 30; }

    // Title and action for an active rule.
    // Returns [titleText, titleFont, actionText, actionFont, titleCenterY, actionCenterY].
    function alertLayout(dc as Graphics.Dc, rule as Number, w as Number, h as Number) as Array {
        var maxW = w - 2 * pad(w);
        var gap = h / 20;
        var titleH = (h - gap) * 6 / 10;
        // One line when it is readable; otherwise two lines in a larger font.
        var one = Texts.title(rule);
        var two = Texts.titleWrapped(rule);
        var i1 = Fit.index(dc, one, maxW, titleH, 0);
        var i2 = Fit.index(dc, two, maxW, titleH, 0);
        var title = (i2 < i1) ? two : one;
        var ti = (i2 < i1) ? i2 : i1;
        var fonts = Fit.fonts();
        var td = dc.getTextDimensions(title, fonts[ti]);
        var action = Texts.action(rule);
        var first = (ti + 1 < fonts.size()) ? ti + 1 : ti;         // the action is never larger than the title
        var ai = Fit.index(dc, action, maxW, h - gap - td[1], first);
        var ad = dc.getTextDimensions(action, fonts[ai]);
        var top = (h - (td[1] + gap + ad[1])) / 2;
        if (top < 0) { top = 0; }
        return [title, fonts[ti], action, fonts[ai], top + td[1] / 2, top + td[1] + gap + ad[1] / 2];
    }

    // White on red: the look of every alert, in the field and in the pop-up box.
    function alert(dc as Graphics.Dc, rule as Number) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_RED);
        dc.clear();
        var l = alertLayout(dc, rule, w, h);
        dc.drawText(w / 2, l[4] as Number, l[1] as Graphics.FontDefinition, l[0] as String, CENTER);
        dc.drawText(w / 2, l[5] as Number, l[3] as Graphics.FontDefinition, l[2] as String, CENTER);
    }

    // Status line (dot + text) with an optional second line beneath it.
    // Returns [font1, textCenterX, y1, dotX, dotR, font2, y2, showSub]; the dot is centred on y1.
    function statusLayout(dc as Graphics.Dc, text as String, sub as String, w as Number, h as Number) as Array {
        var p = pad(w);
        var r = h / 11;                                   // a dot you can read at a glance
        if (r < 10) { r = 10; }
        if (r > 18) { r = 18; }
        var gap = r;
        var fonts = Fit.fonts();
        var hasSub = sub.length() > 0;
        var vgap = h / 30;
        var i1 = Fit.index(dc, text, w - 2 * p - 2 * r - gap, hasSub ? h * 4 / 10 : h, 0);
        var d1 = dc.getTextDimensions(text, fonts[i1]);
        var i2 = fonts.size() - 1;
        var d2 = [0, 0];
        if (hasSub) {
            // The second line is at least one size smaller, and never larger than FONT_SMALL.
            i2 = Fit.index(dc, sub, w - 2 * p, h - d1[1] - vgap, (i1 + 1 > 2) ? i1 + 1 : 2);
            d2 = dc.getTextDimensions(sub, fonts[i2]);
            hasSub = d2[0] <= w && d1[1] + vgap + d2[1] <= h;     // drop it rather than overlap
        }
        var block = hasSub ? d1[1] + vgap + d2[1] : d1[1];
        var top = (h - block) / 2;
        var x0 = (w - (2 * r + gap + d1[0])) / 2;
        if (x0 < 0) { x0 = 0; }
        return [fonts[i1], x0 + 2 * r + gap + d1[0] / 2, top + d1[1] / 2, x0 + r, r,
                fonts[i2], top + d1[1] + vgap + d2[1] / 2, hasSub];
    }

    function status(dc as Graphics.Dc, bg as Number, fg as Number, dotColor as Number, hollow as Boolean, text as String, sub as String) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(fg, bg);
        dc.clear();
        var l = statusLayout(dc, text, sub, w, h);
        var r = l[4] as Number;
        dc.setColor(dotColor, Graphics.COLOR_TRANSPARENT);
        if (hollow) {
            dc.setPenWidth((r / 4 < 2) ? 2 : r / 4);
            dc.drawCircle(l[3] as Number, l[2] as Number, r - 1);
            dc.setPenWidth(1);
        } else {
            dc.fillCircle(l[3] as Number, l[2] as Number, r);
        }
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(l[1] as Number, l[2] as Number, l[0] as Graphics.FontDefinition, text, CENTER);
        if (l[7] == true) {
            dc.drawText(w / 2, l[6] as Number, l[5] as Graphics.FontDefinition, sub, CENTER);
        }
    }
}
