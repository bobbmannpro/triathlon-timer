import Toybox.Application;
import Toybox.Attention;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Racing.
//   Sends:  liveRaces/{race}/athletes/{i}/gps  ← { lat, lng, distanceMi, accuracy, seg, onBike, src:"watch", tok, t }
//           .../gps/watchLap                   ← { seg, n, ago, at: server time }  (one per LAP press;
//                                                ago = ms between the press and sending it)
//   Reads:  watchTokens/{code}/race            ← { started, startAt, splits[5], finished }  (server times,
//                                                kept up to date by the host's screen)
// The times shown are the race's: from when the host sent this athlete off,
// and the leg is whatever the race says — the watch only guesses ahead of
// the race for a few seconds after a LAP press.
class TrackView extends WatchUi.View {
    var raceCode as String;
    var athIdx;
    var token;
    // what the race says
    var started as Boolean = false;
    var startAt = null;               // server ms
    var splits as Array = [0, 0, 0, 0, 0];   // server ms, 0 = not yet
    var raceKnown as Boolean = false;
    // the server's clock, learned from the replies to our own updates
    var serverBase = null;            // server ms …
    var timerBase as Number = 0;      // … at this System.getTimer()
    // our own state
    var localLeg as Number = 0;       // leg shown right after a LAP press, before the race confirms it
    var lastPressMs as Number = -100000;
    var lat = null, lng = null, lastLat = null, lastLng = null;
    var distMi as Float = 0.0;
    var quality as Number = 0;
    var lastSentMs as Number = -1;
    var lastCode as Number = 0;
    var sending as Boolean = false;
    var lapsToSend as Array = [];     // { seg, n, press } not yet acknowledged
    var lapCount as Number = 0;
    var tick as Number = 0;
    var localStart as Number = 0;
    var timer as Timer.Timer;

    function initialize() {
        View.initialize();
        raceCode = Application.Storage.getValue("raceCode").toString();
        athIdx = Application.Storage.getValue("athIdx");
        token = Application.Storage.getValue("token");
        localStart = System.getTimer();
        timer = new Timer.Timer();
    }

    function onShow() as Void {
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        timer.start(method(:onTick), 1000, true);
    }
    function onHide() as Void { timer.stop(); }
    function stop() as Void {
        timer.stop();
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
    }

    // ── time ──
    function serverNow() {
        if (serverBase == null) { return null; }
        return serverBase + (System.getTimer() - timerBase);
    }
    // a number from the database (server ms), or 0
    function toMs(v) {
        if (v instanceof Number || v instanceof Long || v instanceof Float || v instanceof Double) { return v.toLong(); }
        return 0;
    }
    function learnServer(t) as Void {
        if (t instanceof Number || t instanceof Long || t instanceof Float || t instanceof Double) {
            serverBase = t.toLong(); timerBase = System.getTimer();
        }
    }
    // legs the race has finished: count of splits in a row
    function raceLeg() as Number {
        var n = 0;
        while (n < 5 && splits[n] != null && splits[n] > 0) { n++; }
        return n;
    }
    // the leg to show: the race's, except just after a LAP press until the race catches up
    function leg() as Number {
        if (!raceKnown) { return localLeg; }
        var r = raceLeg();
        if (lapsToSend.size() > 0 || System.getTimer() - lastPressMs < 8000) { return localLeg > r ? localLeg : r; }
        return r;
    }

