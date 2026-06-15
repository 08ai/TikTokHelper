/**
 * test_follow.js — 直接调用 TikTok 关注 API
 * 从当前视频获取用户信息并关注
 */
console.log('[TF] Test Follow API');
var GM = Module.getGlobalExportByName;
var oc = new NativeFunction(GM('objc_getClass'), 'pointer', ['pointer']);
var sr = new NativeFunction(GM('sel_registerName'), 'pointer', ['pointer']);
var S = function(n) { return sr(Memory.allocUtf8String(n)); };
var ms = GM('objc_msgSend');
var _p0 = new NativeFunction(ms, 'pointer', ['pointer','pointer']);

setTimeout(function() {
    var RelSvc = oc(Memory.allocUtf8String('AWEUserRelationServiceImpl'));
    var CtxCls = oc(Memory.allocUtf8String('AWEUserRelationContext'));
    console.log('RelSvc: ' + RelSvc + ' CtxCls: ' + CtxCls);

    // Check what properties context has
    var outC = Memory.alloc(4);
    var getP = new NativeFunction(GM('class_copyPropertyList'), 'pointer', ['pointer','pointer']);
    var props = getP(CtxCls, outC);
    var n = outC.readU32();
    console.log('Context properties: ' + n);
    var getName = new NativeFunction(GM('property_getName'), 'pointer', ['pointer']);
    for (var i = 0; i < n; i++) {
        var p = props.add(i*8).readPointer();
        console.log('  ' + getName(p).readCString());
    }

    // Get AWEUserModel header info
    var UserModel = oc(Memory.allocUtf8String('AWEUserModel'));
    if (!UserModel.isNull()) {
        console.log('AWEUserModel found');
        var uprops = getP(UserModel, outC);
        var un = outC.readU32();
        console.log('UserModel properties: ' + un);
        for (var j = 0; j < Math.min(un, 25); j++) {
            var p2 = uprops.add(j*8).readPointer();
            console.log('  ' + getName(p2).readCString());
        }
    }

    // Now try calling follow API directly
    // Create context: [[AWEUserRelationContext alloc] init]
    var allocSel = S('alloc');
    var initSel = S('init');
    var ctx = _p0(CtxCls, allocSel);
    ctx = _p0(ctx, initSel);
    console.log('Created context: ' + ctx);

    // We need user object from somewhere - let's hook to capture one
    // For now, just verify the call structure works

    console.log('=== DONE === Context created, need user model to test follow');
}, 5000);
setTimeout(function(){ console.log('[TF] loaded'); }, 500);
