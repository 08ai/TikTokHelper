/**
 * floating_button.js — TikTok 浮动"展开"按钮注入 (Frida JS)
 *
 * 用法:
 *   frida -U -l floating_button.js -f com.ss.iphone.ugc.Ame
 *   或 Python: device.spawn + script.load + device.resume
 *
 * 注: 此版本的 frida-server 使用 Module.getGlobalExportByName (非 findExportByName)
 */

// ========== 日志 ==========
function log(msg) { console.log('[BTN] ' + msg); }

// ========== ObjC Runtime 原语 (arm64) ==========
var libobjc = 'libobjc.A.dylib';
var _objc_getClass = new NativeFunction(
    Module.getGlobalExportByName('objc_getClass'), 'pointer', ['pointer']);
var _sel_registerName = new NativeFunction(
    Module.getGlobalExportByName('sel_registerName'), 'pointer', ['pointer']);

// objc_msgSend wrappers (variadic, need different arg-count signatures)
function _msg0(id, sel) {
    return new NativeFunction(Module.getGlobalExportByName('objc_msgSend'),
        'pointer', ['pointer', 'pointer'])(id, sel);
}
function _msg1(id, sel, a1) {
    return new NativeFunction(Module.getGlobalExportByName('objc_msgSend'),
        'pointer', ['pointer', 'pointer', 'pointer'])(id, sel, a1);
}
function _msg2(id, sel, a1, a2) {
    return new NativeFunction(Module.getGlobalExportByName('objc_msgSend'),
        'pointer', ['pointer', 'pointer', 'pointer', 'pointer'])(id, sel, a1, a2);
}
function _msg3(id, sel, a1, a2, a3) {
    return new NativeFunction(Module.getGlobalExportByName('objc_msgSend'),
        'pointer', ['pointer', 'pointer', 'pointer', 'pointer', 'pointer'])(id, sel, a1, a2, a3);
}
function _msg4(id, sel, a1, a2, a3, a4) {
    return new NativeFunction(Module.getGlobalExportByName('objc_msgSend'),
        'pointer', ['pointer', 'pointer', 'pointer', 'pointer', 'pointer', 'pointer'])(id, sel, a1, a2, a3, a4);
}
function _msg1v(id, sel, a1) {
    new NativeFunction(Module.getGlobalExportByName('objc_msgSend'),
        'void', ['pointer', 'pointer', 'pointer'])(id, sel, a1);
}
function _msg2v(id, sel, a1, a2) {
    new NativeFunction(Module.getGlobalExportByName('objc_msgSend'),
        'void', ['pointer', 'pointer', 'pointer', 'pointer'])(id, sel, a1, a2);
}
function _msg3v(id, sel, a1, a2, a3) {
    new NativeFunction(Module.getGlobalExportByName('objc_msgSend'),
        'void', ['pointer', 'pointer', 'pointer', 'pointer', 'pointer'])(id, sel, a1, a2, a3);
}
function _msg1dv(id, sel, d) {
    new NativeFunction(Module.getGlobalExportByName('objc_msgSend'),
        'void', ['pointer', 'pointer', 'double'])(id, sel, d);
}
function _msg1d(id, sel, d) {
    return new NativeFunction(Module.getGlobalExportByName('objc_msgSend'),
        'pointer', ['pointer', 'pointer', 'double'])(id, sel, d);
}
function _msg1f(id, sel, f) {
    return new NativeFunction(Module.getGlobalExportByName('objc_msgSend'),
        'pointer', ['pointer', 'pointer', 'float'])(id, sel, f);
}
function _msg1fv(id, sel, f) {
    new NativeFunction(Module.getGlobalExportByName('objc_msgSend'),
        'void', ['pointer', 'pointer', 'float'])(id, sel, f);
}
function _msg4d(id, sel, d1, d2, d3, d4) {
    return new NativeFunction(Module.getGlobalExportByName('objc_msgSend'),
        'pointer', ['pointer', 'pointer', 'double', 'double', 'double', 'double'])(id, sel, d1, d2, d3, d4);
}

// ========== ObjC helpers ==========
function getClass(name) {
    return _objc_getClass(Memory.allocUtf8String(name));
}

function sel(name) {
    return _sel_registerName(Memory.allocUtf8String(name));
}

function nsstring(str) {
    return _msg1(getClass('NSString'), sel('stringWithUTF8String:'), Memory.allocUtf8String(str));
}

