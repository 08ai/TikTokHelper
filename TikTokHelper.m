// TikTokHelper.m — TikTok 自动关注 + 自动私信 dylib
//
// Mac 编译:
//   SDK=$(xcrun --sdk iphoneos --show-sdk-path)
//   clang -arch arm64 -dynamiclib -framework Foundation -framework UIKit \
//         -framework CoreGraphics -framework CoreData -fobjc-arc \
//         -miphoneos-version-min=14.0 -isysroot "$SDK" \
//         -o TikTokHelper.dylib TikTokHelper.m

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ==================== 文件日志 ====================
static void thLog(NSString *msg) {
    NSLog(@"%@", msg);
    NSString *logPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"th.log"];
    FILE *f = fopen([logPath UTF8String], "a");
    if (f) {
        fprintf(f, "%s\n", [msg UTF8String]);
        fclose(f);
    }
}
#define LOG(fmt, ...) thLog([NSString stringWithFormat:@"[TH] " fmt, ##__VA_ARGS__])

// ==================== 安全调用 ====================
static id _msg0(id t, SEL s) { if(!t||![t respondsToSelector:s])return nil; return ((id(*)(id,SEL))objc_msgSend)(t,s); }
static id _msg1(id t, SEL s, id a) { if(!t||![t respondsToSelector:s])return nil; return ((id(*)(id,SEL,id))objc_msgSend)(t,s,a); }

// ==================== 全局状态 ====================
static UIWindow *gWin;
static UIButton *gToggleBtn, *gFollowBtn, *gFollow2Btn, *gDMBtn, *gNurtureBtn, *gDedupBtn, *gBatchBtn;
static UIView   *gPanel;
static UILabel  *gStatusLabel;
static BOOL      gExpanded = NO;
static BOOL      gAutoFollow = NO;
static BOOL      gAutoFollow2 = NO;
static BOOL      gAutoDM = NO;
static BOOL      gDedupOnce = YES;
static BOOL      gIsSending = NO;
static BOOL      gIsLoggedIn = NO;
static NSString  *gUserName;
static NSMutableSet *gRepliedIDs;
static NSTimeInterval gFollowSpeed = 0.3;
static BOOL      gIsBatchSending = NO;

// 登录界面
static UIView    *gLoginView;
static UITextField *gUserField, *gPassField, *gSpeedField;
static UILabel   *gLoginError;

// ==================== 颜色 ====================
static UIColor *rgb(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

// ==================== KeyWindow ====================
static UIWindow *keyWin(void) {
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]])
            for (UIWindow *w in ((UIWindowScene*)s).windows) if (w.isKeyWindow) return w;
    }
    for (UIWindow *w in [UIApplication sharedApplication].windows) if (w.isKeyWindow) return w;
    return nil;
}

// ==================== HTTP 请求 ====================
static NSString *httpGet(NSString *urlStr) {
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return nil;
    NSData *d = [NSData dataWithContentsOfURL:url];
    if (!d) return nil;
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
}

