/**
 * auto_dm.js v2 — Poll inbox via CoreData, auto-reply "你好"
 */
console.log('[ADM2] Auto DM v2');
var GM = Module.getGlobalExportByName;
var ms = GM('objc_msgSend');
var oc = new NativeFunction(GM('objc_getClass'), 'pointer', ['pointer']);
var sr = new NativeFunction(GM('sel_registerName'), 'pointer', ['pointer']);
function C(n) { return oc(Memory.allocUtf8String(n)); }
function S(n) { return sr(Memory.allocUtf8String(n)); }
function nf(r,a) { return new NativeFunction(ms, r, a); }
var _p0 = new NativeFunction(ms, 'pointer', ['pointer','pointer']);
function rS(p) { if(p.isNull())return'';var u=_p0(p,S('UTF8String'));return u.isNull()?'':u.readUtf8String(); }
function ns(s) { return nf('pointer',['pointer','pointer','pointer'])(C('NSString'),S('stringWithUTF8String:'),Memory.allocUtf8String(s)); }

var autoEnabled = false;
var repliedSet = {};
var moc = null;       // NSManagedObjectContext
var sendCtrl = null;  // AWEIMSendMessageController

setTimeout(function() {
    console.log('[ADM2] Init...');

    // Get managed object context
    var app = _p0(C('UIApplication'), S('sharedApplication'));
    var delegate = _p0(app, S('delegate'));
    console.log('[ADM2] delegate: ' + rS(_p0(_p0(delegate,S('class')),S('description'))));

    // Try persistentContainer.viewContext
    var container = _p0(delegate, S('persistentContainer'));
    if (!container.isNull()) {
        moc = _p0(container, S('viewContext'));
    }
    // Fallback: mainManagedObjectContext
    if (!moc || moc.isNull()) {
        moc = _p0(delegate, S('mainManagedObjectContext'));
    }
    // Fallback: managedObjectContext
    if (!moc || moc.isNull()) {
        moc = _p0(delegate, S('managedObjectContext'));
    }
    console.log('[ADM2] MOC: ' + moc);

    // Get send controller
    var SvcCls = C('AWEIMModuleService');
    if (!SvcCls.isNull()) {
        sendCtrl = _p0(SvcCls, S('sendMessageController'));
    }
    console.log('[ADM2] SendCtrl: ' + sendCtrl);

    console.log('[ADM2] Ready. autoEnabled=' + autoEnabled);
}, 8000);

// Toggle auto-DM
function toggleDM() {
    autoEnabled = !autoEnabled;
    console.log('[ADM2] Auto-DM: ' + (autoEnabled ? 'ON' : 'OFF'));
}

// Get all conversations
function getConversations() {
    if (!moc || moc.isNull()) return [];
    var results = [];
    // Fetch TIMOConversation
    var req = _p0(C('NSFetchRequest'), S('alloc'));
    req = _p0(req, S('init'));
    var entity = nf('pointer',['pointer','pointer','pointer'])(C('NSEntityDescription'),S('entityForName:inManagedObjectContext:'),ns('TIMOConversation'),moc);
    if (entity.isNull()) return [];
    nf('void',['pointer','pointer','pointer'])(req, S('setEntity:'), entity);
    var fetched = nf('pointer',['pointer','pointer','pointer'])(moc, S('executeFetchRequest:error:'), req, new NativePointer(0));
    if (fetched.isNull()) return [];

    var n = nf('uint64',['pointer','pointer'])(fetched, S('count')).toInt32();
    for (var i = 0; i < n; i++) {
        results.push(nf('pointer',['pointer','pointer','uint64'])(fetched, S('objectAtIndex:'), i));
    }
    return results;
}

// Send reply
function sendReply(conv, text) {
    if (!sendCtrl || sendCtrl.isNull()) return false;
    var TextContent = C('AWEIMTextMessageContent');
    var content = nf('pointer',['pointer','pointer'])(TextContent, S('alloc'));
    content = nf('pointer',['pointer','pointer','pointer'])(content, S('initWithText:'), ns(text));
    if (content.isNull()) return false;

    var SendModel = C('AWEIMSendTextMessageModel');
    var model = nf('pointer',['pointer','pointer'])(SendModel, S('alloc'));
    model = nf('pointer',['pointer','pointer','pointer'])(model, S('initWithContent:'), content);
    if (model.isNull()) return false;

    nf('void',['pointer','pointer','pointer','pointer'])(sendCtrl, S('sendMessage:conversation:'), model, conv);
    return true;
}

// Poll and auto-reply
function poll() {
    if (!autoEnabled) return;

    var convs = getConversations();
    if (convs.length === 0) return;

    for (var i = 0; i < convs.length; i++) {
        var conv = convs[i];
        if (conv.isNull()) continue;

        // Get last message
        var lastMsg = _p0(conv, S('lastMessage'));
        if (lastMsg.isNull()) continue;

        // Check if from other user
        var sender = _p0(lastMsg, S('sender'));
        if (sender.isNull()) continue;

        var isSelf = nf('char',['pointer','pointer'])(sender, S('isSelf'));
        if (isSelf) continue; // skip own messages

        // Get message ID to avoid double reply
        var msgId = lastMsg.toString();
        if (repliedSet[msgId]) continue;
        repliedSet[msgId] = true;

        var text = rS(_p0(lastMsg, S('text')));
        var fromUID = rS(_p0(sender, S('userID')));
        console.log('[ADM2] New msg: "' + text + '" from ' + fromUID);

        // Send reply
        if (sendReply(conv, '你好')) {
            console.log('[ADM2] Replied!');
        }
    }
}

// Start polling
setInterval(function() {
    try { poll(); } catch(e) {}
}, 500);

// Expose toggle
globalThis.toggleDM = toggleDM;
console.log('[ADM2] Polling started. toggleDM() to enable.');
