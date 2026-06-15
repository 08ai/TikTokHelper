/**
 * test_red_box.js v4 — Explicit NativeFunction, no wrappers
 */
function log(msg) { console.log('[RED] ' + msg); }
var GM = Module.getGlobalExportByName;
var objc_msgSend = GM('objc_msgSend');

// Shortcuts
function nf(ret, argTypes) { return new NativeFunction(objc_msgSend, ret, argTypes); }
function gc(name) {
    return new NativeFunction(GM('objc_getClass'), 'pointer', ['pointer'])(Memory.allocUtf8String(name));
}
function sel(name) {
    return new NativeFunction(GM('sel_registerName'), 'pointer', ['pointer'])(Memory.allocUtf8String(name));
}

setTimeout(function() {
    log('=== START ===');

    // 1. Get window
    var UIApp = gc('UIApplication');
    var app = nf('pointer', ['pointer', 'pointer'])(UIApp, sel('sharedApplication'));
    var keyWin = nf('pointer', ['pointer', 'pointer'])(app, sel('keyWindow'));
    log('keyWindow: ' + keyWin);

    // 2. Create view with initWithFrame:
    var UIView = gc('UIView');
    var v = nf('pointer', ['pointer', 'pointer'])(UIView, sel('alloc'));
    // initWithFrame: takes CGRect = {CGPoint, CGSize} = {double,double, double,double} = 4 doubles
    // On arm64 HFA: d0=origin.x, d1=origin.y, d2=size.width, d3=size.height
    v = nf('pointer', ['pointer','pointer','double','double','double','double'])
        (v, sel('initWithFrame:'), 300, 100, 64, 64);
    log('view: ' + v);

    // 3. Red background
    var UIColor = gc('UIColor');
    var red = nf('pointer', ['pointer','pointer','double','double','double','double'])
        (UIColor, sel('colorWithRed:green:blue:alpha:'), 1, 0.1, 0.1, 1);
    var white = nf('pointer', ['pointer','pointer','double','double','double','double'])
        (UIColor, sel('colorWithRed:green:blue:alpha:'), 1, 1, 1, 1);
    nf('void', ['pointer','pointer','pointer'])(v, sel('setBackgroundColor:'), red);
    log('bg set');

    // 4. Layer
    var layer = nf('pointer', ['pointer','pointer'])(v, sel('layer'));
    nf('void', ['pointer','pointer','double'])(layer, sel('setCornerRadius:'), 16);
    nf('void', ['pointer','pointer','double'])(layer, sel('setBorderWidth:'), 4);
    nf('void', ['pointer','pointer','pointer'])(layer, sel('setBorderColor:'),
        nf('pointer', ['pointer','pointer'])(white, sel('CGColor')));
    log('layer styled');

    // 5. Add to keyWindow via performSelectorOnMainThread
    var perfFunc = nf('void', ['pointer','pointer','pointer','pointer','char']);
    perfFunc(keyWin, sel('performSelectorOnMainThread:withObject:waitUntilDone:'),
        sel('addSubview:'), v, 1);
    log('addSubview done on main thread');

    // 6. Bring to front
    perfFunc(keyWin, sel('performSelectorOnMainThread:withObject:waitUntilDone:'),
        sel('bringSubviewToFront:'), v, 1);
    log('bringToFront done');

    // 7. Re-front loop
    for (var i = 1; i <= 6; i++) {
        setTimeout((function(ii) { return function() {
            perfFunc(keyWin, sel('performSelectorOnMainThread:withObject:waitUntilDone:'),
                sel('bringSubviewToFront:'), v, 1);
            log('front #' + ii);
        };})(i), i * 2000);
    }

    log('=== DONE === Look at TikTok now!');
}, 8000);

setTimeout(function() { log('loaded'); }, 1000);
