// GrindGuard - Vollbild-Warnung (JavaScript for Automation + Cocoa)
//
// Aufruf:  osascript -l JavaScript overlay.js <sekunden> <textdatei> <arch>
//
// Die Textdatei hat bis zu sechs Zeilen:
//   1 Ueberschrift   2 Spruch   3 Detailzeile
//   4 Zaehlerzeile (z. B. AUSRUTSCHER 03 - 20 S)   5 was geschlossen wurde
//   6 Ton: brutal | direkt | ruhig (bestimmt die Akzentfarbe)
// Fehlende Zeilen sind erlaubt (aeltere Aufrufe liefern nur drei).
//
// Das Fenster deckt alle Bildschirme ab, nimmt keine Eingaben an und
// verschwindet nach Ablauf der Zeit von selbst (hoechstens 300 Sekunden).
// Alles, was ueber die schlichte Textanzeige hinausgeht (Ring, Einblenden,
// Schriftgewichte), ist optional: Klappt es auf einem macOS nicht, bleibt die
// Warnung trotzdem sichtbar.
//
// Diese Datei enthaelt absichtlich nur ASCII-Zeichen.
// Hinweis zur Schreibweise: In JXA werden Objective-C-Methoden ohne Argument
// OHNE Klammern aufgerufen (z. B. "win.orderFrontRegardless;").

ObjC.import('Cocoa');

// Globale Liste: solange hier Verweise liegen, raeumt JavaScript die Objekte nicht weg.
var KEEP = [];

// Cocoa-Konstanten mit Namen statt nackter Zahlen
var BORDERLESS = 0;                 // NSWindowStyleMaskBorderless
var BUFFERED = 2;                   // NSBackingStoreBuffered
var LEVEL_SCREENSAVER = 1000;       // NSScreenSaverWindowLevel: ueber allen normalen Fenstern
var ALL_SPACES = 1;                 // NSWindowCollectionBehaviorCanJoinAllSpaces
var STATIONARY = 16;                // ...Stationary: bleibt bei Mission Control stehen
var FULLSCREEN_AUX = 256;           // ...FullScreenAuxiliary: auch ueber Vollbild-Apps
var ACCESSORY = 1;                  // NSApplicationActivationPolicyAccessory: ohne Dock-Symbol
var ROUND_CAP = 1;                  // NSLineCapStyleRound

var THEMES = {                      // Akzentfarbe je nach Ton (sRGB)
    brutal: [0.93, 0.18, 0.24],
    direkt: [0.98, 0.62, 0.18],
    ruhig: [0.40, 0.68, 0.98]
};

function quiet(fn) {
    try { fn(); } catch (e) { /* nicht entscheidend */ }
}

// Setzt eine Eigenschaft: erst ueber die Setter-Methode, sonst per Zuweisung.
function set(o, name, value) {
    var setter = 'set' + name.charAt(0).toUpperCase() + name.slice(1);
    try {
        o[setter](value);
        return;
    } catch (e) { /* zweiter Weg */ }
    o[name] = value;
}

function readLines(path) {
    try {
        var s = $.NSString.stringWithContentsOfFileEncodingError(path, 4, null); // 4 = UTF-8
        var js = ObjC.unwrap(s);
        if (typeof js === 'string') { return js.split('\n'); }
    } catch (e) { /* weiter mit Standardtexten */ }
    return [];
}

function rect(x, y, w, h) {
    try {
        return $.NSMakeRect(x, y, w, h);
    } catch (e) {
        return { origin: { x: x, y: y }, size: { width: w, height: h } };
    }
}

function color(r, g, b, a) {
    try {
        return $.NSColor.colorWithSRGBRedGreenBlueAlpha(r, g, b, a);
    } catch (e) {
        return $.NSColor.colorWithCalibratedRedGreenBlueAlpha(r, g, b, a);
    }
}

// Schrift mit Gewicht (0 = normal, 0.4 = fett, 0.62 = schwarz); mono = Ziffern gleich breit
function font(size, weight, mono) {
    try {
        if (mono) { return $.NSFont.monospacedDigitSystemFontOfSizeWeight(size, weight); }
        return $.NSFont.systemFontOfSizeWeight(size, weight);
    } catch (e) {
        return weight >= 0.3 ? $.NSFont.boldSystemFontOfSize(size) : $.NSFont.systemFontOfSize(size);
    }
}

function makeLabel(view, text, x, y, w, h, fnt, col, align) {
    var tf = $.NSTextField.alloc.initWithFrame(rect(x, y, w, h));
    set(tf, 'stringValue', text);
    set(tf, 'bezeled', false);
    set(tf, 'drawsBackground', false);
    set(tf, 'editable', false);
    set(tf, 'selectable', false);
    set(tf, 'textColor', col);
    set(tf, 'font', fnt);
    quiet(function () { set(tf, 'alignment', align); });
    quiet(function () { set(tf.cell, 'wraps', true); });
    view.addSubview(tf);
    KEEP.push(tf);
    return tf;
}

