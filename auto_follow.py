#!/usr/bin/env python3
"""
auto_follow.py — 一键批量关注 TikTok 用户
从 http://107.148.2.130/tiktokid.php 获取 UID 列表并关注
用法: python auto_follow.py
"""
import frida, sys, time, json, urllib.request, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

URL = 'http://107.148.2.130/tiktokid.php'

# 1. 从服务器获取 UID 列表
resp = urllib.request.urlopen(URL, timeout=10).read().decode().strip()
data = json.loads(resp)
uids = [str(u) for u in data['uids']]
total = len(uids)
print(f'获取到 {total} 个用户: {uids}')

# 2. 连接 TikTok
device = frida.get_usb_device()
session = device.attach('TikTok')
print(f'已连接 TikTok')

# 3. 批量关注
js = f'''
var GM = Module.getGlobalExportByName; var ms = GM('objc_msgSend');
var oc = new NativeFunction(GM('objc_getClass'), 'pointer', ['pointer']);
var sr = new NativeFunction(GM('sel_registerName'), 'pointer', ['pointer']);
function C(n) {{ return oc(Memory.allocUtf8String(n)); }}
function S(n) {{ return sr(Memory.allocUtf8String(n)); }}
function nf(r,a) {{ return new NativeFunction(ms, r, a); }}
function ns(s) {{ return nf('pointer',['pointer','pointer','pointer'])(C('NSString'),S('stringWithUTF8String:'),Memory.allocUtf8String(s)); }}

var RelSvc = C('AWEUserRelationServiceImpl');
var getCM = new NativeFunction(GM('class_getClassMethod'), 'pointer', ['pointer','pointer']);
var getImp = new NativeFunction(GM('method_getImplementation'), 'pointer', ['pointer']);
var cnt = 0;
Interceptor.attach(getImp(getCM(RelSvc, S('follow:completion:'))), {{
    onEnter: function(args) {{
        var ctx = args[2]; var user = nf('pointer',['pointer','pointer'])(ctx, S('user'));
        var uid = nf('pointer',['pointer','pointer'])(user, S('userID'));
        if (!uid.isNull()) {{
            cnt++;
            console.log('[' + cnt + '/{total}] OK: ' + nf('pointer',['pointer','pointer'])(uid,S('UTF8String')).readUtf8String());
        }}
    }}
}});

var uids = {json.dumps(uids)};
var idx = 0;
function followNext() {{
    if (idx >= uids.length) return;
    var uid = uids[idx];
    idx++;
    var UserModel = C('AWEUserModel');
    var user = nf('pointer',['pointer','pointer'])(UserModel, S('alloc'));
    user = nf('pointer',['pointer','pointer'])(user, S('init'));
    nf('void',['pointer','pointer','pointer'])(user, S('setUserID:'), ns(uid));
    var CtxCls = C('AWEUserRelationContext');
    var ctx = nf('pointer',['pointer','pointer'])(CtxCls, S('alloc'));
    ctx = nf('pointer',['pointer','pointer'])(ctx, S('init'));
    nf('void',['pointer','pointer','pointer'])(ctx, S('setUser:'), user);
    nf('void',['pointer','pointer','int64'])(ctx, S('setFromPageType:'), 0);
    nf('void',['pointer','pointer','pointer','pointer'])(RelSvc, S('follow:completion:'), ctx, new NativePointer(0));
    if (idx < uids.length) setTimeout(followNext, 300);
}}
followNext();
'''

script = session.create_script(js)
script.on('message', lambda msg, data: print(f'  {msg["payload"]}') if msg['type'] == 'send' else None)
script.load()
time.sleep(total * 0.5 + 2)  # 等待所有延时完成
session.detach()
print(f'\n✅ 批量关注完成! {total} 个用户 (间隔300ms)')