    function onPosition(info as Position.Info) as Void {
        quality = info.accuracy;
        if (info.position == null || quality < Position.QUALITY_POOR) { return; }
        var d = info.position.toDegrees();
        lat = d[0]; lng = d[1];
        if (quality >= Position.QUALITY_USABLE) {
            if (lastLat != null) {
                var m = metres(lastLat, lastLng, lat, lng);
                if (m > 3 && m < 200) { distMi += (m / 1609.344).toFloat(); lastLat = lat; lastLng = lng; }
            } else { lastLat = lat; lastLng = lng; }
        }
    }
    function metres(a1, o1, a2, o2) as Float {
        var r = 6371000.0, p = Math.PI / 180;
        var dLat = (a2 - a1) * p, dLng = (o2 - o1) * p;
        var x = Math.sin(dLat / 2) * Math.sin(dLat / 2) + Math.cos(a1 * p) * Math.cos(a2 * p) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
        return (2 * r * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x))).toFloat();
    }

    // ── network ── (one request at a time; a LAP press always goes first)
    function gpsUrl() as String { return Tm.RTDB + "/liveRaces/" + raceCode + "/athletes/" + athIdx + "/gps.json"; }
    function patch(body as Dictionary, cb as Method) as Void {
        Communications.makeWebRequest(gpsUrl(), body,
            { :method => Communications.HTTP_REQUEST_METHOD_POST,
              :headers => { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON, "X-HTTP-Method-Override" => "PATCH" },
              :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON },
            cb);
    }

    function onTick() as Void {
        tick++;
        WatchUi.requestUpdate();
        if (sending) { return; }
        if (lapsToSend.size() > 0) {
            sending = true;
            var l = lapsToSend[0] as Dictionary;
            var ago = System.getTimer() - (l.get("press") as Number);
            patch({ "watchLap" => { "seg" => l.get("seg"), "n" => l.get("n"), "ago" => ago, "at" => { ".sv" => "timestamp" } } }, method(:onLapSent));
            return;
        }
        if (token != null && (tick % 4 == 1 || !raceKnown && tick % 2 == 1)) {
            sending = true;
            Communications.makeWebRequest(Tm.RTDB + "/watchTokens/" + token + "/race.json", null,
                { :method => Communications.HTTP_REQUEST_METHOD_GET, :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON },
                method(:onRace));
            return;
        }
        if (tick % 3 == 0 && lat != null) {
            sending = true;
            patch({ "lat" => lat, "lng" => lng, "distanceMi" => distMi, "accuracy" => quality, "seg" => leg(),
                    "onBike" => leg() == 2, "src" => "watch", "tok" => token, "t" => { ".sv" => "timestamp" } }, method(:onGpsSent));
        } else if (serverBase == null && tick % 3 == 0) {
            // no GPS yet: still let the race know we're here (and learn the server's clock)
            sending = true;
            patch({ "src" => "watch", "tok" => token, "t" => { ".sv" => "timestamp" } }, method(:onGpsSent));
        }
    }

    function onGpsSent(code as Number, data as Dictionary or String or Null) as Void {
        sending = false; lastCode = code;
        if (code == 200) { lastSentMs = System.getTimer(); if (data instanceof Dictionary) { learnServer(data.get("t")); } }
    }
    function onLapSent(code as Number, data as Dictionary or String or Null) as Void {
        sending = false; lastCode = code;
        if (code == 200) {
            lapsToSend = lapsToSend.slice(1, null); lastSentMs = System.getTimer();
            if (data instanceof Dictionary && data.get("watchLap") instanceof Dictionary) { learnServer((data.get("watchLap") as Dictionary).get("at")); }
        }
    }
    function onRace(code as Number, data as Dictionary or String or Null) as Void {
        sending = false; lastCode = code;
        if (code != 200 || !(data instanceof Dictionary)) { return; }
        lastSentMs = System.getTimer();
        raceKnown = true;
        started = data.get("started") == true;
        var sa = toMs(data.get("startAt"));
        startAt = sa > 0 ? sa : null;
        var sp = data.get("splits");
        var out = [0, 0, 0, 0, 0];
        if (sp instanceof Array) {
            for (var i = 0; i < 5 && i < sp.size(); i++) { out[i] = toMs(sp[i]); }
        }
        splits = out;
        if (lapsToSend.size() == 0 && System.getTimer() - lastPressMs >= 8000) { localLeg = raceLeg(); }
    }

    // LAP: this leg is done.
    function lap() as Void {
        var l = leg();
        if (l >= 5) { return; }
        lapCount++;
        lastPressMs = System.getTimer();
        lapsToSend.add({ "seg" => l, "n" => lapCount, "press" => lastPressMs });
        localLeg = l + 1;
        if (Attention has :vibrate) { Attention.vibrate([new Attention.VibeProfile(80, 250)]); }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth(), h = dc.getHeight();
        var now = serverNow();
        var l = leg();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.08, Graphics.FONT_XTINY, "Race " + raceCode, Graphics.TEXT_JUSTIFY_CENTER);
        var total = null, legTime = null;
        if (raceKnown && started && startAt != null && now != null) {
            total = now - startAt;
            var from = l == 0 ? startAt : (splits[l - 1] > 0 ? splits[l - 1] : null);
            if (from != null) { legTime = now - from; }
            if (l >= 5 && splits[4] > 0) { total = splits[4] - startAt; }
        }
        if (l >= 5) {
            dc.setColor(0x2FC27A, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.22, Graphics.FONT_MEDIUM, "FINISHED", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.38, Graphics.FONT_NUMBER_MEDIUM, total != null ? Tm.fmt(total.toNumber()) : "--", Graphics.TEXT_JUSTIFY_CENTER);
        } else if (raceKnown && !started) {
            dc.setColor(Tm.legColor(0), Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.24, Graphics.FONT_MEDIUM, "READY", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.42, Graphics.FONT_SMALL, "Waiting to be", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(w / 2, h * 0.52, Graphics.FONT_SMALL, "sent off", Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.setColor(Tm.legColor(l), Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.17, Graphics.FONT_MEDIUM, (Tm.LEGS[l] as String).toUpper(), Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.32, Graphics.FONT_NUMBER_MEDIUM, legTime != null ? Tm.fmt(legTime.toNumber()) : "--:--", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.56, Graphics.FONT_SMALL, "Race " + (total != null ? Tm.fmt(total.toNumber()) : "--:--"), Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(w / 2, h * 0.67, Graphics.FONT_SMALL, distMi.format("%.2f") + " mi", Graphics.TEXT_JUSTIFY_CENTER);
        }
        var nowT = System.getTimer();
        var ok = lastSentMs >= 0 && nowT - lastSentMs < 10000;
        var gps = quality >= Position.QUALITY_USABLE;
        dc.setColor(ok ? 0x2FC27A : 0xFF5A5A, Graphics.COLOR_TRANSPARENT);
        var line = ok ? "Connected to race" : (lastCode < 0 ? "Phone not connected" : (lastSentMs < 0 ? "Connecting..." : "Not sending"));
        if (lapsToSend.size() > 0) { line = "Sending lap..."; }
        dc.drawText(w / 2, h * 0.79, Graphics.FONT_XTINY, line + (gps ? "  GPS ok" : "  GPS ..."), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(0x777777, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.88, Graphics.FONT_XTINY, l < 5 && (!raceKnown || started) ? "LAP = end " + Tm.LEGS[l] : "Hold UP for menu", Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class TrackDelegate extends WatchUi.BehaviorDelegate {
    var view as TrackView;
    function initialize(v as TrackView) { BehaviorDelegate.initialize(); view = v; }

    // The BACK / LAP button ends a leg (it doesn't leave the app mid-race).
    function onBack() as Boolean { view.lap(); return true; }
    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_LAP) { view.lap(); return true; }
        return false;
    }

    // Hold UP: end tracking.
    function onMenu() as Boolean {
        var menu = new WatchUi.Menu2({ :title => "Timeathon" });
        menu.addItem(new WatchUi.MenuItem("Keep going", null, :resume, null));
        menu.addItem(new WatchUi.MenuItem("End tracking", "Stops GPS", :end, null));
        WatchUi.pushView(menu, new TrackMenuDelegate(view), WatchUi.SLIDE_UP);
        return true;
    }
}

class TrackMenuDelegate extends WatchUi.Menu2InputDelegate {
    var view as TrackView;
    function initialize(v as TrackView) { Menu2InputDelegate.initialize(); view = v; }

    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == :end) {
            view.stop();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            var p = new PairView();
            WatchUi.switchToView(p, new PairDelegate(p), WatchUi.SLIDE_RIGHT);
        } else {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }
}