// Ein Textfeld ohne Text, aber mit Hintergrundfarbe: die schmale Akzentlinie oben.
function makeBar(view, x, y, w, h, col) {
    var tf = $.NSTextField.alloc.initWithFrame(rect(x, y, w, h));
    set(tf, 'stringValue', '');
    set(tf, 'bezeled', false);
    set(tf, 'editable', false);
    set(tf, 'selectable', false);
    set(tf, 'backgroundColor', col);
    set(tf, 'drawsBackground', true);
    view.addSubview(tf);
    KEEP.push(tf);
    return tf;
}

// --- Countdown-Ring (optional) ---------------------------------------------
var RING = { ok: false, progress: 1, accent: null, track: null };

function registerRing() {
    try {
        ObjC.registerSubclass({
            name: 'GGRingView',
            superclass: 'NSView',
            methods: {
                'drawRect:': {
                    types: ['void', ['NSRect']],
                    implementation: function (dirty) {
                        try {
                            var b = this.bounds;
                            var w = b.size.width;
                            var h = b.size.height;
                            var lw = Math.max(4, Math.min(w, h) * 0.035);
                            var r = Math.min(w, h) / 2 - lw;
                            var c = $.NSMakePoint(w / 2, h / 2);
                            var track = $.NSBezierPath.bezierPath;
                            track.appendBezierPathWithArcWithCenterRadiusStartAngleEndAngle(c, r, 0, 360);
                            track.setLineWidth(lw);
                            RING.track.setStroke;
                            track.stroke;
                            if (RING.progress > 0.002) {
                                var arc = $.NSBezierPath.bezierPath;
                                arc.appendBezierPathWithArcWithCenterRadiusStartAngleEndAngleClockwise(
                                    c, r, 90, 90 - 360 * RING.progress, true);
                                arc.setLineWidth(lw);
                                arc.setLineCapStyle(ROUND_CAP);
                                RING.accent.setStroke;
                                arc.stroke;
                            }
                        } catch (e) { /* ohne Ring geht es auch */ }
                    }
                }
            }
        });
        RING.ok = true;
    } catch (e) {
        RING.ok = false;
    }
}

function reduceMotion() {
    try {
        return $.NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion === true;
    } catch (e) {
        return false;
    }
}

