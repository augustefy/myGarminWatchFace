import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.ActivityMonitor;
import Toybox.WatchUi;

class myGarminWatchFaceView extends WatchUi.WatchFace {

    function initialize() {
        WatchFace.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {

        var clock = System.getClockTime();

        var timeText = clock.hour.format("%02d") + ":" +
                       clock.min.format("%02d");

        var info = ActivityMonitor.getInfo();

        var stepsText = "--";
        if (info.steps != null) {
            stepsText = info.steps.toString();
        }

        var battery = System.getSystemStats().battery;
        var batteryText = battery.format("%.0f") + "%";

        var centerX = dc.getWidth() / 2;
        var centerY = dc.getHeight() / 2;

        // Fond noir AMOLED
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Heure centrale
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX, centerY - 80,
            Graphics.FONT_NUMBER_HOT,
            timeText,
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // Nombre de pas
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX, centerY + 15,
            Graphics.FONT_MEDIUM,
            "PAS : " + stepsText,
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // Batterie
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX, centerY + 65,
            Graphics.FONT_SMALL,
            "BATTERIE : " + batteryText,
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

}
