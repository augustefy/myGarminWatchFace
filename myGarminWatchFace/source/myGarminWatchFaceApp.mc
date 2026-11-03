import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

(:background)
class myGarminWatchFaceApp extends Application.AppBase {

    private var _view = null;

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
    }

    // Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        // Température Open-Meteo rafraîchie toutes les 15 minutes
        if (Toybox.System has :ServiceDelegate) {
            Background.registerForTemporalEvent(new Time.Duration(15 * 60));
        }
        _view = new myGarminWatchFaceView();
        return [ _view ];
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [ new TemperatureService() ];
    }

    // Réponse du service d'arrière-plan
    function onBackgroundData(data as Application.PersistableType) as Void {
        if (data instanceof Dictionary) {
            Application.Storage.setValue("temp", data["temp"]);
            Application.Storage.setValue("tempAt", data["at"]);
            WatchUi.requestUpdate();
        }
    }

    // New app settings have been received so trigger a UI update
    function onSettingsChanged() as Void {
        if (_view != null) {
            (_view as myGarminWatchFaceView).onSettingsChanged();
        }
        WatchUi.requestUpdate();
    }

}

function getApp() as myGarminWatchFaceApp {
    return Application.getApp() as myGarminWatchFaceApp;
}