function readNSStr(ptr) {
    if (ptr.isNull()) return '(null)';
    return _msg0(ptr, sel('UTF8String')).readUtf8String();
}

// CGRect on arm64: returned in x0/d0/d1 registers (origin.x,origin.y,size.width,size.height)
// We can't easily read that. Use a pragmatic approach: call [NSValue valueWithCGRect:]
function getScreenSize() {
    var UIScreen = getClass('UIScreen');
    var mainScreen = _msg0(UIScreen, sel('mainScreen'));
    // [UIScreen mainScreen].bounds returns CGRect
    // 绕过: 用 performSelector + NSValue
    // 简化: 用固定值 (TikTok 支持 iPhone, 375x812 是逻辑点)
    return {width: 375, height: 812};
}

// ========== 创建浮动按钮 ==========
function createFloatingButton() {
    log('=== Creating floating button ===');

    var scr = getScreenSize();
    log('Screen: ' + scr.width + 'x' + scr.height);

    var btnSize = 58, margin = 10;
    var btnX = scr.width - btnSize - margin;
    var btnY = 150; // 放在顶部往下 150pt，避免被导航栏遮挡

    // --- UIApplication + keyWindow ---
    var app = _msg0(getClass('UIApplication'), sel('sharedApplication'));
    var keyWindow = _msg0(app, sel('keyWindow'));
    if (keyWindow.isNull()) {
        var windows = _msg0(app, sel('windows'));
        var count = _msg0(windows, sel('count'));
        for (var i = 0; i < 3; i++) {
            var w = _msg1(windows, sel('objectAtIndex:'),
                new NativePointer(i));
            if (!w.isNull()) {
                var isKey = _msg0(w, sel('isKeyWindow'));
                if (!isKey.isNull() && isKey.toInt32()) {
                    keyWindow = w;
                    break;
                }
            }
        }
        if (keyWindow.isNull()) {
            keyWindow = _msg1(windows, sel('objectAtIndex:'), new NativePointer(0));
        }
    }
    if (keyWindow.isNull()) { log('ERROR: no keyWindow'); return; }
    // Get topmost window
    var allWindows = _msg0(app, sel('windows'));
    // Use keyWindow as primary, lastObject as fallback
    keyWindow = _msg0(app, sel('keyWindow'));
    if (keyWindow.isNull()) {
        keyWindow = _msg0(allWindows, sel('lastObject'));
    }
    if (keyWindow.isNull()) {
        var f_objAt = new NativeFunction(Module.getGlobalExportByName('objc_msgSend'),
            'pointer', ['pointer', 'pointer', 'uint64']);
        keyWindow = f_objAt(allWindows, sel('objectAtIndex:'), 0);
    }
    log('Using window: ' + keyWindow);

    // --- Create UIButton ---
    var UIButton = getClass('UIButton');
    log('UIButton class: ' + UIButton);
    var f_btnType = new NativeFunction(Module.getGlobalExportByName('objc_msgSend'),
        'pointer', ['pointer', 'pointer', 'int64']);
    var btn = f_btnType(UIButton, sel('buttonWithType:'), 0);
    log('btn created: ' + btn);

    // --- Background color ---
    var UIColor = getClass('UIColor');
    log('UIColor class: ' + UIColor);
    var darkGray = _msg4d(UIColor, sel('colorWithRed:green:blue:alpha:'), 0.9, 0.25, 0.25, 0.9);
    log('darkGray: ' + darkGray);
    _msg1v(btn, sel('setBackgroundColor:'), darkGray);
    log('bgColor set');

    // --- Corner radius + border ---
    var layer = _msg0(btn, sel('layer'));
    log('layer: ' + layer);
    _msg1dv(layer, sel('setCornerRadius:'), btnSize / 2);
    log('cornerRadius set');
    _msg1dv(layer, sel('setBorderWidth:'), 2.5);
    log('borderWidth set');
    var white = _msg4d(UIColor, sel('colorWithRed:green:blue:alpha:'), 1, 1, 1, 1);
    log('white: ' + white);
    var cgColor = _msg0(white, sel('CGColor'));
    log('CGColor: ' + cgColor);
    _msg1v(layer, sel('setBorderColor:'), cgColor);
    log('borderColor set');

    // --- Shadow (skip for now) ---

    // --- Title ---
    log('creating title string...');
    var title = nsstring('展开');
    log('title: ' + title + ' = ' + readNSStr(title));
    log('setting title...');
    // setTitle:forState: takes (NSString*, NSUInteger) → NSUInteger=uint64 on arm64
    var f_setTitle = new NativeFunction(Module.getGlobalExportByName('objc_msgSend'),
        'void', ['pointer', 'pointer', 'pointer', 'uint64']);
    f_setTitle(btn, sel('setTitle:forState:'), title, 0);
    log('title set');
    log('setting titleColor...');
    var f_setColor = new NativeFunction(Module.getGlobalExportByName('objc_msgSend'),
        'void', ['pointer', 'pointer', 'pointer', 'uint64']);
    f_setColor(btn, sel('setTitleColor:forState:'), white, 0);
    log('titleColor set');
    log('titleColor set');

    // --- Font ---
    log('getting UIFont class...');
    var UIFont2 = getClass('UIFont');
    log('UIFont: ' + UIFont2);
    var font = _msg1d(UIFont2, sel('boldSystemFontOfSize:'), 14);
    log('font: ' + font);
    var tl = _msg0(btn, sel('titleLabel'));
    log('titleLabel: ' + tl);
    _msg1v(tl, sel('setFont:'), font);
    log('font set');

    // --- Set frame BEFORE adding to window (bounds + center) ---
    // bounds = CGRect(0, 0, btnSize, btnSize)
    var boundsMem = Memory.alloc(32);
    boundsMem.writeDouble(0); boundsMem.add(8).writeDouble(0);
    boundsMem.add(16).writeDouble(btnSize); boundsMem.add(24).writeDouble(btnSize);
    var f_setBounds = new NativeFunction(Module.getGlobalExportByName('objc_msgSend'),
        'void', ['pointer', 'pointer', 'double', 'double', 'double', 'double']);
    f_setBounds(btn, sel('setBounds:'), 0, 0, btnSize, btnSize);

    // center = CGPoint(btnX + btnSize/2, btnY + btnSize/2)
    var f_setCenter = new NativeFunction(Module.getGlobalExportByName('objc_msgSend'),
        'void', ['pointer', 'pointer', 'double', 'double']);
    f_setCenter(btn, sel('setCenter:'), btnX + btnSize/2, btnY + btnSize/2);
    log('frame set: bounds=56x56, center=(' + (btnX+btnSize/2) + ',' + (btnY+btnSize/2) + ')');

    // --- Add to window via main thread ---
    var f_perf = new NativeFunction(Module.getGlobalExportByName('objc_msgSend'),
        'void', ['pointer', 'pointer', 'pointer', 'pointer', 'char']);
    // Wait until done so frame is preserved
    f_perf(keyWindow, sel('performSelectorOnMainThread:withObject:waitUntilDone:'),
        sel('addSubview:'), btn, 1);  // waitUntilDone:YES

    // Bring to front
    f_perf(keyWindow, sel('performSelectorOnMainThread:withObject:waitUntilDone:'),
        sel('bringSubviewToFront:'), btn, 1);

    // Verify
    var frm = _msg0(btn, sel('frame'));
    log('Button frame ptr: ' + frm);
    send('SUCCESS: Button added! Check iPhone screen right side.');

    // Keep bringing button to front, TikTok's video feed may cover it
    for (var i = 1; i <= 5; i++) {
        setTimeout((function(count) {
            return function() {
                f_perf(keyWindow, sel('performSelectorOnMainThread:withObject:waitUntilDone:'),
                    sel('bringSubviewToFront:'), btn, 1);
                log('re-bring to front #' + count);
            };
        })(i), i * 2000);
    }
    log('=== SUCCESS! Floating button created ===');
}

// ========== 入口 ==========
function main() {
    log('TikTok Floating Button Injector');
    log('libobjc: ' + Process.findModuleByName(libobjc).base);

    var attempts = 0;
    function tryCreate() {
        attempts++;
        try {
            createFloatingButton();
            log('DONE on attempt ' + attempts);
        } catch(e) {
            log('Attempt ' + attempts + ': ' + e.message);
            if (attempts < 20) {
                setTimeout(tryCreate, 2000);
            } else {
                log('FAILED after 20 attempts');
            }
        }
    }

    // Wait for app launch (8s)
    setTimeout(tryCreate, 8000);
}

setTimeout(main, 1000);
