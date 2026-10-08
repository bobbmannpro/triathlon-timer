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

// Racing: GPS to the race every 3 s, LAP ends each leg.
//   liveRaces/{race}/athletes/{i}/gps  ← { lat, lng, distanceMi, accuracy, seg, onBike, src:"watch", t }
//   .../gps/watchLap                     ← { seg, n, at: server time }  (one per LAP press)
// The host's screen turns each watchLap into that leg's split.
class TrackView extends WatchUi.View {
    var raceCode as String;
    var athIdx;
    var leg as Number = 0;            // 0 Swim ... 4 Run, 5 = finished
    var startMs as Number = 0;        // System.getTimer() at START
    var legStartMs as Number = 0;
    var finishMs as Number = 0;
    var lat = null, lng = null, lastLat = null, lastLng = null;
    var distMi as Float = 0.0;
    var quality as Number = 0;
    var lastSentMs as Number = -1;    // when the last GPS update was acknowledged
    var lastCode as Number = 0;
    var sending as Boolean = false;
    var lapsToSend as Array = [];     // lap presses not yet acknowledged
    var lapCount as Number = 0;
    var tick as Number = 0;
    var timer as Timer.Timer;

    function initialize() {
        View.initialize();
        raceCode = Application.Storage.getValue("raceCode").toString();
        athIdx = Application.Storage.getValue("athIdx");
        startMs = System.getTimer();
        legStartMs = startMs;
        timer = new Timer.Timer();
    }

    function onShow() as Void {
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        timer.start(method(:onTick), 1000, true);
    }

    function onHide() as Void {
        timer.stop();
    }

    function stop() as Void {
        timer.stop();
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
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

    function gpsUrl() as String { return Tm.RTDB + "/liveRaces/" + raceCode + "/athletes/" + athIdx + "/gps.json"; }

    // POST with X-HTTP-Method-Override: PATCH — Firebase's way to update a few
    // fields over REST (the watch can't send PATCH directly).
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
        // A lap press goes first, and keeps retrying until it's in.
        if (lapsToSend.size() > 0) {
            sending = true;
            var l = lapsToSend[0] as Dictionary;
            patch({ "watchLap" => { "seg" => l.get("seg"), "n" => l.get("n"), "at" => { ".sv" => "timestamp" } } }, method(:onLapSent));
            return;
        }
        if (tick % 3 == 0 && lat != null && leg < 5) {
            sending = true;
            patch({ "lat" => lat, "lng" => lng, "distanceMi" => distMi, "accuracy" => quality,
                    "seg" => leg, "onBike" => leg == 2, "src" => "watch", "t" => { ".sv" => "timestamp" } }, method(:onGpsSent));
        }
    }

    function onGpsSent(code as Number, data as Dictionary or String or Null) as Void {
        sending = false; lastCode = code;
        if (code == 200) { lastSentMs = System.getTimer(); }
    }

    function onLapSent(code as Number, data as Dictionary or String or Null) as Void {
        sending = false; lastCode = code;
        if (code == 200) { lapsToSend = lapsToSend.slice(1, null); lastSentMs = System.getTimer(); }
    }

    // LAP: this leg is done.
    function lap() as Void {
        if (leg >= 5) { return; }
        var now = System.getTimer();
        lapCount++;
        lapsToSend.add({ "seg" => leg, "n" => lapCount });
        leg++;
        legStartMs = now;
        if (leg >= 5) { finishMs = now - startMs; }
        Application.Storage.setValue("leg", leg);
        if (Attention has :vibrate) { Attention.vibrate([new Attention.VibeProfile(80, 250)]); }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth(), h = dc.getHeight();
        var now = System.getTimer();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.08, Graphics.FONT_XTINY, "Race " + raceCode, Graphics.TEXT_JUSTIFY_CENTER);
        if (leg >= 5) {
            dc.setColor(0x2FC27A, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.24, Graphics.FONT_MEDIUM, "FINISHED", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.40, Graphics.FONT_NUMBER_MEDIUM, Tm.fmt(finishMs), Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.setColor(Tm.legColor(leg), Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.17, Graphics.FONT_MEDIUM, (Tm.LEGS[leg] as String).toUpper(), Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.32, Graphics.FONT_NUMBER_MEDIUM, Tm.fmt(now - legStartMs), Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.56, Graphics.FONT_SMALL, "Total " + Tm.fmt(now - startMs), Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(w / 2, h * 0.67, Graphics.FONT_SMALL, distMi.format("%.2f") + " mi", Graphics.TEXT_JUSTIFY_CENTER);
        }
        // Is it getting through? Green once the race has heard from us in the last 10 s.
        var ok = lastSentMs >= 0 && now - lastSentMs < 10000;
        var gps = quality >= Position.QUALITY_USABLE;
        dc.setColor(ok ? 0x2FC27A : 0xFF5A5A, Graphics.COLOR_TRANSPARENT);
        var line = ok ? "Sending to race" : (lastCode < 0 ? "Phone not connected" : (lastSentMs < 0 ? "Connecting..." : "Not sending"));
        if (lapsToSend.size() > 0) { line = "Sending lap..."; }
        dc.drawText(w / 2, h * 0.79, Graphics.FONT_XTINY, line + (gps ? "  GPS ok" : "  GPS ..."), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(0x777777, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.88, Graphics.FONT_XTINY, leg < 5 ? "LAP = end " + Tm.LEGS[leg] : "Hold UP for menu", Graphics.TEXT_JUSTIFY_CENTER);
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