// ==================== 获取 UID 列表 ====================
static NSArray<NSString *> *fetchUIDs(void) {
    NSString *resp = httpGet([NSString stringWithFormat:@"http://107.149.106.29:2256/tiktokid.php?user=%@", gUserName ?: @""]);
    if (!resp) { LOG(@"HTTP failed"); return @[]; }
    NSData *data = [resp dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *arr = json[@"uids"];
    NSMutableArray *uids = [NSMutableArray array];
    for (id u in arr) [uids addObject:[u stringValue]];
    LOG(@"UIDs: %@", uids);
    return uids;
}

// ==================== 获取自动回复话术 ====================
static NSString *fetchReplyText(void) {
    NSString *resp = httpGet([NSString stringWithFormat:@"http://107.149.106.29:2256/tiktoksms.php?user=%@", gUserName ?: @""]);
    if (!resp) return @"你好";
    NSData *data = [resp dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return @"你好";
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (!json) return @"你好";
    NSString *sms = json[@"sms"];
    return sms.length > 0 ? sms : @"你好";
}

// ==================== 更新状态标签 ====================
static void setStatus(NSString *s) {
    dispatch_async(dispatch_get_main_queue(), ^{ gStatusLabel.text = s; });
}

// ==================== 界面 ====================
@interface TikTokHelper : NSObject
- (void)sendViaTIMOCtrl:(id)timoConv text:(NSString *)text;
+ (void)installMessageHook;
@end

// ─── DM Hook: TIMOConversation.setLastMessage: ───
static IMP gOrigSetLastMsg = NULL;
static void hooked_setLastMsg(id self, SEL _cmd, id message) {
    // 先调用原始实现
    if (gOrigSetLastMsg) {
        ((void(*)(id,SEL,id))gOrigSetLastMsg)(self, _cmd, message);
    }

    if (!gAutoDM || !message) return;

    // 安全检查: 必须是 TIMOConversation
    if (![self isKindOfClass:NSClassFromString(@"TIMOConversation")]) return;

    @try {
        if (gRepliedIDs.count > 500) [gRepliedIDs removeAllObjects];

        // 冷却 0.5s
        static NSTimeInterval lastReply = 0;
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        if (now - lastReply < 0.5) return;
        lastReply = now;

        // 防重入: 正在发送中，跳过
        if (gIsSending) return;

        // 去重复模式: 每个会话只回一次 (按 conversation 指针)
        if (gDedupOnce) {
            NSString *convKey = [NSString stringWithFormat:@"%p", self];
            if ([gRepliedIDs containsObject:convKey]) return;
            [gRepliedIDs addObject:convKey];
        }
        // 加锁防止循环触发
        gIsSending = YES;
        LOG(@"DM reply triggered");

        // 从远程获取话术
        NSString *replyText = fetchReplyText();

        // self 是普通 NSObject (非 NSManagedObject)，直接主线程发送
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                [[[TikTokHelper alloc] init] sendViaTIMOCtrl:self text:replyText];
                LOG(@"DM reply sent: %@", replyText);
            } @catch (NSException *e) {
                LOG(@"sendViaTIMOCtrl crash: %@", e);
            }
            // 发送完成，解锁（延迟 1s 等 setLastMessage 回调过去）
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                gIsSending = NO;
            });
        });
    } @catch (NSException *e) {
        LOG(@"hook crash: %@", e);
    }
}

@implementation TikTokHelper

+ (void)installMessageHook {
    Class TIMO = NSClassFromString(@"TIMOConversation");
    if (!TIMO) { LOG(@"TIMOConversation not found"); return; }
    Method m = class_getInstanceMethod(TIMO, NSSelectorFromString(@"setLastMessage:"));
    if (!m) { LOG(@"setLastMessage: not found"); return; }
    gOrigSetLastMsg = method_getImplementation(m);
    method_setImplementation(m, (IMP)hooked_setLastMsg);
    LOG(@"DM Swizzle installed");
}

// ─── 发送消息 ───
- (void)sendViaTIMOCtrl:(id)timoConv text:(NSString *)text {
    @try {
        Class TC = NSClassFromString(@"AWEIMTextMessageContent");
        Class SM = NSClassFromString(@"AWEIMSendTextMessageModel");
        Class MS = NSClassFromString(@"AWEIMModuleService");
        if (!TC||!SM||!MS) { LOG(@"send: class missing"); return; }

        id c = ((id(*)(id,SEL,NSString*))objc_msgSend)([TC alloc], NSSelectorFromString(@"initWithText:"), text);
        if (!c) c = ((id(*)(id,SEL,NSString*,id))objc_msgSend)([TC alloc], NSSelectorFromString(@"initWithText:referenceVideo:"), text, nil);
        if (!c) { LOG(@"send: content nil"); return; }

        id m = ((id(*)(id,SEL,id))objc_msgSend)([SM alloc], NSSelectorFromString(@"initWithContent:"), c);
        if (!m) { LOG(@"send: model nil"); return; }

        id sc = _msg0(MS, NSSelectorFromString(@"sendMessageController"));
        if (!sc) { LOG(@"send: ctrl nil"); return; }

        SEL ss = NSSelectorFromString(@"sendMessage:conversation:");
        if ([sc respondsToSelector:ss]) {
            id result = ((id(*)(id,SEL,id,id))objc_msgSend)(sc, ss, m, timoConv);
            LOG(@"send: result=%@ conv=%@", result, [timoConv class]);
        }
    } @catch (NSException *e) {
        LOG(@"send crash: %@", e);
    }
}

