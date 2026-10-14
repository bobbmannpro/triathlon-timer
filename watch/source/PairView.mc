import Toybox.Application;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Pair with a race: START → enter the 6-digit code → the watch looks it up.
// Once paired, START again begins tracking.
class PairView extends WatchUi.View {
    var status as String = "";
    var busy as Boolean = false;
    var pending as String = "";
    var sender as ChSender;

    function initialize() { View.initialize(); sender = new ChSender(); sender.onChange = method(:changed); }
    function changed() as Void { WatchUi.requestUpdate(); }
    // runs finished out of the phone's range go as soon as this screen is up
    function onShow() as Void { sender.send(); }

    function isChallenge() as Boolean {
        var m = Application.Storage.getValue("mode");
        return m != null && m.toString().equals("challenge");
    }
    function paired() as Boolean {
        if (isChallenge()) { return Application.Storage.getValue("chCode") != null && Application.Storage.getValue("chTok") != null && Application.Storage.getValue("chUid") != null; }
        // the code is needed too: it is how the watch reads the race's times
        return Application.Storage.getValue("raceCode") != null && Application.Storage.getValue("athIdx") != null
            && Application.Storage.getValue("token") != null;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth(), h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.drawText(w / 2, h * 0.14, Graphics.FONT_SMALL, "TIMEATHON", Graphics.TEXT_JUSTIFY_CENTER);
        if (paired() && isChallenge()) {
            var cn = Application.Storage.getValue("chName");
            dc.drawText(w / 2, h * 0.32, Graphics.FONT_MEDIUM, cn != null ? cn.toString() : "Athlete", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(0xD49A2E, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.47, Graphics.FONT_SMALL, "Challenge " + Application.Storage.getValue("chCode").toString(), Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(0x2FC27A, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.62, Graphics.FONT_SMALL, "START = run", Graphics.TEXT_JUSTIFY_CENTER);
            var np = sender.pending().size();
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.75, Graphics.FONT_XTINY, np > 0 ? np.format("%d") + " run(s) to send" : "Hold UP for a new code", Graphics.TEXT_JUSTIFY_CENTER);
        } else if (paired()) {
            var name = Application.Storage.getValue("athleteName");
            var code = Application.Storage.getValue("raceCode");
            dc.drawText(w / 2, h * 0.32, Graphics.FONT_MEDIUM, name != null ? name.toString() : "Athlete", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.47, Graphics.FONT_SMALL, "Race " + code.toString(), Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(0x2FC27A, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.62, Graphics.FONT_SMALL, "START = begin", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.75, Graphics.FONT_XTINY, "Hold UP for a new code", Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.drawText(w / 2, h * 0.36, Graphics.FONT_SMALL, "Press START", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(w / 2, h * 0.48, Graphics.FONT_SMALL, "to enter the", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(w / 2, h * 0.60, Graphics.FONT_SMALL, "6-digit code", Graphics.TEXT_JUSTIFY_CENTER);
        }
        if (!status.equals("")) {
            dc.setColor(busy ? 0xAAAAAA : 0xFF5A5A, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.86, Graphics.FONT_XTINY, status, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // Look the code up: watchTokens/{CODE} → { raceCode, athIdx, athleteName }
    // for a race, or { challenge, uid, athleteName, unit } for a challenge.
    function lookUp(code as String) as Void {
        busy = true; pending = code; status = "Checking " + code + "...";
        WatchUi.requestUpdate();
        Communications.makeWebRequest(Tm.RTDB + "/watchTokens/" + code + ".json", null,
            { :method => Communications.HTTP_REQUEST_METHOD_GET, :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON },
            method(:onToken));
    }

    function onToken(code as Number, data as Dictionary or String or Null) as Void {
        busy = false;
        if (code == 200 && data instanceof Dictionary && data.get("challenge") != null && data.get("uid") != null) {
            Application.Storage.setValue("mode", "challenge");
            Application.Storage.setValue("chCode", data.get("challenge").toString());
            Application.Storage.setValue("chUid", data.get("uid").toString());
            Application.Storage.setValue("chTok", pending);
            var cnm = data.get("athleteName");
            Application.Storage.setValue("chName", cnm != null ? cnm.toString() : "Athlete");
            var u = data.get("unit");
            Application.Storage.setValue("chUnit", u != null ? u.toString() : "mi");
            status = "";
        } else if (code == 200 && data instanceof Dictionary && data.get("raceCode") != null && data.get("athIdx") != null) {
            Application.Storage.setValue("mode", "race");
            Application.Storage.setValue("raceCode", data.get("raceCode").toString());
            Application.Storage.setValue("athIdx", data.get("athIdx"));
            var nm = data.get("athleteName");
            Application.Storage.setValue("athleteName", nm != null ? nm.toString() : "Athlete");
            Application.Storage.setValue("leg", 0);
            Application.Storage.setValue("token", pending);
            status = "";
        } else if (code == 200) {
            status = "Code not found";
        } else if (code < 0) {
            status = "No phone connection (" + code + ")";
        } else {
            status = "Error " + code;
        }
        WatchUi.requestUpdate();
    }
}

class PairDelegate extends WatchUi.BehaviorDelegate {
    var view as PairView;
    function initialize(v as PairView) { BehaviorDelegate.initialize(); view = v; }

    function onSelect() as Boolean {
        if (view.busy) { return true; }
        if (view.paired() && view.isChallenge()) {
            var c = new ChallengeView();
            WatchUi.switchToView(c, new ChallengeDelegate(c), WatchUi.SLIDE_LEFT);
        } else if (view.paired()) {
            var t = new TrackView();
            WatchUi.switchToView(t, new TrackDelegate(t), WatchUi.SLIDE_LEFT);
        } else {
            var cv = new CodeView();
            WatchUi.pushView(cv, new CodeDelegate(cv, view), WatchUi.SLIDE_UP);
        }
        return true;
    }

    // Hold UP: forget this pairing and type a new code.
    function onMenu() as Boolean {
        Application.Storage.deleteValue("raceCode");
        Application.Storage.deleteValue("athIdx");
        Application.Storage.deleteValue("athleteName");
        Application.Storage.deleteValue("token");
        Application.Storage.deleteValue("mode");
        Application.Storage.deleteValue("chCode");
        Application.Storage.deleteValue("chUid");
        Application.Storage.deleteValue("chTok");
        var cv = new CodeView();
        WatchUi.pushView(cv, new CodeDelegate(cv, view), WatchUi.SLIDE_UP);
        return true;
    }
}
