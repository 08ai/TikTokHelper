/**
 * quick_test.js — 极简测试：红色按钮 + 黄色面板（始终可见）
 * 确认 UI 能否正常渲染
 */
console.log('[Q] === QUICK TEST ===');
var GM = Module.getGlobalExportByName;
var ms = GM('objc_msgSend');

// Pre-allocated NativeFunctions (critical: avoid dynamic creation!)
var oc = new NativeFunction(GM('objc_getClass'), 'pointer', ['pointer']);
var sr = new NativeFunction(GM('sel_registerName'), 'pointer', ['pointer']);
var p0  = new NativeFunction(ms, 'pointer', ['pointer','pointer']);
var v0  = new NativeFunction(ms, 'void',    ['pointer','pointer']);
var p1  = new NativeFunction(ms, 'pointer', ['pointer','pointer','pointer']);
var v1  = new NativeFunction(ms, 'void',    ['pointer','pointer','pointer']);
var v1d = new NativeFunction(ms, 'void',    ['pointer','pointer','double']);
var p1d = new NativeFunction(ms, 'pointer', ['pointer','pointer','double']);
var p4d = new NativeFunction(ms, 'pointer', ['pointer','pointer','double','double','double','double']);
var v4d = new NativeFunction(ms, 'void',    ['pointer','pointer','double','double','double','double']);
var p1i = new NativeFunction(ms, 'pointer', ['pointer','pointer','int64']);
var vpu = new NativeFunction(ms, 'void',    ['pointer','pointer','pointer','uint64']);
var vppc = new NativeFunction(ms, 'void',   ['pointer','pointer','pointer','pointer','char']);
var u64 = new NativeFunction(ms, 'uint64',  ['pointer','pointer']);
var ch = new NativeFunction(ms, 'char',     ['pointer','pointer']);

function C(n) { return oc(Memory.allocUtf8String(n)); }
function S(n) { return sr(Memory.allocUtf8String(n)); }
function rgb(r,g,b,a) { return p4d(C('UIColor'), S('colorWithRed:green:blue:alpha:'), r,g,b,a); }
function ns(s) { return p1(C('NSString'), S('stringWithUTF8String:'), Memory.allocUtf8String(s)); }
function perf(t, sel, o, w) { vppc(t, S('performSelectorOnMainThread:withObject:waitUntilDone:'), S(sel), o, w?1:0); }

setTimeout(function() {
    var app = p0(C('UIApplication'), S('sharedApplication'));
    var win = p0(app, S('keyWindow'));
    console.log('[Q] win=' + win);

    // === RED TOGGLE BUTTON (right side) ===
    var btn = p0(C('UIButton'), S('alloc'));
    btn = p4d(btn, S('initWithFrame:'), 285, 100, 85, 48);
    v1(btn, S('setBackgroundColor:'), rgb(0.9, 0.12, 0.12, 0.92));
    vpu(btn, S('setTitle:forState:'), ns('展开'), 0);
    vpu(btn, S('setTitleColor:forState:'), rgb(1,1,1,1), 0);
    var lb = p0(btn, S('titleLabel'));
    var _v1i = new NativeFunction(ms, 'void', ['pointer','pointer','int64']);
    v1(lb, S('setFont:'), p1d(C('UIFont'), S('boldSystemFontOfSize:'), 18));
    _v1i(lb, S('setNumberOfLines:'), 3);
    _v1i(lb, S('setTextAlignment:'), 1);
    var ly = p0(btn, S('layer'));
    v1d(ly, S('setCornerRadius:'), 16);
    v1d(ly, S('setBorderWidth:'), 2.5);
    v1(ly, S('setBorderColor:'), p0(rgb(1,1,1,0.7), S('CGColor')));
    v1(btn, S('setUserInteractionEnabled:'), 1);
    perf(win, 'addSubview:', btn, true);
    console.log('[Q] red btn created');

    // === YELLOW PANEL (left side, ALWAYS VISIBLE) ===
    var panel = p0(C('UIView'), S('alloc'));
    panel = p4d(panel, S('initWithFrame:'), 110, 90, 170, 210);
    v1(panel, S('setBackgroundColor:'), rgb(0.98, 0.85, 0.05, 0.96)); // BRIGHT YELLOW
    var ply = p0(panel, S('layer'));
    v1d(ply, S('setCornerRadius:'), 14);
    v1d(ply, S('setBorderWidth:'), 3);
    v1(ply, S('setBorderColor:'), p0(rgb(1,1,1,0.9), S('CGColor')));
    // DO NOT HIDE — always visible for test

    // 3 buttons on panel
    var btns = [
        {t:'自动关注', y:10, c:rgb(0.18,0.5,0.92,0.9)},
        {t:'自动私信', y:72, c:rgb(0.15,0.72,0.35,0.9)},
        {t:'自动养号', y:134, c:rgb(0.88,0.48,0.12,0.9)},
    ];
    for (var i = 0; i < 3; i++) {
        var d = btns[i];
        var pb = p0(C('UIButton'), S('alloc'));
        pb = p4d(pb, S('initWithFrame:'), 10, d.y, 150, 52);
        v1(pb, S('setBackgroundColor:'), d.c);
        vpu(pb, S('setTitle:forState:'), ns(d.t), 0);
        vpu(pb, S('setTitleColor:forState:'), rgb(1,1,1,1), 0);
        var plb = p0(pb, S('titleLabel'));
        v1(plb, S('setFont:'), p1d(C('UIFont'), S('boldSystemFontOfSize:'), 16));
        var ply2 = p0(pb, S('layer'));
        v1d(ply2, S('setCornerRadius:'), 10);
        v1(pb, S('setUserInteractionEnabled:'), 1);
        v1(panel, S('addSubview:'), pb);
    }

    perf(win, 'addSubview:', panel, true);
    perf(win, 'bringSubviewToFront:', panel, true);
    perf(win, 'bringSubviewToFront:', btn, true);
    console.log('[Q] YELLOW panel + buttons created — visible now!');

    // === Tap polling ===
    var expanded = false;
    var _wasHi = false;
    var _vc = new NativeFunction(ms, 'void', ['pointer','pointer','char']); // for setHidden:
    setInterval(function() {
        var hi = ch(btn, S('isHighlighted'));
        if (hi && !_wasHi) {
            _wasHi = true;
            expanded = !expanded;
            vpu(btn, S('setTitle:forState:'), ns(expanded ? '收起' : '展开'), 0);
            _vc(panel, S('setHidden:'), expanded ? 0 : 1);
            console.log('[Q] PANEL ' + (expanded ? 'SHOW' : 'HIDE'));
        }
        if (!hi && _wasHi) _wasHi = false;
    }, 150);

    console.log('[Q] === ALL DONE === Look for RED btn + YELLOW panel!');
}, 7000);

setTimeout(function(){ console.log('[Q] loaded'); }, 500);
