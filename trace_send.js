var ms=Module.getGlobalExportByName('objc_msgSend');
var sr=new NativeFunction(Module.getGlobalExportByName('sel_registerName'),'pointer',['pointer']);
function S(n){return sr(Memory.allocUtf8String(n));}
var _p0=new NativeFunction(ms,'pointer',['pointer','pointer']);
function rS(p){if(p.isNull())return'nil';return _p0(p,S('UTF8String')).readUtf8String();}

var sendM=S('sendMessage:conversation:');
var lastM=S('setLastMessage:');
var textS=S('setText:');

Interceptor.attach(ms,{onEnter:function(a){
    var s=a[1];
    if(s.equals(sendM)){
        var model=a[2], conv=a[3];
        console.log('[SEND] model='+model+' cls='+rS(_p0(_p0(model,S('class')),S('description'))));
        console.log('[SEND] conv='+conv+' cls='+rS(_p0(_p0(conv,S('class')),S('description'))));
        // Get conv ID
        if(!conv.isNull()){
            var cid=_p0(conv,S('identifier'));
            console.log('[SEND] convID='+rS(cid));
        }
        // Get model content
        if(!model.isNull()){
            var content=_p0(model,S('content'));
            if(!content.isNull()){
                var text=_p0(content,S('text'));
                console.log('[SEND] content='+rS(content)+' text='+rS(text));
            }
        }
    } else if(s.equals(lastM)){
        console.log('[LAST_MSG]');
    } else if(s.equals(textS)){
        var t=rS(a[2]);
        if(t.length>0&&t!=='nil')console.log('[TYPE] '+t);
    }
}});
console.log('TRACE READY');
