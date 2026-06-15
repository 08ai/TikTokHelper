// TikTokHelper.m — TikTok 自动关注 + 自动私信 dylib
//
// Mac 编译:
//   SDK=$(xcrun --sdk iphoneos --show-sdk-path)
//   clang -arch arm64 -dynamiclib -framework Foundation -framework UIKit \
//         -framework CoreGraphics -framework CoreData -fobjc-arc \
//         -miphoneos-version-min=14.0 -isysroot "$SDK" \
//         -o TikTokHelper.dylib TikTokHelper.m

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define LOG(fmt, ...) NSLog(@"[TH] " fmt, ##__VA_ARGS__)

// ==================== 安全调用 ====================
static id _msg0(id t, SEL s) { if(!t||![t respondsToSelector:s])return nil; return ((id(*)(id,SEL))objc_msgSend)(t,s); }
static id _msg1(id t, SEL s, id a) { if(!t||![t respondsToSelector:s])return nil; return ((id(*)(id,SEL,id))objc_msgSend)(t,s,a); }

// ==================== 全局状态 ====================
static UIWindow *gWin;
static UIButton *gToggleBtn, *gFollowBtn, *gDMBtn, *gNurtureBtn;
static UIView   *gPanel;
static UILabel  *gStatusLabel;
static BOOL      gExpanded = NO;
static BOOL      gAutoFollow = NO;
static BOOL      gAutoDM = NO;
static NSMutableSet *gRepliedMsgIDs; // 已回复的消息 ID

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
@end

@implementation TikTokHelper

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
                [NSThread sleepForTimeInterval:0.3]; // 300ms 间隔
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

// ==================== 自动私信 (Hook conversationUpdated:) ====================
static IMP gOrigConvUpdated = NULL;

static void hooked_convUpdated(id self, SEL _cmd, id info) {
    if (gOrigConvUpdated)
        ((void(*)(id,SEL,id))gOrigConvUpdated)(self, _cmd, info);
    if (!gAutoDM) return;
    @try {
        id lastMsg = _msg0(self, NSSelectorFromString(@"lastMessage"));
        if (!lastMsg) return;
        id sender = _msg0(lastMsg, NSSelectorFromString(@"sender"));
        if (sender) {
            NSNumber *isSelf = _msg0(sender, NSSelectorFromString(@"isSelf"));
            if (isSelf && isSelf.boolValue) return;
        }
        NSString *msgId = [lastMsg description];
        if ([gRepliedMsgIDs containsObject:msgId]) return;
        [gRepliedMsgIDs addObject:msgId];
        NSString *text = _msg0(lastMsg, NSSelectorFromString(@"text"));
        LOG(@"[DM] 新消息: %@", text);
        [[[TikTokHelper alloc] init] sendReply:@"你好" toConversation:self];
        LOG(@"[DM] 已回复: 你好");
    } @catch (NSException *e) {}
}

+ (void)installMessageHook {
    Class ConvCls = NSClassFromString(@"AWEIMMessageConversation");
    if (!ConvCls) return;
    SEL sel = NSSelectorFromString(@"conversationUpdated:");
    Method m = class_getInstanceMethod(ConvCls, sel);
    if (!m) { sel = NSSelectorFromString(@"didInsertNewMessagesWithMessageIdentifiers:belongingConversationMap:reason:"); m = class_getInstanceMethod(ConvCls, sel); }
    if (!m) return;
    gOrigConvUpdated = method_getImplementation(m);
    method_setImplementation(m, (IMP)hooked_convUpdated);
    LOG(@"[DM] Hook: %@", NSStringFromSelector(sel));
}

- (void)sendReply:(NSString *)text toConversation:(id)conv {
    Class TextContent = NSClassFromString(@"AWEIMTextMessageContent");
    Class SendModel = NSClassFromString(@"AWEIMSendTextMessageModel");
    Class ModuleSvc = NSClassFromString(@"AWEIMModuleService");
    if (!TextContent || !SendModel || !ModuleSvc) return;
    id content = [[TextContent alloc] init];
    SEL initSel = NSSelectorFromString(@"initWithText:");
    if ([content respondsToSelector:initSel])
        content = ((id(*)(id,SEL,NSString*))objc_msgSend)(content, initSel, text);
    id model = [[SendModel alloc] init];
    SEL modelSel = NSSelectorFromString(@"initWithContent:");
    if ([model respondsToSelector:modelSel])
        model = ((id(*)(id,SEL,id))objc_msgSend)(model, modelSel, content);
    id sendCtrl = _msg0(ModuleSvc, NSSelectorFromString(@"sendMessageController"));
    if (!sendCtrl) return;
    SEL sendSel = NSSelectorFromString(@"sendMessage:conversation:");
    if ([sendCtrl respondsToSelector:sendSel])
        ((void(*)(id,SEL,id,id))objc_msgSend)(sendCtrl, sendSel, model, conv);
}

- (void)checkInboxAndReply { /* Hook handles this */ }

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

// ==================== 构建 UI ====================
- (void)bringToFront {
    if (gToggleBtn) [gWin bringSubviewToFront:gToggleBtn];
    if (gPanel && gExpanded) [gWin bringSubviewToFront:gPanel];
}

static BOOL _hookInstalled = NO;
- (void)buildUI {
    if (!_hookInstalled) { [TikTokHelper installMessageHook]; _hookInstalled = YES; }
    gWin = keyWin();
    if (!gWin) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self buildUI];}); return; }

    // 找到内容层：UITransitionView 的最后一个子视图
    UIView *contentView = gWin;
    NSArray *subs = gWin.subviews;
    if (subs.count > 0) {
        UIView *tView = subs[0]; // UITransitionView
        if (tView.subviews.count > 0) {
            contentView = tView.subviews.lastObject;
            LOG(@"Using contentView: %@", NSStringFromClass([contentView class]));
        } else {
            contentView = tView;
        }
    }

    CGFloat SW = [UIScreen mainScreen].bounds.size.width;

    // ── 红色展开按钮 (在 contentView 上) ──
    gToggleBtn = [self makeBtn:@"展开" frame:CGRectMake(SW-95,120,85,48) bg:rgb(0.92,0.1,0.1,0.92) fs:18];
    gToggleBtn.layer.cornerRadius = 16;
    [gToggleBtn addTarget:self action:@selector(onToggle) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:gToggleBtn];

    // ── 黄色面板 ──
    CGFloat pW=175, pH=270;
    gPanel = [[UIView alloc] initWithFrame:CGRectMake(100,70,pW,pH)];
    gPanel.backgroundColor = rgb(1,0.85,0.02,0.95);
    gPanel.layer.cornerRadius = 14;
    gPanel.layer.borderWidth = 3;
    gPanel.layer.borderColor = [UIColor whiteColor].CGColor;
    gPanel.alpha = 0;
    [contentView addSubview:gPanel];

    // 标题
    UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(10,8,pW-20,18)];
    tl.text = @"操作面板"; tl.textColor = rgb(1,1,1,0.6);
    tl.font = [UIFont systemFontOfSize:13]; tl.textAlignment = NSTextAlignmentCenter;
    [gPanel addSubview:tl];

    // 状态栏
    gStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10,pH-38,pW-20,30)];
    gStatusLabel.text = @"就绪"; gStatusLabel.textColor = rgb(1,1,1,0.7);
    gStatusLabel.font = [UIFont systemFontOfSize:10]; gStatusLabel.textAlignment = NSTextAlignmentCenter;
    gStatusLabel.numberOfLines = 2;
    [gPanel addSubview:gStatusLabel];

    // 3 个按钮
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

    LOG(@"UI 就绪");
}

@end

// ==================== 入口 ====================
__attribute__((constructor))
static void THInit(void) {
    gRepliedMsgIDs = [NSMutableSet set];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        TikTokHelper *th = [[TikTokHelper alloc] init];
        [th buildUI];
        LOG(@"注入完成!");

        // bringToFront 定时器 (每 2 秒)
        [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *t) {
            [th bringToFront];
        }];

        // 自动私信轮询 (每 500ms)
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
            [[[TikTokHelper alloc] init] checkInboxAndReply];
        }];
    });
}
