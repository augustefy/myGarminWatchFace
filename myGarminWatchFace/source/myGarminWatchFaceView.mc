import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.UserProfile;
import Toybox.Weather;
import Toybox.WatchUi;

class myGarminWatchFaceView extends WatchUi.WatchFace {

    const MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                    "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
    const DAYS = ["M", "T", "W", "T", "F", "S", "S"];

    // Référence : nouvelle lune du 6 janvier 2000, 18:14 UTC
    const NEW_MOON_EPOCH = 947182440;
    const SYNODIC_DAYS = 29.530588853;

    const JUSTIFY_CC = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

    // Géométrie
    private var _cx = 0;
    private var _cy = 0;
    private var _r = 0;

    // Thème (rempli par loadSettings)
    private var _accent = 0xFF6A00;
    private var _dial = 0;
    private var _dialInner = 0;
    private var _ink = 0;
    private var _muted = 0;
    private var _grid = 0;
    private var _disc = 0;
    private var _discRim = 0;
    private var _handDark = 0;
    private var _handLight = 0;
    private var _lume = 0;
    const DATE_RED = 0xD7102A;

    // Polices
    private var _fNumeral as FontType = Graphics.FONT_NUMBER_MILD;
    private var _fValue as FontType = Graphics.FONT_SMALL;
    private var _fValueBig as FontType = Graphics.FONT_MEDIUM;
    private var _fLabel as FontType = Graphics.FONT_XTINY;
    private var _fRing as FontType = Graphics.FONT_XTINY;
    private var _vector = false;

    // Cache : tout sauf les aiguilles et la fréquence cardiaque, redessiné chaque minute
    private var _buffer as BufferedBitmapReference? = null;
    private var _bufferKey = -1;
    private var _dirty = true;

    private var _sleeping = false;

    function initialize() {
        WatchFace.initialize();
        loadSettings();
    }

    function onLayout(dc as Dc) as Void {
        _cx = dc.getWidth() / 2;
        _cy = dc.getHeight() / 2;
        _r = _cx;
        loadFonts();
    }

    function onEnterSleep() as Void {
        _sleeping = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _sleeping = false;
        _dirty = true;
        WatchUi.requestUpdate();
    }

    function onSettingsChanged() as Void {
        loadSettings();
        _dirty = true;
    }

    // ---------- Réglages & polices ----------

    private function loadSettings() as Void {
        var accent = Application.Properties.getValue("AccentColor");
        _accent = accent instanceof Number ? accent : 0xFF6A00;

        var theme = Application.Properties.getValue("Theme");
        if (theme == 1) {
            _dial = 0x1B1C1E;
            _dialInner = 0x222326;
            _ink = 0xEDEDEA;
            _muted = 0x76777A;
            _grid = 0x36373A;
            _disc = 0x0B0B0C;
            _discRim = 0x4C4D50;
            _handDark = 0xF2F2EF;
            _handLight = 0xB9BABC;
            _lume = 0x1B1C1E;
        } else {
            _dial = 0xF3F2ED;
            _dialInner = 0xEAE9E3;
            _ink = 0x151515;
            _muted = 0x8C8B86;
            _grid = 0xD2D1CB;
            _disc = 0x111112;
            _discRim = 0xA4A39E;
            _handDark = 0x141414;
            _handLight = 0x3E3E3E;
            _lume = 0xFFFFFF;
        }
    }

    private function vectorFont(faces as Array<String>, size as Numeric) as VectorFont? {
        return Graphics.getVectorFont({:face => faces, :size => size.toNumber()});
    }

