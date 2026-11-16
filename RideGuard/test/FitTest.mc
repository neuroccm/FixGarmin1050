import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Test;

// Edge 1050 data fields are 239-480 px wide and 158-800 px tall.

(:test)
function testFitPicksLargestFontThatFits(logger as Test.Logger) as Boolean {
    var dc = TestUtil.dc(480, 158);
    var roomy = Fit.font(dc, "RG OK", 460, 150, 0);
    var tight = Fit.font(dc, "RG timer stopped", 200, 150, 0);
    return TestUtil.check(logger, roomy == Graphics.FONT_LARGE, "plenty of room must give the largest font")
        && TestUtil.check(logger, dc.getTextWidthInPixels("RG timer stopped", tight) <= 200, "the chosen font must fit the width")
        && TestUtil.check(logger, Fit.font(dc, "RG timer stopped", 5, 5, 0) == Graphics.FONT_XTINY, "nothing fits: fall back to the smallest font")
        && TestUtil.check(logger, Fit.font(dc, "RG OK", 460, 150, 3) == Graphics.FONT_TINY, "search starts at the given size");
}

(:test)
function testFitRespectsHeightOfMultiLineText(logger as Test.Logger) as Boolean {
    var dc = TestUtil.dc(480, 158);
    var f = Fit.font(dc, "one\ntwo\nthree", 460, 70, 0);
    return TestUtil.check(logger, dc.getTextDimensions("one\ntwo\nthree", f)[1] <= 70, "three lines must fit the height");
}

function alertLayoutOk(logger as Test.Logger, rule as Number, w as Number, h as Number) as Boolean {
    var dc = TestUtil.dc(w, h);
    var l = RgDraw.alertLayout(dc, rule, w, h);           // [titleText, titleFont, actionText, actionFont, titleY, actionY]
    var td = dc.getTextDimensions(l[0] as String, l[1] as Graphics.FontDefinition);
    var ad = dc.getTextDimensions(l[2] as String, l[3] as Graphics.FontDefinition);
    var ty = l[4] as Number;
    var ay = l[5] as Number;
    var where = " (rule " + rule + " in " + w + "x" + h + ")";
    if (!TestUtil.check(logger, td[0] <= w && ad[0] <= w, "alert text wider than the field" + where)) { return false; }
    if (!TestUtil.check(logger, ty - td[1] / 2 >= 0 && ay + ad[1] / 2 <= h, "alert text outside the field" + where)) { return false; }
    return TestUtil.check(logger, ty + td[1] / 2 <= ay - ad[1] / 2, "title and action overlap" + where);
}

(:test)
function testAlertLayoutFitsEveryFieldSize(logger as Test.Logger) as Boolean {
    var sizes = [[239, 158], [480, 158], [480, 316], [480, 800]];
    var failures = [] as Array<Number>;
    for (var s = 0; s < sizes.size(); s++) {
        for (var rule = Rg.R_MOVING; rule <= Rg.R_POWER; rule++) {
            if (!alertLayoutOk(logger, rule, sizes[s][0], sizes[s][1])) { failures.add(rule); }
        }
    }
    return failures.size() == 0;
}

(:test)
function testAlertTitleWrapsToStayLegibleInHalfWidthField(logger as Test.Logger) as Boolean {
    var dc = TestUtil.dc(239, 158);
    var l = RgDraw.alertLayout(dc, Rg.R_MOVING, 239, 158);
    return TestUtil.check(logger, (l[0] as String).find("\n") != null, "TIMER NOT RUNNING must wrap in a half-width field")
        && TestUtil.check(logger, l[1] != Graphics.FONT_XTINY, "the wrapped title must be larger than the smallest font");
}

// One status line + second line in one field size: everything inside the field, nothing overlapping.
function statusLayoutOk(logger as Test.Logger, text as String, sub as String, w as Number, h as Number) as Boolean {
    var dc = TestUtil.dc(w, h);
    var l = RgDraw.statusLayout(dc, text, sub, w, h);     // [font1, textCenterX, y1, dotX, dotR, font2, y2, showSub]
    var d1 = dc.getTextDimensions(text, l[0] as Graphics.FontDefinition);
    var where = " (" + text + " / " + sub.substring(0, 12) + " in " + w + "x" + h + ")";
    var left = (l[1] as Number) - d1[0] / 2;
    var y1 = l[2] as Number;
    if (!TestUtil.check(logger, (l[3] as Number) - (l[4] as Number) >= 0 && left + d1[0] <= w, "status line wider than the field" + where)) { return false; }
    if (!TestUtil.check(logger, (l[3] as Number) + (l[4] as Number) <= left, "dot overlaps the text" + where)) { return false; }
    if (!TestUtil.check(logger, y1 - d1[1] / 2 >= 0, "status line above the field" + where)) { return false; }
    if (sub.length() == 0) {
        return TestUtil.check(logger, y1 + d1[1] / 2 <= h, "status line below the field" + where);
    }
    var d2 = dc.getTextDimensions(sub, l[5] as Graphics.FontDefinition);
    var y2 = l[6] as Number;
    if (!TestUtil.check(logger, l[7] == true, "second line dropped" + where)) { return false; }
    if (!TestUtil.check(logger, d2[0] <= w, "second line wider than the field" + where)) { return false; }
    if (!TestUtil.check(logger, y1 + d1[1] / 2 <= y2 - d2[1] / 2, "lines overlap" + where)) { return false; }
    return TestUtil.check(logger, y2 + d2[1] / 2 <= h, "second line below the field" + where);
}

(:test)
function testStatusLayoutFitsEveryFieldSize(logger as Test.Logger) as Boolean {
    var sizes = [[239, 158], [480, 158], [480, 316], [480, 800]];
    var texts = ["RG ready", "RG OK 12:34", "RG paused", "RG timer stopped", "RG timer off", "RG no speed", "RG ride ended", "RG error"];
    var subs = ["", "Resumes when you move", "No GPS or speed sensor", "12 alerts, last: distance 12:34", Texts.helpPage(0), Texts.helpPage(1), Texts.helpPage(2)];
    var failures = [] as Array<String>;
    for (var s = 0; s < sizes.size(); s++) {
        for (var t = 0; t < texts.size(); t++) {
            for (var u = 0; u < subs.size(); u++) {
                if (!statusLayoutOk(logger, texts[t], subs[u], sizes[s][0], sizes[s][1])) { failures.add(texts[t]); }
            }
        }
    }
    return failures.size() == 0;
}

(:test)
function testStatusUsesTheRoomItHas(logger as Test.Logger) as Boolean {
    var dc = TestUtil.dc(480, 158);
    var l = RgDraw.statusLayout(dc, "RG OK 1:12", "", 480, 158);
    return TestUtil.check(logger, l[0] == Graphics.FONT_LARGE, "a full-width field must show the status in the largest font")
        && TestUtil.check(logger, (l[4] as Number) >= 10, "the dot must be big enough to see at a glance");
}
