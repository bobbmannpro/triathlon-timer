import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.Attention;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// Challenge runs (a month of "most miles", say). Paired once with a code from
// the challenge page; after that START begins a run, recorded as a normal
// Garmin run so it still lands in Garmin Connect. Finishing sends the distance:
//   POST challenges/{code}/entrants/{uid}/entries ← { m, at, dur, src:"watch", tok, added }
// The database accepts it because the token belongs to that athlete and that
// challenge, and only between the challenge's start and end. Runs finished
// without the phone nearby wait in storage ("chPending") and go when it's back.

// Sends waiting runs, oldest first, one request at a time.
class ChSender {
    var busy as Boolean = false;
    var lastCode as Number = 0;
    var onChange = null;         // method to call when the queue changes

    function initialize() {}

    function pending() as Array {
        var p = Application.Storage.getValue("chPending");
        return p instanceof Array ? p : [];
    }

    function send() as Void {
        if (busy) { return; }
        var p = pending();
        if (p.size() == 0) { return; }
        var e = p[0] as Dictionary;
        busy = true;
        Communications.makeWebRequest(Tm.RTDB + "/challenges/" + e.get("code") + "/entrants/" + e.get("uid") + "/entries.json",
            { "m" => e.get("m"), "at" => e.get("at"), "dur" => e.get("dur"), "src" => "watch", "tok" => e.get("tok"), "added" => { ".sv" => "timestamp" } },
            { :method => Communications.HTTP_REQUEST_METHOD_POST,
              :headers => { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON },
              :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON },
            method(:onSent));
    }

    function onSent(code as Number, data as Dictionary or String or Null) as Void {
        busy = false; lastCode = code;
        // sent, or refused for good (challenge over, not signed up): drop it either way
        if (code == 200 || code == 401 || code == 403 || code == 400) {
            var p = pending();
            Application.Storage.setValue("chPending", p.size() > 1 ? p.slice(1, null) : []);
            if (code == 200) { Application.Storage.setValue("chLastOk", true); }
            else { Application.Storage.setValue("chLastOk", false); }
        }
        if (onChange != null) { (onChange as Method).invoke(); }
    }
}

class ChallengeView extends WatchUi.View {
    var session = null;
    var state as Number = 0;          // 0 ready, 1 running, 2 paused, 3 saved
    var timer as Timer.Timer;
    var sender as ChSender;
    var startedAt = null;             // epoch ms when the run began
    var quality as Number = 0;
    var tick as Number = 0;
    var savedM as Float = 0.0;
    var unit as String;

    function initialize() {
        View.initialize();
        timer = new Timer.Timer();
        sender = new ChSender();
        sender.onChange = method(:changed);
        var u = Application.Storage.getValue("chUnit");
        unit = u != null && u.toString().equals("km") ? "km" : "mi";
    }
    function changed() as Void { WatchUi.requestUpdate(); }

    function onShow() as Void {
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        timer.start(method(:onTick), 1000, true);
    }
    function onHide() as Void { timer.stop(); }
    function onPosition(info as Position.Info) as Void { quality = info.accuracy; }
    function onTick() as Void {
        tick++;
        if (tick % 5 == 0) { sender.send(); }
        WatchUi.requestUpdate();
    }
    function stopGps() as Void {
        timer.stop();
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
    }

    function metres() as Float {
        var i = Activity.getActivityInfo();
        return i != null && i.elapsedDistance != null ? i.elapsedDistance.toFloat() : 0.0;
    }
    function elapsed() as Number {
        var i = Activity.getActivityInfo();
        return i != null && i.timerTime != null ? i.timerTime : 0;
    }
    function inUnit(m as Float) as Float { return unit.equals("km") ? m / 1000.0 : m / 1609.344; }

