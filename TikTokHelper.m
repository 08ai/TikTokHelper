// TikTokHelper.m — 自动关注 + 自动私信 (TIMOConversation Hook)
//
// clang -arch arm64 -dynamiclib -framework Foundation -framework UIKit \
//   -framework CoreGraphics -fobjc-arc \
//   -miphoneos-version-min=14.0 -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
//   -o TikTokHelper.dylib TikTokHelper.m

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define LOG(fmt, ...) NSLog(@"[TH] " fmt, ##__VA_ARGS__)

// ─── 安全调用 ───
static id _msg0(id t, SEL s) { if(!t||![t respondsToSelector:s])return nil; return ((id(*)(id,SEL))objc_msgSend)(t,s); }
static id _msg1(id t, SEL s, id a) { if(!t||![t respondsToSelector:s])return nil; return ((id(*)(id,SEL,id))objc_msgSend)(t,s,a); }

// ─── 全局 ───
static UIWindow *gWin; static UIButton *gToggleBtn,*gFollowBtn,*gDMBtn,*gNurtureBtn;
static UIView *gPanel; static UILabel *gStatusLbl;
static BOOL gExpanded=NO,gAutoFollow=NO,gAutoDM=NO;
static NSMutableSet *gRepliedIDs;

// ─── 颜色 ───
static UIColor *rgb(CGFloat r,CGFloat g,CGFloat b,CGFloat a) {
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}
static UIWindow *keyWin(void) {
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes)
        if ([s isKindOfClass:[UIWindowScene class]])
            for (UIWindow *w in ((UIWindowScene*)s).windows) if (w.isKeyWindow) return w;
    for (UIWindow *w in [UIApplication sharedApplication].windows) if (w.isKeyWindow) return w;
    return nil;
}
static NSString *httpGet(NSString *u) {
    NSData *d=[NSData dataWithContentsOfURL:[NSURL URLWithString:u]];
    return d?[[NSString alloc] initWithData:d encoding:4]:nil;
}
static NSArray<NSString*> *fetchUIDs(void) {
    NSString *resp=httpGet(@"http://107.148.2.130/tiktokid.php");
    if(!resp)return @[];
    NSDictionary *json=[NSJSONSerialization JSONObjectWithData:[resp dataUsingEncoding:4] options:0 error:nil];
    NSMutableArray *a=[NSMutableArray array];
    for(id u in json[@"uids"])[a addObject:[u stringValue]];
    return a;
}
static void setStatus(NSString *s){ dispatch_async(dispatch_get_main_queue(),^{ gStatusLbl.text=s; }); }

// ==================== 自动私信 Hook ====================
@interface TikTokHelper : NSObject
- (void)sendReplyToTIMOConv:(id)conv;
+ (void)installHook;
@end

static IMP gOrigSetLastMsg = NULL;

static void hooked_setLastMsg(id self, SEL _cmd, id message) {
    if (gOrigSetLastMsg) ((void(*)(id,SEL,id))gOrigSetLastMsg)(self, _cmd, message);
    if (!gAutoDM || !message) return;
    @try {
        if ([gRepliedIDs containsObject:[message description]]) return;
        [gRepliedIDs addObject:[message description]];
        id sender = _msg0(message, NSSelectorFromString(@"sender"));
        if (sender && [[_msg0(sender, NSSelectorFromString(@"isSelf")) description] isEqualToString:@"1"]) return;
        LOG(@"新消息");
        [[[TikTokHelper alloc] init] sendReplyToTIMOConv:self];
    } @catch (NSException *e) {}
}

@implementation TikTokHelper

+ (void)installHook {
    Class TIMO = NSClassFromString(@"TIMOConversation");
    if (!TIMO) return;
    Method m = class_getInstanceMethod(TIMO, NSSelectorFromString(@"setLastMessage:"));
    if (!m) return;
    gOrigSetLastMsg = method_getImplementation(m);
    method_setImplementation(m, (IMP)hooked_setLastMsg);
    LOG(@"DM Hook 已安装");
}

