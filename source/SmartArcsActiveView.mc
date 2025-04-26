/*
    This file is part of SmartArcs Active watch face.
    https://github.com/okdar/smartarcsactive

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

using Toybox.Activity;
using Toybox.ActivityMonitor;
using Toybox.Application;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Position;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;

class SmartArcsActiveView extends WatchUi.WatchFace {

    //TRYING TO KEEP AS MUCH PRE-COMPUTED VALUES AS POSSIBLE IN MEMORY TO SAVE CPU UTILIZATION
    //AND HOPEFULLY PROLONG BATTERY LIFE. PRE-COMPUTED VARIABLES DON'T NEED TO BE COMPUTED
    //AGAIN AND AGAIN ON EACH SCREEN UPDATE. THAT'S THE REASON FOR LONG LIST OF GLOBAL VARIABLES.

    //global variables
    var isAwake = false;
    var partialUpdatesAllowed = false;
    var floorsClimbedSupported = false;
    var bodyBatterySupported = false;
    var stressSupported = false;
    var fullScreenRefresh;
    var offscreenBuffer;
    var offSettingFlag = -999;
    var font;
    var lastMeasuredHR;
    var powerSaverDrawn = false;
    var sunArcsOffset;
    var lastPhoneConnectedTime;

    //global variables for pre-computation
    var screenRadius;
    var screenResolutionRatio;
    var activity1Y;
    var activity2Y;
    var activityArcY;
    var halfFontHeight;
    var ticks = null;
    var hourHandLength;
    var minuteHandLength;
    var handsTailLength;
    var startActivityAngle = 90;
    var endActivityAngle = 300;
    var hrTextDimension;
    var halfHRTextWidth;
    var startPowerSaverMin;
    var endPowerSaverMin;
	var sunriseStartAngle = 0;
	var sunriseEndAngle = 0;
	var sunsetStartAngle = 0;
	var sunsetEndAngle = 0;
	var locationLatitude;
	var locationLongitude;
    var dateInfo;
	
    //user settings
    var bgColor;
    var handsColor;
    var handsOutlineColor;
    var hourHandWidth;
    var minuteHandWidth;
    var battery100Color;
    var battery30Color;
    var battery15Color;
    var notificationColor;
    var bluetoothColor;
    var dndColor;
    var alarmColor;
    var activityColor;
    var activityProgressGoalColor;
    var activityReachedGoalColor;
    var bbStressArcColor;
    var bbStressWarningArcColor;
    var dateColor;
    var ticksColor;
    var ticks1MinWidth;
    var ticks5MinWidth;
    var ticks15MinWidth;
    var oneColor;
    var handsOnTop;
    var showBatteryIndicator;
    var dateFormat;
    var showZero;
    var showBb;
    var showStress;
    var hrColor;
    var hrRefreshInterval;
    var powerSaver;
    var powerSaverRefreshInterval;
    var sunriseColor;
    var sunsetColor;
    var showLostAndFound;
    var phone;
    var email;

    enum {
        STEPS = 1,
        STAIRS = 2,
        BODY_BATTERY = 3,
        STRESS = 4
    }

    function initialize() {
        WatchFace.initialize();
    }

    //load resources here
    function onLayout(dc) {
        //if this device supports BufferedBitmap, allocate the buffers we use for drawing
        if (Toybox.Graphics has :createBufferedBitmap) {
            // get() used to return resource as Graphics.BufferedBitmap
            //Allocate a full screen size buffer to draw the background image of the watchface.
            offscreenBuffer = Toybox.Graphics.createBufferedBitmap({
                :width => dc.getWidth(),
                :height => dc.getHeight()
            }).get();
        } else if (Toybox.Graphics has :BufferedBitmap) {
            //If this device supports BufferedBitmap, allocate the buffers we use for drawing
            //Allocate a full screen size buffer to draw the background image of the watchface.
            offscreenBuffer = new Toybox.Graphics.BufferedBitmap({
                :width => dc.getWidth(),
                :height => dc.getHeight()
            });
        } else {
            offscreenBuffer = null;
        }

        partialUpdatesAllowed = (Toybox.WatchUi.WatchFace has :onPartialUpdate);
        floorsClimbedSupported = (Toybox.ActivityMonitor.Info has :floorsClimbed);
        bodyBatterySupported = (Toybox.SensorHistory has :getBodyBatteryHistory);
        stressSupported = (Toybox.SensorHistory has :getStressHistory);

        screenRadius = dc.getWidth() / 2;
        //TINY font for screen resolution 240 and lower, SMALL for higher resolution
        if (screenRadius <= 120) {
            font = Graphics.FONT_TINY;
        } else {
            font = Graphics.FONT_SMALL;
        }
        hrTextDimension = dc.getTextDimensions("888", font); //to compute correct clip boundaries

        loadUserSettings();
        fullScreenRefresh = true;
    }

    //called when this View is brought to the foreground. Restore
    //the state of this View and prepare it to be shown. This includes
    //loading resources into memory.
    function onShow() {
    }

    //update the view
    function onUpdate(dc) {
        var clockTime = System.getClockTime();

        var deviceSettings = System.getDeviceSettings();
        if (deviceSettings.phoneConnected) {
            lastPhoneConnectedTime = Time.now();
            if (clockTime.min % 10 == 0) {
                Application.getApp().setProperty("lastPhoneConnectedTime", lastPhoneConnectedTime.value());
            }
        } else if (showLostAndFound != offSettingFlag &&
                    (lastPhoneConnectedTime == null || Time.now().subtract(lastPhoneConnectedTime).value() > showLostAndFound)) {
                //update power saver display
                var targetDc;
                if (offscreenBuffer != null) {
                    //if we have an offscreen buffer that we are using to draw the background,
                    //set the draw context of that buffer as our target.
                    targetDc = offscreenBuffer.getDc();
                    dc.clearClip();
                } else {
                    targetDc = dc;
                }

                drawLostAndFound(targetDc);

                //update screen
                drawBackground(dc);

                return;
        }
        
        //check power saver state
        if (shouldPowerSave()) {
            //if already in power saver mode, check if we need to refresh
            if (powerSaverDrawn) {
                //only refresh at specified intervals or if first time
                if (powerSaverRefreshInterval == offSettingFlag || !(clockTime.min % powerSaverRefreshInterval == 0)) {
                    //preserve current screen state
                    drawBackground(dc);
                    return;
                }
            }

            //update power saver display
            var targetDc;
            if (offscreenBuffer != null) {
                //if we have an offscreen buffer that we are using to draw the background,
                //set the draw context of that buffer as our target.
                targetDc = offscreenBuffer.getDc();
                dc.clearClip();
            } else {
                targetDc = dc;
            }

            //clear screen and draw minimal display
            targetDc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
            targetDc.fillCircle(screenRadius, screenRadius, screenRadius + 2);
            drawHands(targetDc, clockTime);

            //update screen
           drawBackground(dc);

            //update state
            powerSaverDrawn = true;
            return;
        }

        //regular update path
        powerSaverDrawn = false;

        var activityInfo = ActivityMonitor.getInfo();

		if (clockTime.min == 0) {
    		//recompute sunrise/sunset constants every hour - to address new location when traveling
			computeSunConstants();
            //not needed to get date on every refresh event
            dateInfo = Gregorian.info(Time.today(), Time.FORMAT_MEDIUM);
		}

        //we always want to refresh the full screen when we get a regular onUpdate call.
        fullScreenRefresh = true;

        var targetDc = null;
        if (offscreenBuffer != null) {
            //if we have an offscreen buffer that we are using to draw the background,
            //set the draw context of that buffer as our target.
            targetDc = offscreenBuffer.getDc();
            dc.clearClip();
        } else {
            targetDc = dc;
        }

        //clear the screen
        targetDc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        targetDc.fillCircle(screenRadius, screenRadius, screenRadius + 2);

        if (showBatteryIndicator) {
            var batStat = System.getSystemStats().battery;
            if (oneColor != offSettingFlag) {
                drawSmartArc(targetDc, oneColor, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
            } else {
                if (batStat > 30) {
                    drawSmartArc(targetDc, battery100Color, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
                    drawSmartArc(targetDc, battery30Color, Graphics.ARC_CLOCKWISE, 180, 153);
                    drawSmartArc(targetDc, battery15Color, Graphics.ARC_CLOCKWISE, 180, 166.5);
                } else if (batStat <= 30 && batStat > 15) {
                    drawSmartArc(targetDc, battery30Color, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
                    drawSmartArc(targetDc, battery15Color, Graphics.ARC_CLOCKWISE, 180, 166.5);
                } else {
                    drawSmartArc(targetDc, battery15Color, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
                }
            }
        }

        var itemCount = deviceSettings.notificationCount;
        if (notificationColor != offSettingFlag && itemCount > 0) {
            if (itemCount < 11) {
                drawSmartArc(targetDc, notificationColor, Graphics.ARC_CLOCKWISE, 90, 90 - 30 - ((itemCount - 1) * 6));
            } else {
                drawSmartArc(targetDc, notificationColor, Graphics.ARC_CLOCKWISE, 90, 0);
            }
        }

        if (bluetoothColor != offSettingFlag && deviceSettings.phoneConnected) {
            drawSmartArc(targetDc, bluetoothColor, Graphics.ARC_CLOCKWISE, 0, -30);
        }

        if (dndColor != offSettingFlag && deviceSettings.doNotDisturb) {
            drawSmartArc(targetDc, dndColor, Graphics.ARC_COUNTER_CLOCKWISE, 270, -60);
        }

        itemCount = deviceSettings.alarmCount;
        if (alarmColor != offSettingFlag && itemCount > 0) {
            if (itemCount < 11) {
                drawSmartArc(targetDc, alarmColor, Graphics.ARC_CLOCKWISE, 270, 270 - 30 - ((itemCount - 1) * 6));
            } else {
                drawSmartArc(targetDc, alarmColor, Graphics.ARC_CLOCKWISE, 270, 0);
            }
        }

        if (locationLatitude != offSettingFlag) {
    	    drawSun(targetDc);
        }

        if (ticks != null) {
            drawTicks(targetDc);
        }
        
        if (!handsOnTop) {
            drawHands(targetDc, clockTime);
        }

        if (dateColor != offSettingFlag) {
            drawDate(targetDc);
        }

        drawSteps(targetDc, activityInfo.steps, activityInfo.stepGoal, activityInfo.distance, deviceSettings.distanceUnits);
        if (floorsClimbedSupported) {
            drawFloors(targetDc, activityInfo.floorsClimbed, activityInfo.floorsDescended, activityInfo.floorsClimbedGoal);
        }

        if (bodyBatterySupported && showBb) {
            drawBodyBattery(targetDc);
        }

        if (stressSupported && showStress) {
            drawStress(targetDc);
        }
    
        if (handsOnTop) {
            drawHands(targetDc, clockTime);
        }

        //output the offscreen buffers to the main display if required.
        drawBackground(dc);

        if (partialUpdatesAllowed && (hrColor != offSettingFlag)) {
            onPartialUpdate(dc);
        }

        fullScreenRefresh = false;
    }
    
    //called when this View is removed from the screen. Save the state
    //of this View here. This includes freeing resources from memory.
    function onHide() {
    }

    //the user has just looked at their watch. Timers and animations may be started here.
    function onExitSleep() {
        requestUpdate();
        isAwake = true;
    }

    //terminate any active timers and prepare for slow updates.
    function onEnterSleep() {
        isAwake = false;
        requestUpdate();
    }

    function loadUserSettings() {
        var app = Application.getApp();

        oneColor = app.getProperty("oneColor");
        if (oneColor == offSettingFlag) {
            battery100Color = app.getProperty("battery100Color");
            battery30Color = app.getProperty("battery30Color");
            battery15Color = app.getProperty("battery15Color");
            notificationColor = app.getProperty("notificationColor");
            bluetoothColor = app.getProperty("bluetoothColor");
            dndColor = app.getProperty("dndColor");
            alarmColor = app.getProperty("alarmColor");
            activityProgressGoalColor = app.getProperty("activityProgressGoalColor");
            activityReachedGoalColor = app.getProperty("activityReachedGoalColor");
            bbStressArcColor = app.getProperty("bbStressArcColor");
            bbStressWarningArcColor = app.getProperty("bbStressWarningArcColor");
    		sunriseColor = app.getProperty("sunriseColor");
			sunsetColor = app.getProperty("sunsetColor");
        } else {
            notificationColor = oneColor;
            bluetoothColor = oneColor;
            dndColor = oneColor;
            alarmColor = oneColor;
            activityProgressGoalColor = oneColor;
            activityReachedGoalColor = oneColor;
            bbStressArcColor = oneColor;
            bbStressWarningArcColor = oneColor;
    		sunriseColor = oneColor;
			sunsetColor = oneColor;
        }
        bgColor = app.getProperty("bgColor");
        ticksColor = app.getProperty("ticksColor");
        if (ticksColor != offSettingFlag) {
            ticks1MinWidth = app.getProperty("ticks1MinWidth");
            ticks5MinWidth = app.getProperty("ticks5MinWidth");
            ticks15MinWidth = app.getProperty("ticks15MinWidth");
        }
        handsColor = app.getProperty("handsColor");
        handsOutlineColor = app.getProperty("handsOutlineColor");
        hourHandWidth = app.getProperty("hourHandWidth");
        minuteHandWidth = app.getProperty("minuteHandWidth");
        activityColor = app.getProperty("activityColor");
        dateColor = app.getProperty("dateColor");
        showZero = app.getProperty("showZero");
        showBb = app.getProperty("showBb");
        showStress = app.getProperty("showStress");
        hrColor = app.getProperty("hrColor");

        if (dateColor != offSettingFlag) {
            dateFormat = app.getProperty("dateFormat");
        }

        if (hrColor != offSettingFlag) {
            hrRefreshInterval = app.getProperty("hrRefreshInterval");
        }

        handsOnTop = app.getProperty("handsOnTop");

        showBatteryIndicator = app.getProperty("showBatteryIndicator");

        var power = app.getProperty("powerSaver");
		powerSaverRefreshInterval = app.getProperty("powerSaverRefreshInterval");
        if (power == 1) {
        	powerSaver = false;
    	} else {
    		powerSaver = true;
            var powerSaverBeginning = app.getProperty("powerSaverBeginning");
            var powerSaverEnd = app.getProperty("powerSaverEnd");
            startPowerSaverMin = parsePowerSaverTime(powerSaverBeginning);
            if (startPowerSaverMin == -1) {
                powerSaver = false;
            } else {
                endPowerSaverMin = parsePowerSaverTime(powerSaverEnd);
                if (endPowerSaverMin == -1) {
                    powerSaver = false;
                }
            }
        }
		
		locationLatitude = app.getProperty("locationLatitude");
		locationLongitude = app.getProperty("locationLongitude");

        showLostAndFound = app.getProperty("showLostAndFound");
        if (showLostAndFound != offSettingFlag) {
            showLostAndFound *= 3600;
        }
        phone = app.getProperty("phone");
        email = app.getProperty("email");
        if (app.getProperty("lastPhoneConnectedTime") == -999) {
            lastPhoneConnectedTime = null;
        } else {
            lastPhoneConnectedTime = new Time.Moment(app.getProperty("lastPhoneConnectedTime"));
        }

        //ensure that screen will be refreshed when settings are changed 
    	powerSaverDrawn = false;
        
        computeConstants();
		computeSunConstants();
    }

    //pre-compute values which don't need to be computed on each update
    function computeConstants() {
        //computes hand lenght for watches with different screen resolution than 260x260
        screenResolutionRatio = screenRadius / 130.0; //130.0 = half of vivoactive4 resolution; used for coordinates recalculation
        hourHandLength = recalculateCoordinate(60);
        minuteHandLength = recalculateCoordinate(90);
        handsTailLength = recalculateCoordinate(15);
        
        if (!((ticksColor == offSettingFlag) ||
            (ticksColor != offSettingFlag && ticks1MinWidth == 0 && ticks5MinWidth == 0 && ticks15MinWidth == 0))) {
            //array of ticks coordinates
            computeTicks();
        }

        //Y coordinates of activities
        halfFontHeight = Graphics.getFontHeight(font) / 2;
        activity1Y = screenRadius + recalculateCoordinate(10);
        activity2Y = activity1Y + Graphics.getFontAscent(font);
        activityArcY = activity1Y + 1 + halfFontHeight;

        halfHRTextWidth = hrTextDimension[0] / 2;
        
        dateInfo = Gregorian.info(Time.today(), Time.FORMAT_MEDIUM);
    }

    function parsePowerSaverTime(time) {
        var pos = time.find(":");
        if (pos != null) {
            var hour = time.substring(0, pos).toNumber();
            var min = time.substring(pos + 1, time.length()).toNumber();
            if (hour != null && min != null) {
                return (hour * 60) + min;
            } else {
                return -1;
            }
        } else {
            return -1;
        }
    }

    function computeTicks() {
        var angle;
        ticks = new [16];
        //to save the memory compute only a quarter of the ticks, the rest will be mirrored.
        //I believe it will still save some CPU utilization
        for (var i = 0; i < 16; i++) {
            angle = i * Math.PI * 2 / 60.0;
            if ((i % 15) == 0) { //quarter tick
                if (ticks15MinWidth > 0) {
                    ticks[i] = computeTickRectangle(angle, recalculateCoordinate(20), ticks15MinWidth);
                }
            } else if ((i % 5) == 0) { //5-minute tick
                if (ticks5MinWidth > 0) {
                    ticks[i] = computeTickRectangle(angle, recalculateCoordinate(20), ticks5MinWidth);
                }
            } else if (ticks1MinWidth > 0) { //1-minute tick
                ticks[i] = computeTickRectangle(angle, recalculateCoordinate(10), ticks1MinWidth);
            }
        }
    }

    function computeTickRectangle(angle, length, width) {
        var halfWidth = width / 2;
        var coords = [[-halfWidth, screenRadius], [-halfWidth, screenRadius - length], [halfWidth, screenRadius - length], [halfWidth, screenRadius]];
        return computeRectangle(coords, angle);
    }

    function computeRectangle(coords, angle) {
        var rect = new [4];
        var x;
        var y;
        var cos = Math.cos(angle);
        var sin = Math.sin(angle);

        //transform coordinates
        for (var i = 0; i < 4; i++) {
            x = (coords[i][0] * cos) - (coords[i][1] * sin) + 0.5;
            y = (coords[i][0] * sin) + (coords[i][1] * cos) + 0.5;
            rect[i] = [screenRadius + x, screenRadius + y];
        }

        return rect;
    }

    function drawSmartArc(dc, color, arcDirection, startAngle, endAngle) {
        dc.setPenWidth(recalculateCoordinate(10));
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(screenRadius, screenRadius, screenRadius - recalculateCoordinate(5), arcDirection, startAngle, endAngle);
    }

    function drawTicks(dc) {
        var coord = new [4];
        var screenWidth = screenRadius * 2;
        dc.setColor(ticksColor, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 16; i++) {
        	//30-45 ticks
            if (ticks[i] != null) {
                dc.fillPolygon(ticks[i]);
            }

            //mirror pre-computed ticks
            if (i >= 0 && i <= 15 && ticks[i] != null) {
            	//15-30 ticks
                for (var j = 0; j < 4; j++) {
                    coord[j] = [screenWidth - ticks[i][j][0], ticks[i][j][1]];
                }
                dc.fillPolygon(coord);

				//45-60 ticks
                for (var j = 0; j < 4; j++) {
                    coord[j] = [ticks[i][j][0], screenWidth - ticks[i][j][1]];
                }
                dc.fillPolygon(coord);

				//0-15 ticks
                for (var j = 0; j < 4; j++) {
                    coord[j] = [screenWidth - ticks[i][j][0], screenWidth - ticks[i][j][1]];
                }
                dc.fillPolygon(coord);
            }
        }
    }

    function drawHands(dc, clockTime) {
        var hourAngle, minAngle;

        //draw hour hand
        hourAngle = ((clockTime.hour % 12) * 60.0) + clockTime.min;
        hourAngle = hourAngle / (12 * 60.0) * Math.PI * 2;
        if (handsOutlineColor != offSettingFlag) {
            drawHand(dc, handsOutlineColor, computeHandRectangle(hourAngle, hourHandLength + recalculateCoordinate(2), handsTailLength + recalculateCoordinate(2), hourHandWidth + recalculateCoordinate(4)));
        }
        drawHand(dc, handsColor, computeHandRectangle(hourAngle, hourHandLength, handsTailLength, hourHandWidth));

        //draw minute hand
        minAngle = (clockTime.min / 60.0) * Math.PI * 2;
        if (handsOutlineColor != offSettingFlag) {
            drawHand(dc, handsOutlineColor, computeHandRectangle(minAngle, minuteHandLength + recalculateCoordinate(2), handsTailLength + recalculateCoordinate(2), minuteHandWidth + recalculateCoordinate(4)));
        }
        drawHand(dc, handsColor, computeHandRectangle(minAngle, minuteHandLength, handsTailLength, minuteHandWidth));

        //draw bullet
        var bulletRadius = hourHandWidth > minuteHandWidth ? hourHandWidth / 2 : minuteHandWidth / 2;
        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(screenRadius, screenRadius, bulletRadius + 1);
        dc.setPenWidth(bulletRadius);
        dc.setColor(handsColor,Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(screenRadius, screenRadius, bulletRadius + recalculateCoordinate(2));
    }

    function drawHand(dc, color, coords) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(coords);
    }

    function computeHandRectangle(angle, handLength, tailLength, width) {
        var halfWidth = width / 2;
        var coords = [[-halfWidth, tailLength], [-halfWidth, -handLength], [halfWidth, -handLength], [halfWidth, tailLength]];
        return computeRectangle(coords, angle);
    }

    //Handle the partial update event
    function onPartialUpdate(dc) {
        if ((showLostAndFound != offSettingFlag && 
                (lastPhoneConnectedTime == null || Time.now().subtract(lastPhoneConnectedTime).value() > showLostAndFound)) ||
                (powerSaverDrawn && shouldPowerSave())) {
            return;
        }

        powerSaverDrawn = false;

        var refreshHR = false;
        var clockSeconds = System.getClockTime().sec;

        //should be HR refreshed?
        if (hrColor != offSettingFlag) {
            if (hrRefreshInterval == 1) {
                refreshHR = true;
            } else if (clockSeconds % hrRefreshInterval == 0) {
                refreshHR = true;
            }
        }

        //if we're not doing a full screen refresh we need to re-draw the background
        //before drawing the updated second hand position. Note this will only re-draw
        //the background in the area specified by the previously computed clipping region.
        if(!fullScreenRefresh) {
            drawBackground(dc);
        }

        //draw HR
        if (hrColor != offSettingFlag) {
            drawHR(dc, refreshHR);
        }

        if (shouldPowerSave()) {
            requestUpdate();
        }
    }

    //Draw the watch face background
    //onUpdate uses this method to transfer newly rendered Buffered Bitmaps
    //to the main display.
    //onPartialUpdate uses this to blank the second hand from the previous
    //second before outputing the new one.
    function drawBackground(dc) {
        //If we have an offscreen buffer that has been written to
        //draw it to the screen.
        if( null != offscreenBuffer ) {
            dc.drawBitmap(0, 0, offscreenBuffer);
        }
    }

    //Compute a bounding box from the passed in points
    function getBoundingBox(points) {
        var min = [9999,9999];
        var max = [0,0];

        for (var i = 0; i < points.size(); ++i) {
            if(points[i][0] < min[0]) {
                min[0] = points[i][0];
            }
            if(points[i][1] < min[1]) {
                min[1] = points[i][1];
            }
            if(points[i][0] > max[0]) {
                max[0] = points[i][0];
            }
            if(points[i][1] > max[1]) {
                max[1] = points[i][1];
            }
        }

        return [min, max];
    }

    function drawDate(dc) {
        var dateString = "";
        switch (dateFormat) {
            case 0: dateString = dateInfo.day;
                    break;
            case 1: dateString = Lang.format("$1$ $2$", [dateInfo.day_of_week.substring(0, 3), dateInfo.day]);
                    break;
            case 2: dateString = Lang.format("$1$ $2$", [dateInfo.day, dateInfo.day_of_week.substring(0, 3)]);
                    break;
            case 3: dateString = Lang.format("$1$ $2$", [dateInfo.day, dateInfo.month.substring(0, 3)]);
                    break;
            case 4: dateString = Lang.format("$1$ $2$", [dateInfo.month.substring(0, 3), dateInfo.day]);
                    break;
        }
        dc.setColor(dateColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(screenRadius, (screenRadius * 2) - recalculateCoordinate(30) - (halfFontHeight * 2), font, dateString, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawSteps(dc, steps, stepsGoal, distance, distanceUnits) {
        if (steps == null) {
            steps = 0;
        }
        if (stepsGoal == null) {
            stepsGoal = 0;
        }
        if (distance == null) {
            distance = 0;
        } else {
            if (distanceUnits == System.UNIT_STATUTE) {
                distance = distance/1.609344;
            }
            distance = (distance/100000.0).format("%.2f");
        }

        drawActivity(dc, STEPS, steps, distance, stepsGoal, recalculateCoordinate(70), activity1Y, activity2Y, activityArcY);
    }

    function drawFloors(dc, floorsClimbed, floorsDescended, floorsGoal) {
        if (floorsClimbed == null) {
            floorsClimbed = 0;
        }
        if (floorsDescended == null) {
            floorsDescended = 0;
        }
        if (floorsGoal == null) {
            floorsGoal = 0;
        }

        drawActivity(dc, STAIRS, floorsClimbed, floorsDescended.toString(), floorsGoal, recalculateCoordinate(-30), activity1Y, activity2Y, activityArcY);
    }

    function drawBodyBattery(dc) {
        drawActivity(dc, BODY_BATTERY, getLastHistoryValue(Toybox.SensorHistory.getBodyBatteryHistory({:period=>1})), -1, 100, recalculateCoordinate(40), screenRadius - (activity1Y - screenRadius + (halfFontHeight * 2)) - recalculateCoordinate(10 - 1), -1, screenRadius - (activityArcY - screenRadius) - recalculateCoordinate(7));
    }

    function drawStress(dc) {
        drawActivity(dc, STRESS, getLastHistoryValue(Toybox.SensorHistory.getStressHistory({:period=>1})), -1, 100, recalculateCoordinate(-40), screenRadius - (activity1Y - screenRadius + (halfFontHeight * 2)) - recalculateCoordinate(10 - 1), -1, screenRadius - (activityArcY - screenRadius) - recalculateCoordinate(7));
    }

    //activityType - 1 steps, 2 stairs, 3 body battery, 4 stress
    //activity1 - first line activity value
    //activity2 - second line activity value; -1 means "don't show activity2 value"
    //goal - activity goal
    //xShift - X position shift from middle of the screen
    //activity1Y - Y position of first line activity text
    //activity2Y - Y position of second line activity text
    //activityArcY - Y position of activity arc center
    function drawActivity(dc, activityType, activity1, activity2, goal, xShift, activity1Y, activity2Y, activityArcY) {
        var progressXShift = xShift - recalculateCoordinate(5);

        dc.setColor(activityColor, Graphics.COLOR_TRANSPARENT);
        if (activity1 > 0 || activity2.toFloat() > 0 || showZero) {
            dc.setPenWidth(1);
            dc.drawArc(screenRadius - progressXShift, activityArcY, halfFontHeight - 1, Graphics.ARC_COUNTER_CLOCKWISE, startActivityAngle, endActivityAngle);
            dc.drawArc(screenRadius - progressXShift, activityArcY, halfFontHeight + 3, Graphics.ARC_COUNTER_CLOCKWISE, startActivityAngle, endActivityAngle);
        }

        if (activity1 > 0 || showZero) {
            if (activity1 == 999999) {
                dc.drawText(screenRadius - xShift, activity1Y, font, "--", Graphics.TEXT_JUSTIFY_LEFT);
                activity1 = 0;
            } else {
                dc.drawText(screenRadius - xShift, activity1Y, font, activity1, Graphics.TEXT_JUSTIFY_LEFT);
            }

            dc.setPenWidth(recalculateCoordinate(5));

            if (activity1 > 0) {
                dc.setColor(activityProgressGoalColor, Graphics.COLOR_TRANSPARENT);
                var endAngle = (startActivityAngle + ((activity1/goal.toFloat()) * 210));
                if (endAngle >= endActivityAngle) {
                    endAngle = endActivityAngle;
                    dc.setColor(activityReachedGoalColor, Graphics.COLOR_TRANSPARENT);
                } else if (endAngle.toNumber() == startActivityAngle) {
                    endAngle = startActivityAngle + 1;
                }
                if ((activityType == BODY_BATTERY && activity1 > 25) || (activityType == STRESS && activity1 < 75)) {
                    dc.setColor(bbStressArcColor, Graphics.COLOR_TRANSPARENT);
                } else if (activityType >= BODY_BATTERY) {
                    dc.setColor(bbStressWarningArcColor, Graphics.COLOR_TRANSPARENT);
                }
                dc.drawArc(screenRadius - progressXShift, activityArcY, halfFontHeight + 1, Graphics.ARC_COUNTER_CLOCKWISE, startActivityAngle, endAngle);
            }
        }
        if (activityType <= STAIRS && (activity2.toFloat() > 0 || showZero)) {
            dc.setColor(activityColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(screenRadius - xShift + recalculateCoordinate(20), activity2Y, font, activity2, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    function getLastHistoryValue(iterator) {
        var value = iterator.next();
        if (value == null) {
            return 999999;
        } else {
            return value.data.toNumber();
        }
    }

    //coordinates are optimized for 260x260 resolution (vivoactive4)
    //this method recalculates coordinates for watches with different resolution
    function recalculateCoordinate(coordinate) {
        return (coordinate * screenResolutionRatio).toNumber();
    }

    function drawHR(dc, refreshHR) {
        var hr = 0;
        var hrText;
        var activityInfo;

        if (refreshHR) {
            activityInfo = Activity.getActivityInfo();
            if (activityInfo != null) {
                hr = activityInfo.currentHeartRate;
                lastMeasuredHR = hr;
            }
        } else {
            hr = lastMeasuredHR;
        }

        if (hr == null || hr == 0) {
            hrText = "";
        } else {
            hrText = hr.format("%i");
        }

        dc.setClip(screenRadius - halfHRTextWidth, recalculateCoordinate(30), hrTextDimension[0], hrTextDimension[1]);

        dc.setColor(hrColor, Graphics.COLOR_TRANSPARENT);
        //debug rectangle
        //dc.drawRectangle(screenRadius - halfHRTextWidth, recalculateCoordinate(30), hrTextDimension[0], hrTextDimension[1]);
        dc.drawText(screenRadius, recalculateCoordinate(30), font, hrText, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function shouldPowerSave() {
        if (!powerSaver || isAwake) {
            return false;
        }

        var time = System.getClockTime();
        var timeMinOfDay = (time.hour * 60) + time.min;        
        //check if we're in power saver time window
        var inPowerSaverWindow = false;
        if (startPowerSaverMin <= endPowerSaverMin) {
            inPowerSaverWindow = (startPowerSaverMin <= timeMinOfDay && timeMinOfDay < endPowerSaverMin);
        } else {
            inPowerSaverWindow = (startPowerSaverMin <= timeMinOfDay || timeMinOfDay < endPowerSaverMin);
        }
        return inPowerSaverWindow;
    }

    function drawLostAndFound(dc) {
        //clean the screen
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(screenRadius, screenRadius, screenRadius + 2);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        drawMessage(dc, "If found, contact:", screenRadius, recalculateCoordinate(45), recalculateCoordinate(230));
        drawMessage(dc, phone, screenRadius, recalculateCoordinate(105), recalculateCoordinate(260));
        drawMessage(dc, email, screenRadius, recalculateCoordinate(138), recalculateCoordinate(260));
        drawMessage(dc, "Thank you!", screenRadius, recalculateCoordinate(195), recalculateCoordinate(220));
    }

    function drawMessage(dc, msg, screenRadius, posY, width) {
        var font = Graphics.FONT_SMALL;
        var textDimension = dc.getTextDimensions(msg, font);

        if (textDimension[0] > width) {
            font = Graphics.FONT_TINY;
            textDimension = dc.getTextDimensions(msg, font);
            if (textDimension[0] > width) {
                font = Graphics.FONT_XTINY;
            }
        }

        dc.drawText(screenRadius, posY, font, msg, Graphics.TEXT_JUSTIFY_CENTER);
    }

	function computeSunConstants() {
    	var posInfo = Toybox.Position.getInfo();
    	if (posInfo != null && posInfo.position != null) {
	    	var sc = new SunCalc();
	    	var time_now = Time.now();    	
	    	var loc = posInfo.position.toRadians();
    		var hasLocation = (loc[0].format("%.2f").equals("3.14") && loc[1].format("%.2f").equals("3.14")) || (loc[0] == 0 && loc[1] == 0) ? false : true;

	    	if (!hasLocation && locationLatitude != offSettingFlag) {
	    		loc[0] = locationLatitude;
	    		loc[1] = locationLongitude;
	    	}

	    	if (hasLocation) {
				Application.getApp().setProperty("locationLatitude", loc[0]);
				Application.getApp().setProperty("locationLongitude", loc[1]);
				locationLatitude = loc[0];
				locationLongitude = loc[1];
			}
			
	        sunriseStartAngle = computeSunAngle(sc.calculate(time_now, loc, SunCalc.DAWN));	        
	        sunriseEndAngle = computeSunAngle(sc.calculate(time_now, loc, SunCalc.SUNRISE));
	        sunsetStartAngle = computeSunAngle(sc.calculate(time_now, loc, SunCalc.SUNSET));
	        sunsetEndAngle = computeSunAngle(sc.calculate(time_now, loc, SunCalc.DUSK));

            if (((sunriseStartAngle < sunsetStartAngle) && (sunriseStartAngle > sunsetEndAngle)) ||
                    ((sunriseEndAngle < sunsetStartAngle) && (sunriseEndAngle > sunsetEndAngle)) ||
                    ((sunsetStartAngle < sunriseStartAngle) && (sunsetStartAngle > sunriseEndAngle)) ||
                    ((sunsetEndAngle < sunriseStartAngle) && (sunsetEndAngle > sunriseEndAngle))) {
                sunArcsOffset = recalculateCoordinate(10);
            } else {
                sunArcsOffset = recalculateCoordinate(12);
            }
        }
	}

	function computeSunAngle(time) {
        var timeInfo = Time.Gregorian.info(time, Time.FORMAT_SHORT);       
        var angle = ((timeInfo.hour % 12) * 60.0) + timeInfo.min;
        angle = angle / (12 * 60.0) * Math.PI * 2;
        return Math.toDegrees(-angle + Math.PI/2);	
	}

	function drawSun(dc) {
        dc.setPenWidth(1);

        var arcWidth = recalculateCoordinate(9);
        if (sunArcsOffset == recalculateCoordinate(10)) {
            arcWidth = recalculateCoordinate(7);
        }

        //draw sunrise
        if (sunriseColor != offSettingFlag) {
	        if (sunriseStartAngle > sunriseEndAngle) {
    	        dc.setColor(sunriseColor, Graphics.COLOR_TRANSPARENT);
                var step = (sunriseStartAngle - sunriseEndAngle) / arcWidth;
                for (var i = 0; i < arcWidth; i++) {
                    if (sunArcsOffset == recalculateCoordinate(10)) {
				        dc.drawArc(screenRadius, screenRadius, screenRadius - recalculateCoordinate(20) + i, Graphics.ARC_CLOCKWISE, sunriseStartAngle - (step * i), sunriseEndAngle);
                    } else {
				        dc.drawArc(screenRadius, screenRadius, screenRadius - recalculateCoordinate(12) - i, Graphics.ARC_CLOCKWISE, sunriseStartAngle - (step * i), sunriseEndAngle);
                    }
                }
			} else {
		        dc.setColor(sunriseColor, Graphics.COLOR_TRANSPARENT);
    			dc.drawArc(screenRadius, screenRadius, screenRadius - recalculateCoordinate(17), Graphics.ARC_COUNTER_CLOCKWISE, sunriseStartAngle, sunriseEndAngle);
			}
		}

        //draw sunset
        if (sunsetColor != offSettingFlag) {
	        if (sunsetStartAngle > sunsetEndAngle) {
    	        dc.setColor(sunsetColor, Graphics.COLOR_TRANSPARENT);
                var step = (sunsetStartAngle - sunsetEndAngle) / arcWidth;
                for (var i = 0; i < arcWidth; i++) {
				    dc.drawArc(screenRadius, screenRadius, screenRadius - sunArcsOffset - i, Graphics.ARC_CLOCKWISE, sunsetStartAngle, sunsetEndAngle + (step * i));
                }
			} else {
    	        dc.setColor(sunsetColor, Graphics.COLOR_TRANSPARENT);
				dc.drawArc(screenRadius, screenRadius, screenRadius - sunArcsOffset, Graphics.ARC_COUNTER_CLOCKWISE, sunsetStartAngle, sunsetEndAngle);
			}
		}
	}

}
