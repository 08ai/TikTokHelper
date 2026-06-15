// TikTokHelper.m — TikTok 浮动面板 + 自动关注 + 自动私信 (Whee 方案)
//
// clang -arch arm64 -dynamiclib -framework Foundation -framework UIKit \
//   -framework CoreGraphics -framework CoreData -fobjc-arc \
//   -miphoneos-version-min=14.0 -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
//   -o TikTokHelper.dylib TikTokHelper.m

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>
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
static NSHashTable *gAllConvs; // 弱引用追踪所有 TIMOConversation
static NSManagedObjectContext *gMOC;

// ─── 颜色 ───
static UIColor *rgb(CGFloat r,CGFloat g,CGFloat b,CGFloat a) {
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

// ─── KeyWindow ───
static UIWindow *keyWin(void) {
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes)
        if ([s isKindOfClass:[UIWindowScene class]])
            for (UIWindow *w in ((UIWindowScene*)s).windows) if (w.isKeyWindow) return w;
    for (UIWindow *w in [UIApplication sharedApplication].windows) if (w.isKeyWindow) return w;
    return nil;
}

// ─── HTTP ───
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

// ─── 更新状态 ───
static void setStatus(NSString *s){ dispatch_async(dispatch_get_main_queue(),^{ gStatusLbl.text=s; }); }

// ==================== TIMOConversation 追踪 (Whee 方案) ====================
static IMP gOrigAwakeImp = NULL;

static void tracked_awake(id self, SEL _cmd) {
    if (gOrigAwakeImp) ((void(*)(id,SEL))gOrigAwakeImp)(self,_cmd);
    if (gAllConvs) [gAllConvs addObject:self];
    // 拿到第一个实例后就尝试获取 MOC
    if (!gMOC && [gAllConvs count] > 0) {
        id moc = _msg0(self, @selector(managedObjectContext));
        if (moc) gMOC = moc;
    }
}

static void installConvTracking(void) {
    Class TIMO = NSClassFromString(@"TIMOConversation");
    if (!TIMO) return;
    gAllConvs = [NSHashTable weakObjectsHashTable];

    // Hook awakeFromFetch / awakeFromInsert
    SEL s = @selector(awakeFromFetch);
    Method m = class_getInstanceMethod(TIMO, s);
    if (!m) { s = @selector(awakeFromInsert); m = class_getInstanceMethod(TIMO, s); }
    if (m) {
        gOrigAwakeImp = method_getImplementation(m);
        method_setImplementation(m, (IMP)tracked_awake);
        LOG(@"[DM] TIMOConversation tracking installed");
    }
}

static NSArray *getAllConversations(void) {
    NSMutableArray *r = [NSMutableArray array];
    if (gAllConvs) for (id o in gAllConvs) [r addObject:o];

    if (gMOC) {
        NSFetchRequest *req = [[NSFetchRequest alloc] init];
        NSEntityDescription *e = [NSEntityDescription entityForName:@"TIMOConversation" inManagedObjectContext:gMOC];
        if (e) {
            [req setEntity:e]; [req setIncludesPendingChanges:YES];
            NSArray *f = [gMOC executeFetchRequest:req error:nil];
            if (f) [r addObjectsFromArray:f];
        }
    }
    return r;
}

// ==================== 发消息 ====================
static BOOL sendTextToConv(id conv, NSString *text) {
    Class TC=NSClassFromString(@"AWEIMTextMessageContent");
    Class SM=NSClassFromString(@"AWEIMSendTextMessageModel");
    Class MS=NSClassFromString(@"AWEIMModuleService");
    if(!TC||!SM||!MS||!conv)return NO;
    id c=((id(*)(id,SEL,NSString*))objc_msgSend)([TC alloc],NSSelectorFromString(@"initWithText:"),text);
    id m=((id(*)(id,SEL,id))objc_msgSend)([SM alloc],NSSelectorFromString(@"initWithContent:"),c);
    id sc=_msg0(MS, NSSelectorFromString(@"sendMessageController"));
    SEL ss=NSSelectorFromString(@"sendMessage:conversation:");
    if(![sc respondsToSelector:ss])return NO;
    ((void(*)(id,SEL,id,id))objc_msgSend)(sc,ss,m,conv);
    return YES;
}