    // START: begin, pause, carry on
    function startOrPause() as Void {
        if (state == 0) {
            if (!(Toybox has :ActivityRecording)) { return; }
            try {
                session = ActivityRecording.createSession({ :name => "Timeathon challenge", :sport => Activity.SPORT_RUNNING, :subSport => Activity.SUB_SPORT_GENERIC });
                session.start();
                startedAt = Time.now().value().toLong() * 1000;
                state = 1;
            } catch (e) { session = null; }
        } else if (state == 1) {
            session.stop(); state = 2;
        } else if (state == 2) {
            session.start(); state = 1;
        }
        if (Attention has :vibrate) { Attention.vibrate([new Attention.VibeProfile(80, 200)]); }
        WatchUi.requestUpdate();
    }
    function lap() as Void {
        if (state == 1 && session != null) {
            try { session.addLap(); } catch (e) { }
            if (Attention has :vibrate) { Attention.vibrate([new Attention.VibeProfile(60, 150)]); }
        }
    }
    // Finish: save the Garmin run, queue the distance for the challenge.
    function finish() as Void {
        if (session == null) { return; }
        var m = metres(), dur = elapsed();
        try { if (session.isRecording()) { session.stop(); } session.save(); } catch (e) { }
        session = null;
        savedM = m;
        state = 3;
        if (m >= 50) {
            var p = sender.pending();
            p.add({ "code" => Application.Storage.getValue("chCode"), "uid" => Application.Storage.getValue("chUid"),
                    "tok" => Application.Storage.getValue("chTok"), "m" => m.toNumber(), "at" => startedAt, "dur" => dur });
            Application.Storage.setValue("chPending", p);
            Application.Storage.deleteValue("chLastOk");
            sender.send();
        }
        if (Attention has :vibrate) { Attention.vibrate([new Attention.VibeProfile(100, 400)]); }
        WatchUi.requestUpdate();
    }
    function discard() as Void {
        if (session != null) { try { if (session.isRecording()) { session.stop(); } session.discard(); } catch (e) { } }
        session = null; state = 0;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth(), h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(0xD49A2E, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.08, Graphics.FONT_XTINY, "CHALLENGE", Graphics.TEXT_JUSTIFY_CENTER);
        var nPending = sender.pending().size();
        if (state == 3) {
            dc.setColor(0x2FC27A, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.22, Graphics.FONT_MEDIUM, "SAVED", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.36, Graphics.FONT_NUMBER_MEDIUM, inUnit(savedM).format("%.2f"), Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(w / 2, h * 0.58, Graphics.FONT_SMALL, unit, Graphics.TEXT_JUSTIFY_CENTER);
            var ok = Application.Storage.getValue("chLastOk");
            var line = savedM < 50 ? "Too short to count" : nPending > 0 ? (sender.lastCode < 0 ? "Waiting for phone" : "Sending...") : ok == false ? "Not accepted" : "Added to challenge";
            dc.setColor(nPending > 0 || ok == false ? 0xFFB347 : 0x2FC27A, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.70, Graphics.FONT_XTINY, line, Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(0x777777, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.82, Graphics.FONT_XTINY, "START = done", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        var m = metres();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.18, Graphics.FONT_NUMBER_HOT, inUnit(m).format("%.2f"), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.44, Graphics.FONT_XTINY, unit, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.51, Graphics.FONT_MEDIUM, Tm.fmt(elapsed()), Graphics.TEXT_JUSTIFY_CENTER);
        // pace from the average speed
        var i = Activity.getActivityInfo();
        var pace = "--:--";
        if (i != null && i.averageSpeed != null && i.averageSpeed > 0.3) {
            var sPer = (unit.equals("km") ? 1000.0 : 1609.344) / i.averageSpeed;
            pace = (sPer / 60).toNumber().format("%d") + ":" + (sPer.toNumber() % 60).format("%02d");
        }
        var hr = i != null && i.currentHeartRate != null ? "  HR " + i.currentHeartRate.format("%d") : "";
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.64, Graphics.FONT_XTINY, pace + " /" + unit + hr, Graphics.TEXT_JUSTIFY_CENTER);
        var gps = quality >= Position.QUALITY_USABLE;
        dc.setColor(gps ? 0x2FC27A : 0xFFB347, Graphics.COLOR_TRANSPARENT);
        var st = state == 0 ? (gps ? "GPS ready" : "Finding GPS...") : state == 2 ? "PAUSED" : (gps ? "GPS ok" : "GPS weak");
        dc.drawText(w / 2, h * 0.73, Graphics.FONT_XTINY, st + (nPending > 0 ? "  (" + nPending.format("%d") + " to send)" : ""), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(0x777777, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.83, Graphics.FONT_XTINY, state == 0 ? "START = run" : "START pause · hold UP end", Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class ChallengeDelegate extends WatchUi.BehaviorDelegate {
    var view as ChallengeView;
    function initialize(v as ChallengeView) { BehaviorDelegate.initialize(); view = v; }

    function onSelect() as Boolean {
        if (view.state == 3) { back(); return true; }
        view.startOrPause();
        return true;
    }
    // BACK / LAP: a lap while running; leaves the screen before the run starts
    function onBack() as Boolean {
        if (view.state == 0 || view.state == 3) { back(); return true; }
        view.lap();
        return true;
    }
    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_LAP) { view.lap(); return true; }
        return false;
    }
    // Hold UP: finish, discard or carry on
    function onMenu() as Boolean {
        if (view.state != 1 && view.state != 2) { return true; }
        var menu = new WatchUi.Menu2({ :title => "Run" });
        menu.addItem(new WatchUi.MenuItem("Finish & save", "Adds it to the challenge", :finish, null));
        menu.addItem(new WatchUi.MenuItem("Keep going", null, :resume, null));
        menu.addItem(new WatchUi.MenuItem("Discard", "Throws this run away", :discard, null));
        WatchUi.pushView(menu, new ChallengeMenuDelegate(view), WatchUi.SLIDE_UP);
        return true;
    }
    function back() as Void {
        view.stopGps();
        var p = new PairView();
        WatchUi.switchToView(p, new PairDelegate(p), WatchUi.SLIDE_RIGHT);
    }
}

class ChallengeMenuDelegate extends WatchUi.Menu2InputDelegate {
    var view as ChallengeView;
    function initialize(v as ChallengeView) { Menu2InputDelegate.initialize(); view = v; }
    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (id == :finish) { view.finish(); }
        else if (id == :discard) { view.discard(); }
    }
}
