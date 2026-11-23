// Fuehrt overlay.js unter Node mit einer nachgebauten ObjC-Bruecke aus.
// Prueft den Ablauf: keine JS-Fehler, richtige Texte, Layout ohne Ueberlappung,
// Laufzeit, Einblenden, Ring, Rueckfallebenen und die Selbstkontrolle.
// Aufruf: node overlay_mock.js <pfad/zu/overlay.js>
const fs = require('fs'), vm = require('vm');
const src = fs.readFileSync(process.argv[2], 'utf8');
const screens = [
  { frame: { origin: { x: 0, y: 0 }, size: { width: 1440, height: 900 } } },
  { frame: { origin: { x: 1440, y: 0 }, size: { width: 1080, height: 1920 } } },
];
// Reihenfolge der Textfelder pro Fenster (siehe overlay.js)
const BAR = 0, BRAND = 1, COUNTER = 2, HEAD = 3, NUMBER = 4, MSG = 5, DETAIL = 6, FOOT = 7;
const PER_WINDOW = 8;

function makeWorld(opts) {
  const calls = [], labels = [], windows = [], rings = [], colors = [];
  function record(kind, extra) {
    const state = Object.assign({ kind, props: {} }, extra || {});
    return new Proxy(state, {
      get(t, p) {
        if (typeof p !== 'string') return undefined;
        if (p in t) return t[p];
        if (p.startsWith('set') && p.length > 3) {
          if (opts.noSetters) return undefined;           // Aufruf wirft TypeError
          const name = p.charAt(3).toLowerCase() + p.slice(4);
          return v => { t.props[name] = v; calls.push(kind + '.' + p); };
        }
        if (p === 'isVisible') return opts.invisible ? false : true;
        if (p === 'cell') return record('cell');
        if (p === 'contentView') return { addSubview: l => { t.subviews.push(l); } };
        if (p === 'orderFrontRegardless') { t.ordered = true; calls.push('orderFrontRegardless'); return undefined; }
        if (p === 'display') { calls.push('display'); return undefined; }
        if (p === 'orderOut') return () => { t.ordered = false; calls.push('orderOut'); };
        if (p === 'animator') {
          if (opts.noAnimator) throw new Error('kein animator');
          return { setAlphaValue: v => { t.props.alphaValue = v; calls.push('animator.setAlphaValue(' + v + ')'); } };
        }
        return undefined;
      },
      set(t, p, v) { t.props[p] = v; calls.push(kind + '.' + String(p) + '='); return true; }
    });
  }
  const app = {
    setActivationPolicy: v => { calls.push('setActivationPolicy(' + v + ')'); return true; },
    get finishLaunching() { calls.push('finishLaunching'); return undefined; },
    activateIgnoringOtherApps: v => { calls.push('activateIgnoringOtherApps(' + v + ')'); },
    get activate() { if (opts.oldMac) throw new Error('unrecognized selector'); calls.push('activate'); return undefined; },
    nextEventMatchingMaskUntilDateInModeDequeue: (mask, until, mode, deq) => {
      if (opts.pumpThrows) throw new Error('bridge');
      calls.push('nextEvent(' + mask + ',' + mode + ',' + deq + ')');
      return opts.events ? { isNil: () => false } : { isNil: () => true };
    },
    sendEvent: () => { calls.push('sendEvent'); },
  };
  let ringClass = null;
  const fontApi = {
    boldSystemFontOfSize: s => 'bold ' + s,
    systemFontOfSize: s => 'regular ' + s,
  };
  if (!opts.oldFonts) {
    fontApi.systemFontOfSizeWeight = (s, w) => 'system ' + s + '/' + w;
    fontApi.monospacedDigitSystemFontOfSizeWeight = (s, w) => 'mono ' + s + '/' + w;
  }
  const $ = new Proxy({}, { get(_, prop) {
    switch (prop) {
      case 'NSApplication': return { sharedApplication: app };
      case 'NSScreen': return { screens: { count: opts.noScreens ? 0 : screens.length, objectAtIndex: i => screens[i] } };
      case 'NSMakeRect': return (x, y, w, h) => ({ origin: { x, y }, size: { width: w, height: h } });
      case 'NSString': return { stringWithContentsOfFileEncodingError: (p, enc, err) => {
        if (enc !== 4) throw new Error('falsches Encoding');
        try { return { __str: fs.readFileSync(p, 'utf8') }; } catch (e) { return { __nil: true }; } } };
      case 'NSColor': return {
        whiteColor: 'white',
        colorWithCalibratedRedGreenBlueAlpha: (r, g, b, a) => { const c = 'cal(' + [r, g, b, a] + ')'; colors.push(c); return c; },
        colorWithSRGBRedGreenBlueAlpha: (r, g, b, a) => { if (opts.noSRGB) throw new Error('alt'); const c = 'srgb(' + [r, g, b, a] + ')'; colors.push(c); return c; },
      };
      case 'NSFont': return fontApi;
      case 'NSDate': return { dateWithTimeIntervalSinceNow: s => ({ in: s }) };
      case 'NSRunLoop': return { currentRunLoop: { runUntilDate: () => { calls.push('runUntilDate'); } } };
      case 'NSWorkspace': return { sharedWorkspace: { accessibilityDisplayShouldReduceMotion: !!opts.reduceMotion } };
      case 'NSAnimationContext': return {
        get beginGrouping() { calls.push('beginGrouping'); return undefined; },
        get endGrouping() { calls.push('endGrouping'); return undefined; },
        currentContext: { setDuration: d => calls.push('setDuration(' + d + ')') },
      };
      case 'NSTextField': return { alloc: { initWithFrame: r => { const l = record('label', { frame: r }); labels.push(l); return l; } } };
      case 'NSWindow': return { alloc: { initWithContentRectStyleMaskBackingDefer: (frame, mask, backing, defer) => {
        calls.push('initWindow(' + mask + ',' + backing + ',' + defer + ')');
        const w = record('window', { frame, subviews: [], ordered: false }); windows.push(w); return w; } } };
      case 'GGRingView':
        if (!ringClass) throw new Error('Klasse nicht registriert');
        return { alloc: { initWithFrame: r => { const v = record('ring', { frame: r }); rings.push(v); return v; } } };
      default: throw new Error('unerwartet: $.' + String(prop));
    }
  } });
  const ObjC = {
    import: () => {},
    unwrap: v => (v && v.__str !== undefined ? v.__str : undefined),
    registerSubclass: def => {
      if (opts.noSubclass) throw new Error('registerSubclass nicht verfuegbar');
      if (!def || def.name !== 'GGRingView' || !def.methods['drawRect:']) throw new Error('falsche Definition');
      ringClass = def; calls.push('registerSubclass');
    },
  };
  let fake = 1e12;
  const FakeDate = class extends Date { static now() { fake += 50; return fake; } };
  const ctx = { ObjC, $, delay: () => { calls.push('delay'); }, Math, Date: FakeDate, parseInt, String, Error };
  vm.createContext(ctx);
  vm.runInContext(src, ctx);
  return { ctx, calls, labels, windows, rings, colors, elapsed: () => (fake - 1e12) / 1000 };
}