- (void)sendReplyToTIMOConv:(id)timoConv {
    NSString *cid = _msg0(timoConv, NSSelectorFromString(@"identifier"));
    if (!cid) return;
    Class TC = NSClassFromString(@"AWEIMTextMessageContent");
    Class SM = NSClassFromString(@"AWEIMSendTextMessageModel");
    Class MS = NSClassFromString(@"AWEIMModuleService");
    if (!TC||!SM||!MS) return;
    id c = ((id(*)(id,SEL,NSString*))objc_msgSend)([TC alloc], NSSelectorFromString(@"initWithText:"), @"你好");
    id m = ((id(*)(id,SEL,id))objc_msgSend)([SM alloc], NSSelectorFromString(@"initWithContent:"), c);
    id sc = _msg0(MS, NSSelectorFromString(@"sendMessageController"));
    SEL addSel = NSSelectorFromString(@"addMessageLocally:conversationID:");
    if ([sc respondsToSelector:addSel])
        ((void(*)(id,SEL,id,NSString*))objc_msgSend)(sc, addSel, m, cid);
    LOG(@"已回复: %@", cid);
}

// ==================== UI ====================
- (UIButton*)makeBtn:(NSString*)t frame:(CGRect)f bg:(UIColor*)bg fs:(CGFloat)fs {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom];
    b.frame=f;b.backgroundColor=bg;b.layer.cornerRadius=10;
    b.layer.borderWidth=2;b.layer.borderColor=[UIColor whiteColor].CGColor;
    b.titleLabel.font=[UIFont boldSystemFontOfSize:fs];
    b.titleLabel.numberOfLines=2;b.titleLabel.textAlignment=NSTextAlignmentCenter;
    [b setTitle:t forState:0];[b setTitleColor:[UIColor whiteColor] forState:0];
    return b;
}
- (void)onToggle { gExpanded=!gExpanded; [UIView animateWithDuration:.25 animations:^{gPanel.alpha=gExpanded?1:0;}]; [gToggleBtn setTitle:gExpanded?@"收起":@"展开" forState:0]; }

- (void)onAutoFollow {
    gAutoFollow=!gAutoFollow;
    if(gAutoFollow){
        [gFollowBtn setTitle:@"停止关注" forState:0];gFollowBtn.backgroundColor=rgb(.85,.25,.25,.9);
        setStatus(@"获取中...");
        dispatch_async(dispatch_get_global_queue(0,0),^{
            NSArray *uids=fetchUIDs(); if(!uids.count){setStatus(@"无用户");gAutoFollow=NO;return;}
            for(NSInteger i=0;i<uids.count&&gAutoFollow;i++){
                dispatch_async(dispatch_get_main_queue(),^{setStatus([NSString stringWithFormat:@"%ld/%lu %@",(long)(i+1),(unsigned long)uids.count,uids[i]]);});
                Class RS=NSClassFromString(@"AWEUserRelationServiceImpl");
                id user=[[NSClassFromString(@"AWEUserModel") alloc]init];[user setValue:uids[i] forKey:@"userID"];
                id ctx=[[NSClassFromString(@"AWEUserRelationContext") alloc]init];[ctx setValue:user forKey:@"user"];[ctx setValue:@0 forKey:@"fromPageType"];
                ((void(*)(id,SEL,id,void(^)(id)))objc_msgSend)(RS,NSSelectorFromString(@"follow:completion:"),ctx,^(id r){});
                [NSThread sleepForTimeInterval:.3];
            }
            dispatch_async(dispatch_get_main_queue(),^{setStatus([NSString stringWithFormat:@"完成 %lu",(unsigned long)uids.count]);gAutoFollow=NO;[gFollowBtn setTitle:@"自动关注" forState:0];gFollowBtn.backgroundColor=rgb(.18,.5,.92,.9);});
        });
    }else{[gFollowBtn setTitle:@"自动关注" forState:0];gFollowBtn.backgroundColor=rgb(.18,.5,.92,.9);setStatus(@"已停止");}
}

