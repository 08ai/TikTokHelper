// debug_probe.js — TikTok 动态调试探测脚本
// 用法: frida -U -l debug_probe.js -f com.ss.iphone.ugc.Ame --no-pause

console.log("[PROBE] Starting...");

// 轮询等待 ObjC 运行时初始化
var attempts = 0;
var maxAttempts = 30; // 最多等 15 秒

function waitForObjC() {
    attempts++;
    if (ObjC.available) {
        console.log("[PROBE] ObjC runtime available (after " + (attempts * 500) + "ms)");
        runProbe();
    } else if (attempts < maxAttempts) {
        setTimeout(waitForObjC, 500);
    } else {
        console.log("[PROBE] ERROR: ObjC not available after " + (maxAttempts * 500) + "ms");
        console.log("[PROBE] Check frida-server version on device");
    }
}

function runProbe() {
    console.log("[PROBE] ========================================");
    console.log("[PROBE] TikTok Debug Probe");
    console.log("[PROBE] ========================================");

    var app = ObjC.classes.UIApplication.sharedApplication();
    console.log("[PROBE] App: " + app.$className);

    // keyWindow
    var keyWindow = app.keyWindow();
    if (!keyWindow) {
        var wins = app.windows();
        for (var i = 0; i < wins.count(); i++) {
            var w = wins.objectAtIndex_(i);
            if (w.isKeyWindow()) { keyWindow = w; break; }
        }
    }

    if (keyWindow) {
        console.log("[PROBE] keyWindow: " + keyWindow.$className);
        var subs = keyWindow.subviews();
        console.log("[PROBE] subviews count: " + subs.count());

        // 列出前15个子视图
        for (var i = 0; i < Math.min(15, subs.count()); i++) {
            var sv = subs.objectAtIndex_(i);
            var f = sv.frame();
            console.log("[PROBE] [" + i + "] " + sv.$className +
                " frame=(" + Math.round(f.origin.x) + "," + Math.round(f.origin.y) +
                "," + Math.round(f.size.width) + "," + Math.round(f.size.height) + ")" +
                " hidden=" + sv.isHidden());
        }
    }

    // 关键 ObjC 类
    var allClasses = Object.keys(ObjC.classes);
    console.log("[PROBE] Total ObjC classes: " + allClasses.length);

    // 搜索前缀
    var prefixes = ["TikTokCore", "AWEUI", "TTPlayer", "TTVideo",
                    "HTSLive", "IESLive", "DanceUI", "TikTokShop"];
    for (var k = 0; k < prefixes.length; k++) {
        var kw = prefixes[k];
        var matches = allClasses.filter(function(c) { return c.indexOf(kw) === 0; });
        console.log("[PROBE] '" + kw + "': " + matches.length + " classes");
        if (matches.length > 0 && matches.length <= 5) {
            console.log("[PROBE]    " + matches.join(", "));
        }
    }

    // 模块
    var mods = Process.enumerateModules();
    console.log("[PROBE] Total modules: " + mods.length);

    // TikTok 相关模块
    for (var i = 0; i < mods.length; i++) {
        var m = mods[i];
        var name = m.name.toLowerCase();
        if (name.indexOf("tiktok") !== -1 || name.indexOf("tik") !== -1) {
            console.log("[PROBE] MODULE: " + m.name +
                " base=" + m.base + " size=" + (m.size / 1024 / 1024).toFixed(1) + "MB");
        }
    }

    console.log("[PROBE] ========================================");
    console.log("[PROBE] Probe complete!");
}

// 启动轮询
setTimeout(waitForObjC, 500);