    private function loadFonts() as Void {
        if (!(Graphics has :getVectorFont)) {
            return;
        }
        var numeral = vectorFont(["BionicBold", "RobotoCondensedBold"], _r * 0.17);
        var value = vectorFont(["RobotoCondensedBold"], _r * 0.13);
        var valueBig = vectorFont(["RobotoCondensedBold"], _r * 0.17);
        var label = vectorFont(["RobotoCondensedBold"], _r * 0.065);
        var ring = vectorFont(["RobotoCondensedBold"], _r * 0.072);
        if (numeral != null && value != null && valueBig != null && label != null && ring != null) {
            _fNumeral = numeral;
            _fValue = value;
            _fValueBig = valueBig;
            _fLabel = label;
            _fRing = ring;
            _vector = true;
        }
    }

    // ---------- Rendu ----------

    function onUpdate(dc as Dc) as Void {
        var clock = System.getClockTime();

        // AMOLED en veille : affichage minimal pour éviter le marquage
        if (_sleeping && System.getDeviceSettings().requiresBurnInProtection) {
            drawSleep(dc, clock);
            return;
        }

        var key = clock.hour * 60 + clock.min;
        if (Graphics has :createBufferedBitmap) {
            var bitmap = _buffer != null ? _buffer.get() : null;
            if (bitmap == null) {
                _buffer = Graphics.createBufferedBitmap({:width => dc.getWidth(), :height => dc.getHeight()});
                bitmap = _buffer.get();
                _dirty = true;
            }
            if (_dirty || key != _bufferKey) {
                var bdc = (bitmap as BufferedBitmap).getDc();
                bdc.setAntiAlias(true);
                drawFace(bdc);
                _bufferKey = key;
                _dirty = false;
            }
            dc.drawBitmap(0, 0, _buffer);
        } else {
            drawFace(dc);
        }

        dc.setAntiAlias(true);
        drawHeartRate(dc, _cx, _cy + _r * 0.40, _r * 0.19);
        drawHands(dc, clock, !_sleeping);
    }

    private function drawFace(dc as Dc) as Void {
        var today = Gregorian.info(Time.now(), Time.FORMAT_SHORT);

        dc.setColor(_dial, _dial);
        dc.clear();

        drawSector(dc);
        drawTrack(dc);
        drawNumerals(dc);
        drawMonths(dc, today.month as Number);
        drawWeekdays(dc, today.day_of_week as Number);
        drawMoon(dc, _cx, _cy - _r * 0.39, _r * 0.068);
        drawDate(dc, today.day as Number);

        var vo2 = getVo2Max();
        drawGauge(dc, _cx - _r * 0.42, _cy, _r * 0.175,
                  vo2 == null ? null : (vo2 - 20) / 45.0,
                  vo2 == null ? "--" : vo2.toString(), :vo2);

        savePosition();
        var temp = getTemperature();
        drawGauge(dc, _cx + _r * 0.42, _cy, _r * 0.175,
                  temp == null ? null : (temp + 10) / 50.0,
                  temp == null ? "--" : temp.toString() + "°C", :temp);

        var stats = System.getSystemStats();
        drawBattery(dc, _cx - _r * 0.34, _cy + _r * 0.34, stats.battery);
        drawSleepScore(dc, _cx + _r * 0.34, _cy + _r * 0.34, getSleepScore());

        drawHeartRateDisc(dc, _cx, _cy + _r * 0.40, _r * 0.19);
    }

    // ---------- Données ----------

    private function getVo2Max() as Number? {
        var profile = UserProfile.getProfile();
        if (profile has :vo2maxRunning && profile.vo2maxRunning != null) {
            return profile.vo2maxRunning;
        }
        if (profile has :vo2maxCycling && profile.vo2maxCycling != null) {
            return profile.vo2maxCycling;
        }
        return null;
    }

    // Toujours en °C : Open-Meteo à ta position si la mesure a moins d'une heure, sinon météo Garmin
    private function getTemperature() as Number? {
        var temp = Application.Storage.getValue("temp");
        var at = Application.Storage.getValue("tempAt");
        if (temp instanceof Float && at instanceof Number && Time.now().value() - at < 3600) {
            return Math.round(temp).toNumber();
        }
        if (!(Toybox has :Weather)) {
            return null;
        }
        var conditions = Weather.getCurrentConditions();
        if (conditions == null || conditions.temperature == null) {
            return null;
        }
        return Math.round(conditions.temperature as Numeric).toNumber();
    }

