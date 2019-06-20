using Toybox.ActivityMonitor;
using Toybox.Application;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;

class SmartArcsActiveView extends WatchUi.WatchFace {

    var deviceSettings;
    var activityInfo;
    var arcPenWidth;
    var isAwake = false;
    var offSettingFlag = -999;
    var font = Graphics.FONT_TINY;
    var precompute;

    // variables for pre-computation
    var screenWidth;
    var screenRadius;
    var arcRadius;
    var twoPI = Math.PI * 2;
    var activity1Y;
    var activity2Y;
    var activityArcY;
    var halfFontHeight;
    var ticks;
    var showTicks;
    var startActivityAngle = 90;
    var endActivityAngle = 300;

    // user settings
    var bgColor;
    var handsColor;
    var handsOutlineColor;
    var secondHandColor;
    var hourHandWidth;
    var minuteHandWidth;
    var secondHandWidth;
    var hourHandLength;
    var minuteHandLength;
    var secondHandLength;
    var handsTailLength;
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
    var ticks1MinLength;
    var ticks5MinLength;
    var ticks15MinLength;
    var useBatterySecondHandColor;
    var oneColor;
    var handsOnTop;
    var showBatteryIndicator;
    var dateFormat;
    var showZero;

    function initialize() {
        loadUserSettings();
        WatchFace.initialize();
    }

    // Load resources here
    function onLayout(dc) {
        setLayout(Rez.Layouts.WatchFace(dc));
    }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() {
    }

    // Update the view
    function onUpdate(dc) {
        deviceSettings = System.getDeviceSettings();
        activityInfo = ActivityMonitor.getInfo();

        // compute what does not need to be computed on each update
        if (precompute) {
            computeConstants(dc);
        }

        // clear the screen
        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(screenRadius, screenRadius, screenRadius + 2);

        if (showBatteryIndicator) {
            drawBattery(dc);
        }
        if (notificationColor != offSettingFlag) {
            drawNotifications(dc);
        }
        if (bluetoothColor != offSettingFlag) {
            drawBluetooth(dc);
        }
        if (dndColor != offSettingFlag) {
            drawDoNotDisturb(dc);
        }
        if (alarmColor != offSettingFlag) {
            drawAlarms(dc);
        }

        if (showTicks) {
            drawTicks(dc);
        }

        if (!handsOnTop) {
            drawHands(dc, System.getClockTime());
        }

        if (dateColor != offSettingFlag) {
            drawDate(dc, Time.today());
        }

        drawSteps(dc);
        drawFloors(dc);

        if (handsOnTop) {
            drawHands(dc, System.getClockTime());
        }
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    function onHide() {
    }

    // The user has just looked at their watch. Timers and animations may be started here.
    function onExitSleep() {
        isAwake = true;
    }

    // Terminate any active timers and prepare for slow updates.
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
        } else {
            notificationColor = oneColor;
            bluetoothColor = oneColor;
            dndColor = oneColor;
            alarmColor = oneColor;
            secondHandColor = oneColor;
            activityProgressGoalColor = oneColor;
            activityReachedGoalColor = oneColor;
        }
        bgColor = app.getProperty("bgColor");
        ticksColor = app.getProperty("ticksColor");
        if (ticksColor != offSettingFlag) {
            ticks1MinWidth = app.getProperty("ticks1MinWidth");
            ticks5MinWidth = app.getProperty("ticks5MinWidth");
            ticks15MinWidth = app.getProperty("ticks15MinWidth");
            ticks1MinLength = app.getProperty("ticks1MinLength");
            ticks5MinLength = app.getProperty("ticks5MinLength");
            ticks15MinLength = app.getProperty("ticks15MinLength");
        }
        handsColor = app.getProperty("handsColor");
        handsOutlineColor = app.getProperty("handsOutlineColor");
        hourHandWidth = app.getProperty("hourHandWidth");
        minuteHandWidth = app.getProperty("minuteHandWidth");
        secondHandWidth = app.getProperty("secondHandWidth");
        hourHandLength = app.getProperty("hourHandLength");
        minuteHandLength = app.getProperty("minuteHandLength");
        secondHandLength = app.getProperty("secondHandLength");
        handsTailLength = app.getProperty("handsTailLength");
        activityColor = app.getProperty("activityColor");
        dateColor = app.getProperty("dateColor");
        arcPenWidth = app.getProperty("indicatorWidth");
        showZero = app.getProperty("showZero");