function overlap(a, b) {
  const ax2 = a.origin.x + a.size.width, ay2 = a.origin.y + a.size.height;
  const bx2 = b.origin.x + b.size.width, by2 = b.origin.y + b.size.height;
  return a.origin.x < bx2 - 0.01 && b.origin.x < ax2 - 0.01 && a.origin.y < by2 - 0.01 && b.origin.y < ay2 - 0.01;
}

let failures = 0;
function test(name, opts, args, expect) {
  const w = makeWorld(opts);
  const problems = [];
  let result, error = null;
  try { result = w.ctx.run(args); } catch (e) { error = e; }
  if (expect.throws) {
    if (!error) problems.push('haette abbrechen muessen');
  } else {
    if (error) problems.push('Fehler: ' + error.message);
    if (result !== 'ok') problems.push('Rueckgabe ' + result);
    if (expect.loops && (w.calls.filter(c => c.startsWith(expect.pumpCall || 'nextEvent')).length < expect.loops)) problems.push('zu wenige Durchlaeufe');
    const n = opts.noScreens ? 0 : 2;
    if (w.windows.length !== n) problems.push(w.windows.length + ' Fenster statt ' + n);
    if (w.labels.length !== n * PER_WINDOW) problems.push(w.labels.length + ' Textfelder statt ' + n * PER_WINDOW);
    const want = expect.texts || {};
    for (const idx of Object.keys(want)) {
      const got = w.labels[Number(idx)].props.stringValue;
      if (got !== want[idx]) problems.push('Feld ' + idx + ': [' + got + '] statt [' + want[idx] + ']');
    }
    w.windows.forEach((win, si) => {
      const L = w.labels.slice(si * PER_WINDOW, (si + 1) * PER_WINDOW);
      if (win.props.level !== 1000) problems.push('Fensterebene ' + win.props.level);
      if (win.props.opaque !== true || !win.props.backgroundColor) problems.push('Hintergrund fehlt');
      if (win.props.collectionBehavior !== 273) problems.push('collectionBehavior ' + win.props.collectionBehavior);
      if (win.frame !== screens[si].frame) problems.push('Fenster deckt Bildschirm ' + si + ' nicht ab');
      if (win.props.alphaValue !== undefined && win.props.alphaValue !== 1) problems.push('Fenster ' + si + ' am Ende nicht voll sichtbar (alpha ' + win.props.alphaValue + ')');
      const expectSub = PER_WINDOW + (expect.ring === false ? 0 : 1);
      if (win.subviews.length !== expectSub) problems.push('Fenster ' + si + ' hat ' + win.subviews.length + ' Unteransichten statt ' + expectSub);
      if (win.ordered !== false) problems.push('Fenster ' + si + ' am Ende nicht ausgeblendet');
      // Ausrichtung und Stil
      const al = expect.align;
      [HEAD, NUMBER, MSG, DETAIL, FOOT].forEach(k => { if (L[k].props.alignment !== al.center) problems.push('Feld ' + k + ' nicht zentriert (' + L[k].props.alignment + ')'); });
      if (L[BRAND].props.alignment !== 0) problems.push('Marke nicht links');
      if (L[COUNTER].props.alignment !== al.right) problems.push('Zaehler nicht rechts (' + L[COUNTER].props.alignment + ')');
      L.forEach((l, k) => {
        for (const p of ['bezeled', 'editable', 'selectable']) if (l.props[p] !== false) problems.push(p + ' nicht false (Feld ' + k + ')');
        if (k === BAR) { if (l.props.drawsBackground !== true || !l.props.backgroundColor) problems.push('Akzentlinie ohne Farbe'); }
        else {
          if (l.props.drawsBackground !== false) problems.push('drawsBackground nicht false (Feld ' + k + ')');
          if (!l.props.font || !l.props.textColor) problems.push('Schrift/Farbe fehlt (Feld ' + k + ')');
        }
      });
      // Innerhalb des Bildschirms, keine Ueberlappung (die Zahl sitzt absichtlich im Ring)
      const size = screens[si].frame.size;
      L.forEach((l, k) => {
        const f = l.frame;
        if (f.origin.x < 0 || f.origin.y < 0 || f.origin.x + f.size.width > size.width + 0.01 || f.origin.y + f.size.height > size.height + 0.01) problems.push('Feld ' + k + ' ausserhalb: ' + JSON.stringify(f));
      });
      for (let a = 0; a < L.length; a++) for (let b = a + 1; b < L.length; b++) {
        if (overlap(L[a].frame, L[b].frame)) problems.push('Felder ' + a + ' und ' + b + ' ueberlappen auf Bildschirm ' + si);
      }
      if (expect.ring !== false) {
        const r = w.rings[si];
        if (!r) problems.push('kein Ring auf Bildschirm ' + si);
        else {
          if (!overlap(r.frame, L[NUMBER].frame)) problems.push('Zahl sitzt nicht im Ring');
          if (overlap(r.frame, L[HEAD].frame) || overlap(r.frame, L[MSG].frame)) problems.push('Ring ueberlappt Text');
          if (!w.calls.some(c => c === 'ring.setNeedsDisplay' || c === 'ring.needsDisplay=')) problems.push('Ring wird nie neu gezeichnet');
        }
      }
      if (!/noch 1 s$/.test(L[FOOT].props.stringValue)) problems.push('Countdown endet bei [' + L[FOOT].props.stringValue + ']');
      if (L[NUMBER].props.stringValue !== '1') problems.push('Zahl endet bei [' + L[NUMBER].props.stringValue + ']');
    });
    for (const need of expect.calls || []) if (!w.calls.some(c => c.includes(need))) problems.push('Aufruf fehlt: ' + need);
    for (const not of expect.notCalls || []) if (w.calls.some(c => c.includes(not))) problems.push('unerwarteter Aufruf: ' + not);
    for (const col of expect.colors || []) if (!w.colors.some(c => c.includes(col))) problems.push('Farbe fehlt: ' + col);
  }
  if (problems.length) failures++;
  console.log((problems.length ? 'FAIL  ' : 'ok    ') + name + (problems.length ? '\n        ' + [...new Set(problems)].join('\n        ') : ''));
}

