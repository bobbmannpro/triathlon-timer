import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.Attention;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.System;
import Toybox.UserProfile;
import Toybox.Timer;
import Toybox.WatchUi;

// Racing.
//   Sends:  liveRaces/{race}/athletes/{i}/gps  ← { lat, lng, distanceMi, accuracy, seg, onBike, src:"watch", tok, t }
//           .../gps/watchLap                   ← { seg, n, ago, at: server time }  (one per LAP press;
//                                                ago = ms between the press and sending it)
//   Reads:  watchTokens/{code}/race            ← { started, startAt, splits[5], finished,  (server times,
//                                                dist[5], unit[5] }  kept up to date by the host's screen)
// The times shown are the race's: from when the host sent this athlete off,
// and the leg is whatever the race says — the watch only guesses ahead of
// the race for a few seconds after a LAP press.
// It also records a normal Garmin activity (cycling for a bike ride, a
// triathlon with one lap per leg for a race) from the send-off to the finish,
// so the effort lands in Garmin Connect — and Strava / TrainingPeaks if linked.
class TrackView extends WatchUi.View {
    var raceCode as String;
    var athIdx;
    var token;
    // what the race says
    var started as Boolean = false;
    var startAt = null;               // server ms
    var splits as Array = [0, 0, 0, 0, 0];   // server ms, 0 = not yet
    var raceKnown as Boolean = false;
    var legDist as Array = [0, 0, 0, 0, 0];   // each leg's distance in its unit (0 = none, e.g. transitions)
    var legUnit as Array = ["", "", "", "", ""];
    // the server's clock, learned from the replies to our own updates
    var serverBase = null;            // server ms …
    var timerBase as Number = 0;      // … at this System.getTimer()
    // our own state
    var localLeg as Number = 0;       // leg shown right after a LAP press, before the race confirms it
    var lastPressMs as Number = -100000;
    var lat = null, lng = null, lastLat = null, lastLng = null;
    var totalM as Float = 0.0;        // GPS metres since tracking began
    var legStartM as Float = 0.0;     // … when the leg on screen began
    var shownLeg as Number = -1;
    var quality as Number = 0;
    var lastSentMs as Number = 0;
    var everSent as Boolean = false;   // System.getTimer() goes negative after ~25 days of uptime, so never test its sign
    var everPressed as Boolean = false;
    var lastCode as Number = 0;
    var sending as Boolean = false;
    var lapsToSend as Array = [];     // { seg, n, press } not yet acknowledged
    var lapCount as Number = 0;
    var tick as Number = 0;
    var localStart as Number = 0;
    var timer as Timer.Timer;
    // Garmin activity recording
    var session = null;
    var isRide as Boolean = false;    // a bike ride ("W" codes) rather than a race
    var zones = null;                 // heart-rate zone thresholds from the watch's user profile

    function initialize() {
        View.initialize();
        raceCode = Application.Storage.getValue("raceCode").toString();
        athIdx = Application.Storage.getValue("athIdx");
        token = Application.Storage.getValue("token");
        localStart = System.getTimer();
        timer = new Timer.Timer();
        isRide = raceCode.length() > 0 && raceCode.substring(0, 1).equals("W");
        try {
            zones = UserProfile.getHeartRateZones(isRide ? UserProfile.HR_ZONE_SPORT_BIKING : UserProfile.HR_ZONE_SPORT_GENERIC);
        } catch (e) { zones = null; }
    }