        useBatterySecondHandColor = app.getProperty("useBatterySecondHandColor");

        if (dateColor != offSettingFlag) {
            dateFormat = app.getProperty("dateFormat");
        }

        handsOnTop = app.getProperty("handsOnTop");

        showBatteryIndicator = app.getProperty("showBatteryIndicator");

        precompute = true;
    }

    // pre-compute values which don't need to be computed on each update
    function computeConstants(dc) {
        screenWidth = dc.getWidth();
        screenRadius = screenWidth / 2;

        showTicks = ((ticksColor == offSettingFlag) ||
            (ticksColor != offSettingFlag && ticks1MinWidth == 0 && ticks5MinWidth == 0 && ticks15MinWidth == 0 &&
            ticks1MinLength == 0 && ticks5MinLength == 0 && ticks15MinLength == 0)) ? false : true;
        if (showTicks) {
            computeTicks(); // array of ticks coordinates
        }

        // Y coordinates of activities
        halfFontHeight = Graphics.getFontHeight(font) / 2;
        activity1Y = screenRadius + 10;
        activity2Y = screenRadius + 10 + Graphics.getFontAscent(font);
        activityArcY = activity1Y + 1 + halfFontHeight;

        arcRadius = screenRadius - (arcPenWidth / 2);

        precompute = false;
    }

    function drawTicks(dc) {
        dc.setColor(ticksColor, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 60; i++) {
            if (ticks[i] != null) {
                dc.fillPolygon(ticks[i]);
            }
        }
    }

    function getSecondHandColor() {
        var color;
        if (useBatterySecondHandColor) {
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

    function drawBluetooth(dc) {
        if (deviceSettings.phoneConnected == true) {
            dc.setColor(bluetoothColor, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(arcPenWidth);
            dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 0, -30);
        }
    }

    function drawDoNotDisturb(dc) {
        if (deviceSettings.doNotDisturb == true) {
            dc.setColor(dndColor, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(arcPenWidth);
            dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_COUNTER_CLOCKWISE, 270, -60);
        }
    }

    function drawBattery(dc) {
        var batStat = System.getSystemStats().battery;
        dc.setPenWidth(arcPenWidth);
        if (oneColor != offSettingFlag) {
            dc.setColor(oneColor, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
        } else {
            if (batStat > 30) {
                dc.setColor(battery100Color, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
                dc.setColor(battery30Color, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 180, 153);
                dc.setColor(battery15Color, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 180, 166.5);
            } else if (batStat <= 30 && batStat > 15){
                dc.setColor(battery30Color, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
                dc.setColor(battery15Color, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 180, 166.5);
            } else {
                dc.setColor(battery15Color, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
            }
        }
    }

    function drawAlarms(dc) {
        var alarms = deviceSettings.alarmCount;
        if (alarms > 0) {
            drawItems(dc, alarms, 270, alarmColor);
        }
    }

    function drawNotifications(dc) {
        var notifications = deviceSettings.notificationCount;
        if (notifications > 0) {
            drawItems(dc, notifications, 90, notificationColor);
        }
    }

    function drawItems(dc, count, angle, color) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(arcPenWidth);
        if (count < 11) {
            dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, angle, angle - 30 - ((count - 1) * 6));
        } else {
            dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, angle, angle - 90);
        }
    }

    function drawSteps(dc) {
        var steps = activityInfo.steps;
        var stepsGoal = activityInfo.stepGoal;
        var distance = activityInfo.distance;

        if (steps == null) {
            steps = 0;
        }
        if (stepsGoal == null) {
            stepsGoal = 0;
        }
        if (distance == null) {
            distance = 0;
        } else {
            if (deviceSettings.distanceUnits == System.UNIT_STATUTE) {
                distance = distance/1.609344;
            }
            distance = (distance/100000.0).format("%.2f");
        }

        drawActivity(dc, steps, distance, stepsGoal, 70);
    }

    function drawFloors(dc) {
        var floorsClimbed = activityInfo.floorsClimbed;
        var floorsDescended = activityInfo.floorsDescended;
        var floorsGoal = activityInfo.floorsClimbedGoal;

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
                if (endAngle > endActivityAngle) {
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

    function drawDate(dc, today) {
        var info = Gregorian.info(today, Time.FORMAT_MEDIUM);

        var dateString;
        switch (dateFormat) {
            case 0: dateString = info.day;
                    break;
            case 1: dateString = Lang.format("$1$ $2$", [info.day_of_week.substring(0, 3), info.day]);
                    break;
            case 2: dateString = Lang.format("$1$ $2$", [info.day, info.day_of_week.substring(0, 3)]);
                    break;
            case 3: dateString = Lang.format("$1$ $2$", [info.day, info.month.substring(0, 3)]);
                    break;
            case 4: dateString = Lang.format("$1$ $2$", [info.month.substring(0, 3), info.day]);
                    break;
        }
        dc.setColor(dateColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(screenRadius, 35, font, dateString, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawHands(dc, clockTime) {
        var hourAngle, minAngle, secAngle;

        //draw hour hand
        hourAngle = ((clockTime.hour % 12) * 60.0) + clockTime.min;
        hourAngle = hourAngle / (12 * 60.0) * twoPI;
        if (handsOutlineColor != offSettingFlag) {
            drawHand(dc, handsOutlineColor, computeHandRectangle(hourAngle, hourHandLength + 2, handsTailLength + 2, hourHandWidth + 4));
        }
        drawHand(dc, handsColor, computeHandRectangle(hourAngle, hourHandLength, handsTailLength, hourHandWidth));

        //draw minute hand
        minAngle = (clockTime.min / 60.0) * twoPI;
        if (handsOutlineColor != offSettingFlag) {
            drawHand(dc, handsOutlineColor, computeHandRectangle(minAngle, minuteHandLength + 2, handsTailLength + 2, minuteHandWidth + 4));
        }
        drawHand(dc, handsColor, computeHandRectangle(minAngle, minuteHandLength, handsTailLength, minuteHandWidth));

        //draw second hand
        var secondHandColor = -1;
        if (isAwake && secondHandWidth > 0 && secondHandLength > 0) {
            secondHandColor = getSecondHandColor();

            secAngle = (clockTime.sec / 60.0) *  twoPI;
            if (handsOutlineColor != offSettingFlag) {
                drawHand(dc, handsOutlineColor, computeHandRectangle(secAngle, secondHandLength + 2, handsTailLength + 2, secondHandWidth + 4));
            }
            drawHand(dc, secondHandColor, computeHandRectangle(secAngle, secondHandLength, handsTailLength, secondHandWidth));
        }

        //draw center bullet
        var bulletRadius = hourHandWidth > minuteHandWidth ? hourHandWidth / 2 : minuteHandWidth / 2;
        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(screenRadius, screenRadius, bulletRadius + 1);
        if (isAwake && secondHandWidth > 0 && secondHandLength > 0) {
            dc.setPenWidth(secondHandWidth);
            dc.setColor(secondHandColor, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(screenRadius, screenRadius, bulletRadius + 2);
        } else {
            dc.setPenWidth(bulletRadius);
            dc.setColor(handsColor,Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(screenRadius, screenRadius, bulletRadius + 2);
        }
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

    function computeTicks() {
        var angle;
        ticks = new [60];
        for (var i = 0; i < 60; i++) {
            angle = i * twoPI / 60.0;
            if ((i % 15) == 0) { //quarter tick
                if (ticks15MinWidth > 0 && ticks15MinLength > 0) {
                    ticks[i] = computeTickRectangle(angle, ticks15MinLength, ticks15MinWidth);
                }
            } else if ((i % 5) == 0) { //5-minute tick
                if (ticks5MinWidth > 0 && ticks5MinLength > 0) {
                    ticks[i] = computeTickRectangle(angle, ticks5MinLength, ticks5MinWidth);
                }
            } else if (ticks1MinWidth > 0 && ticks1MinLength > 0) { //1-minute tick
                ticks[i] = computeTickRectangle(angle, ticks1MinLength, ticks1MinWidth);
            }
        }
    }

}
