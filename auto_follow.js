/**
 * auto_follow.js v10 — Complete: HTTP fetch UIDs + Follow by UID
 */
console.log('[AF10] Complete Auto Follow');
var GM = Module.getGlobalExportByName;
var ms = GM('objc_msgSend');
var oc = new NativeFunction(GM('objc_getClass'), 'pointer', ['pointer']);
var sr = new NativeFunction(GM('sel_registerName'), 'pointer', ['pointer']);
function C(n) { return oc(Memory.allocUtf8String(n)); }
function S(n) { return sr(Memory.allocUtf8String(n)); }
function nf(r,a) { return new NativeFunction(ms, r, a); }
function ns(s) { return nf('pointer',['pointer','pointer','pointer'])(C('NSString'),S('stringWithUTF8String:'),Memory.allocUtf8String(s)); }

// ─── HTTP fetch UIDs ───
function fetchUIDs() {
    var url = nf('pointer',['pointer','pointer','pointer'])(C('NSURL'),S('URLWithString:'),
        ns('http://39.102.210.175:5323/tiktokid.php'));
    if (url.isNull()) { console.log('[AF10] bad URL'); return []; }

    var data = nf('pointer',['pointer','pointer','pointer','uint64','pointer'])
        (C('NSData'),S('dataWithContentsOfURL:options:error:'),url,0,new NativePointer(0));
    if (data.isNull()) { console.log('[AF10] no data'); return []; }

    var len = nf('uint64',['pointer','pointer'])(data, S('length')).toInt32();
    var bytes = nf('pointer',['pointer','pointer'])(data, S('bytes'));
    console.log('[AF10] HTTP response: ' + len + ' bytes');

    var text = '';
    for (var i = 0; i < len; i++) {
        var b = bytes.add(i).readU8();
        if (b >= 32 && b < 127) text += String.fromCharCode(b);
    }
    text = text.trim();
    console.log('[AF10] UIDs: [' + text + ']');

    var uids = [];
    var parts = text.split(/[^0-9]+/);
    for (var j = 0; j < parts.length; j++) {
        var t = parts[j].trim();
        if (t.length > 10) uids.push(t); // valid UID is > 10 digits
    }
    return uids;
}

// ─── Follow user by UID ───
function followUID(uidStr) {
    var RelSvc = C('AWEUserRelationServiceImpl');
    if (RelSvc.isNull()) { console.log('[AF10] RelSvc not found'); return; }

    var UserModel = C('AWEUserModel');
    var user = nf('pointer',['pointer','pointer'])(UserModel, S('alloc'));
    user = nf('pointer',['pointer','pointer'])(user, S('init'));
    nf('void',['pointer','pointer','pointer'])(user, S('setUserID:'), ns(uidStr));

    var CtxCls = C('AWEUserRelationContext');
    var ctx = nf('pointer',['pointer','pointer'])(CtxCls, S('alloc'));
    ctx = nf('pointer',['pointer','pointer'])(ctx, S('init'));
    nf('void',['pointer','pointer','pointer'])(ctx, S('setUser:'), user);
    nf('void',['pointer','pointer','int64'])(ctx, S('setFromPageType:'), 0);

    nf('void',['pointer','pointer','pointer','pointer'])(RelSvc, S('follow:completion:'), ctx, new NativePointer(0));
    console.log('[AF10] Followed: ' + uidStr);
}

// ─── Main ───
setTimeout(function() {
    console.log('[AF10] ========================================');
    console.log('[AF10] Fetching UIDs from server...');

    var uids = fetchUIDs();
    if (uids.length === 0) {
        console.log('[AF10] No UIDs found, using hardcoded fallback');
        uids = ['7114345548233098241'];
    }

    console.log('[AF10] Following ' + uids.length + ' users: ' + uids.join(', '));

    // Hook follow to confirm
    var RelSvc = C('AWEUserRelationServiceImpl');
    var getCM = new NativeFunction(GM('class_getClassMethod'), 'pointer', ['pointer','pointer']);
    var getImp = new NativeFunction(GM('method_getImplementation'), 'pointer', ['pointer']);
    Interceptor.attach(getImp(getCM(RelSvc, S('follow:completion:'))), {
        onEnter: function(args) {
            var ctx = args[2]; var user = nf('pointer',['pointer','pointer'])(ctx, S('user'));
            var uid = nf('pointer',['pointer','pointer'])(user, S('userID'));
            if (!uid.isNull()) {
                var utf8 = nf('pointer',['pointer','pointer'])(uid, S('UTF8String'));
                if (!utf8.isNull()) console.log('[AF10] ⭐ API CALL: ' + utf8.readUtf8String());
            }
        }
    });

    // Follow all
    for (var vi = 0; vi < uids.length; vi++) {
        followUID(uids[vi]);
    }

    console.log('[AF10] All done! Check TikTok.');
}, 8000);

setTimeout(function(){ console.log('[AF10] loaded'); }, 500);
