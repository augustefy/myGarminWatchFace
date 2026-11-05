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

    // Colonnes des planches de nombres (voir tools/render_numbers.py)
    const SHEET_COLS = 6;

    // ---------- Géométrie ----------
    // Longueurs : fractions du rayon d'écran. Angles : degrés façon montre (0 à midi, sens horaire).
    // Chaque zone se déduit de la précédente, du bord de l'écran vers le centre.

    // Anneau des mois et des chiffres, ligne médiane centrée entre le cadran central et les index
    const INNER_DIAL = 0.8185;
    const HOUR_TICK_END = 0.9615;
    const MINUTE_TICK_END = 0.978;
    const NUMERAL_RING = (INNER_DIAL + HOUR_TICK_END) / 2;
    const SLEEP_TICK_END = 0.93;

    // Cadran central : piste graduée, bande des cases, puis couronne des compteurs autour du moyeu.
    // Les rainures séparent des secteurs : jours, jauges, date et lune en occupent toujours le milieu.
    const SECTOR_ANGLE = 15.0;
    const TRACK_INNER = INNER_DIAL - 0.03;
    const CASE_CIRCLE = TRACK_INNER - 0.115;
    const HUB_CIRCLE = 0.24;

    // Bande des cases : un jour par case, et son repère sous la lettre
    const DAY_RING = 0.74;
    const DAY_DOT_RING = 0.6925;
    const DAY_DOT_RADIUS = 0.009;

    // Couronne des compteurs : tous les disques, liseré compris, s'y inscrivent exactement,
    // à la même distance du cercle des cases et de celui du moyeu
    const COUNTER_MARGIN = 0.0225;
    const COUNTER_OUTER = CASE_CIRCLE - COUNTER_MARGIN;
    const COUNTER_INNER = HUB_CIRCLE + COUNTER_MARGIN;
    const DISC_RIM = 0.013;

    // Trois grands compteurs à 9 h, 3 h et 6 h
    const GAUGE_RADIUS = (COUNTER_OUTER - COUNTER_INNER) / 2 - DISC_RIM;
    const GAUGE_DIST = (COUNTER_OUTER + COUNTER_INNER) / 2;
    const GAUGE_ARC_INSET = 0.035;
    const GAUGE_ARC_PEN = 0.026;
    const GAUGE_TEXT_MARGIN = 0.053;

    // Petits disques au bord extérieur de la couronne : date à midi, batterie et sommeil en diagonale
    const SMALL_RADIUS = 0.09;
    const SMALL_DIST = COUNTER_OUTER - SMALL_RADIUS - DISC_RIM;
    const BATTERY_ANGLE = 225;
    const SLEEP_ANGLE = 135;
    const MINI_ARC_INSET = 0.018;
    const MINI_ARC_PEN = 0.013;
    const ICON_SIZE = 0.035;
    const ICON_DIST = 0.40;

    // Lune au bord intérieur de la couronne, entre le moyeu et la date
    const MOON_RADIUS = 0.065;
    const MOON_DIST = COUNTER_INNER + MOON_RADIUS + DISC_RIM;

    // Tailles des polices
    const VALUE_FONT = 0.15;
    const LABEL_FONT = 0.065;
    const DAY_FONT = 0.072;
    const MONTH_FONT = 0.0638;

    // Graduations et bord d'écran
    const HOUR_TICK_PEN = 0.013;
    const MINUTE_TICK_PEN = 0.009;
    const BEZEL_PEN = 0.013;

    // Ombre des aiguilles (lumière venant du haut à gauche) et largeur du fondu de l'ombre de l'anneau,
    // qui reste concentrique pour que le fond épouse la courbe de l'anneau
    const SHADOW_DX = 0.013;
    const SHADOW_DY = 0.022;
    const SHADOW_FADE = 0.053;

    // Aiguilles et axe central
    const HOUR_HAND = 0.52;
    const HOUR_HAND_WIDTH = 0.088;
    const MINUTE_HAND = 0.80;
    const MINUTE_HAND_WIDTH = 0.066;
    const HAND_OUTLINE_PEN = 0.009;
    const SECOND_TIP = 0.90;
    const SECOND_TAIL = 0.20;
    const SECOND_LOLLY = 0.66;
    const SECOND_WEIGHT = 0.13;
    const SECOND_PEN = 0.013;
    const SECOND_DOT = 0.031;
    const SECOND_DOT_HOLE = 0.013;
    const HUB_OUTER = 0.048;
    const HUB_MIDDLE = 0.026;
    const HUB_PIN = 0.009;
    const SLEEP_HOUR_WIDTH = 0.079;
    const SLEEP_MINUTE_WIDTH = 0.057;
    const SLEEP_HUB = 0.035;

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
    private var _groove = 0;
    private var _shadow = 0;
    private var _disc = 0;
    private var _discRim = 0;
    private var _handShade = 0;
    const DATE_RED = 0x991A1A;

    // Polices
    private var _fValue as FontType = Graphics.FONT_SMALL;
    private var _fLabel as FontType = Graphics.FONT_XTINY;
    private var _fRing as FontType = Graphics.FONT_XTINY;
    private var _fMonth as FontType = Graphics.FONT_XTINY;
    private var _vector = false;

    // Nombres en Telma : planches d'images blanches, teintées à l'affichage
    private var _hours as BitmapReference? = null;
    private var _days as BitmapReference? = null;

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
            _dialInner = 0x111214;
            _ink = 0xEDEDEA;
            _muted = 0x76777A;
            _grid = 0x36373A;
            _groove = 0xD8D8D4;
            _shadow = 0x050506;
            _disc = 0x0B0B0C;
            _discRim = 0x4C4D50;
            _handShade = 0x2E2F32;
        } else {
            _dial = 0xF3F2ED;
            _dialInner = 0xFFFFFF;
            _ink = 0x151515;
            _muted = 0x8C8B86;
            _grid = 0xD2D1CB;
            _groove = 0x000000;
            _shadow = 0xD6D6D2;
            _disc = 0x111112;
            _discRim = 0xA4A39E;
            _handShade = 0xE2E2DE;
        }
    }

    private function vectorFont(faces as Array<String>, size as Numeric) as VectorFont? {
        return Graphics.getVectorFont({:face => faces, :size => size.toNumber()});
    }

    private function loadFonts() as Void {
        _hours = WatchUi.loadResource(Rez.Drawables.Hours) as BitmapReference;
        _days = WatchUi.loadResource(Rez.Drawables.Days) as BitmapReference;

        if (!(Graphics has :getVectorFont)) {
            return;
        }
        var value = vectorFont(["RobotoCondensedBold"], _r * VALUE_FONT);
        var label = vectorFont(["RobotoCondensedBold"], _r * LABEL_FONT);
        var ring = vectorFont(["RobotoCondensedBold"], _r * DAY_FONT);
        var month = vectorFont(["RobotoCondensedBold"], _r * MONTH_FONT);
        if (value != null && label != null && ring != null && month != null) {
            _fValue = value;
            _fLabel = label;
            _fRing = ring;
            _fMonth = month;
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
        drawHeartRate(dc, _cx, _cy + px(GAUGE_DIST), px(GAUGE_RADIUS));
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
        drawMoon(dc, _cx, _cy - px(MOON_DIST), px(MOON_RADIUS));
        drawDate(dc, today.day as Number);

        var gaugeDist = px(GAUGE_DIST);
        var gaugeRadius = px(GAUGE_RADIUS);

        var vo2 = getVo2Max();
        drawGauge(dc, _cx - gaugeDist, _cy, gaugeRadius,
                  vo2 == null ? null : (vo2 - 20) / 45.0,
                  vo2 == null ? "--" : vo2.toString(), :vo2);

        savePosition();
        var temp = getTemperature();
        drawGauge(dc, _cx + gaugeDist, _cy, gaugeRadius,
                  temp == null ? null : (temp + 10) / 50.0,
                  temp == null ? "--" : temp.toString() + "°C", :temp);

        drawHeartRateDisc(dc, _cx, _cy + gaugeDist, gaugeRadius);

        var stats = System.getSystemStats();
        drawBattery(dc, stats.battery);
        drawSleepScore(dc, getSleepScore());
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

    // Position sur un cercle arrondie au pixel. Les primitives peuvent tronquer les coordonnées
    // flottantes, ce qui tire tout vers le haut à gauche. L'écart au centre commun est arrondi en valeur
    // absolue : deux points symétriques restent exactement symétriques, même sur un demi-pixel.
    private function polarPx(angleDeg as Numeric, radius as Numeric) as [Number, Number] {
        var a = Math.toRadians(angleDeg - 90);
        return [_cx + roundFromCentre(radius * Math.cos(a)), _cy + roundFromCentre(radius * Math.sin(a))];
    }

    // Le léger surplus absorbe le bruit des flottants quand la valeur tombe sur un demi-pixel
    private function roundFromCentre(offset as Numeric) as Number {
        var n = Math.round(offset.abs() + 0.001).toNumber();
        return offset < 0 ? -n : n;
    }

    private function radialLine(dc as Dc, angleDeg as Numeric, r1 as Numeric, r2 as Numeric) as Void {
        var p1 = polarPx(angleDeg, r1);
        var p2 = polarPx(angleDeg, r2);
        dc.drawLine(p1[0], p1[1], p2[0], p2[1]);
    }

    // Texte qui suit le cercle, toujours lisible (sens inversé dans la moitié basse)
    private function ringText(dc as Dc, font as FontType, text as String, angleDeg as Numeric, radius as Numeric) as Void {
        if (_vector && dc has :drawRadialText) {
            var bottom = angleDeg > 90 && angleDeg < 270;
            dc.drawRadialText(_cx, _cy, font, text, JUSTIFY_CC, 90 - angleDeg, radius,
                              bottom ? Graphics.RADIAL_TEXT_DIRECTION_COUNTER_CLOCKWISE
                                     : Graphics.RADIAL_TEXT_DIRECTION_CLOCKWISE);
        } else {
            var p = polar(angleDeg, radius);
            dc.drawText(p[0], p[1], Graphics.FONT_XTINY, text, JUSTIFY_CC);
        }
    }

    // Nombre n (à partir de 1) tiré d'une planche, centré sur (x, y).
    // La planche entière est dessinée, et seule la case voulue passe à travers le clip.
    // Les cases ont un nombre impair de pixels : leur pixel central tombe exactement sur (x, y).
    private function drawNumber(dc as Dc, sheet as BitmapReference, rows as Number, n as Number,
                                x as Number, y as Number, color as Number) as Void {
        var w = sheet.getWidth() / SHEET_COLS;
        var h = sheet.getHeight() / rows;
        var left = x - (w - 1) / 2;
        var top = y - (h - 1) / 2;
        dc.setClip(left, top, w, h);
        dc.drawBitmap2(left - (n - 1) % SHEET_COLS * w, top - (n - 1) / SHEET_COLS * h, sheet, {
            :tintColor => color
        });
        dc.clearClip();
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

    // Fraction du rayon d'écran convertie en pixels entiers. Tous les rayons passent par là : un cercle
    // et le trait qui s'y arrête tombent sur le même pixel, quelle que soit la résolution.
    private function px(fraction as Float) as Number {
        return Math.round(_r * fraction).toNumber();
    }

    // Mélange de deux couleurs RGB : t = 0 donne a, t = 1 donne b
    private function mix(a as Number, b as Number, t as Float) as Number {
        var red = ((a >> 16) & 0xFF) * (1 - t) + ((b >> 16) & 0xFF) * t;
        var green = ((a >> 8) & 0xFF) * (1 - t) + ((b >> 8) & 0xFF) * t;
        var blue = (a & 0xFF) * (1 - t) + (b & 0xFF) * t;
        return (red.toNumber() << 16) | (green.toNumber() << 8) | blue.toNumber();
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
        var inner = px(INNER_DIAL);
        var track = px(TRACK_INNER);
        var hub = px(HUB_CIRCLE);

        // Très légère ombre portée par l'anneau sur le fond : un disque de plus en plus clair par pixel
        // de fondu, tous sur le centre commun pour que le fond reste concentrique à l'anneau
        var fade = px(SHADOW_FADE);
        for (var i = 0; i <= fade; i++) {
            dc.setColor(mix(_shadow, _dialInner, i.toFloat() / fade), Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(_cx, _cy, inner - i);
        }

        dc.setColor(_groove, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawCircle(_cx, _cy, inner);
        dc.drawCircle(_cx, _cy, track);
        dc.drawCircle(_cx, _cy, px(CASE_CIRCLE));
        dc.drawCircle(_cx, _cy, hub);

        // Piste graduée : un trait par demi-secteur, soit en face de chaque chiffre, de chaque mois
        // et de chaque rainure
        var halfSector = SECTOR_ANGLE / 2;
        for (var i = 0; i < 48; i++) {
            radialLine(dc, i * halfSector, track, inner);
        }
        // Rainures : elles ferment les cases et séparent les secteurs
        for (var i = 0; i < 24; i++) {
            radialLine(dc, i * SECTOR_ANGLE + halfSector, hub, track);
        }
    }

    private function drawTrack(dc as Dc) as Void {
        var hourPen = px(HOUR_TICK_PEN);
        var minutePen = px(MINUTE_TICK_PEN);
        var hourEnd = px(HOUR_TICK_END);
        var minuteEnd = px(MINUTE_TICK_END);

        // Léger anneau de bord pour donner de la profondeur
        dc.setColor(_grid, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(px(BEZEL_PEN));
        dc.drawCircle(_cx, _cy, _r - 1);

        // Graduations : ancrées au bord de l'écran, elles filent vers l'intérieur
        dc.setColor(_ink, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 60; i++) {
            if (i % 5 == 0) {
                dc.setPenWidth(hourPen);
                radialLine(dc, i * 6, _r, hourEnd);
            } else {
                dc.setPenWidth(minutePen);
                radialLine(dc, i * 6, _r, minuteEnd);
            }
        }
        dc.setPenWidth(1);

        // Index de midi en couleur d'accent
        dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(hourPen);
        radialLine(dc, 0, _r, hourEnd);
        dc.setPenWidth(1);
    }

    private function drawNumerals(dc as Dc) as Void {
        var ring = px(NUMERAL_RING);
        for (var h = 1; h <= 12; h++) {
            var p = polarPx(h * 30, ring);
            drawNumber(dc, _hours as BitmapReference, 2, h, p[0], p[1], _ink);
        }
    }

    private function drawMonths(dc as Dc, month as Number) as Void {
        for (var m = 0; m < 12; m++) {
            dc.setColor(m + 1 == month ? DATE_RED : _muted, Graphics.COLOR_TRANSPARENT);
            ringText(dc, _fMonth, MONTHS[m], m * 30 + 15, px(NUMERAL_RING));
        }
    }

    private function drawWeekdays(dc as Dc, dayOfWeek as Number) as Void {
        // Gregorian : 1 = dimanche ... 7 = samedi → index lundi = 0
        var current = (dayOfWeek + 5) % 7;
        for (var i = 0; i < 7; i++) {
            var angle = (i - 3) * SECTOR_ANGLE;   // un jour par case, jeudi à midi
            dc.setColor(i == current ? DATE_RED : _ink, Graphics.COLOR_TRANSPARENT);
            ringText(dc, _fRing, DAYS[i], angle, px(DAY_RING));
            if (i == current) {
                var dot = polarPx(angle, px(DAY_DOT_RING));
                dc.fillCircle(dot[0], dot[1], px(DAY_DOT_RADIUS));
            }
        }
    }

    private function drawMoon(dc as Dc, x as Numeric, y as Numeric, radius as Numeric) as Void {
        var days = (Time.now().value() - NEW_MOON_EPOCH) / 86400.0;
        var phase = days / SYNODIC_DAYS;
        phase = phase - Math.floor(phase);

        dc.setColor(_discRim, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, radius + px(DISC_RIM));
        dc.setColor(0x26272A, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, radius);

        // Partie éclairée : entre le bord du disque et le terminateur (ellipse)
        var k = Math.cos(2 * Math.PI * phase);
        var side = phase < 0.5 ? 1 : -1;
        var steps = 18;
        var limb = [] as Array<[Numeric, Numeric]>;
        var term = [] as Array<[Numeric, Numeric]>;
        for (var i = 0; i <= steps; i++) {
            var t = -1.0 + 2.0 * i / steps;     // reste dans [-1, 1] : la racine ne peut pas donner NaN
            var dy = radius * t;
            var s = radius * Math.sqrt(1 - t * t);
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
                var t = -1.0 + 2.0 * i / steps;
                var dy = radius * t;
                var s = radius * Math.sqrt(1 - t * t);
                dark.add([x - side * s, y + dy]);
                unlit.add([x + side * k * s, y + dy]);
            }
            dark.addAll(unlit.reverse());
            dc.setColor(0x26272A, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon(dark);
        }
    }

    private function drawDate(dc as Dc, day as Number) as Void {
        var y = _cy - px(SMALL_DIST);
        var radius = px(SMALL_RADIUS);
        dc.setColor(_discRim, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, y, radius + px(DISC_RIM));
        dc.setColor(DATE_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, y, radius);
        drawNumber(dc, _days as BitmapReference, 6, day, _cx, y, Graphics.COLOR_BLACK);
    }

    // Disque noir avec liseré métallique
    private function drawDisc(dc as Dc, x as Numeric, y as Numeric, radius as Numeric) as Void {
        dc.setColor(_discRim, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, radius + px(DISC_RIM));
        dc.setColor(_disc, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, radius);
        dc.setColor(0x2A2A2C, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(x, y, radius - 1);
    }

    private function drawGauge(dc as Dc, x as Numeric, y as Numeric, radius as Numeric,
                               ratio as Float?, value as String, kind as Symbol) as Void {
        drawDisc(dc, x, y, radius);

        // Arc de 270°, ouvert vers le bas (de 7h30 à 4h30)
        var arcR = radius - px(GAUGE_ARC_INSET);
        var arcPen = px(GAUGE_ARC_PEN);
        roundArc(dc, x, y, arcR, arcPen, 225, 495, 0x2C2C2E);
        if (ratio != null) {
            var r = clamp01(ratio);
            if (r > 0.005) {
                gradientArc(dc, x, y, arcR, arcPen, kind, r);
            }
        }

        // « -12°C » ne tient pas toujours : on retire alors le C
        if (dc.getTextWidthInPixels(value, _fValue) > (arcR - px(GAUGE_TEXT_MARGIN)) * 2) {
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
        roundArc(dc, x, y, radius - px(GAUGE_ARC_INSET), px(GAUGE_ARC_PEN), 225, 495, 0x2C2C2E);
        dc.setColor(0x8A8A8C, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + radius * 0.66, _fLabel, "BPM", JUSTIFY_CC);
    }

    // Partie vivante : valeur, cœur et jauge rouge (40 → 220 bpm)
    private function drawHeartRate(dc as Dc, x as Numeric, y as Numeric, radius as Numeric) as Void {
        var hr = getHeartRate();

        if (hr != null) {
            var ratio = clamp01((hr - 40).toFloat() / 180);
            if (ratio > 0.005) {
                roundArc(dc, x, y, radius - px(GAUGE_ARC_INSET), px(GAUGE_ARC_PEN), 225, 225 + 270 * ratio, 0xE5322D);
            }
        }

        drawHeartIcon(dc, x, y - radius * 0.52, radius * 0.12, hr == null ? 0x5A5A5C : 0xE5322D);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + radius * 0.06, _fValue, hr == null ? "--" : hr.toString(), JUSTIFY_CC);
    }

    // Petit compteur : disque, arc de progression sur tout le tour et valeur au centre
    private function drawMiniDial(dc as Dc, x as Numeric, y as Numeric, ratio as Float, color as Number, value as String) as Void {
        var radius = px(SMALL_RADIUS);
        var arcR = radius - px(MINI_ARC_INSET);
        var arcPen = px(MINI_ARC_PEN);
        drawDisc(dc, x, y, radius);
        roundArc(dc, x, y, arcR, arcPen, 0, 359.9, 0x2C2C2E);
        if (ratio > 0.005) {
            roundArc(dc, x, y, arcR, arcPen, 0, 360 * ratio, color);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, _fLabel, value, JUSTIFY_CC);
    }

    // Compteur de batterie ; son icône se place vers le centre, au milieu du même secteur
    private function drawBattery(dc as Dc, level as Float) as Void {
        var p = polarPx(BATTERY_ANGLE, px(SMALL_DIST));
        var icon = polarPx(BATTERY_ANGLE, px(ICON_DIST));
        var ratio = clamp01(level / 100.0);
        var color = level <= 15 ? 0xE5322D : (level <= 30 ? 0xF2B705 : 0x3FC46A);
        drawMiniDial(dc, p[0], p[1], ratio, color, level.toNumber().toString());
        drawBatteryIcon(dc, icon[0], icon[1], px(ICON_SIZE), ratio, color);
    }

    // Compteur de sommeil ; son icône se place vers le centre, au milieu du même secteur
    private function drawSleepScore(dc as Dc, score as Number?) as Void {
        var p = polarPx(SLEEP_ANGLE, px(SMALL_DIST));
        var icon = polarPx(SLEEP_ANGLE, px(ICON_DIST));
        var violet = 0x8E6CF0;
        drawMiniDial(dc, p[0], p[1], score == null ? 0.0 : clamp01(score / 100.0), violet,
                     score == null ? "--" : score.toString());
        drawSleepIcon(dc, icon[0], icon[1], px(ICON_SIZE), violet);
    }

    // Petite pile, remplie selon le niveau
    private function drawBatteryIcon(dc as Dc, x as Numeric, y as Numeric, s as Numeric, ratio as Float, color as Number) as Void {
        var w = s * 2;
        var inset = s * 0.25;
        dc.setColor(_muted, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x - w / 2, y - s / 2, w, s, inset);
        dc.fillRectangle(x + w / 2, y - inset, inset, inset * 2);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - w / 2 + inset, y - s / 2 + inset, (w - inset * 2) * ratio, s - inset * 2);
    }

    // Croissant de lune et deux petites étoiles
    private function drawSleepIcon(dc as Dc, x as Numeric, y as Numeric, s as Numeric, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - s * 0.25, y, s * 0.75);
        dc.setColor(_dialInner, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x + s * 0.125, y - s * 0.25, s * 0.625);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        drawStar(dc, x + s * 0.75, y - s * 0.5, s * 0.3125);
        drawStar(dc, x + s, y + s * 0.375, s * 0.2);
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

    // Trace le contour fermé d'un polygone
    private function strokePolygon(dc as Dc, shape as Array<[Numeric, Numeric]>, color as Number, pen as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(pen);
        for (var i = 0; i < shape.size(); i++) {
            var a = shape[i];
            var b = shape[(i + 1) % shape.size()];
            dc.drawLine(a[0], a[1], b[0], b[1]);
        }
        dc.setPenWidth(1);
    }

    // Aiguille glaive inversée : corps à deux facettes couleur du fond, contour et église en encre,
    // avec ombre portée
    private function drawHand(dc as Dc, angleDeg as Numeric, length as Numeric, width as Numeric,
                              shadow as Boolean) as Void {
        var w = width / 2.0;
        var tail = length * 0.16;
        var left = [[0, tail], [-w, tail * 0.6], [-w, -length * 0.82], [0, -length]];
        var right = [[0, tail], [w, tail * 0.6], [w, -length * 0.82], [0, -length]];
        var outline = [[0, tail], [-w, tail * 0.6], [-w, -length * 0.82], [0, -length],
                       [w, -length * 0.82], [w, tail * 0.6]];

        if (shadow && Graphics has :createColor) {
            dc.setColor(Graphics.createColor(0x46, 0, 0, 0), Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon(rotated(outline, angleDeg, _r * SHADOW_DX, _r * SHADOW_DY));
        }

        dc.setColor(_dialInner, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(rotated(left, angleDeg, 0, 0));
        dc.setColor(_handShade, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(rotated(right, angleDeg, 0, 0));
        strokePolygon(dc, rotated(outline, angleDeg, 0, 0), _ink, px(HAND_OUTLINE_PEN));

        var lw = w * 0.42;
        var church = [[-lw, -length * 0.28], [-lw, -length * 0.78], [0, -length * 0.84],
                      [lw, -length * 0.78], [lw, -length * 0.28]];
        dc.setColor(_ink, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(rotated(church, angleDeg, 0, 0));
    }

    private function drawHands(dc as Dc, clock as System.ClockTime, withSeconds as Boolean) as Void {
        var minuteAngle = (clock.min + clock.sec / 60.0) * 6;
        var hourAngle = ((clock.hour % 12) + clock.min / 60.0) * 30;

        drawHand(dc, hourAngle, _r * HOUR_HAND, _r * HOUR_HAND_WIDTH, true);
        drawHand(dc, minuteAngle, _r * MINUTE_HAND, _r * MINUTE_HAND_WIDTH, true);

        if (withSeconds) {
            var angle = clock.sec * 6;
            var tip = polarPx(angle, px(SECOND_TIP));
            var tail = polarPx(angle + 180, px(SECOND_TAIL));
            var lolly = polarPx(angle, px(SECOND_LOLLY));
            var weight = polarPx(angle + 180, px(SECOND_WEIGHT));
            dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(px(SECOND_PEN));
            dc.drawLine(tail[0], tail[1], tip[0], tip[1]);
            dc.setPenWidth(1);
            dc.fillCircle(weight[0], weight[1], px(SECOND_DOT));
            dc.fillCircle(lolly[0], lolly[1], px(SECOND_DOT));
            dc.setColor(_dialInner, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(lolly[0], lolly[1], px(SECOND_DOT_HOLE));
        }

        // Axe central
        dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, _cy, px(HUB_OUTER));
        dc.setColor(_disc, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, _cy, px(HUB_MIDDLE));
        dc.setColor(0xC8C8C4, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, _cy, px(HUB_PIN));
    }

    // Mode « toujours allumé » : aiguilles en contour, quelques repères, très peu de pixels allumés
    private function drawSleep(dc as Dc, clock as System.ClockTime) as Void {
        dc.setAntiAlias(true);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(0x6A6A6A, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(px(HOUR_TICK_PEN));
        var tickEnd = px(SLEEP_TICK_END);
        for (var h = 1; h < 12; h++) {
            radialLine(dc, h * 30, _r, tickEnd);
        }
        dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
        radialLine(dc, 0, _r, tickEnd);
        dc.setPenWidth(1);

        var minuteAngle = clock.min * 6;
        var hourAngle = ((clock.hour % 12) + clock.min / 60.0) * 30;
        drawSleepHand(dc, hourAngle, _r * HOUR_HAND, _r * SLEEP_HOUR_WIDTH);
        drawSleepHand(dc, minuteAngle, _r * MINUTE_HAND, _r * SLEEP_MINUTE_WIDTH);

        dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(px(MINUTE_TICK_PEN));
        dc.drawCircle(_cx, _cy, px(SLEEP_HUB));
        dc.setPenWidth(1);
    }

    private function drawSleepHand(dc as Dc, angleDeg as Numeric, length as Numeric, width as Numeric) as Void {
        var w = width / 2.0;
        var tail = length * 0.16;
        var shape = rotated([[0, tail], [-w, tail * 0.6], [-w, -length * 0.82], [0, -length],
                             [w, -length * 0.82], [w, tail * 0.6]], angleDeg, 0, 0);
        strokePolygon(dc, shape, 0x9A9A9A, px(HAND_OUTLINE_PEN));
    }

}