// ─── 创建按钮 ───
- (UIButton *)makeBtn:(NSString *)t frame:(CGRect)f bg:(UIColor *)bg fs:(CGFloat)fs {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = f; b.backgroundColor = bg;
    b.layer.cornerRadius = 10;
    b.layer.borderWidth = 2;
    b.layer.borderColor = [UIColor whiteColor].CGColor;
    b.titleLabel.font = [UIFont boldSystemFontOfSize:fs];
    b.titleLabel.numberOfLines = 2;
    b.titleLabel.textAlignment = NSTextAlignmentCenter;
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    return b;
}

// ─── 展开/收起面板 ───
- (void)onToggle {
    if (!gIsLoggedIn) {
        [UIView animateWithDuration:0.3 animations:^{ gLoginView.alpha = 1.0; }];
        return;
    }
    gExpanded = !gExpanded;
    [UIView animateWithDuration:0.25 animations:^{ gPanel.alpha = gExpanded?1.0:0.0; }];
    [gToggleBtn setTitle:gExpanded?@"收起":@"展开" forState:UIControlStateNormal];
}

// ==================== 批量群发 ====================
- (void)onBatchSend {
    if (gIsBatchSending) {
        [self onStopBatchSend];
        return;
    }
    gIsBatchSending = YES;
    [gBatchBtn setTitle:@"停止群发" forState:UIControlStateNormal];
    gBatchBtn.backgroundColor = rgb(0.9,0.25,0.25,0.9);
    setStatus(@"批量群发中...");
    LOG(@"Batch send START");
    NSArray *uids = @[@"7584084336589767698", @"7114345548233098241", @"7307413705494168578", @"3830352445428"];
    [self batchSendNext:0 uids:uids];
}

- (void)batchSendNext:(NSInteger)i uids:(NSArray *)uids {
    if (!gIsBatchSending || i >= uids.count) {
        dispatch_async(dispatch_get_main_queue(), ^{
            setStatus([NSString stringWithFormat:@"群发完成 %lu 人", (unsigned long)uids.count]);
            LOG(@"Batch send DONE");
            gIsBatchSending = NO;
            [gBatchBtn setTitle:@"批量群发" forState:UIControlStateNormal];
            gBatchBtn.backgroundColor = rgb(0.75,0.3,0.85,0.9);
        });
        return;
    }
    NSString *uid = uids[i];
    setStatus([NSString stringWithFormat:@"群发 %ld/%lu: %@", (long)(i+1), (unsigned long)uids.count, uid]);

    Class MS = NSClassFromString(@"AWEIMModuleService");
    if (!MS) {
        LOG(@"Batch [%ld] MS not found", (long)i);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, gFollowSpeed*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self batchSendNext:i+1 uids:uids];
        });
        return;
    }
    SEL sel = NSSelectorFromString(@"getConversationWithPeerUid:completion:");
    LOG(@"Batch [%ld] calling getConversationWithPeerUid: %@", (long)i, uid);

    // 注意: completion 签名可能是 void(^)(id conv, NSError *err) 或 void(^)(id conv)
    __weak typeof(self) ws = self;
    void (^cb)(id, id) = ^(id conv, id err) {
        LOG(@"Batch [%ld] callback conv=%@ err=%@", (long)i, [conv class], err);
        if (conv && gIsBatchSending) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [ws sendViaTIMOCtrl:conv text:@"你好啊！在干嘛"];
            });
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, gFollowSpeed*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [ws batchSendNext:i+1 uids:uids];
        });
    };
    ((void(*)(id,SEL,id,void(^)(id,id)))objc_msgSend)(MS, sel, uid, cb);
}

- (void)onStopBatchSend {
    gIsBatchSending = NO;
    [gBatchBtn setTitle:@"批量群发" forState:UIControlStateNormal];
    gBatchBtn.backgroundColor = rgb(0.75,0.3,0.85,0.9);
    setStatus(@"已停止群发");
    LOG(@"Batch send STOPPED");
}