    function onShow() as Void {
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        try { Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]); } catch (e) { }
        try { Sensor.enableSensorEvents(method(:onSensor)); } catch (e) { }
        timer.start(method(:onTick), 1000, true);
    }
    function onHide() as Void { timer.stop(); }
    function stop() as Void {
        timer.stop();
        finishRecording();
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        try { Sensor.enableSensorEvents(null); } catch (e) { }
    }

    // ── Garmin activity ──
    function startRecording() as Void {
        if (session != null || !(Toybox has :ActivityRecording)) { return; }
        try {
            session = ActivityRecording.createSession(isRide
                ? { :name => "Timeathon ride", :sport => Activity.SPORT_CYCLING, :subSport => Activity.SUB_SPORT_ROAD }
                : { :name => "Timeathon tri", :sport => Activity.SPORT_MULTISPORT, :subSport => Activity.SUB_SPORT_GENERIC });
            session.start();
        } catch (e) { session = null; }
    }
    function finishRecording() as Void {
        if (session == null) { return; }
        try {
            if (session.isRecording()) { session.stop(); }
            session.save();
        } catch (e) { }
        session = null;
    }
    // heart rate now, or null
    var sensorHr = null;
    function onSensor(info as Sensor.Info) as Void {
        if (info != null && info.heartRate != null) { sensorHr = info.heartRate; }
    }
    // heart rate now: the live sensor, else the activity's reading, else null
    function heartRate() {
        if (sensorHr != null) { return sensorHr; }
        try {
            var si = Sensor.getInfo();
            if (si != null && si.heartRate != null) { return si.heartRate; }
        } catch (e) { }
        var info = Activity.getActivityInfo();
        if (info != null && info.currentHeartRate != null) { return info.currentHeartRate; }
        return null;
    }
    // zone 1-5 for a heart rate (0 = below zone 1)
    function hrZone(hr) as Number {
        if (zones == null || hr == null || zones.size() < 6) { return 0; }
        for (var z = 5; z >= 1; z--) {
            if (hr > zones[z - 1]) { return z; }
        }
        return 0;
    }
    function zoneColor(z as Number) as Number {
        if (z == 1) { return 0xAAAAAA; }
        if (z == 2) { return 0x3D7BFF; }
        if (z == 3) { return 0x2FC27A; }
        if (z == 4) { return 0xFF8A3D; }
        if (z == 5) { return 0xFF4040; }
        return 0x777777;
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
        if (lapsToSend.size() > 0 || (everPressed && System.getTimer() - lastPressMs < 8000)) { return localLeg > r ? localLeg : r; }
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
                if (m > 3 && m < 200) { totalM += m; lastLat = lat; lastLng = lng; }
            } else { lastLat = lat; lastLng = lng; }
        }
    }
    // metres on the leg showing now (starts again from 0 each new leg)
    function legMetres() as Float {
        var l = leg();
        if (l != shownLeg) { shownLeg = l; legStartM = totalM; }
        return totalM - legStartM;
    }
    // metres in a leg's unit
    function inUnit(m as Float, u as String) as Float {
        if (u.equals("yd")) { return m * 1.09361; }
        if (u.equals("m")) { return m; }
        if (u.equals("km")) { return m / 1000.0; }
        return m / 1609.344;
    }
    function fmtDist(d as Float, u as String) as String {
        return (u.equals("yd") || u.equals("m")) ? d.toNumber().format("%d") : d.format("%.2f");
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

    // heart rate in its zone colour (resets the colour to grey afterwards)
    function drawHr(dc as Graphics.Dc, x, y, just) as Void {
        var hrNow = heartRate();
        var zn = hrZone(hrNow);
        dc.setColor(zoneColor(zn), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, hrNow != null ? ("HR " + hrNow.format("%d") + (zn > 0 ? " Z" + zn.format("%d") : "")) : "HR --", just);
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
    }

    // Heart-rate zone ticker: Z1-Z5 in colour, a marker at the current heart rate.
    function drawZoneBar(dc as Graphics.Dc, cx, y, bw) as Void {
        var hrNow = heartRate();
        var segW = bw / 5;
        var x0 = cx - bw / 2;
        var bh = 8;
        for (var z = 1; z <= 5; z++) {
            dc.setColor(zoneColor(z), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x0 + (z - 1) * segW + 1, y, segW - 2, bh);
        }
        if (hrNow != null && zones != null && zones.size() >= 6) {
            var z = hrZone(hrNow);
            var pos;
            if (z <= 0) { pos = 0.0; }
            else {
                var lo = zones[z - 1], hi = zones[z];
                var f = hi > lo ? (hrNow - lo).toFloat() / (hi - lo) : 0.5;
                if (f < 0) { f = 0.0; } if (f > 1) { f = 1.0; }
                pos = (z - 1) + f;
            }
            var mx = x0 + (pos * segW).toNumber();
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[mx - 7, y - 9], [mx + 7, y - 9], [mx, y]]);
            dc.fillRectangle(mx - 1, y, 3, bh + 3);
        }
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
    }

    function onTick() as Void {
        tick++;
        // Diagnostics: written to GARMIN/APPS/LOGS/TIMEATHON.TXT when that file exists.
        if (tick % 15 == 1) {
            var si = null;
            try { si = Sensor.getInfo(); } catch (e) { }
            System.println("t=" + tick + " sensorHr=" + sensorHr + " infoHr=" + (si != null ? si.heartRate : "n/a")
                + " actHr=" + (Activity.getActivityInfo() != null ? Activity.getActivityInfo().currentHeartRate : "n/a")
                + " code=" + lastCode + " sent=" + everSent + " rec=" + (session != null));
        }
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
            patch({ "lat" => lat, "lng" => lng, "distanceMi" => legMetres() / 1609.344, "accuracy" => quality, "seg" => leg(), "hr" => heartRate(),
                    "onBike" => leg() == 2, "src" => "watch", "tok" => token, "t" => { ".sv" => "timestamp" } }, method(:onGpsSent));
        } else if (tick % 3 == 0) {
            // no GPS yet: keep letting the race know we're here (and learn the server's clock)
            sending = true;
            patch({ "src" => "watch", "tok" => token, "t" => { ".sv" => "timestamp" } }, method(:onGpsSent));
        }
    }

    function onGpsSent(code as Number, data as Dictionary or String or Null) as Void {
        sending = false; lastCode = code;
        if (code == 200) { lastSentMs = System.getTimer(); everSent = true; if (data instanceof Dictionary) { learnServer(data.get("t")); } }
    }
    function onLapSent(code as Number, data as Dictionary or String or Null) as Void {
        sending = false; lastCode = code;
        if (code == 200) {
            lapsToSend = lapsToSend.slice(1, null); lastSentMs = System.getTimer(); everSent = true;
            if (data instanceof Dictionary && data.get("watchLap") instanceof Dictionary) { learnServer((data.get("watchLap") as Dictionary).get("at")); }
        }
    }
    function onRace(code as Number, data as Dictionary or String or Null) as Void {
        sending = false; lastCode = code;
        if (code != 200 || !(data instanceof Dictionary)) { return; }
        lastSentMs = System.getTimer();
        everSent = true;
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
        if (started && raceLeg() < 5) { startRecording(); }
        if (raceLeg() >= 5 || data.get("finished") == true) { finishRecording(); }
        var ds = data.get("dist"), us = data.get("unit");
        if (ds instanceof Array && us instanceof Array) {
            for (var i = 0; i < 5 && i < ds.size() && i < us.size(); i++) {
                var dv = ds[i];
                legDist[i] = (dv instanceof Number || dv instanceof Float || dv instanceof Double || dv instanceof Long) ? dv.toFloat() : 0;
                legUnit[i] = us[i] != null ? us[i].toString() : "";
            }
        }
        if (lapsToSend.size() == 0 && (!everPressed || System.getTimer() - lastPressMs >= 8000)) { localLeg = raceLeg(); }
    }

    // LAP: this leg is done.
    function lap() as Void {
        // On a bike ride LAP is an ordinary Garmin lap; the ride itself ends from the phone.
        if (isRide) {
            if (session != null && session.isRecording()) { try { session.addLap(); } catch (e) { } }
            if (Attention has :vibrate) { Attention.vibrate([new Attention.VibeProfile(60, 200)]); }
            return;
        }
        var l = leg();
        if (l >= 5) { return; }
        lapCount++;
        lastPressMs = System.getTimer();
        everPressed = true;
        lapsToSend.add({ "seg" => l, "n" => lapCount, "press" => lastPressMs });
        localLeg = l + 1;
        if (session != null && session.isRecording() && !isRide) {
            try { session.addLap(); } catch (e) { }
        }
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
        var ct = System.getClockTime();
        var hr12 = ct.hour % 12 == 0 ? 12 : ct.hour % 12;
        dc.drawText(w / 2, h * 0.08, Graphics.FONT_XTINY, hr12.format("%d") + ":" + ct.min.format("%02d") + (session != null ? "  REC" : ""), Graphics.TEXT_JUSTIFY_CENTER);
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
            drawHr(dc, w / 2, h * 0.60, Graphics.TEXT_JUSTIFY_CENTER);
            drawZoneBar(dc, w / 2, (h * 0.68).toNumber(), (w * 0.56).toNumber());
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.38, Graphics.FONT_NUMBER_MEDIUM, total != null ? Tm.fmt(total.toNumber()) : "--", Graphics.TEXT_JUSTIFY_CENTER);
        } else if (raceKnown && !started) {
            dc.setColor(Tm.legColor(0), Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.24, Graphics.FONT_MEDIUM, "READY", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.42, Graphics.FONT_SMALL, "Waiting to be", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(w / 2, h * 0.52, Graphics.FONT_SMALL, "sent off", Graphics.TEXT_JUSTIFY_CENTER);
            drawHr(dc, w / 2, h * 0.63, Graphics.TEXT_JUSTIFY_CENTER);
            drawZoneBar(dc, w / 2, (h * 0.71).toNumber(), (w * 0.56).toNumber());
        } else {
            dc.setColor(Tm.legColor(l), Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.17, Graphics.FONT_MEDIUM, (Tm.LEGS[l] as String).toUpper(), Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.32, Graphics.FONT_NUMBER_MEDIUM, legTime != null ? Tm.fmt(legTime.toNumber()) : "--:--", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2 - 6, h * 0.49, Graphics.FONT_XTINY, (isRide ? "Ride " : "Race ") + (total != null ? Tm.fmt(total.toNumber()) : "--:--"), Graphics.TEXT_JUSTIFY_RIGHT);
            drawHr(dc, w / 2 + 6, h * 0.49, Graphics.TEXT_JUSTIFY_LEFT);
            drawZoneBar(dc, w / 2, (h * 0.575).toNumber(), (w * 0.56).toNumber());
            // distance on this leg: done of the leg's total, what's left, and a ring round the edge
            var u = legUnit[l] as String, goal = legDist[l] as Float;
            var done = inUnit(legMetres(), u.length() > 0 ? u : "mi");
            if (goal > 0) {
                var frac = done / goal;
                if (frac > 1.0) { frac = 1.0; }
                dc.setPenWidth(w / 40 > 4 ? w / 40 : 4);
                dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(w / 2, h / 2, w / 2 - w / 40, Graphics.ARC_CLOCKWISE, 90, 90 - 359);
                if (frac > 0.005) {
                    dc.setColor(Tm.legColor(l), Graphics.COLOR_TRANSPARENT);
                    dc.drawArc(w / 2, h / 2, w / 2 - w / 40, Graphics.ARC_CLOCKWISE, 90, 90 - (frac * 359).toNumber());
                }
                dc.setPenWidth(1);
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(w / 2, h * 0.605, Graphics.FONT_SMALL, fmtDist(done, u) + " / " + fmtDist(goal, u) + " " + u, Graphics.TEXT_JUSTIFY_CENTER);
                var left = goal - done;
                dc.setColor(left > 0 ? 0xAAAAAA : 0x2FC27A, Graphics.COLOR_TRANSPARENT);
                dc.drawText(w / 2, h * 0.69, Graphics.FONT_XTINY, left > 0 ? fmtDist(left, u) + " " + u + " left" : "Distance done", Graphics.TEXT_JUSTIFY_CENTER);
            } else if (l == 1 || l == 3) {
                dc.drawText(w / 2, h * 0.63, Graphics.FONT_XTINY, "Transition", Graphics.TEXT_JUSTIFY_CENTER);
            } else {
                dc.drawText(w / 2, h * 0.63, Graphics.FONT_SMALL, fmtDist(done, "mi") + " mi", Graphics.TEXT_JUSTIFY_CENTER);
            }
        }
        var nowT = System.getTimer();
        var ok = everSent && nowT - lastSentMs < 10000;
        var gps = quality >= Position.QUALITY_USABLE;
        dc.setColor(ok ? 0x2FC27A : 0xFF5A5A, Graphics.COLOR_TRANSPARENT);
        var line = ok ? "Connected" : (lastCode < 0 ? "No phone" : (!everSent ? "Connecting..." : "Not sending"));
        if (lapsToSend.size() > 0) { line = "Sending lap..."; }
        dc.drawText(w / 2, h * 0.76, Graphics.FONT_XTINY, line + (gps ? "  GPS ok" : "  GPS ..."), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(0x777777, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.84, Graphics.FONT_XTINY, l < 5 && (!raceKnown || started) ? (isRide ? "LAP = lap" : "LAP = end " + Tm.LEGS[l]) : "Hold UP for menu", Graphics.TEXT_JUSTIFY_CENTER);
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
