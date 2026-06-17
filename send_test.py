import frida, sys, io, time
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
d = frida.get_usb_device()
session = d.attach('TikTok')
print('Attached')

js = '''
var ms=Module.getGlobalExportByName('objc_msgSend');
var oc=new NativeFunction(Module.getGlobalExportByName('objc_getClass'),'pointer',['pointer']);
var sr=new NativeFunction(Module.getGlobalExportByName('sel_registerName'),'pointer',['pointer']);
function S(n){return sr(Memory.allocUtf8String(n));}
function nf(r,a){return new NativeFunction(ms,r,a);}
function ns(s){return nf('pointer',['pointer','pointer','pointer'])(oc(Memory.allocUtf8String('NSString')),S('stringWithUTF8String:'),Memory.allocUtf8String(s));}

var cid='0:1:6906173486697563137:7627777775978873877';
var ModuleSvc=oc(Memory.allocUtf8String('AWEIMModuleService'));
var sendCtrl=nf('pointer',['pointer','pointer'])(ModuleSvc,S('sendMessageController'));
send('sc:'+sendCtrl);

var TC=oc(Memory.allocUtf8String('AWEIMTextMessageContent'));
var c1=nf('pointer',['pointer','pointer'])(TC,S('alloc'));
c1=nf('pointer',['pointer','pointer','pointer','pointer'])(c1,S('initWithText:referenceVideo:'),ns('test'),new NativePointer(0));
send('c:'+c1);

if(!c1.isNull()){
    var SM=oc(Memory.allocUtf8String('AWEIMSendTextMessageModel'));
    var model=nf('pointer',['pointer','pointer'])(SM,S('alloc'));
    model=nf('pointer',['pointer','pointer','pointer'])(model,S('initWithContent:'),c1);
    send('m:'+model);
    if(!model.isNull()){
        var ConvCls=oc(Memory.allocUtf8String('AWEIMMessageConversation'));
        var conv=nf('pointer',['pointer','pointer'])(ConvCls,S('alloc'));
        conv=nf('pointer',['pointer','pointer','pointer','pointer'])(conv,S('initWithConversationID:options:'),ns(cid),new NativePointer(0));
        send('conv:'+conv);
        nf('void',['pointer','pointer','pointer','pointer'])(sendCtrl,S('sendMessage:conversation:'),model,conv);
        send('SENT');
    }
}
'''
script = session.create_script(js)
script.on('message', lambda m,d: print('  '+m['payload']) if m['type']=='send' else None)
script.load()
time.sleep(5)
session.detach()
print('Done')