    // Mémorise la position pour le service d'arrière-plan :
    // dernier fix GPS de la montre s'il date de moins d'une heure, sinon position du téléphone (météo)
    private function savePosition() as Void {
        var loc = null;
        var info = Position.getInfo();
        if (info.accuracy != Position.QUALITY_NOT_AVAILABLE && info.position != null
            && info.when != null && Time.now().compare(info.when) < 3600) {
            loc = info.position;
        }
        if (loc == null && Toybox has :Weather) {
            var conditions = Weather.getCurrentConditions();
            if (conditions != null) {
                loc = conditions.observationLocationPosition;
            }
        }
        if (loc == null) {
            return;
        }
        var deg = loc.toDegrees();
        var lat = deg[0].toFloat();
        var lon = deg[1].toFloat();
        if (lat == 0.0 && lon == 0.0) {
            return;
        }
        // N'écrire que si on a bougé d'environ 1 km
        var oldLat = Application.Storage.getValue("lat");
        var oldLon = Application.Storage.getValue("lon");
        if (oldLat instanceof Float && oldLon instanceof Float
            && (oldLat - lat).abs() < 0.01 && (oldLon - lon).abs() < 0.01) {
            return;
        }
        Application.Storage.setValue("lat", lat);
        Application.Storage.setValue("lon", lon);
    }

    private function getSleepScore() as Number? {
        if (!(Toybox has :Complications)) {
            return null;
        }
        try {
            var complication = Complications.getComplication(
                new Complications.Id(Complications.COMPLICATION_TYPE_SLEEP_SCORE));
            var value = complication.value;
            if (value instanceof Number || value instanceof Float || value instanceof Double) {
                return value.toNumber();
            }
        } catch (e) {
        }
        return null;
    }

