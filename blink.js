/**
 * blink.js v3 — Toggle via addSubview/removeFromSuperview (ALL main thread)
 */
console.log('[B3] Start');
var ms = Module.getGlobalExportByName('objc_msgSend');
var oc = new NativeFunction(Module.getGlobalExportByName('objc_getClass'), 'pointer', ['pointer']);
var sr = new NativeFunction(Module.getGlobalExportByName('sel_registerName'), 'pointer', ['pointer']);
function C(n) { return oc(Memory.allocUtf8String(n)); }
function S(n) { return sr(Memory.allocUtf8String(n)); }
function nf(r,a) { return new NativeFunction(ms, r, a); }

setTimeout(function() {
    var app = nf('pointer',['pointer','pointer'])(C('UIApplication'), S('sharedApplication'));
    var win = nf('pointer',['pointer','pointer'])(app, S('keyWindow'));

    var yellow = nf('pointer',['pointer','pointer','double','double','double','double'])
        (C('UIColor'), S('colorWithRed:green:blue:alpha:'), 1, 0.85, 0, 0.95);
    var white = nf('pointer',['pointer','pointer','double','double','double','double'])
        (C('UIColor'), S('colorWithRed:green:blue:alpha:'), 1, 1, 1, 1);
    var perf = nf('void',['pointer','pointer','pointer','pointer','char']);

    // Create panel
    var panel = nf('pointer',['pointer','pointer'])(C('UIView'), S('alloc'));
    panel = nf('pointer',['pointer','pointer','double','double','double','double'])(panel, S('initWithFrame:'), 105, 80, 175, 215);
    nf('void',['pointer','pointer','pointer'])(panel, S('setBackgroundColor:'), yellow);
    var ply = nf('pointer',['pointer','pointer'])(panel, S('layer'));
    nf('void',['pointer','pointer','double'])(ply, S('setCornerRadius:'), 14);
    nf('void',['pointer','pointer','double'])(ply, S('setBorderWidth:'), 3);
    nf('void',['pointer','pointer','pointer'])(ply, S('setBorderColor:'), nf('pointer',['pointer','pointer'])(white, S('CGColor')));

    // DO NOT add to window yet — panel starts not in hierarchy (hidden)

    // Blink: add/remove from window
    var inHierarchy = false, cnt = 0;
    setInterval(function() {
        inHierarchy = !inHierarchy; cnt++;
        if (inHierarchy) {
            perf(win, S('performSelectorOnMainThread:withObject:waitUntilDone:'), S('addSubview:'), panel, 1);
            perf(win, S('performSelectorOnMainThread:withObject:waitUntilDone:'), S('bringSubviewToFront:'), panel, 1);
        } else {
            perf(panel, S('performSelectorOnMainThread:withObject:waitUntilDone:'), S('removeFromSuperview'), new NativePointer(0), 1);
        }
        console.log('[B3] BLINK #' + cnt + ' ' + (inHierarchy ? 'ADDED' : 'REMOVED'));
    }, 3000);

    console.log('[B3] === Watch for YELLOW panel blinking ===');
}, 7000);
setTimeout(function(){ console.log('[B3] loaded'); }, 500);