// ==================== 自动关注 ====================
- (void)followUID:(NSString *)uid {
    Class RelSvc = NSClassFromString(@"AWEUserRelationServiceImpl");
    Class UserModel = NSClassFromString(@"AWEUserModel");
    Class CtxCls = NSClassFromString(@"AWEUserRelationContext");
    if (!RelSvc || !UserModel || !CtxCls) return;

    id user = [[UserModel alloc] init];
    [user setValue:uid forKey:@"userID"];

    id ctx = [[CtxCls alloc] init];
    [ctx setValue:user forKey:@"user"];
    [ctx setValue:@(0) forKey:@"fromPageType"];

    SEL sel = NSSelectorFromString(@"follow:completion:");
    ((void(*)(id,SEL,id,void(^)(id)))objc_msgSend)(RelSvc, sel, ctx, ^(id r){});
}

// 自动关注2 专用: 使用 AWEUserRelation.getLoginContextWithUserID:fromPageType: 创建上下文
- (void)followUID2:(NSString *)uid {
    Class RelCls = NSClassFromString(@"AWEUserRelation");
    if (!RelCls) { [self followUID:uid]; return; }

    SEL getCtx = NSSelectorFromString(@"getLoginContextWithUserID:fromPageType:");
    if (![RelCls respondsToSelector:getCtx]) { [self followUID:uid]; return; }

    id ctx = ((id(*)(id,SEL,id,long long))objc_msgSend)(RelCls, getCtx, uid, 1);

    if (ctx) {
        Class RelSvc = NSClassFromString(@"AWEUserRelationServiceImpl");
        SEL sel = NSSelectorFromString(@"follow:completion:");
        ((void(*)(id,SEL,id,void(^)(id)))objc_msgSend)(RelSvc, sel, ctx, ^(id r){});
    } else {
        [self followUID:uid];
    }
}

- (void)onAutoFollow {
    gAutoFollow = !gAutoFollow;
    if (gAutoFollow) {
        [gFollowBtn setTitle:@"停止关注" forState:UIControlStateNormal];
        gFollowBtn.backgroundColor = rgb(0.85,0.25,0.25,0.9);
        setStatus(@"获取用户列表...");
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0), ^{
            NSArray *uids = fetchUIDs();
            if (uids.count == 0) { setStatus(@"无用户"); gAutoFollow=NO; return; }
            dispatch_async(dispatch_get_main_queue(), ^{
                setStatus([NSString stringWithFormat:@"开始关注 %lu 人",(unsigned long)uids.count]);
            });
            for (NSInteger i = 0; i < uids.count && gAutoFollow; i++) {
                NSString *uid = uids[i];
                dispatch_async(dispatch_get_main_queue(), ^{
                    setStatus([NSString stringWithFormat:@"关注 %ld/%lu: %@",(long)(i+1),(unsigned long)uids.count,uid]);
                });
                [self followUID:uid];
                [NSThread sleepForTimeInterval:gFollowSpeed];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                setStatus([NSString stringWithFormat:@"完成 %lu 人",(unsigned long)uids.count]);
                if (gAutoFollow) {
                    gAutoFollow = NO;
                    [gFollowBtn setTitle:@"自动关注" forState:UIControlStateNormal];
                    gFollowBtn.backgroundColor = rgb(0.18,0.50,0.92,0.9);
                }
            });
        });
    } else {
        [gFollowBtn setTitle:@"自动关注" forState:UIControlStateNormal];
        gFollowBtn.backgroundColor = rgb(0.18,0.50,0.92,0.9);
        setStatus(@"已停止关注");
    }
}

