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
static UIButton *gToggleBtn, *gFollowBtn, *gDMBtn, *gNurtureBtn, *gDedupBtn;
static UIView   *gPanel;
static UILabel  *gStatusLabel;
static BOOL      gExpanded = NO;
static BOOL      gAutoFollow = NO;
static BOOL      gAutoDM = NO;
static BOOL      gDedupOnce = YES;
static NSMutableSet *gRepliedIDs;

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
    NSString *resp = httpGet(@"http://107.148.2.130/tiktokid.php");
    if (!resp) { LOG(@"HTTP failed"); return @[]; }
    NSData *data = [resp dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *arr = json[@"uids"];
    NSMutableArray *uids = [NSMutableArray array];
    for (id u in arr) [uids addObject:[u stringValue]];
    LOG(@"UIDs: %@", uids);
    return uids;
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

        // 去重复模式: 每个会话只回一次 (按 conversation 指针)
        if (gDedupOnce) {
            NSString *convKey = [NSString stringWithFormat:@"%p", self];
            if ([gRepliedIDs containsObject:convKey]) return;
            [gRepliedIDs addObject:convKey];
        }
        LOG(@"DM reply triggered");

        // self 是普通 NSObject (非 NSManagedObject)，直接主线程发送
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                [[[TikTokHelper alloc] init] sendViaTIMOCtrl:self text:@"你好"];
                LOG(@"DM reply sent");
            } @catch (NSException *e) {
                LOG(@"sendViaTIMOCtrl crash: %@", e);
            }
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
            ((void(*)(id,SEL,id,id))objc_msgSend)(sc, ss, m, timoConv);
            LOG(@"send: OK");
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
    gExpanded = !gExpanded;
    [UIView animateWithDuration:0.25 animations:^{ gPanel.alpha = gExpanded?1.0:0.0; }];
    [gToggleBtn setTitle:gExpanded?@"收起":@"展开" forState:UIControlStateNormal];
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
                [NSThread sleepForTimeInterval:0.3];
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
- (void)onAutoDedup {
    gDedupOnce = !gDedupOnce;
    if (gDedupOnce) {
        [gDedupBtn setTitle:@"✓ 去重复" forState:UIControlStateNormal];
        gDedupBtn.backgroundColor = rgb(0.15,0.72,0.35,0.8);
    } else {
        [gDedupBtn setTitle:@"✗ 去重复" forState:UIControlStateNormal];
        gDedupBtn.backgroundColor = rgb(0.5,0.5,0.5,0.8);
    }
}

// ==================== 构建 UI ====================
- (void)bringToFront {
    if (gToggleBtn) [gWin bringSubviewToFront:gToggleBtn];
    if (gPanel && gExpanded) [gWin bringSubviewToFront:gPanel];
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

    // ── 黄色面板 ──
    CGFloat pW=175, pH=320;
    gPanel = [[UIView alloc] initWithFrame:CGRectMake(100,70,pW,pH)];
    gPanel.backgroundColor = rgb(1,0.85,0.02,0.95);
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

    gFollowBtn = [self makeBtn:@"自动关注" frame:CGRectMake(bX,sY,bW,bH) bg:rgb(0.18,0.50,0.92,0.9) fs:16];
    [gFollowBtn addTarget:self action:@selector(onAutoFollow) forControlEvents:UIControlEventTouchUpInside];
    [gPanel addSubview:gFollowBtn];

    gDMBtn = [self makeBtn:@"自动私信" frame:CGRectMake(bX,sY+bH+g,bW,bH) bg:rgb(0.15,0.72,0.35,0.9) fs:16];
    [gDMBtn addTarget:self action:@selector(onAutoDM) forControlEvents:UIControlEventTouchUpInside];
    [gPanel addSubview:gDMBtn];

    gNurtureBtn = [self makeBtn:@"自动养号" frame:CGRectMake(bX,sY+2*(bH+g),bW,bH) bg:rgb(0.88,0.48,0.12,0.9) fs:16];
    [gNurtureBtn addTarget:self action:@selector(onAutoNurture) forControlEvents:UIControlEventTouchUpInside];
    [gPanel addSubview:gNurtureBtn];

    // 去重复复选框
    gDedupBtn = [self makeBtn:@"✓ 去重复" frame:CGRectMake(bX,sY+3*(bH+g),bW,32) bg:rgb(0.15,0.72,0.35,0.8) fs:14];
    gDedupBtn.layer.cornerRadius = 8;
    [gDedupBtn addTarget:self action:@selector(onAutoDedup) forControlEvents:UIControlEventTouchUpInside];
    [gPanel addSubview:gDedupBtn];

    LOG(@"UI 就绪");
}

@end

// ==================== 入口 ====================
__attribute__((constructor))
static void THInit(void) {
    gRepliedIDs = [NSMutableSet set];
    gDedupOnce = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        TikTokHelper *th = [[TikTokHelper alloc] init];
        [th buildUI];
        LOG(@"注入完成!");

        // bringToFront 定时器 (每 2 秒)
        [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *t) {
            [th bringToFront];
        }];

        // 自动私信——method swizzle（事件驱动）
        [TikTokHelper installMessageHook];
    });
}
