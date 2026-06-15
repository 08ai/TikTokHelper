/**
 * trace_follow.js v13 — Minimal hook on AWEUserRelationServiceImpl.follow:completion:
 */
console.log('[T13] Minimal follow hook');
setTimeout(function() {
    var GM = Module.getGlobalExportByName;
    var oc = new NativeFunction(GM('objc_getClass'), 'pointer', ['pointer']);
    var cls = oc(Memory.allocUtf8String('AWEUserRelationServiceImpl'));
    var getCM = new NativeFunction(GM('class_getClassMethod'), 'pointer', ['pointer','pointer']);
    var getImp = new NativeFunction(GM('method_getImplementation'), 'pointer', ['pointer']);
    var sr = new NativeFunction(GM('sel_registerName'), 'pointer', ['pointer']);
    var S = function(n) { return sr(Memory.allocUtf8String(n)); };
    var ms = GM('objc_msgSend');
    var _p0 = new NativeFunction(ms, 'pointer', ['pointer','pointer']);

    var imp = getImp(getCM(cls, S('follow:completion:')));
    console.log('IMP: ' + imp);

    Interceptor.attach(imp, {
        onEnter: function(args) {
            console.log('[FOLLOW] CALLED!');
            console.log('  class=' + args[0]);
            console.log('  userParam=' + args[2]);
            console.log('  completionBlock=' + args[3]);
            // Try to describe the user param
            var param = args[2];
            if (!param.isNull()) {
                var desc = _p0(param, S('description'));
                if (!desc.isNull()) {
                    var u = _p0(desc, S('UTF8String'));
                    if (!u.isNull()) console.log('  param: ' + u.readUtf8String());
                }
            }
        }
    });
    console.log('[T13] Hooked! Tap FOLLOW now.');
}, 5000);
setTimeout(function(){ console.log('[T13] loaded'); }, 500);
