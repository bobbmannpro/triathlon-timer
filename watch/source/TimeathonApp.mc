import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Timeathon on the watch.
//   1. Pair: enter the 6-digit code from the Timeathon web app (athlete's
//      race screen → Connect watch). The watch looks it up to learn the race
//      and which athlete it is.
//   2. Track: GPS goes to the race every 3 seconds; the LAP (back) button
//      ends each leg — Swim, T1, Bike, T2, Run. The host's screen turns each
//      press into a split (in Auto), and the host can always override.
// Everything goes over the phone's Garmin Connect app, so the phone needs to
// be within Bluetooth range for data to send.
class TimeathonApp extends Application.AppBase {
    function initialize() { AppBase.initialize(); }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var view = new PairView();
        return [view, new PairDelegate(view)];
    }
}

// Shared bits.
module Tm {
    const RTDB = "https://timeathon-default-rtdb.firebaseio.com";
    const LEGS = ["Swim", "T1", "Bike", "T2", "Run"];

    function legColor(i as Number) as Number {
        if (i == 0) { return 0x3D7BFF; }
        if (i == 2) { return 0xFF8A3D; }
        if (i == 4) { return 0x2FC27A; }
        return 0xAAAAAA;
    }

    // m:ss or h:mm:ss
    function fmt(ms as Number) as String {
        var s = ms / 1000;
        var h = s / 3600, m = (s % 3600) / 60, sec = s % 60;
        if (h > 0) { return h.format("%d") + ":" + m.format("%02d") + ":" + sec.format("%02d"); }
        return m.format("%d") + ":" + sec.format("%02d");
    }
}
