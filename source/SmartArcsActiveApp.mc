using Toybox.Application;

class SmartArcsActiveApp extends Application.AppBase {

    var view;

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state) {
    }

    // onStop() is called when your application is exiting
    function onStop(state) {
    }

    // Return the initial view of your application here
    function getInitialView() {
        view = new SmartArcsActiveView();
        return [ view ];
    }

    // triggered by settings change in GCM
    function onSettingsChanged() {
        view.loadUserSettings();
        view.requestUpdate(); //update the view to reflect changes
    }

}