// ==================== 自动关注2 ====================
- (void)onAutoFollow2 {
    gAutoFollow2 = !gAutoFollow2;
    if (gAutoFollow2) {
        [gFollow2Btn setTitle:@"停止关注2" forState:UIControlStateNormal];
        gFollow2Btn.backgroundColor = rgb(0.85,0.25,0.25,0.9);
        setStatus(@"获取用户列表...");
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0), ^{
            NSArray *uids = fetchUIDs();
            if (uids.count == 0) { setStatus(@"无用户"); gAutoFollow2=NO; return; }
            dispatch_async(dispatch_get_main_queue(), ^{
                setStatus([NSString stringWithFormat:@"开始关注2 %lu 人",(unsigned long)uids.count]);
            });
            for (NSInteger i = 0; i < uids.count && gAutoFollow2; i++) {
                NSString *uid = uids[i];
                dispatch_async(dispatch_get_main_queue(), ^{
                    setStatus([NSString stringWithFormat:@"关注2 %ld/%lu: %@",(long)(i+1),(unsigned long)uids.count,uid]);
                });
                [self followUID2:uid];
                [NSThread sleepForTimeInterval:gFollowSpeed];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                setStatus([NSString stringWithFormat:@"完成2 %lu 人",(unsigned long)uids.count]);
                if (gAutoFollow2) {
                    gAutoFollow2 = NO;
                    [gFollow2Btn setTitle:@"自动关注2" forState:UIControlStateNormal];
                    gFollow2Btn.backgroundColor = rgb(0.18,0.50,0.92,0.9);
                }
            });
        });
    } else {
        [gFollow2Btn setTitle:@"自动关注2" forState:UIControlStateNormal];
        gFollow2Btn.backgroundColor = rgb(0.18,0.50,0.92,0.9);
        setStatus(@"已停止关注2");
    }
}

// ==================== 自动私信 ====================
- (void)onAutoDM {
    gAutoDM = !gAutoDM;
    if (gAutoDM) {
        [gDMBtn setTitle:@"停止私信" forState:UIControlStateNormal];
        gDMBtn.backgroundColor = rgb(0.85,0.25,0.25,0.9);
        setStatus(@"自动私信已开启");
        LOG(@"Auto-DM ON");
    } else {
        [gDMBtn setTitle:@"自动私信" forState:UIControlStateNormal];
        gDMBtn.backgroundColor = rgb(0.15,0.72,0.35,0.9);
        setStatus(@"自动私信已关闭");
        LOG(@"Auto-DM OFF");
    }
}

// ─── 自动养号(TODO) ───
- (void)onAutoNurture {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"自动养号" message:@"TODO" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *vc = keyWin().rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    [vc presentViewController:a animated:YES completion:nil];
}

// ─── 去重复 ───
- (void)updateDedupBtn {
    if (gDedupOnce) {
        [gDedupBtn setTitle:@"✓ 去重复" forState:UIControlStateNormal];
        gDedupBtn.backgroundColor = rgb(0.15,0.72,0.35,0.8);
    } else {
        [gDedupBtn setTitle:@"✗ 去重复" forState:UIControlStateNormal];
        gDedupBtn.backgroundColor = rgb(0.5,0.5,0.5,0.8);
    }
}

- (void)onAutoDedup {
    gDedupOnce = !gDedupOnce;
    [self updateDedupBtn];
}

- (void)onSpeedChange {
    NSString *text = gSpeedField.text;
    if (text.length == 0) { gFollowSpeed = 0.3; return; }
    double val = [text doubleValue];
    if (val == 0) { gFollowSpeed = 0; return; }      // 0 = 不限速
    if (val < 0)  { gFollowSpeed = 0.3; return; }    // 负数无效
    gFollowSpeed = val / 1000.0;
}

- (void)fetchSpeedSetting {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0), ^{
        NSString *resp = httpGet([NSString stringWithFormat:@"http://107.149.106.29:2256/tiktoksudu.php?user=%@", gUserName ?: @""]);
        dispatch_async(dispatch_get_main_queue(), ^{
            int val = [resp intValue];
            if (val == 0) {
                gFollowSpeed = 0;           // 0 = 不限速
                gSpeedField.text = @"0";
            } else if (val > 0) {
                gFollowSpeed = val / 1000.0;
                gSpeedField.text = [NSString stringWithFormat:@"%d", val];
            }
            LOG(@"Speed: %dms", val);
        });
    });
}

- (void)fetchDedupSetting {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0), ^{
        NSString *resp = httpGet([NSString stringWithFormat:@"http://107.149.106.29:2256/tiktokchongfu.php?user=%@", gUserName ?: @""]);
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([resp isEqualToString:@"1"]) {
                gDedupOnce = YES;
                LOG(@"Dedup: ON (remote=1)");
            } else if ([resp isEqualToString:@"2"]) {
                gDedupOnce = NO;
                LOG(@"Dedup: OFF (remote=2)");
            }
            [self updateDedupBtn];
        });
    });
}

