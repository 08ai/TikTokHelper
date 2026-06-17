var ms=Module.getGlobalExportByName('objc_msgSend');
var oc=new NativeFunction(Module.getGlobalExportByName('objc_getClass'),'pointer',['pointer']);
var sr=new NativeFunction(Module.getGlobalExportByName('sel_registerName'),'pointer',['pointer']);
function S(n){return sr(Memory.allocUtf8String(n));}
var _p0=new NativeFunction(ms,'pointer',['pointer','pointer']);

// Get button and window from dylib
var mod=Process.findModuleByName('TH.dylib');
var btn=null, panel=null;
var syms=mod.enumerateSymbols();
for(var i=0;i<syms.length;i++){
    if(syms[i].name==='gToggleBtn')btn=syms[i].address.readPointer();
    if(syms[i].name==='gPanel')panel=syms[i].address.readPointer();
}
console.log('btn:'+btn+' panel:'+panel);

// If button is null, call buildUI manually
if(btn.isNull()){
    console.log('calling buildUI...');
    var TH=oc(Memory.allocUtf8String('TikTokHelper'));
    var th=new NativeFunction(ms,'pointer',['pointer','pointer'])(TH,S('alloc'));
    th=new NativeFunction(ms,'pointer',['pointer','pointer'])(th,S('init'));
    new NativeFunction(ms,'void',['pointer','pointer'])(th,S('buildUI'));
    console.log('buildUI called');
    // re-read
    for(var j=0;j<syms.length;j++){
        if(syms[j].name==='gToggleBtn')btn=syms[j].address.readPointer();
        if(syms[j].name==='gPanel')panel=syms[j].address.readPointer();
    }
}

// Bring to front
var app=_p0(oc(Memory.allocUtf8String('UIApplication')),S('sharedApplication'));
var win=_p0(app,S('keyWindow'));
console.log('win:'+win);

if(!btn.isNull()&&!win.isNull()){
    new NativeFunction(ms,'void',['pointer','pointer','pointer'])(win,S('bringSubviewToFront:'),btn);
    // Also add to window
    new NativeFunction(ms,'void',['pointer','pointer','pointer'])(win,S('addSubview:'),btn);
    console.log('btn added+front');
}
if(!panel.isNull()&&!win.isNull()){
    new NativeFunction(ms,'void',['pointer','pointer','pointer'])(win,S('addSubview:'),panel);
    new NativeFunction(ms,'void',['pointer','pointer','double'])(panel,S('setAlpha:'),0);
    new NativeFunction(ms,'void',['pointer','pointer','pointer'])(win,S('bringSubviewToFront:'),btn);
    console.log('panel added');
}
console.log('DONE - check screen!');