const os = require('os');
const tmp3 = os.tmpdir() + '/ov_test3.txt';
fs.writeFileSync(tmp3, 'STOPP.\nDeine Ziele warten nicht, bis du fertig gescrollt hast.\nyoutube.com wurde geschlossen. Erster Ausrutscher heute.\n');
const tmp6 = os.tmpdir() + '/ov_test6.txt';
fs.writeFileSync(tmp6, 'JAGD ERKANNT.\nKurz durchatmen.\nyoutube.com wurde geschlossen.\nAUSRUTSCHER 03 · 60 S · JAGD\nyoutube.com\nruhig\n');
const T3 = { [HEAD]: 'STOPP.', [MSG]: 'Deine Ziele warten nicht, bis du fertig gescrollt hast.', [DETAIL]: 'youtube.com wurde geschlossen. Erster Ausrutscher heute.', [BRAND]: 'GRINDGUARD', [COUNTER]: '' };
const ARM = { center: 1, right: 2 }, INTEL = { center: 2, right: 1 };
const base = ['initWindow(0,2,false)', 'setActivationPolicy(1)', 'finishLaunching', 'orderFrontRegardless', 'display', 'activateIgnoringOtherApps(true)', 'orderOut', 'registerSubclass'];
const fadeCalls = ['beginGrouping', 'setDuration(0.15)', 'animator.setAlphaValue(1)', 'endGrouping'];

