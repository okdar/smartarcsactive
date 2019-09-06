/*
    This file is part of SmartArcs Active watch face.
    https://github.com/okdar/smartarcs

    SmartArcs Active is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    SmartArcs Active is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with SmartArcs Active. If not, see <https://www.gnu.org/licenses/gpl.html>.
*/

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