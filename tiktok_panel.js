/**
 * tiktok_panel.js — FINAL WORKING VERSION
 * Red "展开" button → tap → yellow panel with 3 buttons
 * Toggle via addSubview/removeFromSuperview (ALL main thread)
 * Tap detection via isHighlighted polling
 */
console.log('[T] Panel vFinal');
var GM = Module.getGlobalExportByName;
var ms = GM('objc_msgSend');
var oc = new NativeFunction(GM('objc_getClass'), 'pointer', ['pointer']);
var sr = new NativeFunction(GM('sel_registerName'), 'pointer', ['pointer']);
function C(n) { return oc(Memory.allocUtf8String(n)); }
function S(n) { return sr(Memory.allocUtf8String(n)); }
function nf(r,a) { return new NativeFunction(ms, r, a); }

setTimeout(function() {
    console.log('[T] === START ===');
    var app = nf('pointer',['pointer','pointer'])(C('UIApplication'), S('sharedApplication'));
    var win = nf('pointer',['pointer','pointer'])(app, S('keyWindow'));
    console.log('[T] win ok');

    // Colors
    var red    = nf('pointer',['pointer','pointer','double','double','double','double'])(C('UIColor'), S('colorWithRed:green:blue:alpha:'), 0.9, 0.10, 0.10, 0.92);
    var white  = nf('pointer',['pointer','pointer','double','double','double','double'])(C('UIColor'), S('colorWithRed:green:blue:alpha:'), 1, 1, 1, 1);
    var yellow = nf('pointer',['pointer','pointer','double','double','double','double'])(C('UIColor'), S('colorWithRed:green:blue:alpha:'), 1, 0.85, 0.02, 0.95);
    var blue   = nf('pointer',['pointer','pointer','double','double','double','double'])(C('UIColor'), S('colorWithRed:green:blue:alpha:'), 0.18, 0.50, 0.92, 0.9);
    var green  = nf('pointer',['pointer','pointer','double','double','double','double'])(C('UIColor'), S('colorWithRed:green:blue:alpha:'), 0.15, 0.72, 0.35, 0.9);
    var orange = nf('pointer',['pointer','pointer','double','double','double','double'])(C('UIColor'), S('colorWithRed:green:blue:alpha:'), 0.88, 0.48, 0.12, 0.9);

    // Main thread dispatcher
    var perf = nf('void',['pointer','pointer','pointer','pointer','char']);

    // ─── RED TOGGLE BUTTON ───
    var toggleBtn = nf('pointer',['pointer','pointer'])(C('UIButton'), S('alloc'));
    toggleBtn = nf('pointer',['pointer','pointer','double','double','double','double'])(toggleBtn, S('initWithFrame:'), 282, 105, 88, 48);
    nf('void',['pointer','pointer','pointer'])(toggleBtn, S('setBackgroundColor:'), red);
    nf('void',['pointer','pointer','pointer','uint64'])(toggleBtn, S('setTitle:forState:'),
        nf('pointer',['pointer','pointer','pointer'])(C('NSString'), S('stringWithUTF8String:'), Memory.allocUtf8String('展开')), 0);
    nf('void',['pointer','pointer','pointer','uint64'])(toggleBtn, S('setTitleColor:forState:'), white, 0);
    var tlbl = nf('pointer',['pointer','pointer'])(toggleBtn, S('titleLabel'));
    nf('void',['pointer','pointer','pointer'])(tlbl, S('setFont:'), nf('pointer',['pointer','pointer','double'])(C('UIFont'), S('boldSystemFontOfSize:'), 18));
    nf('void',['pointer','pointer','int64'])(tlbl, S('setNumberOfLines:'), 2);
    var tly = nf('pointer',['pointer','pointer'])(toggleBtn, S('layer'));
    nf('void',['pointer','pointer','double'])(tly, S('setCornerRadius:'), 16);
    nf('void',['pointer','pointer','double'])(tly, S('setBorderWidth:'), 2.5);
    nf('void',['pointer','pointer','pointer'])(tly, S('setBorderColor:'), nf('pointer',['pointer','pointer'])(white, S('CGColor')));
    nf('void',['pointer','pointer','char'])(toggleBtn, S('setUserInteractionEnabled:'), 1);
    perf(win, S('performSelectorOnMainThread:withObject:waitUntilDone:'), S('addSubview:'), toggleBtn, 1);
    perf(win, S('performSelectorOnMainThread:withObject:waitUntilDone:'), S('bringSubviewToFront:'), toggleBtn, 1);
    console.log('[T] toggle btn added');

    // ─── YELLOW PANEL ───
    var panel = nf('pointer',['pointer','pointer'])(C('UIView'), S('alloc'));
    panel = nf('pointer',['pointer','pointer','double','double','double','double'])(panel, S('initWithFrame:'), 100, 80, 178, 220);
    nf('void',['pointer','pointer','pointer'])(panel, S('setBackgroundColor:'), yellow);
    var ply = nf('pointer',['pointer','pointer'])(panel, S('layer'));
    nf('void',['pointer','pointer','double'])(ply, S('setCornerRadius:'), 14);
    nf('void',['pointer','pointer','double'])(ply, S('setBorderWidth:'), 3);
    nf('void',['pointer','pointer','pointer'])(ply, S('setBorderColor:'), nf('pointer',['pointer','pointer'])(white, S('CGColor')));

    // 3 sub-buttons on panel
    var panelBtns = [];
    var defs = [
        {t:'自动关注', y:12, c:blue},
        {t:'自动私信', y:74, c:green},
        {t:'自动养号', y:136, c:orange},
    ];
    for (var i = 0; i < 3; i++) {
        var d = defs[i];
        var pb = nf('pointer',['pointer','pointer'])(C('UIButton'), S('alloc'));
        pb = nf('pointer',['pointer','pointer','double','double','double','double'])(pb, S('initWithFrame:'), 12, d.y, 154, 52);
        nf('void',['pointer','pointer','pointer'])(pb, S('setBackgroundColor:'), d.c);
        nf('void',['pointer','pointer','pointer','uint64'])(pb, S('setTitle:forState:'),
            nf('pointer',['pointer','pointer','pointer'])(C('NSString'), S('stringWithUTF8String:'), Memory.allocUtf8String(d.t)), 0);
        nf('void',['pointer','pointer','pointer','uint64'])(pb, S('setTitleColor:forState:'), white, 0);
        var plb = nf('pointer',['pointer','pointer'])(pb, S('titleLabel'));
        nf('void',['pointer','pointer','pointer'])(plb, S('setFont:'), nf('pointer',['pointer','pointer','double'])(C('UIFont'), S('boldSystemFontOfSize:'), 16));
        var ply2 = nf('pointer',['pointer','pointer'])(pb, S('layer'));
        nf('void',['pointer','pointer','double'])(ply2, S('setCornerRadius:'), 10);
        nf('void',['pointer','pointer','pointer'])(panel, S('addSubview:'), pb);
        nf('void',['pointer','pointer','char'])(pb, S('setUserInteractionEnabled:'), 1);
        // Save reference for tap detection
        panelBtns.push(pb);
    }

    // Panel starts NOT in hierarchy (will be added on tap)
    console.log('[T] panel built (not added yet)');

    // ─── TAP DETECTION (toggle + panel buttons) ───
    var expanded = false;
    var wasToggleHi = false;
    var wasPanelHi = [false, false, false];

    setInterval(function() {
        try {
            // ── Toggle button ──
            var tHi = nf('char',['pointer','pointer'])(toggleBtn, S('isHighlighted'));
            if (tHi && !wasToggleHi) {
                wasToggleHi = true;
                expanded = !expanded;
                nf('void',['pointer','pointer','pointer','uint64'])(toggleBtn, S('setTitle:forState:'),
                    nf('pointer',['pointer','pointer','pointer'])(C('NSString'), S('stringWithUTF8String:'),
                        Memory.allocUtf8String(expanded ? '收起' : '展开')), 0);
                if (expanded) {
                    perf(win, S('performSelectorOnMainThread:withObject:waitUntilDone:'), S('addSubview:'), panel, 1);
                    perf(win, S('performSelectorOnMainThread:withObject:waitUntilDone:'), S('bringSubviewToFront:'), panel, 1);
                    perf(win, S('performSelectorOnMainThread:withObject:waitUntilDone:'), S('bringSubviewToFront:'), toggleBtn, 1);
                } else {
                    perf(panel, S('performSelectorOnMainThread:withObject:waitUntilDone:'), S('removeFromSuperview'), new NativePointer(0), 1);
                }
                console.log('[T] ' + (expanded ? 'OPEN' : 'CLOSE'));
            }
            if (!tHi && wasToggleHi) wasToggleHi = false;

            // ── Panel buttons (only check when expanded) ──
            if (expanded && panelBtns.length === 3) {
                for (var bi = 0; bi < 3; bi++) {
                    var pHi = nf('char',['pointer','pointer'])(panelBtns[bi], S('isHighlighted'));
                    if (pHi && !wasPanelHi[bi]) {
                        wasPanelHi[bi] = true;
                        var names = ['自动关注', '自动私信', '自动养号'];
                        console.log('[T] PANEL BTN TAP: ' + names[bi]);
                        if (bi === 0) autoFollowAll();
                        if (bi === 1) showAlert('自动私信', 'TODO');
                        if (bi === 2) showAlert('自动养号', 'TODO');
                    }
                    if (!pHi && wasPanelHi[bi]) wasPanelHi[bi] = false;
                }
            }
        } catch(e) {}
    }, 150);

    // ─── Alert helper ───
    function showAlert(title, msg) {
        var alertCtrl = nf('pointer',['pointer','pointer','pointer','pointer','int64'])
            (C('UIAlertController'), S('alertControllerWithTitle:message:preferredStyle:'),
             ns(title), ns(msg), 1);
        var ok = nf('pointer',['pointer','pointer','pointer','int64','pointer'])
            (C('UIAlertAction'), S('actionWithTitle:style:handler:'), ns('OK'), 0, new NativePointer(0));
        nf('void',['pointer','pointer','pointer'])(alertCtrl, S('addAction:'), ok);
        var vc = nf('pointer',['pointer','pointer'])(win, S('rootViewController'));
        while (true) {
            var p = nf('pointer',['pointer','pointer'])(vc, S('presentedViewController'));
            if (p.isNull()) break;
            vc = p;
        }
        nf('void',['pointer','pointer','pointer','char','pointer'])(vc, S('presentViewController:animated:completion:'), alertCtrl, 1, new NativePointer(0));
    }

    // ─── Auto-Follow function ───
    var RelSvc = C('AWEUserRelationServiceImpl');
    function doFollowUser(uidStr) {
        if (uidStr === '(null)' || !uidStr) { showAlert('错误', '无用户 UID'); return; }
        console.log('[T] Following: ' + uidStr);
        // Create AWEUserModel
        var UserModel = C('AWEUserModel');
        var user = nf('pointer',['pointer','pointer'])(UserModel, S('alloc'));
        user = nf('pointer',['pointer','pointer'])(user, S('init'));
        nf('void',['pointer','pointer','pointer'])(user, S('setUserID:'), ns(uidStr));
        // Create context
        var CtxCls = C('AWEUserRelationContext');
        var ctx = nf('pointer',['pointer','pointer'])(CtxCls, S('alloc'));
        ctx = nf('pointer',['pointer','pointer'])(ctx, S('init'));
        nf('void',['pointer','pointer','pointer'])(ctx, S('setUser:'), user);
        nf('void',['pointer','pointer','int64'])(ctx, S('setFromPageType:'), 0);
        // Call follow API
        nf('void',['pointer','pointer','pointer','pointer'])(RelSvc, S('follow:completion:'), ctx, new NativePointer(0));
        showAlert('关注', '已发送关注请求: ' + uidStr);
    }

    // ─── Hardcoded user → UID mapping (from manual search) ───
    var knownUsers = {
        'lisarobest265': '7359784926495900690',
    };

    function autoFollowAll() {
        var users = Object.keys(knownUsers);
        if (users.length === 0) { showAlert('无用户', '请先获取用户列表'); return; }
        console.log('[T] Auto-follow: ' + users.length + ' users');
        for (var ui = 0; ui < users.length; ui++) {
            var uname = users[ui];
            var uid = knownUsers[uname];
            console.log('[T] Following ' + uname + ' = ' + uid);
            doFollowUser(uid);
        }
        showAlert('自动关注', '已处理 ' + users.length + ' 个用户');
    }

    console.log('[T] === READY === Tap red button!');
}, 7000);

setTimeout(function(){ console.log('[T] loaded'); }, 500);
