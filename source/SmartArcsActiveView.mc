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
    var curClip;
    var fullScreenRefresh;
    var offscreenBuffer;
    var offSettingFlag = -999;
    var font = Graphics.FONT_TINY;
    var lastMeasuredHR;
    var powerSaverDrawn = false;
    var sunArcsOffset;

    //global variables for pre-computation
    var screenWidth;
    var screenRadius;
    var activity1Y;
    var activity2Y;
    var activityArcY;
    var halfFontHeight;
    var ticks = null;
    var hourHandLength;
    var minuteHandLength;
    var secondHandLength;
    var handsTailLength;
    var startActivityAngle = 90;
    var endActivityAngle = 300;
    var hrTextDimension;
    var halfHRTextWidth;
    var startPowerSaverMin;
    var endPowerSaverMin;
    var powerSaverIconRatio;
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
    var secondHandColor;
    var hourHandWidth;
    var minuteHandWidth;
    var showSecondHand;
    var secondHandWidth;
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
    var dateColor;
    var ticksColor;
    var ticks1MinWidth;
    var ticks5MinWidth;
    var ticks15MinWidth;
    var useBatterySecondHandColor;
    var oneColor;
    var handsOnTop;
    var showBatteryIndicator;
    var dateFormat;
    var showZero;
    var hrColor;
    var hrRefreshInterval;
    var powerSaver;
    var powerSaverRefreshInterval;
    var powerSaverIconColor;
    var sunriseColor;
    var sunsetColor;

    function initialize() {
        WatchFace.initialize();
    }

    //load resources here
    function onLayout(dc) {
        //if this device supports BufferedBitmap, allocate the buffers we use for drawing
        if (Toybox.Graphics has :BufferedBitmap) {
            //Allocate a full screen size buffer to draw the background image of the watchface.
            //This is used to facilitate blanking the second hand during partial updates of the display
            offscreenBuffer = new Graphics.BufferedBitmap({
                :width => dc.getWidth(),
                :height => dc.getHeight()
            });
        } else {
            offscreenBuffer = null;
        }

        partialUpdatesAllowed = (Toybox.WatchUi.WatchFace has :onPartialUpdate);
        floorsClimbedSupported = (Toybox.ActivityMonitor.Info has :floorsClimbed);
        loadUserSettings();
        computeConstants(dc);
		computeSunConstants();
        fullScreenRefresh = true;

        curClip = null;
    }

    //called when this View is brought to the foreground. Restore
    //the state of this View and prepare it to be shown. This includes
    //loading resources into memory.
    function onShow() {
    }

    //update the view
    function onUpdate(dc) {
        var clockTime = System.getClockTime();

		//refresh whole screen before drawing power saver icon
        if (powerSaverDrawn && shouldPowerSave()) {
            //should be screen refreshed in given intervals?
            if (powerSaverRefreshInterval == offSettingFlag || !(clockTime.min % powerSaverRefreshInterval == 0)) {
                return;
            }
        }

        powerSaverDrawn = false;

        var deviceSettings = System.getDeviceSettings();
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
            dc.clearClip();
            curClip = null;
            //if we have an offscreen buffer that we are using to draw the background,
            //set the draw context of that buffer as our target.
            targetDc = offscreenBuffer.getDc();
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

        if (handsOnTop) {
            drawHands(targetDc, clockTime);
        }

        if (isAwake && showSecondHand == 1) {
            drawSecondHand(targetDc, clockTime);
        }

        //output the offscreen buffers to the main display if required.
        drawBackground(dc);

        if (shouldPowerSave()) {
            drawPowerSaverIcon(dc);
            return;
        }

        if (partialUpdatesAllowed && (hrColor != offSettingFlag || showSecondHand == 2)) {
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
            secondHandColor = app.getProperty("secondHandColor");
            activityProgressGoalColor = app.getProperty("activityProgressGoalColor");
            activityReachedGoalColor = app.getProperty("activityReachedGoalColor");
    		sunriseColor = app.getProperty("sunriseColor");
			sunsetColor = app.getProperty("sunsetColor");
        } else {
            notificationColor = oneColor;
            bluetoothColor = oneColor;
            dndColor = oneColor;
            alarmColor = oneColor;
            secondHandColor = oneColor;
            activityProgressGoalColor = oneColor;
            activityReachedGoalColor = oneColor;
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
        showSecondHand = app.getProperty("showSecondHand");
        if (showSecondHand > 0) {
            secondHandWidth = app.getProperty("secondHandWidth");
        }
        activityColor = app.getProperty("activityColor");
        dateColor = app.getProperty("dateColor");
        showZero = app.getProperty("showZero");
        hrColor = app.getProperty("hrColor");

        useBatterySecondHandColor = app.getProperty("useBatterySecondHandColor");

        if (dateColor != offSettingFlag) {
            dateFormat = app.getProperty("dateFormat");
        }

        if (hrColor != offSettingFlag) {
            hrRefreshInterval = app.getProperty("hrRefreshInterval");
            if (showSecondHand == 2) {
                showSecondHand = 1;
            }
        }

        handsOnTop = app.getProperty("handsOnTop");

        showBatteryIndicator = app.getProperty("showBatteryIndicator");

        var power = app.getProperty("powerSaver");
        if (power == 1) {
        	powerSaver = false;
    	} else {
    		powerSaver = true;
            var powerSaverBeginning;
            var powerSaverEnd;
            if (power == 2) {
                powerSaverBeginning = app.getProperty("powerSaverBeginning");
                powerSaverEnd = app.getProperty("powerSaverEnd");
            } else {
                powerSaverBeginning = "00:00";
                powerSaverEnd = "23:59";
            }
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
		powerSaverRefreshInterval = app.getProperty("powerSaverRefreshInterval");
		powerSaverIconColor = app.getProperty("powerSaverIconColor");
		
		locationLatitude = app.getProperty("locationLatitude");
		locationLongitude = app.getProperty("locationLongitude");

        //ensure that screen will be refreshed when settings are changed 
    	powerSaverDrawn = false;   	
    }

    //pre-compute values which don't need to be computed on each update
    function computeConstants(dc) {
        screenWidth = dc.getWidth();
        screenRadius = screenWidth / 2;

        //computes hand lenght for watches with different screen resolution than 240x240
        var screenResolutionRatio = screenWidth / 240.0;
        hourHandLength = (60 * screenResolutionRatio).toNumber();
        minuteHandLength = (90 * screenResolutionRatio).toNumber();
        secondHandLength = (100 * screenResolutionRatio).toNumber();
        handsTailLength = (15 * screenResolutionRatio).toNumber();
        
        powerSaverIconRatio = screenResolutionRatio; //big icon
        if (powerSaverRefreshInterval != offSettingFlag) {
            powerSaverIconRatio = 0.6 * screenResolutionRatio; //small icon
        }

        if (!((ticksColor == offSettingFlag) ||
            (ticksColor != offSettingFlag && ticks1MinWidth == 0 && ticks5MinWidth == 0 && ticks15MinWidth == 0))) {
            //array of ticks coordinates
            computeTicks();
        }

        //Y coordinates of activities
        halfFontHeight = Graphics.getFontHeight(font) / 2;
        activity1Y = screenRadius + 10;
        activity2Y = screenRadius + 10 + Graphics.getFontAscent(font);
        activityArcY = activity1Y + 1 + halfFontHeight;

        hrTextDimension = dc.getTextDimensions("888", Graphics.FONT_TINY); //to compute correct clip boundaries
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
                    ticks[i] = computeTickRectangle(angle, 20, ticks15MinWidth);
                }
            } else if ((i % 5) == 0) { //5-minute tick
                if (ticks5MinWidth > 0) {
                    ticks[i] = computeTickRectangle(angle, 20, ticks5MinWidth);
                }
            } else if (ticks1MinWidth > 0) { //1-minute tick
                ticks[i] = computeTickRectangle(angle, 10, ticks1MinWidth);
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
        dc.setPenWidth(10);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(screenRadius, screenRadius, screenRadius - 5, arcDirection, startAngle, endAngle);
    }

    function drawTicks(dc) {
        var coord = new [4];
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
            drawHand(dc, handsOutlineColor, computeHandRectangle(hourAngle, hourHandLength + 2, handsTailLength + 2, hourHandWidth + 4));
        }
        drawHand(dc, handsColor, computeHandRectangle(hourAngle, hourHandLength, handsTailLength, hourHandWidth));

        //draw minute hand
        minAngle = (clockTime.min / 60.0) * Math.PI * 2;
        if (handsOutlineColor != offSettingFlag) {
            drawHand(dc, handsOutlineColor, computeHandRectangle(minAngle, minuteHandLength + 2, handsTailLength + 2, minuteHandWidth + 4));
        }
        drawHand(dc, handsColor, computeHandRectangle(minAngle, minuteHandLength, handsTailLength, minuteHandWidth));

        //draw bullet
        var bulletRadius = hourHandWidth > minuteHandWidth ? hourHandWidth / 2 : minuteHandWidth / 2;
        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(screenRadius, screenRadius, bulletRadius + 1);
        if (showSecondHand == 2) {
            dc.setPenWidth(secondHandWidth);
            dc.setColor(getSecondHandColor(), Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(screenRadius, screenRadius, bulletRadius + 2);
        } else {
            dc.setPenWidth(bulletRadius);
            dc.setColor(handsColor,Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(screenRadius, screenRadius, bulletRadius + 2);
        }
    }

    function drawSecondHand(dc, clockTime) {
        var secAngle;
        var secondHandColor = getSecondHandColor();

        //if we are out of sleep mode, draw the second hand directly in the full update method.
        secAngle = (clockTime.sec / 60.0) * Math.PI * 2;
        if (handsOutlineColor != offSettingFlag) {
            drawHand(dc, handsOutlineColor, computeHandRectangle(secAngle, secondHandLength + 2, handsTailLength + 2, secondHandWidth + 4));
        }
        drawHand(dc, secondHandColor, computeHandRectangle(secAngle, secondHandLength, handsTailLength, secondHandWidth));

        //draw center bullet
        var bulletRadius = hourHandWidth > minuteHandWidth ? hourHandWidth / 2 : minuteHandWidth / 2;
        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(screenRadius, screenRadius, bulletRadius + 1);
        dc.setPenWidth(secondHandWidth);
        dc.setColor(secondHandColor, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(screenRadius, screenRadius, bulletRadius + 2);
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

    function getSecondHandColor() {
        var color;
        if (oneColor != offSettingFlag) {
            color = oneColor;
        } else if (useBatterySecondHandColor) {
            var batStat = System.getSystemStats().battery;
            if (batStat > 30) {
                color = battery100Color;
            } else if (batStat <= 30 && batStat > 15) {
                color = battery30Color;
            } else {
                color = battery15Color;
            }
        } else {
            color = secondHandColor;
        }

        return color;
    }

    //Handle the partial update event
    function onPartialUpdate(dc) {
		//refresh whole screen before drawing power saver icon
        if (powerSaverDrawn && shouldPowerSave()) {
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

        if (showSecondHand == 2) {
            var secAngle = (clockSeconds / 60.0) * Math.PI * 2;
            var secondHandPoints = computeHandRectangle(secAngle, secondHandLength, handsTailLength, secondHandWidth);

            //update the cliping rectangle to the new location of the second hand.
            curClip = getBoundingBox(secondHandPoints);

            var bboxWidth = curClip[1][0] - curClip[0][0] + 1;
            var bboxHeight = curClip[1][1] - curClip[0][1] + 1;
            //merge clip boundaries with HR area
            if (hrColor != offSettingFlag) {
                //top Y position
                if (curClip[0][1] > 70) {
                    bboxHeight = (curClip[0][1] - 70) + bboxHeight;
                    curClip[0][1] = 70;
                }
                //left X position
                if (curClip[0][0] > (screenRadius - halfHRTextWidth)) {
                    curClip[0][0] = screenRadius - halfHRTextWidth;
                    bboxWidth = curClip[1][0] - curClip[0][0];
                }
                //right X position
                if (curClip[1][0] < (screenRadius + halfHRTextWidth)) {
                    bboxWidth = screenRadius + halfHRTextWidth - curClip[0][0];
                }
            }
            dc.setClip(curClip[0][0], curClip[0][1], bboxWidth, bboxHeight);

            if (hrColor != offSettingFlag) {
                drawHR(dc, refreshHR);
            }

            //draw the second hand to the screen.
            dc.setColor(getSecondHandColor(), Graphics.COLOR_TRANSPARENT);
            //debug rectangle
            //dc.drawRectangle(curClip[0][0], curClip[0][1], bboxWidth, bboxHeight);
            dc.fillPolygon(secondHandPoints);

            //draw center bullet
            var bulletRadius = hourHandWidth > minuteHandWidth ? hourHandWidth / 2 : minuteHandWidth / 2;
            dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(screenRadius, screenRadius, bulletRadius + 1);
        }

        //draw HR
        if (hrColor != offSettingFlag && showSecondHand != 2) {
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
    function getBoundingBox( points ) {
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
        var dateString;
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
        dc.drawText(screenRadius, 35, font, dateString, Graphics.TEXT_JUSTIFY_CENTER);
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

        drawActivity(dc, steps, distance, stepsGoal, 70);
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

        drawActivity(dc, floorsClimbed, floorsDescended.toString(), floorsGoal, -30);
    }

    function drawActivity(dc, activity1, activity2, goal, xShift) {
        var progressXShift = xShift - 5;

        dc.setColor(activityColor, Graphics.COLOR_TRANSPARENT);
        if (activity1 > 0 || showZero) {
            dc.drawText(screenRadius - xShift, activity1Y, font, activity1, Graphics.TEXT_JUSTIFY_LEFT);

            dc.setPenWidth(1);
            dc.drawArc(screenRadius - progressXShift, activityArcY, halfFontHeight - 2, Graphics.ARC_COUNTER_CLOCKWISE, startActivityAngle, endActivityAngle);
            dc.drawArc(screenRadius - progressXShift, activityArcY, halfFontHeight + 2, Graphics.ARC_COUNTER_CLOCKWISE, startActivityAngle, endActivityAngle);

            dc.setColor(activityProgressGoalColor, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(5);

            if (activity1 > 0) {
                var endAngle = (startActivityAngle + ((activity1/goal.toFloat()) * 210));
                if (endAngle >= endActivityAngle) {
                    endAngle = endActivityAngle;
                    dc.setColor(activityReachedGoalColor, Graphics.COLOR_TRANSPARENT);
                } else if (endAngle.toNumber() == startActivityAngle) {
                    endAngle = startActivityAngle + 1;
                }
                dc.drawArc(screenRadius - progressXShift, activityArcY, halfFontHeight, Graphics.ARC_COUNTER_CLOCKWISE, startActivityAngle, endAngle);
            }
        }
        if (activity2.toFloat() > 0 || showZero) {
            dc.setColor(activityColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(screenRadius - xShift + 20, activity2Y, font, activity2, Graphics.TEXT_JUSTIFY_LEFT);
        }
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

        if (showSecondHand != 2) {
            dc.setClip(screenRadius - halfHRTextWidth, 70, hrTextDimension[0], hrTextDimension[1]);
        }

        dc.setColor(hrColor, Graphics.COLOR_TRANSPARENT);
        //debug rectangle
        //dc.drawRectangle(screenRadius - halfHRTextWidth, 70, hrTextDimension[0], hrTextDimension[1]);
        dc.drawText(screenRadius, 70, Graphics.FONT_TINY, hrText, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function shouldPowerSave() {
        if (powerSaver && !isAwake) {
            var refreshDisplay = true;
            var time = System.getClockTime();
            var timeMinOfDay = (time.hour * 60) + time.min;

            if (startPowerSaverMin <= endPowerSaverMin) {
                if ((startPowerSaverMin <= timeMinOfDay) && (timeMinOfDay < endPowerSaverMin)) {
                    refreshDisplay = false;
                }
            } else {
                if ((startPowerSaverMin <= timeMinOfDay) || (timeMinOfDay < endPowerSaverMin)) {
                    refreshDisplay = false;
                }
        	}
             return !refreshDisplay;
        } else {
            return false;
        }
    }

    function drawPowerSaverIcon(dc) {
        dc.setColor(handsColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(screenRadius, screenRadius, 45 * powerSaverIconRatio);
        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(screenRadius, screenRadius, 40 * powerSaverIconRatio);
        dc.setColor(handsColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(screenRadius - (13 * powerSaverIconRatio), screenRadius - (23 * powerSaverIconRatio), 26 * powerSaverIconRatio, 51 * powerSaverIconRatio);
        dc.fillRectangle(screenRadius - (4 * powerSaverIconRatio), screenRadius - (27 * powerSaverIconRatio), 8 * powerSaverIconRatio, 5 * powerSaverIconRatio);
        if (oneColor == offSettingFlag) {
            dc.setColor(powerSaverIconColor, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(oneColor, Graphics.COLOR_TRANSPARENT);
        }
        dc.fillRectangle(screenRadius - (10 * powerSaverIconRatio), screenRadius - (20 * powerSaverIconRatio), 20 * powerSaverIconRatio, 45 * powerSaverIconRatio);

        powerSaverDrawn = true;
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
                sunArcsOffset = 13;
            } else {
                sunArcsOffset = 17;
            }
        }
	}

	function computeSunAngle(time) {
        var timeInfo = Time.Gregorian.info(time, Time.FORMAT_SHORT);       
        var angle = ((timeInfo.hour % 12) * 60.0) + timeInfo.min;
        angle = angle / (12 * 60.0) * Math.PI * 2;
        return -(angle - Math.PI/2) * 180 / Math.PI;	
	}

	function drawSun(dc) {
        dc.setPenWidth(7);

        //draw sunrise
        if (sunriseColor != offSettingFlag) {
	        dc.setColor(sunriseColor, Graphics.COLOR_TRANSPARENT);
	        if (sunriseStartAngle > sunriseEndAngle) {
				dc.drawArc(screenRadius, screenRadius, screenRadius - 17, Graphics.ARC_CLOCKWISE, sunriseStartAngle, sunriseEndAngle);
			} else {
				dc.drawArc(screenRadius, screenRadius, screenRadius - 17, Graphics.ARC_COUNTER_CLOCKWISE, sunriseStartAngle, sunriseEndAngle);
			}
		}

        //draw sunset
        if (sunsetColor != offSettingFlag) {
	        dc.setColor(sunsetColor, Graphics.COLOR_TRANSPARENT);
	        if (sunsetStartAngle > sunsetEndAngle) {
				dc.drawArc(screenRadius, screenRadius, screenRadius - sunArcsOffset, Graphics.ARC_CLOCKWISE, sunsetStartAngle, sunsetEndAngle);
			} else {
				dc.drawArc(screenRadius, screenRadius, screenRadius - sunArcsOffset, Graphics.ARC_COUNTER_CLOCKWISE, sunsetStartAngle, sunsetEndAngle);
			}
		}
	}
	
}