test('Normalfall, Apple-Prozessor', {}, ['4', tmp3, 'arm64'], { texts: T3, align: ARM, loops: 10, calls: base.concat(fadeCalls, ['nextEvent(9007199254740991,kCFRunLoopDefaultMode,true)', 'window.setLevel', 'label.setStringValue']), notCalls: ['sendEvent', 'runUntilDate'], colors: ['srgb(0.93,0.18,0.24,1)'] });
test('Normalfall, Intel-Prozessor', {}, ['12', tmp3, 'x86_64'], { texts: T3, align: INTEL, loops: 30, calls: base });
test('Sechs Zeilen: Zaehler, Ton ruhig -> blauer Akzent', {}, ['4', tmp6, 'arm64'], { texts: { [HEAD]: 'JAGD ERKANNT.', [COUNTER]: 'AUSRUTSCHER 03 · 60 S · JAGD' }, align: ARM, calls: base, colors: ['srgb(0.4,0.68,0.98,1)'] });
test('Bewegung reduzieren: kein Einblenden', { reduceMotion: true }, ['4', tmp3, 'arm64'], { texts: T3, align: ARM, calls: base, notCalls: ['beginGrouping', 'animator.setAlphaValue'] });
test('kein animator: Sicherheitsnetz blendet hart ein', { noAnimator: true }, ['4', tmp3, 'arm64'], { texts: T3, align: ARM, calls: base.concat(['window.setAlphaValue']) });
test('registerSubclass fehlt: ohne Ring, sonst gleich', { noSubclass: true }, ['4', tmp3, 'arm64'], { texts: T3, align: ARM, ring: false, calls: base.filter(c => c !== 'registerSubclass') });
test('aeltere Schrift-API und Farbraum', { oldFonts: true, noSRGB: true }, ['4', tmp3, 'arm64'], { texts: T3, align: ARM, calls: base, colors: ['cal('] });
test('Bruecke kennt keine Setter-Methoden -> Zuweisung', { noSetters: true }, ['4', tmp3, 'arm64'], { texts: T3, align: ARM, calls: base.concat(['label.stringValue=', 'window.level=']), notCalls: ['label.setStringValue'] });
test('Ereignisse werden weitergereicht', { events: true }, ['4', tmp3, 'arm64'], { texts: T3, align: ARM, calls: base.concat(['sendEvent']) });
test('Ereignisschleife wirft -> RunLoop als Ersatz', { pumpThrows: true }, ['4', tmp3, 'arm64'], { texts: T3, align: ARM, loops: 10, pumpCall: 'runUntilDate', calls: base.concat(['runUntilDate']), notCalls: ['sendEvent'] });
test('aelteres macOS ohne app.activate', { oldMac: true }, ['4', tmp3, 'arm64'], { texts: T3, align: ARM, calls: base });
test('Textdatei fehlt -> Standardtexte', {}, ['5', '/gibt/es/nicht', 'arm64'], { texts: { [HEAD]: 'STOPP.', [MSG]: 'Zurück an die Arbeit. Jetzt.', [DETAIL]: '' }, align: ARM, calls: base });
test('unsinnige Sekunden -> 10', {}, ['abc', tmp3, 'arm64'], { texts: T3, align: ARM, loops: 25, calls: base });
test('Obergrenze 300 Sekunden', {}, ['99999', tmp3, 'arm64'], { texts: T3, align: ARM, loops: 500, calls: base });
test('kein Fenster sichtbar -> Abbruch (Dialog uebernimmt)', { invisible: true }, ['4', tmp3, 'arm64'], { throws: true });
test('kein Bildschirm -> Abbruch', { noScreens: true }, ['4', tmp3, 'arm64'], { throws: true });
process.exit(failures ? 1 : 0);
