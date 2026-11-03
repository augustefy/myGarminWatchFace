import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// Service d'arrière-plan : demande à Open-Meteo la température à la dernière position connue
(:background)
class TemperatureService extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        var lat = Application.Storage.getValue("lat");
        var lon = Application.Storage.getValue("lon");
        if (!(lat instanceof Float) || !(lon instanceof Float)) {
            Background.exit(null);
            return;
        }
        Communications.makeWebRequest(
            "https://api.open-meteo.com/v1/forecast",
            {
                "latitude" => lat.format("%.3f"),
                "longitude" => lon.format("%.3f"),
                "current" => "temperature_2m"
            },
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onResponse)
        );
    }

    function onResponse(code as Number, data as Dictionary or String or Null) as Void {
        var temp = null;
        if (code == 200 && data instanceof Dictionary) {
            var current = data["current"];
            if (current instanceof Dictionary) {
                temp = current["temperature_2m"];
            }
        }
        if (temp instanceof Number || temp instanceof Float || temp instanceof Double) {
            Background.exit({"temp" => temp.toFloat(), "at" => Time.now().value()});
        } else {
            Background.exit(null);
        }
    }

}
