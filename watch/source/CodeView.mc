import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Type the 6-digit watch code with the buttons: UP / DOWN change the digit,
// START keeps it and moves on, BACK goes back a digit (or cancels).
class CodeView extends WatchUi.View {
    var digits as Array<Number> = [0, 0, 0, 0, 0, 0];
    var pos as Number = 0;

    function initialize() { View.initialize(); }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth(), h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.drawText(w / 2, h * 0.16, Graphics.FONT_SMALL, "Watch code", Graphics.TEXT_JUSTIFY_CENTER);
        var font = Graphics.FONT_NUMBER_MILD;
        var cw = w / 9;
        var x0 = w / 2 - cw * 3 + cw / 2;
        for (var i = 0; i < 6; i++) {
            var x = x0 + i * cw;
            if (i == pos) {
                dc.setColor(0x3D7BFF, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(x - cw / 2 + 2, h * 0.38, cw - 4, h * 0.22, 6);
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(i < pos ? Graphics.COLOR_WHITE : 0x777777, Graphics.COLOR_TRANSPARENT);
            }
            dc.drawText(x, h * 0.40, font, i <= pos ? digits[i].format("%d") : "_", Graphics.TEXT_JUSTIFY_CENTER);
        }
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.68, Graphics.FONT_XTINY, "UP / DOWN change", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 0.76, Graphics.FONT_XTINY, "START next · BACK back", Graphics.TEXT_JUSTIFY_CENTER);
    }

    function code() as String {
        var s = "";
        for (var i = 0; i < 6; i++) { s += digits[i].format("%d"); }
        return s;
    }
}

class CodeDelegate extends WatchUi.BehaviorDelegate {
    var view as CodeView;
    var pair as PairView;
    function initialize(v as CodeView, p as PairView) { BehaviorDelegate.initialize(); view = v; pair = p; }

    function onNextPage() as Boolean { view.digits[view.pos] = (view.digits[view.pos] + 9) % 10; WatchUi.requestUpdate(); return true; }
    function onPreviousPage() as Boolean { view.digits[view.pos] = (view.digits[view.pos] + 1) % 10; WatchUi.requestUpdate(); return true; }

    function onSelect() as Boolean {
        if (view.pos < 5) { view.pos++; WatchUi.requestUpdate(); return true; }
        var c = view.code();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        pair.lookUp(c);
        return true;
    }

    function onBack() as Boolean {
        if (view.pos > 0) { view.pos--; WatchUi.requestUpdate(); return true; }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
