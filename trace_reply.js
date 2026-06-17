var ms=Module.getGlobalExportByName('objc_msgSend');
var sr=new NativeFunction(Module.getGlobalExportByName('sel_registerName'),'pointer',['pointer']);
function S(n){return sr(Memory.allocUtf8String(n));}
var _p0=new NativeFunction(ms,'pointer',['pointer','pointer']);
function rS(p){if(p.isNull())return'nil';return _p0(p,S('UTF8String')).readUtf8String();}

// Trace setLastMessage + sendMessage
var lastM=S('setLastMessage:');
var sendM=S('sendMessage:conversation:');

Interceptor.attach(ms,{onEnter:function(a){
    var s=a[1];
    if(s.equals(lastM)){
        var conv=a[0];
        var msg=a[2];
        console.log('[NEW_MSG] conv='+conv+' msg='+msg);
        // Check if our reply follows
    } else if(s.equals(sendM)){
        var model=a[2];var conv=a[3];
        var cid='?';
        if(!conv.isNull()){var ci=_p0(conv,S('identifier'));if(!ci.isNull())cid=_p0(ci,S('UTF8String')).readUtf8String();}
        console.log('[SEND] conv='+conv+' id='+cid);
    }
}});
console.log('TRACE ACTIVE - have someone send you a DM');
