// inject.js — Frida 注入脚本
// 用法: frida -U -l inject.js TikTok
// 将 dylib 加载到目标进程

const DYLIB_NAME = "TikTokHelper.dylib";

// ---------- 方式1: 通过 dlopen 加载 dylib ----------
function loadDylib(path) {
    const dlopen = new NativeFunction(Module.findExportByName(null, "dlopen"), "pointer", ["pointer", "int"]);
    const dlerror = new NativeFunction(Module.findExportByName(null, "dlerror"), "pointer", []);

    const pathPtr = Memory.allocUtf8String(path);
    const RTLD_NOW = 2;
    const RTLD_GLOBAL = 8;

    const handle = dlopen(pathPtr, RTLD_NOW | RTLD_GLOBAL);
    if (handle.isNull()) {
        const err = dlerror();
        console.log("[-] dlopen 失败: " + (err.isNull() ? "未知错误" : err.readUtf8String()));
        return false;
    }
    console.log("[+] dylib 已加载: " + path);
    return true;
}

// ---------- 主入口 ----------
console.log("[*] TikTokHelper Injector");
console.log("[*] 正在加载 dylib...");

// 尝试多个可能的路径
const paths = [
    "/var/root/" + DYLIB_NAME,                     // root 目录
    "/var/mobile/" + DYLIB_NAME,                    // mobile 目录
    "/Library/MobileSubstrate/DynamicLibraries/" + DYLIB_NAME,
    "/var/containers/Bundle/Application/" + DYLIB_NAME,
];

let loaded = false;
for (const p of paths) {
    try {
        const f = new File(p, "r");
        f.close();
        loaded = loadDylib(p);
        if (loaded) break;
    } catch (e) {
        // 文件不存在，继续尝试
    }
}

if (!loaded) {
    console.log("[-] 未找到 dylib 文件，请先 push 到设备:");
    console.log("    adb push TikTokHelper.dylib /var/root/");
}