- (void)onAutoDM {
    gAutoDM=!gAutoDM;
    if(gAutoDM){[gDMBtn setTitle:@"停止私信" forState:0];gDMBtn.backgroundColor=rgb(.85,.25,.25,.9);setStatus(@"自动私信开启");}
    else{[gDMBtn setTitle:@"自动私信" forState:0];gDMBtn.backgroundColor=rgb(.15,.72,.35,.9);setStatus(@"自动私信关闭");}
}

- (void)onNurture {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"自动养号" message:@"TODO" preferredStyle:1];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:0 handler:nil]];
    UIViewController *vc=keyWin().rootViewController; while(vc.presentedViewController)vc=vc.presentedViewController;
    [vc presentViewController:a animated:YES completion:nil];
}

- (void)buildUI {
    gWin=keyWin(); if(!gWin){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self buildUI];});return;}
    CGFloat SW=[UIScreen mainScreen].bounds.size.width;
    gToggleBtn=[self makeBtn:@"展开" frame:CGRectMake(SW-95,120,85,48) bg:rgb(.92,.1,.1,.92) fs:18];
    gToggleBtn.layer.cornerRadius=16;[gToggleBtn addTarget:self action:@selector(onToggle) forControlEvents:1<<6];[gWin addSubview:gToggleBtn];
    CGFloat pW=175,pH=240;
    gPanel=[[UIView alloc]initWithFrame:CGRectMake(100,70,pW,pH)];
    gPanel.backgroundColor=rgb(1,.85,.02,.95);gPanel.layer.cornerRadius=14;
    gPanel.layer.borderWidth=3;gPanel.layer.borderColor=[UIColor whiteColor].CGColor;gPanel.alpha=0;[gWin addSubview:gPanel];
    UILabel *tl=[[UILabel alloc]initWithFrame:CGRectMake(10,8,pW-20,18)];tl.text=@"操作面板";tl.textColor=rgb(1,1,1,.6);tl.font=[UIFont systemFontOfSize:13];tl.textAlignment=NSTextAlignmentCenter;[gPanel addSubview:tl];
    gStatusLbl=[[UILabel alloc]initWithFrame:CGRectMake(10,pH-38,pW-20,30)];gStatusLbl.text=@"就绪";gStatusLbl.textColor=rgb(1,1,1,.7);gStatusLbl.font=[UIFont systemFontOfSize:10];gStatusLbl.textAlignment=NSTextAlignmentCenter;gStatusLbl.numberOfLines=2;[gPanel addSubview:gStatusLbl];
    CGFloat bX=12,bW=pW-24,bH=48,g=6,sY=30;
    gFollowBtn=[self makeBtn:@"自动关注" frame:CGRectMake(bX,sY,bW,bH) bg:rgb(.18,.5,.92,.9) fs:16];[gFollowBtn addTarget:self action:@selector(onAutoFollow) forControlEvents:1<<6];[gPanel addSubview:gFollowBtn];
    gDMBtn=[self makeBtn:@"自动私信" frame:CGRectMake(bX,sY+bH+g,bW,bH) bg:rgb(.15,.72,.35,.9) fs:16];[gDMBtn addTarget:self action:@selector(onAutoDM) forControlEvents:1<<6];[gPanel addSubview:gDMBtn];
    gNurtureBtn=[self makeBtn:@"自动养号" frame:CGRectMake(bX,sY+2*(bH+g),bW,bH) bg:rgb(.88,.48,.12,.9) fs:16];[gNurtureBtn addTarget:self action:@selector(onNurture) forControlEvents:1<<6];[gPanel addSubview:gNurtureBtn];
    LOG(@"UI 就绪");
}
@end

// ==================== 入口 ====================
__attribute__((constructor)) static void THInit(void) {
    gRepliedIDs=[NSMutableSet set];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        [TikTokHelper installHook];
        [[[TikTokHelper alloc] init] buildUI];
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer*t){
            if(gToggleBtn)[gWin bringSubviewToFront:gToggleBtn];
            if(gPanel&&gExpanded)[gWin bringSubviewToFront:gPanel];
        }];
        LOG(@"注入完成");
    });
}
