/**
 * trace_dm.js v2 — Trace DM receive flow
 */
console.log('[DM2] Receive trace');
var GM = Module.getGlobalExportByName;
var ms = GM('objc_msgSend');
var oc = new NativeFunction(GM('objc_getClass'), 'pointer', ['pointer']);
var sr = new NativeFunction(GM('sel_registerName'), 'pointer', ['pointer']);
function C(n) { return oc(Memory.allocUtf8String(n)); }
function S(n) { return sr(Memory.allocUtf8String(n)); }
function nf(r,a) { return new NativeFunction(ms, r, a); }
var _p0 = new NativeFunction(ms, 'pointer', ['pointer','pointer']);
function rS(p) { if(p.isNull())return'(nil)';var u=_p0(p,S('UTF8String'));return u.isNull()?'(nil)':u.readUtf8String(); }
var getIM = new NativeFunction(GM('class_getInstanceMethod'), 'pointer', ['pointer','pointer']);
var getImp = new NativeFunction(GM('method_getImplementation'), 'pointer', ['pointer']);

function hook(className, selName, label) {
    var cls = C(className);
    if (cls.isNull()) return;
    var m = getIM(cls, S(selName));
    if (m.isNull()) return;
    var imp = getImp(m);
    if (imp.isNull()) return;
    Interceptor.attach(imp, {
        onEnter: function(args) {
            console.log('[' + label + '] ' + className + '.' + selName);
            for (var i = 2; i < Math.min(args.length, 4); i++) {
                if (!args[i].isNull()) console.log('  a' + i + '=' + args[i] + ' ' + rS(_p0(args[i], S('description'))));
            }
        }
    });
    console.log('[DM2] Hooked: ' + label);
}

setTimeout(function() {
    console.log('[DM2] Setting up receive hooks...');

    // Message reception on conversation
    hook('AWEIMMessageConversation', 'insertNewMessages:', 'INSERT');
    hook('AWEIMMessageConversation', 'addMessage:', 'ADD_MSG');
    hook('AWEIMMessageConversation', 'receiveMessage:', 'RECV_MSG');
    hook('AWEIMMessageConversation', 'handleNewMessage:', 'HANDLE');

    // Inbox/notification
    hook('AWEIMMessageConversationEventNotifier', 'conversation:didReceiveMessage:', 'EVENT');
    hook('AWEIMModuleService', 'didReceiveMessage:', 'MOD_RECV');
    hook('AWEIMModuleService', 'onNewMessageArrived:', 'NEW_MSG');

    // Conversation list (inbox)
    hook('AWEIMMessageConversationCache', 'allConversations', 'ALL_CONV');
    hook('AWEIMMessageConversationCache', 'conversations', 'CONVS');

    // Message model
    hook('AWEIMMessage', 'initWithMessageDict:', 'MSG_INIT');
    hook('AWEIMTextMessageContent', 'initWithText:', 'TEXT_INIT');

    // In-app notification
    hook('AWEIMInAppPushMessageConfig', 'handlePushMessage:', 'PUSH');
    hook('AWEIMUserManager', 'didReceiveMessage:', 'USR_RECV');

    // Also hook AWEIMSendMessageController for send (from v1)
    var svcCls = C('AWEIMModuleService');
    if (!svcCls.isNull()) {
        var sendCtrl = _p0(svcCls, S('sendMessageController'));
        if (!sendCtrl.isNull()) {
            var ctrlCls = _p0(sendCtrl, S('class'));
            var sendM = getIM(ctrlCls, S('sendMessage:conversation:'));
            if (!sendM.isNull()) {
                Interceptor.attach(getImp(sendM), {
                    onEnter: function(args) {
                        console.log('[SEND] sendMessage:conversation: msg=' + args[2] + ' conv=' + args[3]);
                    }
                });
                console.log('[DM2] Hooked: sendMessage:conversation:');
            }
        }
    }

    console.log('[DM2] === READY - Have someone send you a DM! ===');
}, 8000);

setTimeout(function(){ console.log('[DM2] loaded'); }, 500);
