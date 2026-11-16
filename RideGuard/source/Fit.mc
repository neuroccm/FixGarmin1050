import Toybox.Graphics;
import Toybox.Lang;

// Picks fonts by measuring, so text fits any field size (Edge 1050: 239-480 px wide, 158-800 px tall).
module Fit {
    // Largest first.
    function fonts() as Array<Graphics.FontDefinition> {
        return [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY];
    }

    // Index (into fonts()) of the largest font, starting at `first`, in which `text` fits maxW x maxH.
    // Returns the smallest font's index when nothing fits. `text` may contain line breaks.
    function index(dc as Graphics.Dc, text as String, maxW as Number, maxH as Number, first as Number) as Number {
        var f = fonts();
        for (var i = first; i < f.size(); i++) {
            var d = dc.getTextDimensions(text, f[i]);
            if (d[0] <= maxW && d[1] <= maxH) { return i; }
        }
        return f.size() - 1;
    }

    function font(dc as Graphics.Dc, text as String, maxW as Number, maxH as Number, first as Number) as Graphics.FontDefinition {
        return fonts()[index(dc, text, maxW, maxH, first)];
    }
}