// ==================== 创建会话并发送 ====================
- (void)sendDMToUser:(NSString *)uid message:(NSString *)text {
    // 1. 先尝试从 CoreData 找到已有会话
    NSArray *convs = getAllConversations();
    for (id conv in convs) {
        NSString *ident = _msg0(conv, NSSelectorFromString(@"identifier"));
        if (ident && [ident containsString:uid]) {
            if (sendTextToConv(conv, text)) { LOG(@"[DM] Sent via existing conv"); return; }
        }
    }

    // 2. 没有就创建
    Class ConvCls = NSClassFromString(@"AWEIMMessageConversation");
    NSSet *parts = [NSSet setWithObject:uid];
    SEL sel = NSSelectorFromString(@"createConversationWithOtherParticipants:type:inInbox:completion:");
    if (![ConvCls respondsToSelector:sel]) return;

    ((void(*)(id,SEL,NSSet*,NSInteger,NSInteger,void(^)(id,NSError*)))objc_msgSend)
    (ConvCls, sel, parts, 1, 0, ^(id apiConv, NSError *err) {
        if (err || !apiConv) return;
        // 等 CoreData 同步
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC), dispatch_get_global_queue(0,0), ^{
            NSArray *convs2 = getAllConversations();
            for (id c in convs2) {
                NSString *ident = _msg0(c, NSSelectorFromString(@"identifier"));
                if (ident && [ident containsString:uid]) {
                    sendTextToConv(c, text);
                    LOG(@"[DM] Sent after create+sync");
                    return;
                }
            }
        });
    });
}

// ─── DM 轮询 ───
static void pollDM(void) {
    if (!gAutoDM) return;
    NSArray *convs = getAllConversations();
    for (id conv in convs) {
        id last = _msg0(conv, NSSelectorFromString(@"lastMessage"));
        if (!last) continue;
        id sender = _msg0(last, NSSelectorFromString(@"sender"));
        NSNumber *isSelf = _msg0(sender, NSSelectorFromString(@"isSelf"));
        if (isSelf && isSelf.boolValue) continue;
        NSString *mid = [last description];
        if ([gRepliedIDs containsObject:mid]) continue;
        [gRepliedIDs addObject:mid];
        sendTextToConv(conv, @"你好");
        LOG(@"[DM] Auto-replied");
    }
}

// ==================== 界面 ====================
@interface TikTokHelper : NSObject @end
@implementation TikTokHelper

- (UIButton*)makeBtn:(NSString*)t frame:(CGRect)f bg:(UIColor*)bg fs:(CGFloat)fs {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom];
    b.frame=f;b.backgroundColor=bg;b.layer.cornerRadius=10;
    b.layer.borderWidth=2;b.layer.borderColor=[UIColor whiteColor].CGColor;
    b.titleLabel.font=[UIFont boldSystemFontOfSize:fs];
    b.titleLabel.numberOfLines=2;b.titleLabel.textAlignment=NSTextAlignmentCenter;
    [b setTitle:t forState:0];[b setTitleColor:[UIColor whiteColor] forState:0];
    return b;
}

- (void)onToggle {
    gExpanded=!gExpanded;
    [UIView animateWithDuration:.25 animations:^{gPanel.alpha=gExpanded?1:0;}];
    [gToggleBtn setTitle:gExpanded?@"收起":@"展开" forState:0];
}

