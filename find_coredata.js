var GM = Module.getGlobalExportByName;
var oc = new NativeFunction(GM('objc_getClass'), 'pointer', ['pointer']);
var sr = new NativeFunction(GM('sel_registerName'), 'pointer', ['pointer']);
var _p0 = new NativeFunction(GM('objc_msgSend'), 'pointer', ['pointer','pointer']);
function rS(p) { if(p.isNull())return'n';var u=_p0(p,S('UTF8String'));return u.isNull()?'n':u.readUtf8String(); }
var S = function(n) { return sr(Memory.allocUtf8String(n)); };

var buf = Memory.alloc(30000*8);
var n = new NativeFunction(GM('objc_getClassList'), 'int', ['pointer','int'])(buf, 30000);
for (var i = 0; i < n; i++) {
    var cp = buf.add(i*8).readPointer();
    try {
        var cn = _p0(_p0(cp, S('description')), S('UTF8String')).readUtf8String();
        if (cn.indexOf('CoreData') !== -1 || cn.indexOf('Persistent') !== -1 || cn.indexOf('TIMOConversation') !== -1) {
            console.log(cn);
        }
    } catch(e) {}
}
console.log('Done: ' + n + ' classes scanned');
