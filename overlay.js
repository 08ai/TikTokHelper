/**
 * overlay.js — Creates a SEPARATE high-level UIWindow for our button
 * This window floats ABOVE TikTok's content and receives touches independently
 */
console.log('[O] Overlay window');
var ms = Module.getGlobalExportByName('objc_msgSend');
var oc = new NativeFunction(Module.getGlobalExportByName('objc_getClass'), 'pointer', ['pointer']);
var sr = new NativeFunction(Module.getGlobalExportByName('sel_registerName'), 'pointer', ['pointer']);
function C(n) { return oc(Memory.allocUtf8String(n)); }
function S(n) { return sr(Memory.allocUtf8String(n)); }
function nf(r, a) { return new NativeFunction(ms, r, a); }

setTimeout(function() {
    console.log('[O] === START ===');

    // 1. Create a NEW UIWindow with high windowLevel
    var UIWindow = C('UIWindow');
    var screen = nf('pointer',['pointer','pointer'])(C('UIScreen'), S('mainScreen'));
    var bounds = nf('pointer',['pointer','pointer'])(screen, S('bounds'));
    // CGRect is tricky — just use initWithFrame with screen size
    var ovWin = nf('pointer',['pointer','pointer'])(UIWindow, S('alloc'));
    ovWin = nf('pointer',['pointer','pointer','double','double','double','double'])
        (ovWin, S('initWithFrame:'), 0, 0, 375, 812); // iPhone X

    // Set window level HIGHER than normal (UIWindowLevelNormal=0, Alert=2000, StatusBar=1000)
    // Use 100 to float above TikTok but below alerts
    nf('void',['pointer','pointer','double'])(ovWin, S('setWindowLevel:'), 100);
    // Transparent background
    nf('void',['pointer','pointer','pointer'])(ovWin, S('setBackgroundColor:'),
        nf('pointer',['pointer','pointer','double','double','double','double'])
        (C('UIColor'), S('colorWithWhite:alpha:'), 0, 0.01)); // nearly transparent
    // Make it visible
    nf('void',['pointer','pointer','char'])(ovWin, S('setHidden:'), 0);
    // Don't become key window (let TikTok remain key)
    // Just make it visible
    nf('void',['pointer','pointer','char'])(ovWin, S('makeKeyAndVisible'), 1);
    console.log('[O] overlay window: ' + ovWin);

    // 2. Create red button on overlay window
    var colors = {};
    ['red','white','yellow','blue','green','orange'].forEach(function(c, i) {
        var vals = {
            red: [0.9,0.1,0.1,0.92],
            white: [1,1,1,1],
            yellow: [1,0.9,0,0.95],
            blue: [0.18,0.5,0.92,0.9],
            green: [0.15,0.72,0.35,0.9],
            orange: [0.88,0.48,0.12,0.9],
        }[c];
        colors[c] = nf('pointer',['pointer','pointer','double','double','double','double'])
            (C('UIColor'), S('colorWithRed:green:blue:alpha:'), vals[0], vals[1], vals[2], vals[3]);
    });

    var btn = nf('pointer',['pointer','pointer'])(C('UIButton'), S('alloc'));
    btn = nf('pointer',['pointer','pointer','double','double','double','double'])
        (btn, S('initWithFrame:'), 280, 100, 90, 50);
    nf('void',['pointer','pointer','pointer'])(btn, S('setBackgroundColor:'), colors.red);
    var pbt = nf('pointer',['pointer','pointer','pointer'])(C('NSString'), S('stringWithUTF8String:'), Memory.allocUtf8String('展开'));
    nf('void',['pointer','pointer','pointer','uint64'])(btn, S('setTitle:forState:'), pbt, 0);
    nf('void',['pointer','pointer','pointer','uint64'])(btn, S('setTitleColor:forState:'), colors.white, 0);
    var lbl = nf('pointer',['pointer','pointer'])(btn, S('titleLabel'));
    nf('void',['pointer','pointer','pointer'])(lbl, S('setFont:'), nf('pointer',['pointer','pointer','double'])(C('UIFont'), S('boldSystemFontOfSize:'), 18));
    var ly = nf('pointer',['pointer','pointer'])(btn, S('layer'));
    nf('void',['pointer','pointer','double'])(ly, S('setCornerRadius:'), 16);
    nf('void',['pointer','pointer','double'])(ly, S('setBorderWidth:'), 2.5);
    nf('void',['pointer','pointer','pointer'])(ly, S('setBorderColor:'), nf('pointer',['pointer','pointer'])(colors.white, S('CGColor')));
    nf('void',['pointer','pointer','pointer'])(ovWin, S('addSubview:'), btn);
    console.log('[O] btn on overlay: ' + btn);

    // 3. Create panel on overlay window
    var panel = nf('pointer',['pointer','pointer'])(C('UIView'), S('alloc'));
    panel = nf('pointer',['pointer','pointer','double','double','double','double'])
        (panel, S('initWithFrame:'), 100, 80, 175, 215);
    nf('void',['pointer','pointer','pointer'])(panel, S('setBackgroundColor:'), colors.yellow);
    var ply = nf('pointer',['pointer','pointer'])(panel, S('layer'));
    nf('void',['pointer','pointer','double'])(ply, S('setCornerRadius:'), 14);
    nf('void',['pointer','pointer','double'])(ply, S('setBorderWidth:'), 3);
    nf('void',['pointer','pointer','pointer'])(ply, S('setBorderColor:'), nf('pointer',['pointer','pointer'])(colors.white, S('CGColor')));
    nf('void',['pointer','pointer','double'])(panel, S('setAlpha:'), 0);
    nf('void',['pointer','pointer','pointer'])(ovWin, S('addSubview:'), panel);

    // 4 buttons on panel
    var btns = [
        {t:'自动关注', y:12, c:colors.blue},
        {t:'自动私信', y:74, c:colors.green},
        {t:'自动养号', y:136, c:colors.orange},
    ];
    for (var i = 0; i < 3; i++) {
        var d = btns[i];
        var pb = nf('pointer',['pointer','pointer'])(C('UIButton'), S('alloc'));
        pb = nf('pointer',['pointer','pointer','double','double','double','double'])(pb, S('initWithFrame:'), 12, d.y, 151, 52);
        nf('void',['pointer','pointer','pointer'])(pb, S('setBackgroundColor:'), d.c);
        var tstr = nf('pointer',['pointer','pointer','pointer'])(C('NSString'), S('stringWithUTF8String:'), Memory.allocUtf8String(d.t));
        nf('void',['pointer','pointer','pointer','uint64'])(pb, S('setTitle:forState:'), tstr, 0);
        nf('void',['pointer','pointer','pointer','uint64'])(pb, S('setTitleColor:forState:'), colors.white, 0);
        var plb = nf('pointer',['pointer','pointer'])(pb, S('titleLabel'));
        nf('void',['pointer','pointer','pointer'])(plb, S('setFont:'), nf('pointer',['pointer','pointer','double'])(C('UIFont'), S('boldSystemFontOfSize:'), 16));
        var ply2 = nf('pointer',['pointer','pointer'])(pb, S('layer'));
        nf('void',['pointer','pointer','double'])(ply2, S('setCornerRadius:'), 10);
        nf('void',['pointer','pointer','pointer'])(panel, S('addSubview:'), pb);
    }
    console.log('[O] panel ready');

    // 5. Tap detection via isHighlighted (NOW on independent window, should work!)
    var _wasHi = false;
    var _expanded = false;
    setInterval(function() {
        try {
            var hi = nf('char',['pointer','pointer'])(btn, S('isHighlighted'));
            if (hi && !_wasHi) {
                _wasHi = true;
                _expanded = !_expanded;
                var newT = nf('pointer',['pointer','pointer','pointer'])(C('NSString'), S('stringWithUTF8String:'), Memory.allocUtf8String(_expanded ? '收起' : '展开'));
                nf('void',['pointer','pointer','pointer','uint64'])(btn, S('setTitle:forState:'), newT, 0);
                nf('void',['pointer','pointer','double'])(panel, S('setAlpha:'), _expanded ? 1 : 0);
                console.log('[O] ' + (_expanded ? 'OPEN' : 'CLOSE'));
            }
            if (!hi && _wasHi) _wasHi = false;
        } catch(e) {}
    }, 150);

    console.log('[O] === READY — independent overlay window ===');
}, 7000);

setTimeout(function(){ console.log('[O] loaded'); }, 500);