- (void)onAutoFollow {
    gAutoFollow=!gAutoFollow;
    if(gAutoFollow){
        [gFollowBtn setTitle:@"停止关注" forState:0];gFollowBtn.backgroundColor=rgb(.85,.25,.25,.9);
        setStatus(@"获取用户列表...");
        dispatch_async(dispatch_get_global_queue(0,0),^{
            NSArray *uids=fetchUIDs();
            if(!uids.count){setStatus(@"无用户");gAutoFollow=NO;return;}
            for(NSInteger i=0;i<uids.count&&gAutoFollow;i++){
                dispatch_async(dispatch_get_main_queue(),^{setStatus([NSString stringWithFormat:@"关注 %ld/%lu: %@",(long)(i+1),(unsigned long)uids.count,uids[i]]);});
                Class RS=NSClassFromString(@"AWEUserRelationServiceImpl");
                Class UM=NSClassFromString(@"AWEUserModel");
                Class CC=NSClassFromString(@"AWEUserRelationContext");
                id user=[[UM alloc]init];[user setValue:uids[i] forKey:@"userID"];
                id ctx=[[CC alloc]init];[ctx setValue:user forKey:@"user"];[ctx setValue:@0 forKey:@"fromPageType"];
                SEL fs=NSSelectorFromString(@"follow:completion:");
                ((void(*)(id,SEL,id,void(^)(id)))objc_msgSend)(RS,fs,ctx,^(id r){});
                [NSThread sleepForTimeInterval:.3];
            }
            dispatch_async(dispatch_get_main_queue(),^{
                setStatus([NSString stringWithFormat:@"完成 %lu 人",(unsigned long)uids.count]);
                gAutoFollow=NO;[gFollowBtn setTitle:@"自动关注" forState:0];gFollowBtn.backgroundColor=rgb(.18,.5,.92,.9);
            });
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
    UIViewController *vc=keyWin().rootViewController;
    while(vc.presentedViewController)vc=vc.presentedViewController;
    [vc presentViewController:a animated:YES completion:nil];
}

- (void)buildUI {
    gWin=keyWin();
    if(!gWin){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self buildUI];});return;}
    CGFloat SW=[UIScreen mainScreen].bounds.size.width;

    gToggleBtn=[self makeBtn:@"展开" frame:CGRectMake(SW-95,120,85,48) bg:rgb(.92,.1,.1,.92) fs:18];
    gToggleBtn.layer.cornerRadius=16;[gToggleBtn addTarget:self action:@selector(onToggle) forControlEvents:1<<6];
    [gWin addSubview:gToggleBtn];

    CGFloat pW=175,pH=270;
    gPanel=[[UIView alloc]initWithFrame:CGRectMake(100,70,pW,pH)];
    gPanel.backgroundColor=rgb(1,.85,.02,.95);gPanel.layer.cornerRadius=14;
    gPanel.layer.borderWidth=3;gPanel.layer.borderColor=[UIColor whiteColor].CGColor;gPanel.alpha=0;
    [gWin addSubview:gPanel];

    UILabel *tl=[[UILabel alloc]initWithFrame:CGRectMake(10,8,pW-20,18)];
    tl.text=@"操作面板";tl.textColor=rgb(1,1,1,.6);tl.font=[UIFont systemFontOfSize:13];tl.textAlignment=NSTextAlignmentCenter;
    [gPanel addSubview:tl];

    gStatusLbl=[[UILabel alloc]initWithFrame:CGRectMake(10,pH-38,pW-20,30)];
    gStatusLbl.text=@"就绪";gStatusLbl.textColor=rgb(1,1,1,.7);
    gStatusLbl.font=[UIFont systemFontOfSize:10];gStatusLbl.textAlignment=NSTextAlignmentCenter;gStatusLbl.numberOfLines=2;
    [gPanel addSubview:gStatusLbl];

    CGFloat bX=12,bW=pW-24,bH=50,g=6,sY=30;
    gFollowBtn=[self makeBtn:@"自动关注" frame:CGRectMake(bX,sY,bW,bH) bg:rgb(.18,.5,.92,.9) fs:16];
    [gFollowBtn addTarget:self action:@selector(onAutoFollow) forControlEvents:1<<6];[gPanel addSubview:gFollowBtn];

    gDMBtn=[self makeBtn:@"自动私信" frame:CGRectMake(bX,sY+bH+g,bW,bH) bg:rgb(.15,.72,.35,.9) fs:16];
    [gDMBtn addTarget:self action:@selector(onAutoDM) forControlEvents:1<<6];[gPanel addSubview:gDMBtn];

    gNurtureBtn=[self makeBtn:@"自动养号" frame:CGRectMake(bX,sY+2*(bH+g),bW,bH) bg:rgb(.88,.48,.12,.9) fs:16];
    [gNurtureBtn addTarget:self action:@selector(onNurture) forControlEvents:1<<6];[gPanel addSubview:gNurtureBtn];

    LOG(@"UI 就绪");
}

@end

// ==================== 入口 ====================
__attribute__((constructor)) static void THInit(void) {
    gRepliedIDs=[NSMutableSet set];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        installConvTracking();
        [[[TikTokHelper alloc] init] buildUI];
        // bringToFront 每2秒
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer*t){
            if(gToggleBtn)[gWin bringSubviewToFront:gToggleBtn];
            if(gPanel&&gExpanded)[gWin bringSubviewToFront:gPanel];
        }];
        // DM 轮询 每500ms
        [NSTimer scheduledTimerWithTimeInterval:.5 repeats:YES block:^(NSTimer*t){pollDM();}];
        LOG(@"注入完成");
    });
}
