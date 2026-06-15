/**
 * build.js — Step-by-step: RED btn + YELLOW panel
 * Uses the SAME pattern as working test_red_box.js v4
 */
console.log('[B] Start');
var ms = Module.getGlobalExportByName('objc_msgSend');
var oc = new NativeFunction(Module.getGlobalExportByName('objc_getClass'), 'pointer', ['pointer']);
var sr = new NativeFunction(Module.getGlobalExportByName('sel_registerName'), 'pointer', ['pointer']);
function C(n) { return oc(Memory.allocUtf8String(n)); }
function S(n) { return sr(Memory.allocUtf8String(n)); }

// CRITICAL: use the exact same pattern as test_red_box v4
function nf(ret, types) { return new NativeFunction(ms, ret, types); }

setTimeout(function() {
    console.log('[B] === BUILD ===');

    // 1. Window
    var app = nf('pointer',['pointer','pointer'])(C('UIApplication'), S('sharedApplication'));
    var win = nf('pointer',['pointer','pointer'])(app, S('keyWindow'));
    console.log('[B] win ok');

    // 2. Red button
    var btn = nf('pointer',['pointer','pointer'])(C('UIButton'), S('alloc'));
    btn = nf('pointer',['pointer','pointer','double','double','double','double'])
        (btn, S('initWithFrame:'), 280, 90, 90, 50);
    console.log('[B] btn alloc');

    var red = nf('pointer',['pointer','pointer','double','double','double','double'])
        (C('UIColor'), S('colorWithRed:green:blue:alpha:'), 0.92, 0.12, 0.12, 0.92);
    var white = nf('pointer',['pointer','pointer','double','double','double','double'])
        (C('UIColor'), S('colorWithRed:green:blue:alpha:'), 1, 1, 1, 1);
    var yellow = nf('pointer',['pointer','pointer','double','double','double','double'])
        (C('UIColor'), S('colorWithRed:green:blue:alpha:'), 0.98, 0.85, 0.05, 0.95);
    var blue = nf('pointer',['pointer','pointer','double','double','double','double'])
        (C('UIColor'), S('colorWithRed:green:blue:alpha:'), 0.18, 0.5, 0.92, 0.9);
    var green = nf('pointer',['pointer','pointer','double','double','double','double'])
        (C('UIColor'), S('colorWithRed:green:blue:alpha:'), 0.15, 0.72, 0.35, 0.9);
    var orange = nf('pointer',['pointer','pointer','double','double','double','double'])
        (C('UIColor'), S('colorWithRed:green:blue:alpha:'), 0.88, 0.48, 0.12, 0.9);
    console.log('[B] colors ok');

    // Configure button
    nf('void',['pointer','pointer','pointer'])(btn, S('setBackgroundColor:'), red);
    var nsTitle = nf('pointer',['pointer','pointer','pointer'])
        (C('NSString'), S('stringWithUTF8String:'), Memory.allocUtf8String('展开'));
    nf('void',['pointer','pointer','pointer','uint64'])(btn, S('setTitle:forState:'), nsTitle, 0);
    nf('void',['pointer','pointer','pointer','uint64'])(btn, S('setTitleColor:forState:'), white, 0);
    var lbl = nf('pointer',['pointer','pointer'])(btn, S('titleLabel'));
    var font = nf('pointer',['pointer','pointer','double'])(C('UIFont'), S('boldSystemFontOfSize:'), 18);
    nf('void',['pointer','pointer','pointer'])(lbl, S('setFont:'), font);
    var ly = nf('pointer',['pointer','pointer'])(btn, S('layer'));
    nf('void',['pointer','pointer','double'])(ly, S('setCornerRadius:'), 16);
    nf('void',['pointer','pointer','double'])(ly, S('setBorderWidth:'), 2.5);
    nf('void',['pointer','pointer','pointer'])(ly, S('setBorderColor:'), nf('pointer',['pointer','pointer'])(white, S('CGColor')));
    nf('void',['pointer','pointer','char'])(btn, S('setUserInteractionEnabled:'), 1);

    // Add to window
    var perf = nf('void',['pointer','pointer','pointer','pointer','char']);
    perf(win, S('performSelectorOnMainThread:withObject:waitUntilDone:'), S('addSubview:'), btn, 1);
    perf(win, S('performSelectorOnMainThread:withObject:waitUntilDone:'), S('bringSubviewToFront:'), btn, 1);
    // Verify button is actually in hierarchy
    var sv = nf('pointer',['pointer','pointer'])(btn, S('superview'));
    var w = nf('pointer',['pointer','pointer'])(btn, S('window'));
    console.log('[B] btn superview=' + sv + ' window=' + w);
    // If superview is null, button wasn't added!
    if (sv.isNull()) {
        console.log('[B] WARN: btn has no superview! Trying direct add...');
        nf('void',['pointer','pointer','pointer'])(win, S('addSubview:'), btn);
        sv = nf('pointer',['pointer','pointer'])(btn, S('superview'));
        console.log('[B] after direct add: superview=' + sv);
    }
    console.log('[B] red btn ready');

    // 3. Yellow panel (left side, always visible)
    var panel = nf('pointer',['pointer','pointer'])(C('UIView'), S('alloc'));
    panel = nf('pointer',['pointer','pointer','double','double','double','double'])
        (panel, S('initWithFrame:'), 105, 80, 175, 215);
    nf('void',['pointer','pointer','pointer'])(panel, S('setBackgroundColor:'), yellow);
    var ply = nf('pointer',['pointer','pointer'])(panel, S('layer'));
    nf('void',['pointer','pointer','double'])(ply, S('setCornerRadius:'), 14);
    nf('void',['pointer','pointer','double'])(ply, S('setBorderWidth:'), 3);
    nf('void',['pointer','pointer','pointer'])(ply, S('setBorderColor:'), nf('pointer',['pointer','pointer'])(white, S('CGColor')));

    // 3 sub-buttons
    var defs = [
        {t:'自动关注', y:12, c:blue},
        {t:'自动私信', y:74, c:green},
        {t:'自动养号', y:136, c:orange},
    ];
    for (var i = 0; i < 3; i++) {
        var d = defs[i];
        var pb = nf('pointer',['pointer','pointer'])(C('UIButton'), S('alloc'));
        pb = nf('pointer',['pointer','pointer','double','double','double','double'])
            (pb, S('initWithFrame:'), 12, d.y, 151, 52);
        nf('void',['pointer','pointer','pointer'])(pb, S('setBackgroundColor:'), d.c);
        var pbt = nf('pointer',['pointer','pointer','pointer'])
            (C('NSString'), S('stringWithUTF8String:'), Memory.allocUtf8String(d.t));
        nf('void',['pointer','pointer','pointer','uint64'])(pb, S('setTitle:forState:'), pbt, 0);
        nf('void',['pointer','pointer','pointer','uint64'])(pb, S('setTitleColor:forState:'), white, 0);
        var plb = nf('pointer',['pointer','pointer'])(pb, S('titleLabel'));
        nf('void',['pointer','pointer','pointer'])(plb, S('setFont:'),
            nf('pointer',['pointer','pointer','double'])(C('UIFont'), S('boldSystemFontOfSize:'), 16));
        var ply2 = nf('pointer',['pointer','pointer'])(pb, S('layer'));
        nf('void',['pointer','pointer','double'])(ply2, S('setCornerRadius:'), 10);
        nf('void',['pointer','pointer','pointer'])(panel, S('addSubview:'), pb);
        nf('void',['pointer','pointer','char'])(pb, S('setUserInteractionEnabled:'), 1);
    }
    console.log('[B] panel btns ok');

    // Add panel to window (START with alpha=0, invisible)
    nf('void',['pointer','pointer','double'])(panel, S('setAlpha:'), 0); // start hidden
    perf(win, S('performSelectorOnMainThread:withObject:waitUntilDone:'), S('addSubview:'), panel, 1);
    perf(win, S('performSelectorOnMainThread:withObject:waitUntilDone:'), S('bringSubviewToFront:'), btn, 1);
    console.log('[B] panel added (alpha=0)');

    // 4. Tap detection
    var _wasHi = false;
    var _expanded = false;
    var _pollCount = 0;
    setInterval(function() {
        try {
            _pollCount++;
            if (_pollCount % 50 === 0) console.log('[B] poll alive #' + _pollCount);
            var hi = nf('char',['pointer','pointer'])(btn, S('isHighlighted'));
            if (hi && !_wasHi) {
                _wasHi = true;
                _expanded = !_expanded;
                var newTitle = nf('pointer',['pointer','pointer','pointer'])
                    (C('NSString'), S('stringWithUTF8String:'), Memory.allocUtf8String(_expanded ? '收起' : '展开'));
                nf('void',['pointer','pointer','pointer','uint64'])(btn, S('setTitle:forState:'), newTitle, 0);
                // Set alpha value (model layer)
                nf('void',['pointer','pointer','double'])(panel, S('setAlpha:'), _expanded ? 1 : 0);
                nf('void',['pointer','pointer','char'])(panel, S('setHidden:'), _expanded ? 0 : 1);
                // Trigger main-thread re-render
                var perf2 = nf('void',['pointer','pointer','pointer','pointer','char']);
                perf2(panel, S('performSelectorOnMainThread:withObject:waitUntilDone:'),
                    S('setNeedsLayout'), new NativePointer(0), 0);
                perf2(panel, S('performSelectorOnMainThread:withObject:waitUntilDone:'),
                    S('layoutIfNeeded'), new NativePointer(0), 1);
                if (_expanded) {
                    perf(win, S('performSelectorOnMainThread:withObject:waitUntilDone:'), S('bringSubviewToFront:'), panel, 1);
                    perf(win, S('performSelectorOnMainThread:withObject:waitUntilDone:'), S('bringSubviewToFront:'), btn, 1);
                }
                console.log('[B] ' + (_expanded ? 'OPEN (panel visible)' : 'CLOSE (panel hidden)'));
            }
            if (!hi && _wasHi) _wasHi = false;
        } catch(e) {}
    }, 150);

    console.log('[B] === ALL DONE ===');
}, 7000);

setTimeout(function(){ console.log('[B] loaded'); }, 500);