    private function getHeartRate() as Number? {
        var info = Activity.getActivityInfo();
        if (info != null && info.currentHeartRate != null) {
            return info.currentHeartRate;
        }
        if (ActivityMonitor has :getHeartRateHistory) {
            var sample = ActivityMonitor.getHeartRateHistory(1, true).next();
            if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                return sample.heartRate;
            }
        }
        return null;
    }

    // ---------- Outils ----------

    // Angle façon montre : 0° à midi, sens horaire
    private function polarAt(x as Numeric, y as Numeric, angleDeg as Numeric, radius as Numeric) as [Numeric, Numeric] {
        var a = Math.toRadians(angleDeg - 90);
        return [x + radius * Math.cos(a), y + radius * Math.sin(a)];
    }

    private function polar(angleDeg as Numeric, radius as Numeric) as [Numeric, Numeric] {
        return polarAt(_cx, _cy, angleDeg, radius);
    }

    private function radialLine(dc as Dc, angleDeg as Numeric, r1 as Numeric, r2 as Numeric) as Void {
        var p1 = polar(angleDeg, r1);
        var p2 = polar(angleDeg, r2);
        dc.drawLine(p1[0], p1[1], p2[0], p2[1]);
    }

    // Texte qui suit le cercle, toujours lisible (sens inversé dans la moitié basse)
    private function ringText(dc as Dc, text as String, angleDeg as Numeric, radius as Numeric) as Void {
        if (_vector && dc has :drawRadialText) {
            var bottom = angleDeg > 90 && angleDeg < 270;
            dc.drawRadialText(_cx, _cy, _fRing, text, JUSTIFY_CC, 90 - angleDeg, radius,
                              bottom ? Graphics.RADIAL_TEXT_DIRECTION_COUNTER_CLOCKWISE
                                     : Graphics.RADIAL_TEXT_DIRECTION_CLOCKWISE);
        } else {
            var p = polar(angleDeg, radius);
            dc.drawText(p[0], p[1], Graphics.FONT_XTINY, text, JUSTIFY_CC);
        }
    }

    // Arc simple ; angles façon montre, du début vers la fin en sens horaire
    private function roundArc(dc as Dc, x as Numeric, y as Numeric, radius as Numeric,
                              width as Number, fromDeg as Numeric, toDeg as Numeric, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(width);
        dc.drawArc(x, y, radius, Graphics.ARC_CLOCKWISE, 90 - fromDeg, 90 - toDeg);
        dc.setPenWidth(1);
    }

    private function clamp01(v as Numeric) as Float {
        return (v < 0 ? 0.0 : (v > 1 ? 1.0 : v)).toFloat();
    }

    // Teinte (0–360°) → couleur RGB
    private function hsv(h as Float, s as Float, v as Float) as Number {
        var c = v * s;
        var hp = h / 60.0;
        var f = hp - Math.floor(hp / 2) * 2;
        var x = c * (1 - (f - 1).abs());
        var r = 0.0;
        var g = 0.0;
        var b = 0.0;
        if (hp < 1) { r = c; g = x; }
        else if (hp < 2) { r = x; g = c; }
        else if (hp < 3) { g = c; b = x; }
        else if (hp < 4) { g = x; b = c; }
        else if (hp < 5) { r = x; b = c; }
        else { r = c; b = x; }
        var m = v - c;
        return (((r + m) * 255).toNumber() << 16) | (((g + m) * 255).toNumber() << 8) | ((b + m) * 255).toNumber();
    }

    // Couleur d'une position t (0–1) sur l'échelle de la jauge
    private function gaugeColor(kind as Symbol, t as Float) as Number {
        if (kind == :vo2) {
            return hsv(280.0 * t, 0.72, 0.97);          // rouge → violet, par tout l'arc-en-ciel
        }
        return hsv(220.0 * (1 - t), 0.72, 0.97);        // bleu → rouge
    }

    // Arc de jauge en dégradé, de 7h30 jusqu'à la valeur ; chaque portion prend la couleur de sa position
    private function gradientArc(dc as Dc, x as Numeric, y as Numeric, radius as Numeric,
                                 width as Number, kind as Symbol, ratio as Float) as Void {
        var span = 270 * ratio;
        var steps = (span / 5).toNumber() + 1;
        var end = 225 + span;
        dc.setPenWidth(width);
        for (var i = 0; i < steps; i++) {
            var a0 = 225 + span * i / steps;
            var a1 = 225 + span * (i + 1) / steps + 1;
            if (a1 > end) { a1 = end; }
            dc.setColor(gaugeColor(kind, ratio * (i + 0.5) / steps), Graphics.COLOR_TRANSPARENT);
            dc.drawArc(x, y, radius, Graphics.ARC_CLOCKWISE, 90 - a0, 90 - a1);
        }
        dc.setPenWidth(1);
    }

    // ---------- Cadran ----------

    private function drawSector(dc as Dc) as Void {
        var inner = _r * 0.67;
        dc.setColor(_dialInner, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, _cy, inner);

        dc.setColor(_grid, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawCircle(_cx, _cy, inner);
        dc.drawCircle(_cx, _cy, inner - 7);
        for (var i = 0; i < 72; i++) {
            radialLine(dc, i * 5, inner - 7, inner);
        }
        // Rayons fins du secteur central
        for (var i = 0; i < 24; i++) {
            radialLine(dc, i * 15 + 7.5, _r * 0.24, inner - 7);
        }
        dc.drawCircle(_cx, _cy, _r * 0.24);
    }

    private function drawTrack(dc as Dc) as Void {
        // Léger anneau de bord pour donner de la profondeur
        dc.setColor(_grid, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawCircle(_cx, _cy, _r - 1);

        dc.setColor(_ink, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawCircle(_cx, _cy, _r - 15);

        for (var i = 0; i < 60; i++) {
            if (i % 5 == 0) {
                dc.setPenWidth(5);
                radialLine(dc, i * 6, _r - 4, _r - 24);
            } else {
                dc.setPenWidth(2);
                radialLine(dc, i * 6, _r - 5, _r - 15);
            }
        }
        dc.setPenWidth(1);

        // Index de midi en couleur d'accent
        dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(5);
        radialLine(dc, 0, _r - 4, _r - 24);
        dc.setPenWidth(1);
    }

    private function drawNumerals(dc as Dc) as Void {
        dc.setColor(_ink, Graphics.COLOR_TRANSPARENT);
        for (var h = 1; h <= 12; h++) {
            var p = polar(h * 30, _r * 0.785);
            dc.drawText(p[0], p[1], _fNumeral, h.toString(), JUSTIFY_CC);
        }
    }

    private function drawMonths(dc as Dc, month as Number) as Void {
        for (var m = 0; m < 12; m++) {
            dc.setColor(m + 1 == month ? DATE_RED : _muted, Graphics.COLOR_TRANSPARENT);
            ringText(dc, MONTHS[m], m * 30 + 15, _r * 0.79);
        }
    }

    private function drawWeekdays(dc as Dc, dayOfWeek as Number) as Void {
        // Gregorian : 1 = dimanche ... 7 = samedi → index lundi = 0
        var current = (dayOfWeek + 5) % 7;
        for (var i = 0; i < 7; i++) {
            var angle = -33 + i * 11;
            dc.setColor(i == current ? DATE_RED : _ink, Graphics.COLOR_TRANSPARENT);
            ringText(dc, DAYS[i], angle, _r * 0.575);
            if (i == current) {
                var dot = polar(angle, _r * 0.505);
                dc.fillCircle(dot[0], dot[1], 2.5);
            }
        }
    }

    private function drawMoon(dc as Dc, x as Numeric, y as Numeric, radius as Numeric) as Void {
        var days = (Time.now().value() - NEW_MOON_EPOCH) / 86400.0;
        var phase = days / SYNODIC_DAYS;
        phase = phase - Math.floor(phase);

        dc.setColor(_discRim, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, radius + 3);
        dc.setColor(0x26272A, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, radius);

        // Partie éclairée : entre le bord du disque et le terminateur (ellipse)
        var k = Math.cos(2 * Math.PI * phase);
        var side = phase < 0.5 ? 1 : -1;
        var steps = 18;
        var limb = [] as Array<[Numeric, Numeric]>;
        var term = [] as Array<[Numeric, Numeric]>;
        for (var i = 0; i <= steps; i++) {
            var dy = -radius + 2.0 * radius * i / steps;
            var s = Math.sqrt(radius * radius - dy * dy);
            limb.add([x + side * s, y + dy]);
            term.add([x + side * k * s, y + dy]);
        }
        limb.addAll(term.reverse());
        dc.setColor(0xE4E1D6, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(limb);

        // Quelques cratères discrets
        dc.setColor(0xB9B6AB, Graphics.COLOR_TRANSPARENT);
        if (phase > 0.03 && phase < 0.97) {
            dc.fillCircle(x - radius * 0.30, y - radius * 0.25, radius * 0.16);
            dc.fillCircle(x + radius * 0.25, y + radius * 0.30, radius * 0.12);
            dc.fillCircle(x + radius * 0.35, y - radius * 0.35, radius * 0.08);
        }
        // Ré-ombrer les cratères tombés dans la partie sombre
        if (phase < 0.47 || phase > 0.53) {
            var dark = [] as Array<[Numeric, Numeric]>;
            var unlit = [] as Array<[Numeric, Numeric]>;
            for (var i = 0; i <= steps; i++) {
                var dy = -radius + 2.0 * radius * i / steps;
                var s = Math.sqrt(radius * radius - dy * dy);
                dark.add([x - side * s, y + dy]);
                unlit.add([x + side * k * s, y + dy]);
            }
            dark.addAll(unlit.reverse());
            dc.setColor(0x26272A, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon(dark);
        }
    }

    private function drawDate(dc as Dc, day as Number) as Void {
        var y = _cy - _r * 0.19;
        var radius = _r * 0.078;
        dc.setColor(_discRim, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, y, radius + 3);
        dc.setColor(DATE_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, y, radius);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, y, _fValue, day.toString(), JUSTIFY_CC);
    }

    // Disque noir avec liseré métallique
    private function drawDisc(dc as Dc, x as Numeric, y as Numeric, radius as Numeric) as Void {
        dc.setColor(_discRim, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, radius + 3);
        dc.setColor(_disc, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, radius);
        dc.setColor(0x2A2A2C, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(x, y, radius - 1);
    }

    private function drawGauge(dc as Dc, x as Numeric, y as Numeric, radius as Numeric,
                               ratio as Float?, value as String, kind as Symbol) as Void {
        drawDisc(dc, x, y, radius);

        // Arc de 270°, ouvert vers le bas (de 7h30 à 4h30)
        var arcR = radius - 8;
        roundArc(dc, x, y, arcR, 6, 225, 495, 0x2C2C2E);
        if (ratio != null) {
            var r = clamp01(ratio);
            if (r > 0.005) {
                gradientArc(dc, x, y, arcR, 6, kind, r);
            }
        }

        // « -12°C » ne tient pas toujours : on retire alors le C
        if (dc.getTextWidthInPixels(value, _fValue) > (arcR - 12) * 2) {
            value = value.substring(0, value.length() - 1) as String;
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + radius * 0.02, _fValue, value, JUSTIFY_CC);

        var iy = y + radius * 0.66;
        var labelColor = gaugeColor(kind, ratio == null ? 0.5 : clamp01(ratio));
        if (kind == :temp) {
            drawThermometer(dc, x, iy, radius * 0.16, labelColor);
        } else {
            dc.setColor(labelColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, iy, _fLabel, "VO2", JUSTIFY_CC);
        }
    }

    private function drawThermometer(dc as Dc, x as Numeric, y as Numeric, s as Numeric, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y + s * 0.6, s * 0.55);
        dc.fillRoundedRectangle(x - s * 0.25, y - s * 1.1, s * 0.5, s * 1.6, s * 0.25);
        dc.setColor(_disc, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - s * 0.06, y - s * 0.9, s * 0.12, s * 0.9);
    }

    private function drawHeartIcon(dc as Dc, x as Numeric, y as Numeric, s as Numeric, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - s * 0.5, y - s * 0.15, s * 0.55);
        dc.fillCircle(x + s * 0.5, y - s * 0.15, s * 0.55);
        dc.fillPolygon([[x - s * 1.03, y + s * 0.05], [x + s * 1.03, y + s * 0.05], [x, y + s * 1.1]]);
    }

    // Partie fixe du compteur cardiaque (dans le cache)
    private function drawHeartRateDisc(dc as Dc, x as Numeric, y as Numeric, radius as Numeric) as Void {
        drawDisc(dc, x, y, radius);
        roundArc(dc, x, y, radius - 8, 6, 225, 495, 0x2C2C2E);
        dc.setColor(0x8A8A8C, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + radius * 0.66, _fLabel, "BPM", JUSTIFY_CC);
    }

    // Partie vivante : valeur, cœur et jauge rouge (40 → 220 bpm)
    private function drawHeartRate(dc as Dc, x as Numeric, y as Numeric, radius as Numeric) as Void {
        var hr = getHeartRate();

        if (hr != null) {
            var ratio = clamp01((hr - 40).toFloat() / 180);
            if (ratio > 0.005) {
                roundArc(dc, x, y, radius - 8, 6, 225, 225 + 270 * ratio, 0xE5322D);
            }
        }

        drawHeartIcon(dc, x, y - radius * 0.52, radius * 0.12, hr == null ? 0x5A5A5C : 0xE5322D);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + radius * 0.06, _fValueBig, hr == null ? "--" : hr.toString(), JUSTIFY_CC);
    }

    private function drawBattery(dc as Dc, x as Numeric, y as Numeric, level as Float) as Void {
        var radius = _r * 0.085;
        drawDisc(dc, x, y, radius);
        var color = level <= 15 ? 0xE5322D : (level <= 30 ? 0xF2B705 : 0x3FC46A);
        roundArc(dc, x, y, radius - 4, 3, 0, 359.9, 0x2C2C2E);
        if (level > 0.5) {
            roundArc(dc, x, y, radius - 4, 3, 0, 360 * clamp01(level / 100.0), color);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, _fLabel, level.toNumber().toString(), JUSTIFY_CC);

        // Petite pile sous la bulle
        var by = y + radius + 11;
        var w = 16;
        var h = 8;
        dc.setColor(_muted, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x - w / 2, by - h / 2, w, h, 2);
        dc.fillRectangle(x + w / 2, by - 2, 2, 4);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - w / 2 + 2, by - h / 2 + 2, (w - 4) * clamp01(level / 100.0), h - 4);
    }

    private function drawSleepScore(dc as Dc, x as Numeric, y as Numeric, score as Number?) as Void {
        var radius = _r * 0.085;
        var violet = 0x8E6CF0;
        drawDisc(dc, x, y, radius);
        roundArc(dc, x, y, radius - 4, 3, 0, 359.9, 0x2C2C2E);
        if (score != null && score > 0) {
            roundArc(dc, x, y, radius - 4, 3, 0, 360 * clamp01(score / 100.0), violet);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, _fLabel, score == null ? "--" : score.toString(), JUSTIFY_CC);

        // Logo : croissant de lune et deux petites étoiles
        var by = y + radius + 11;
        dc.setColor(violet, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 2, by, 6);
        dc.setColor(_dialInner, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x + 1, by - 2, 5);
        dc.setColor(violet, Graphics.COLOR_TRANSPARENT);
        drawStar(dc, x + 6, by - 4, 2.5);
        drawStar(dc, x + 8, by + 3, 1.6);
    }

    private function drawStar(dc as Dc, x as Numeric, y as Numeric, s as Numeric) as Void {
        dc.fillPolygon([[x, y - s * 1.6], [x + s * 0.4, y - s * 0.4], [x + s * 1.6, y],
                        [x + s * 0.4, y + s * 0.4], [x, y + s * 1.6], [x - s * 0.4, y + s * 0.4],
                        [x - s * 1.6, y], [x - s * 0.4, y - s * 0.4]]);
    }

    // ---------- Aiguilles ----------

    // Polygone défini aiguille vers le haut (y négatif), tourné de angleDeg autour du centre
    private function rotated(points as Array<[Numeric, Numeric]>, angleDeg as Numeric,
                             dx as Numeric, dy as Numeric) as Array<[Numeric, Numeric]> {
        var a = Math.toRadians(angleDeg);
        var c = Math.cos(a);
        var s = Math.sin(a);
        var out = [] as Array<[Numeric, Numeric]>;
        for (var i = 0; i < points.size(); i++) {
            var px = points[i][0];
            var py = points[i][1];
            out.add([_cx + dx + px * c - py * s, _cy + dy + px * s + py * c]);
        }
        return out;
    }

    // Aiguille glaive à deux facettes, avec insert luminescent et ombre portée
    private function drawHand(dc as Dc, angleDeg as Numeric, length as Numeric, width as Numeric,
                              shadow as Boolean) as Void {
        var w = width / 2.0;
        var tail = length * 0.16;
        var left = [[0, tail], [-w, tail * 0.6], [-w, -length * 0.82], [0, -length]];
        var right = [[0, tail], [w, tail * 0.6], [w, -length * 0.82], [0, -length]];

        if (shadow && Graphics has :createColor) {
            var outline = [[0, tail], [-w, tail * 0.6], [-w, -length * 0.82], [0, -length],
                           [w, -length * 0.82], [w, tail * 0.6]];
            dc.setColor(Graphics.createColor(0x46, 0, 0, 0), Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon(rotated(outline, angleDeg, 3, 5));
        }

        dc.setColor(_handDark, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(rotated(left, angleDeg, 0, 0));
        dc.setColor(_handLight, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(rotated(right, angleDeg, 0, 0));

        var lw = w * 0.42;
        var insert = [[-lw, -length * 0.28], [-lw, -length * 0.78], [0, -length * 0.84],
                      [lw, -length * 0.78], [lw, -length * 0.28]];
        dc.setColor(_lume, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(rotated(insert, angleDeg, 0, 0));
    }

    private function drawHands(dc as Dc, clock as System.ClockTime, withSeconds as Boolean) as Void {
        var minuteAngle = (clock.min + clock.sec / 60.0) * 6;
        var hourAngle = ((clock.hour % 12) + clock.min / 60.0) * 30;

        drawHand(dc, hourAngle, _r * 0.52, 20, true);
        drawHand(dc, minuteAngle, _r * 0.80, 15, true);

        if (withSeconds) {
            var angle = clock.sec * 6;
            var tip = polar(angle, _r * 0.90);
            var tail = polar(angle + 180, _r * 0.20);
            var lolly = polar(angle, _r * 0.66);
            var weight = polar(angle + 180, _r * 0.13);
            dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(3);
            dc.drawLine(tail[0], tail[1], tip[0], tip[1]);
            dc.setPenWidth(1);
            dc.fillCircle(weight[0], weight[1], 7);
            dc.fillCircle(lolly[0], lolly[1], 7);
            dc.setColor(_dial, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(lolly[0], lolly[1], 3);
        }

        // Axe central
        dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, _cy, 11);
        dc.setColor(_disc, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, _cy, 6);
        dc.setColor(0xC8C8C4, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, _cy, 2);
    }

    // Mode « toujours allumé » : aiguilles en contour, quelques repères, très peu de pixels allumés
    private function drawSleep(dc as Dc, clock as System.ClockTime) as Void {
        dc.setAntiAlias(true);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(0x6A6A6A, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        for (var h = 1; h < 12; h++) {
            radialLine(dc, h * 30, _r - 6, _r - 20);
        }
        dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
        radialLine(dc, 0, _r - 6, _r - 24);
        dc.setPenWidth(1);

        var minuteAngle = clock.min * 6;
        var hourAngle = ((clock.hour % 12) + clock.min / 60.0) * 30;
        drawSleepHand(dc, hourAngle, _r * 0.52, 18);
        drawSleepHand(dc, minuteAngle, _r * 0.80, 13);

        dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(_cx, _cy, 8);
        dc.setPenWidth(1);
    }

    private function drawSleepHand(dc as Dc, angleDeg as Numeric, length as Numeric, width as Numeric) as Void {
        var w = width / 2.0;
        var tail = length * 0.16;
        var shape = rotated([[0, tail], [-w, tail * 0.6], [-w, -length * 0.82], [0, -length],
                             [w, -length * 0.82], [w, tail * 0.6]], angleDeg, 0, 0);
        dc.setColor(0x9A9A9A, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        for (var i = 0; i < shape.size(); i++) {
            var a = shape[i];
            var b = shape[(i + 1) % shape.size()];
            dc.drawLine(a[0], a[1], b[0], b[1]);
        }
        dc.setPenWidth(1);
    }

}