function run(argv) {
    var seconds = parseInt(argv[0], 10);
    if (!(seconds >= 3)) { seconds = 10; }
    if (seconds > 300) { seconds = 300; }

    var lines = readLines(argv[1]);
    var headline = lines[0] || 'STOPP.';
    var message = lines[1] || 'Zur\u00fcck an die Arbeit. Jetzt.';
    var detail = lines[2] || '';
    var counter = lines[3] || '';
    var tone = THEMES[lines[5]] ? lines[5] : 'brutal';

    // NSTextAlignment hat je nach Prozessor andere Zahlenwerte (links ist immer 0).
    var arm = (argv[2] === 'arm64');
    var CENTER = arm ? 1 : 2;
    var RIGHT = arm ? 2 : 1;
    var LEFT = 0;

    var app = $.NSApplication.sharedApplication;
    app.setActivationPolicy(ACCESSORY);
    quiet(function () { app.finishLaunching; });

    var t = THEMES[tone];
    var bg = color(0.035, 0.035, 0.043, 1.0);        // fast schwarz, kein Rot-Teppich
    var white = color(0.97, 0.97, 0.98, 1.0);
    var soft = color(0.62, 0.63, 0.67, 1.0);
    var accent = color(t[0], t[1], t[2], 1.0);
    RING.accent = accent;
    RING.track = color(1, 1, 1, 0.09);
    registerRing();
    var fade = !reduceMotion();

    var screens = $.NSScreen.screens;
    var count = screens.count;
    var wins = [];
    var numbers = [];
    var footers = [];
    var rings = [];

    for (var i = 0; i < count; i++) {
        var frame = screens.objectAtIndex(i).frame;
        var W = frame.size.width;
        var H = frame.size.height;

        var win = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(frame, BORDERLESS, BUFFERED, false);
        KEEP.push(win);
        (function (w) {
            quiet(function () { set(w, 'releasedWhenClosed', false); });
            set(w, 'opaque', true);
            set(w, 'backgroundColor', bg);
            set(w, 'level', LEVEL_SCREENSAVER);
            quiet(function () { set(w, 'hasShadow', false); });
            quiet(function () { set(w, 'collectionBehavior', ALL_SPACES + STATIONARY + FULLSCREEN_AUX); });
            if (fade) { quiet(function () { set(w, 'alphaValue', 0); }); }
        })(win);

        var view = win.contentView;
        var x = W * 0.08;
        var cw = W * 0.84;
        var edge = Math.max(24, Math.min(W, H) * 0.04);
        var big = Math.min(H * 0.11, W * 0.075);
        var mid = Math.min(H * 0.036, W * 0.024);
        var small = Math.max(12, mid * 0.66);
        var ring = Math.min(H * 0.24, W * 0.2);
        var ringY = H * 0.36;

        // Rangfolge von oben nach unten: Akzentlinie, Marke + Zaehler, Ueberschrift,
        // Ring mit Restsekunden, Spruch, Detail, Fusszeile. Nichts ueberlappt.
        makeBar(view, 0, H - 6, W, 6, accent);
        makeLabel(view, 'GRINDGUARD', edge, H - edge - small * 1.6, W * 0.4, small * 1.6, font(small, 0.5, false), soft, LEFT);
        makeLabel(view, counter, W * 0.5, H - edge - small * 1.6, W * 0.5 - edge, small * 1.6, font(small, 0.5, true), accent, RIGHT);
        makeLabel(view, headline, x, H * 0.64, cw, big * 1.3, font(big, 0.62, false), white, CENTER);

        var rv = null;
        if (RING.ok) {
            quiet(function () {
                rv = $.GGRingView.alloc.initWithFrame(rect((W - ring) / 2, ringY, ring, ring));
                view.addSubview(rv);
                KEEP.push(rv);
            });
        }
        rings.push(rv);
        numbers.push(makeLabel(view, String(seconds), (W - ring) / 2, ringY + ring * 0.3, ring, ring * 0.4,
            font(ring * 0.3, 0.3, true), white, CENTER));

        makeLabel(view, message, x, H * 0.22, cw, H * 0.12, font(mid, 0.4, false), white, CENTER);
        makeLabel(view, detail, x, H * 0.13, cw, H * 0.08, font(small, 0, false), soft, CENTER);
        footers.push(makeLabel(view, '', x, H * 0.05, cw, small * 1.6, font(small, 0, true), soft, CENTER));

        win.orderFrontRegardless;
        (function (w) { quiet(function () { w.display; }); })(win);
        wins.push(win);
    }

    quiet(function () { app.activateIgnoringOtherApps(true); });
    quiet(function () { app.activate; });           // neuere macOS-Versionen

    // Sanft einblenden (150 ms). Wer "Bewegung reduzieren" eingeschaltet hat, bekommt es sofort.
    if (fade) {
        quiet(function () {
            $.NSAnimationContext.beginGrouping;
            $.NSAnimationContext.currentContext.setDuration(0.15);
            for (var a = 0; a < wins.length; a++) { wins[a].animator.setAlphaValue(1.0); }
            $.NSAnimationContext.endGrouping;
        });
    }

    // Ereignisse abholen, damit macOS das Fenster nicht als "reagiert nicht" markiert.
    var pumpMode = 0;
    function pump(sec) {
        var until = $.NSDate.dateWithTimeIntervalSinceNow(sec);
        if (pumpMode === 0) {
            try {
                var ev = app.nextEventMatchingMaskUntilDateInModeDequeue(
                    9007199254740991, until, 'kCFRunLoopDefaultMode', true);
                var none = true;
                try { none = !ev || ev.isNil(); } catch (e0) { none = !ev; }
                if (!none) {
                    try { app.sendEvent(ev); } catch (e1) { /* egal */ }
                }
                return;
            } catch (e) { pumpMode = 1; }
        }
        if (pumpMode === 1) {
            try {
                $.NSRunLoop.currentRunLoop.runUntilDate(until);
                return;
            } catch (e2) { pumpMode = 2; }
        }
        delay(sec);
    }

    var start = Date.now();
    var total = seconds * 1000;
    var end = start + total;
    var shown = -1;
    var checked = false;
    var opaqueDone = !fade;
    while (true) {
        var now = Date.now();
        var left = Math.ceil((end - now) / 1000);
        if (left <= 0) { break; }
        if (left !== shown) {
            shown = left;
            for (var c = 0; c < numbers.length; c++) {
                set(numbers[c], 'stringValue', String(left));
                set(footers[c], 'stringValue', 'Bildschirm gesperrt \u2013 noch ' + left + ' s');
            }
        }
        if (RING.ok) {
            RING.progress = Math.max(0, (end - now) / total);
            for (var g = 0; g < rings.length; g++) {
                if (rings[g]) { (function (r) { quiet(function () { set(r, 'needsDisplay', true); }); })(rings[g]); }
            }
        }
        pump(0.05);
        if (!opaqueDone && Date.now() - start > 300) {
            // Sicherheitsnetz: Hat die Animation nicht gegriffen, wird jetzt hart eingeblendet.
            opaqueDone = true;
            for (var o = 0; o < wins.length; o++) {
                (function (w) { quiet(function () { set(w, 'alphaValue', 1.0); }); })(wins[o]);
            }
        }
        if (!checked && Date.now() - start > 400) {
            // Selbstkontrolle: Meldet macOS, dass kein einziges Fenster sichtbar ist,
            // wird abgebrochen - das Hauptskript zeigt dann ein Dialogfenster.
            checked = true;
            var hidden = 0;
            for (var v = 0; v < wins.length; v++) {
                var vis = null;
                try { vis = wins[v].isVisible; } catch (e3) { vis = null; }
                if (vis === false) { hidden++; }
            }
            if (wins.length === 0 || hidden === wins.length) {
                throw new Error('Fenster nicht sichtbar');
            }
        }
    }

    for (var k = 0; k < wins.length; k++) {
        (function (w) { quiet(function () { w.orderOut(w); }); })(wins[k]);
    }
    return 'ok';
}