// ==================== 登录 ====================
- (void)onLogin {
    NSString *user = gUserField.text ?: @"";
    NSString *pass = gPassField.text ?: @"";
    if (user.length == 0 || pass.length == 0) {
        gLoginError.text = @"请输入账号和密码";
        return;
    }
    gLoginError.text = @"登录中...";
    gLoginError.textColor = [UIColor whiteColor];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0), ^{
        NSString *urlStr = [NSString stringWithFormat:@"http://107.149.106.29:2256/tiktoklogin.php?user=%@&pass=%@",
                            [user stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]],
                            [pass stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
        NSString *resp = httpGet(urlStr);
        BOOL ok = [resp isEqualToString:@"OK"];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ok) {
                gIsLoggedIn = YES;
                gUserName = user;
                [[NSUserDefaults standardUserDefaults] setObject:user forKey:@"TH_UserName"];
                [[NSUserDefaults standardUserDefaults] synchronize];
                gLoginError.text = nil;
                [UIView animateWithDuration:0.3 animations:^{ gLoginView.alpha = 0.0; }];
                LOG(@"Login OK: %@", user);
            } else {
                gLoginError.text = @"密码错误或失效";
                gLoginError.textColor = rgb(1,0.3,0.3,1);
                LOG(@"Login FAIL: %@", user);
            }
        });
    });
}

- (void)buildLogin {
    CGFloat SW = [UIScreen mainScreen].bounds.size.width;
    CGFloat SH = [UIScreen mainScreen].bounds.size.height;

    // 半透明背景
    gLoginView = [[UIView alloc] initWithFrame:CGRectMake(0,0,SW,SH)];
    gLoginView.backgroundColor = rgb(0,0,0,0.65);
    gLoginView.alpha = 0;
    [gWin addSubview:gLoginView];

    // 登录卡片
    CGFloat cW = 260, cH = 260;
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake((SW-cW)/2,(SH-cH)/2-60,cW,cH)];
    card.backgroundColor = rgb(0.15,0.15,0.18,0.95);
    card.layer.cornerRadius = 16;
    card.layer.borderWidth = 2;
    card.layer.borderColor = rgb(0.3,0.6,1,0.8).CGColor;
    [gLoginView addSubview:card];

    // 标题
    UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(0,20,cW,24)];
    tl.text = @"🔐 登录"; tl.textColor = [UIColor whiteColor];
    tl.font = [UIFont boldSystemFontOfSize:20]; tl.textAlignment = NSTextAlignmentCenter;
    [card addSubview:tl];

    // 用户名
    gUserField = [[UITextField alloc] initWithFrame:CGRectMake(24,58,cW-48,38)];
    gUserField.placeholder = @"账号";
    gUserField.backgroundColor = rgb(1,1,1,0.12);
    gUserField.textColor = [UIColor whiteColor];
    gUserField.layer.cornerRadius = 8;
    gUserField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0,0,10,0)];
    gUserField.leftViewMode = UITextFieldViewModeAlways;
    gUserField.autocorrectionType = UITextAutocorrectionTypeNo;
    gUserField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [card addSubview:gUserField];

    // 密码
    gPassField = [[UITextField alloc] initWithFrame:CGRectMake(24,108,cW-48,38)];
    gPassField.placeholder = @"密码";
    gPassField.secureTextEntry = YES;
    gPassField.backgroundColor = rgb(1,1,1,0.12);
    gPassField.textColor = [UIColor whiteColor];
    gPassField.layer.cornerRadius = 8;
    gPassField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0,0,10,0)];
    gPassField.leftViewMode = UITextFieldViewModeAlways;
    [card addSubview:gPassField];

    // 登录按钮
    UIButton *loginBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    loginBtn.frame = CGRectMake(24,162,cW-48,42);
    loginBtn.backgroundColor = rgb(0.2,0.55,0.95,1);
    loginBtn.layer.cornerRadius = 10;
    [loginBtn setTitle:@"登 录" forState:UIControlStateNormal];
    loginBtn.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [loginBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [loginBtn addTarget:self action:@selector(onLogin) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:loginBtn];

    // 错误提示
    gLoginError = [[UILabel alloc] initWithFrame:CGRectMake(0,215,cW,20)];
    gLoginError.text = nil;
    gLoginError.textColor = rgb(1,0.3,0.3,1);
    gLoginError.font = [UIFont systemFontOfSize:13];
    gLoginError.textAlignment = NSTextAlignmentCenter;
    [card addSubview:gLoginError];

    // 关闭按钮
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(cW-40,10,30,30);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:rgb(1,1,1,0.5) forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:18];
    [closeBtn addTarget:self action:@selector(hideLogin) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:closeBtn];

    LOG(@"Login UI ready");
}

