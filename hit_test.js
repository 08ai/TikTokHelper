/**
 * hit_test.js — Hook UIWindow.hitTest:withEvent: to detect touches on our button
 * This bypasses TikTok's gesture interceptors
 */
console.log('[H] Hit test hook');
var ms = Module.getGlobalExportByName('objc_msgSend');
var oc = new NativeFunction(Module.getGlobalExportByName('objc_getClass'), 'pointer', ['pointer']);
var sr = new NativeFunction(Module.getGlobalExportByName('sel_registerName'), 'pointer', ['pointer']);
function C(n) { return oc(Memory.allocUtf8String(n)); }
function S(n) { return sr(Memory.allocUtf8String(n)); }
function nf(r, a) { return new NativeFunction(ms, r, a); }

setTimeout(function() {
    console.log('[H] === START ===');

    // Get window
    var app = nf('pointer',['pointer','pointer'])(C('UIApplication'), S('sharedApplication'));
    var win = nf('pointer',['pointer','pointer'])(app, S('keyWindow'));
    console.log('[H] win: ' + win);

    // Create button
    var btn = nf('pointer',['pointer','pointer'])(C('UIButton'), S('alloc'));
    btn = nf('pointer',['pointer','pointer','double','double','double','double'])
        (btn, S('initWithFrame:'), 280, 100, 90, 50);
    var red = nf('pointer',['pointer','pointer','double','double','double','double'])
        (C('UIColor'), S('colorWithRed:green:blue:alpha:'), 0.9, 0.1, 0.1, 0.92);
    var white = nf('pointer',['pointer','pointer','double','double','double','double'])
        (C('UIColor'), S('colorWithRed:green:blue:alpha:'), 1, 1, 1, 1);
    var yellow = nf('pointer',['pointer','pointer','double','double','double','double'])
        (C('UIColor'), S('colorWithRed:green:blue:alpha:'), 1, 0.9, 0, 0.95);
    nf('void',['pointer','pointer','pointer'])(btn, S('setBackgroundColor:'), red);
    var nsT = nf('pointer',['pointer','pointer','pointer'])(C('NSString'), S('stringWithUTF8String:'), Memory.allocUtf8String('展开'));
    nf('void',['pointer','pointer','pointer','uint64'])(btn, S('setTitle:forState:'), nsT, 0);
    nf('void',['pointer','pointer','pointer','uint64'])(btn, S('setTitleColor:forState:'), white, 0);
    var lbl = nf('pointer',['pointer','pointer'])(btn, S('titleLabel'));
    nf('void',['pointer','pointer','pointer'])(lbl, S('setFont:'), nf('pointer',['pointer','pointer','double'])(C('UIFont'), S('boldSystemFontOfSize:'), 18));
    var ly = nf('pointer',['pointer','pointer'])(btn, S('layer'));
    nf('void',['pointer','pointer','double'])(ly, S('setCornerRadius:'), 16);
    nf('void',['pointer','pointer','double'])(ly, S('setBorderWidth:'), 2.5);
    nf('void',['pointer','pointer','pointer'])(ly, S('setBorderColor:'), nf('pointer',['pointer','pointer'])(white, S('CGColor')));
    var perf = nf('void',['pointer','pointer','pointer','pointer','char']);
    perf(win, S('performSelectorOnMainThread:withObject:waitUntilDone:'), S('addSubview:'), btn, 1);
    console.log('[H] btn added');

    // Create panel
    var panel = nf('pointer',['pointer','pointer'])(C('UIView'), S('alloc'));
    panel = nf('pointer',['pointer','pointer','double','double','double','double'])
        (panel, S('initWithFrame:'), 100, 80, 175, 215);
    nf('void',['pointer','pointer','pointer'])(panel, S('setBackgroundColor:'), yellow);
    var ply = nf('pointer',['pointer','pointer'])(panel, S('layer'));
    nf('void',['pointer','pointer','double'])(ply, S('setCornerRadius:'), 14);
    nf('void',['pointer','pointer','double'])(ply, S('setBorderWidth:'), 3);
    nf('void',['pointer','pointer','pointer'])(ply, S('setBorderColor:'), nf('pointer',['pointer','pointer'])(white, S('CGColor')));
    nf('void',['pointer','pointer','double'])(panel, S('setAlpha:'), 0);
    perf(win, S('performSelectorOnMainThread:withObject:waitUntilDone:'), S('addSubview:'), panel, 1);
    console.log('[H] panel added (alpha=0)');

    // === HOOK: Intercept UIView.hitTest:withEvent: on ALL views ===
    // When ANY view's hitTest is called, check if the touch point is on our button
    var UIWindow = C('UIWindow');
    var getMethod = new NativeFunction(Module.getGlobalExportByName('class_getInstanceMethod'), 'pointer', ['pointer','pointer']);
    var getImp = new NativeFunction(Module.getGlobalExportByName('method_getImplementation'), 'pointer', ['pointer']);

    // Try hooking hitTest on the specific window class
    var winClass = nf('pointer',['pointer','pointer'])(win, S('class'));
    var method = getMethod(winClass, S('hitTest:withEvent:'));
    if (!method.isNull()) {
        var imp = getImp(method);
        console.log('[H] hitTest IMP: ' + imp);

        var touchCount = 0;
        Interceptor.attach(imp, {
            onEnter: function(args) {
                touchCount++;
                // args[0]=self(UIWindow), args[1]=_cmd, args[2]=CGPoint, args[3]=UIEvent
                // CGPoint is 2 doubles in d0/d1 registers
                // We can't easily read from FP registers...
                // BUT: we can check the return value (the view that gets the touch)
            },
            onLeave: function(retval) {
                if (touchCount <= 10) {
                    console.log('[H] hitTest #' + touchCount + ' -> view=' + retval);
                }
                if (touchCount === 20) console.log('[H] hitTest still active');
            }
        });
        console.log('[H] hitTest hook ACTIVE');
    } else {
        console.log('[H] hitTest method NOT FOUND');
    }

    console.log('[H] === READY === Tap the right side of screen');
}, 7000);

setTimeout(function(){ console.log('[H] loaded'); }, 500);