- (void)hideLogin {
    [UIView animateWithDuration:0.3 animations:^{ gLoginView.alpha = 0.0; }];
    [gUserField resignFirstResponder];
    [gPassField resignFirstResponder];
}

// ==================== 构建 UI ====================
- (void)bringToFront {
    if (gToggleBtn) [gWin bringSubviewToFront:gToggleBtn];
    if (gPanel && gExpanded) [gWin bringSubviewToFront:gPanel];
    if (gLoginView && gLoginView.alpha > 0) [gWin bringSubviewToFront:gLoginView];
}

- (void)buildUI {
    gWin = keyWin();
    if (!gWin) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self buildUI];}); return; }

    UIView *contentView = gWin;
    NSArray *subs = gWin.subviews;
    if (subs.count > 0) {
        UIView *tView = subs[0];
        if (tView.subviews.count > 0) {
            contentView = tView.subviews.lastObject;
            LOG(@"Using contentView: %@", NSStringFromClass([contentView class]));
        } else {
            contentView = tView;
        }
    }

    CGFloat SW = [UIScreen mainScreen].bounds.size.width;

    // ── 红色展开按钮 ──
    gToggleBtn = [self makeBtn:@"展开" frame:CGRectMake(SW-95,120,85,48) bg:rgb(0.92,0.1,0.1,0.92) fs:18];
    gToggleBtn.layer.cornerRadius = 16;
    [gToggleBtn addTarget:self action:@selector(onToggle) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:gToggleBtn];

    // ── 雅黑面板 ──
    CGFloat pW=175, pH=430;
    gPanel = [[UIView alloc] initWithFrame:CGRectMake(100,70,pW,pH)];
    gPanel.backgroundColor = rgb(0.1,0.1,0.12,0.95);
    gPanel.layer.cornerRadius = 14;
    gPanel.layer.borderWidth = 3;
    gPanel.layer.borderColor = [UIColor whiteColor].CGColor;
    gPanel.alpha = 0;
    [contentView addSubview:gPanel];

    UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(10,8,pW-20,18)];
    tl.text = @"操作面板"; tl.textColor = rgb(1,1,1,0.6);
    tl.font = [UIFont systemFontOfSize:13]; tl.textAlignment = NSTextAlignmentCenter;
    [gPanel addSubview:tl];

    gStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10,pH-38,pW-20,30)];
    gStatusLabel.text = @"就绪"; gStatusLabel.textColor = rgb(1,1,1,0.7);
    gStatusLabel.font = [UIFont systemFontOfSize:10]; gStatusLabel.textAlignment = NSTextAlignmentCenter;
    gStatusLabel.numberOfLines = 2;
    [gPanel addSubview:gStatusLabel];

    CGFloat bX=12, bW=pW-24, bH=50, g=6, sY=30;

    // 批量群发（暂隐藏）
    // 批量群发（暂隐藏——下次接着开发）
    gBatchBtn = [self makeBtn:@"批量群发" frame:CGRectMake(bX,sY,bW,bH) bg:rgb(0.75,0.3,0.85,0.9) fs:15];
    [gBatchBtn addTarget:self action:@selector(onBatchSend) forControlEvents:UIControlEventTouchUpInside];
    gBatchBtn.hidden = YES;
    [gPanel addSubview:gBatchBtn];

    gFollowBtn = [self makeBtn:@"自动关注" frame:CGRectMake(bX,sY,bW,bH) bg:rgb(0.18,0.50,0.92,0.9) fs:16];
    [gFollowBtn addTarget:self action:@selector(onAutoFollow) forControlEvents:UIControlEventTouchUpInside];
    [gPanel addSubview:gFollowBtn];

    gFollow2Btn = [self makeBtn:@"自动关注2" frame:CGRectMake(bX,sY+bH+g,bW,bH) bg:rgb(0.18,0.50,0.92,0.9) fs:16];
    [gFollow2Btn addTarget:self action:@selector(onAutoFollow2) forControlEvents:UIControlEventTouchUpInside];
    [gPanel addSubview:gFollow2Btn];

    gDMBtn = [self makeBtn:@"自动私信" frame:CGRectMake(bX,sY+2*(bH+g),bW,bH) bg:rgb(0.15,0.72,0.35,0.9) fs:16];
    [gDMBtn addTarget:self action:@selector(onAutoDM) forControlEvents:UIControlEventTouchUpInside];
    [gPanel addSubview:gDMBtn];

    gNurtureBtn = [self makeBtn:@"自动养号" frame:CGRectMake(bX,sY+3*(bH+g),bW,bH) bg:rgb(0.88,0.48,0.12,0.9) fs:16];
    [gNurtureBtn addTarget:self action:@selector(onAutoNurture) forControlEvents:UIControlEventTouchUpInside];
    [gPanel addSubview:gNurtureBtn];

    // 去重复复选框
    gDedupBtn = [self makeBtn:@"✓ 去重复" frame:CGRectMake(bX,sY+4*(bH+g),bW,32) bg:rgb(0.15,0.72,0.35,0.8) fs:14];
    gDedupBtn.layer.cornerRadius = 8;
    [gDedupBtn addTarget:self action:@selector(onAutoDedup) forControlEvents:UIControlEventTouchUpInside];
    [gPanel addSubview:gDedupBtn];

    // 速度输入框
    CGFloat spY = sY+4*(bH+g)+38;
    UILabel *spLabel = [[UILabel alloc] initWithFrame:CGRectMake(bX,spY,80,26)];
    spLabel.text = @"速度(ms)"; spLabel.textColor = rgb(1,1,1,0.7);
    spLabel.font = [UIFont systemFontOfSize:11];
    [gPanel addSubview:spLabel];

    gSpeedField = [[UITextField alloc] initWithFrame:CGRectMake(bX+78,spY,73,26)];
    gSpeedField.text = @"300";
    gSpeedField.keyboardType = UIKeyboardTypeNumberPad;
    gSpeedField.backgroundColor = rgb(1,1,1,0.15);
    gSpeedField.textColor = [UIColor whiteColor];
    gSpeedField.font = [UIFont systemFontOfSize:13];
    gSpeedField.textAlignment = NSTextAlignmentCenter;
    gSpeedField.layer.cornerRadius = 5;
    [gSpeedField addTarget:self action:@selector(onSpeedChange) forControlEvents:UIControlEventEditingChanged];
    [gPanel addSubview:gSpeedField];

    LOG(@"UI 就绪");
}

@end

// ==================== 入口 ====================
__attribute__((constructor))
static void THInit(void) {
    // 构造函数做越少越好——避免跟 TikTok 初始化冲突被杀
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        gRepliedIDs = [NSMutableSet set];
        gDedupOnce = YES;
        // 恢复上次登录
        NSString *savedUser = [[NSUserDefaults standardUserDefaults] stringForKey:@"TH_UserName"];
        if (savedUser.length > 0) {
            gIsLoggedIn = YES;
            gUserName = savedUser;
            LOG(@"Auto-login: %@", savedUser);
        }
        TikTokHelper *th = [[TikTokHelper alloc] init];
        [th buildUI];
        [th buildLogin];
        [th fetchDedupSetting];
        [th fetchSpeedSetting];
        LOG(@"注入完成!");

        // bringToFront 定时器 (每 2 秒)
        [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *t) {
            [th bringToFront];
        }];

        // 自动私信——method swizzle（事件驱动）
        [TikTokHelper installMessageHook];
    });
}
