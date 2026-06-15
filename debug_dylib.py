#!/usr/bin/env python3
"""debug_dylib.py — 连接 TikTok 进程进行 dylib 动态调试

用法:
  python debug_dylib.py             # 连接到 TikTok 并进入交互调试
  python debug_dylib.py --check     # 仅检查 dylib 是否成功加载
  python debug_dylib.py --eval "<JS>" # 执行单条 JS 并退出

前置条件:
  1. TikTok 已安装 (含 FridaGadget + TikTokHelper.dylib)
  2. iPhone 已信任此电脑 (解锁 → 点"信任" → 输入密码)
  3. Apple Mobile Device Service 已启动
"""
import code
import frida
import sys
import time


def on_message(message, data):
    """Frida 消息回调"""
    if message["type"] == "send":
        print(f"[JS] {message['payload']}")
    elif message["type"] == "error":
        print(f"[JS ERROR] {message.get('stack', message.get('description', str(message)))}")
    else:
        print(f"[JS] {message}")


def connect_to_tiktok():
    """连接到 USB 上的 TikTok 进程"""
    try:
        device = frida.get_usb_device()
        print(f"✓ 已连接设备: {device.name}")
    except frida.TransportError:
        print("✗ 找不到 USB 设备! 请检查:")
        print("  1. iPhone 是否已解锁并'信任'此电脑")
        print("  2. Apple Mobile Device Service 是否运行")
        sys.exit(1)

    try:
        # 方式1: 通过进程名
        pid = device.get_process("TikTok").pid
        session = device.attach(pid)
        print(f"✓ 已附加 TikTok (PID: {pid})")
        return session
    except frida.ProcessNotFoundError:
        pass

    # 方式2: 列出所有进程，搜索
    print("搜索 TikTok 进程...")
    for app in device.enumerate_applications():
        if "tiktok" in app.identifier.lower() or "aweme" in app.identifier.lower():
            print(f"  找到: {app.name} ({app.identifier}) PID={app.pid}")
            if app.pid != 0:
                session = device.attach(app.pid)
                print(f"✓ 已附加 (PID: {app.pid})")
                return session

    print("✗ 未找到运行的 TikTok 进程! 请先启动 TikTok")
    sys.exit(1)


def check_dylib(session):
    """检查 TikTokHelper.dylib 是否已加载"""
    script = session.create_script("""
        'use strict';

        // 查找已加载的 dylib
        const modules = Process.enumerateModules();
        const helper = modules.find(m => m.name.toLowerCase().includes('tiktokhelper'));
        const fridaGadget = modules.find(m => m.name.toLowerCase().includes('fridagadget'));

        if (helper) {
            send(`✓ TikTokHelper.dylib 已加载!`);
            send(`  Base: ${helper.base}`);
            send(`  Size: ${helper.size} bytes`);
            send(`  Path: ${helper.path}`);
        } else {
            send(`✗ TikTokHelper.dylib 未加载`);
            send(`  已加载模块数: ${modules.length}`);
        }

        if (fridaGadget) {
            send(`✓ FridaGadget.dylib 已加载`);
        } else {
            send(`✗ FridaGadget.dylib 未加载`);
        }

        // 检查 dylib 的 ObjC 类
        if (ObjC.available) {
            const klass = ObjC.classes.TikTokHelper;
            if (klass) {
                send(`✓ ObjC 类 TikTokHelper 已注册`);
                send(`  方法: ${klass.$ownMethods.join(', ')}`);
            } else {
                send(`✗ ObjC 类 TikTokHelper 未找到`);
            }

            // 检查按钮是否存在
            send('');
            send('=== 检查浮动按钮 ===');
            const wins = ObjC.classes.UIApplication.sharedApplication().keyWindow();
            // 列出 keyWindow 的子视图
            send(`  keyWindow 子视图数: ${wins.subviews().count()}`);
            for (let i = 0; i < Math.min(wins.subviews().count(), 20); i++) {
                const sv = wins.subviews().objectAtIndex_(i);
                send(`  [${i}] ${sv.$className} frame=(${sv.frame().origin.x.toFixed(0)},${sv.frame().origin.y.toFixed(0)},${sv.frame().size.width.toFixed(0)},${sv.frame().size.height.toFixed(0)})`);
            }
        }
    """)
    script.on("message", on_message)
    script.load()
    time.sleep(3)  # 等待脚本执行完成
    script.unload()


def check_ui(session):
    """深度检查 UI 状态"""
    script = session.create_script("""
        'use strict';
        send('=== 深度 UI 检查 ===');

        const app = ObjC.classes.UIApplication.sharedApplication();

        // 枚举所有 window
        send(`Windows 总数: ${app.windows().count()}`);

        // 在每个 window 中搜索 UIButton
        const allWindows = app.windows();
        for (let w = 0; w < allWindows.count(); w++) {
            const win = allWindows.objectAtIndex_(w);
            send(`Window[${w}]: ${win.$className} keyWindow=${win.isKeyWindow()} hidden=${win.isHidden()}`);

            // 递归搜索 UIButton
            function findButtons(view, depth) {
                if (depth > 5) return;
                if (view.$className.includes('UIButton') || view.$className.includes('Button')) {
                    const title = view.currentTitle ? view.currentTitle().toString() : '(no title)';
                    send(`  ${'  '.repeat(depth)}[BTN] ${view.$className} title="${title}" frame=(${view.frame().origin.x.toFixed(1)},${view.frame().origin.y.toFixed(1)},${view.frame().size.width.toFixed(1)},${view.frame().size.height.toFixed(1)}) hidden=${view.isHidden()}`);
                }
                const subs = view.subviews();
                if (subs) {
                    for (let i = 0; i < subs.count(); i++) {
                        findButtons(subs.objectAtIndex_(i), depth + 1);
                    }
                }
            }
            findButtons(win, 0);
        }

        // 检查 NSUserDefaults 中的 gExpanded 状态
        send('');
        send('=== 全局状态 ===');
        // 通过 NSNotification 或自定义方式获取状态
        const defaults = ObjC.classes.NSUserDefaults.standardUserDefaults();
        send(`  gExpanded 状态无法直接从 JS 读取 (C 静态变量)`);

        send('');
        send('=== 可用操作 ===');
        send('  debug_dylib.py --eval "ObjC.classes.TikTokHelper.onExpandTap()"    # 切换展开');
        send('  debug_dylib.py --eval "ObjC.classes.TikTokHelper.onExtra1Tap()"   # 功能1');
        send('  debug_dylib.py --eval "ObjC.classes.TikTokHelper.onExtra2Tap()"   # 功能2');
    """)
    script.on("message", on_message)
    script.load()
    time.sleep(3)
    script.unload()


def interactive_debug(session):
    """交互式调试 REPL"""
    print()
    print("=" * 60)
    print("TikTokHelper dylib 交互式调试")
    print("=" * 60)
    print("快捷命令:")
    print("  check()     — 检查 dylib 状态")
    print("  ui()        — 检查 UI 状态")
    print("  eval(js)    — 执行 Frida JS 代码")
    print("  toggle()    — 切换展开/收起")
    print("  q           — 退出")
    print("=" * 60)
    print()

    def check():
        check_dylib(session)

    def ui():
        check_ui(session)

    def do_eval(js):
        script = session.create_script(js)
        script.on("message", on_message)
        script.load()
        time.sleep(1)
        script.unload()

    def toggle():
        do_eval("ObjC.classes.TikTokHelper.onExpandTap(); send('已切换');")

    namespace = {
        "session": session,
        "check": check,
        "ui": ui,
        "eval": do_eval,
        "toggle": toggle,
        "q": lambda: sys.exit(0),
    }

    # 先执行一次检查
    check_dylib(session)

    # 进入交互 REPL
    code.interact(
        banner="输入 check() 查看状态, ui() 检查UI, toggle() 切换展开",
        local=namespace,
    )


def main():
    import argparse
    parser = argparse.ArgumentParser(description="TikTok dylib 调试工具")
    parser.add_argument("--check", action="store_true", help="仅检查 dylib 状态")
    parser.add_argument("--ui", action="store_true", help="深度检查 UI 状态")
    parser.add_argument("--eval", type=str, help="执行 JS 代码后退出")
    parser.add_argument("--toggle", action="store_true", help="切换展开/收起")
    args = parser.parse_args()

    try:
        session = connect_to_tiktok()
    except Exception as e:
        print(f"连接失败: {e}")
        sys.exit(1)

    try:
        if args.check:
            check_dylib(session)
        elif args.ui:
            check_ui(session)
        elif args.toggle:
            script = session.create_script("ObjC.classes.TikTokHelper.onExpandTap(); send('已切换');")
            script.on("message", on_message)
            script.load()
            time.sleep(1)
            script.unload()
        elif args.eval:
            script = session.create_script(args.eval)
            script.on("message", on_message)
            script.load()
            time.sleep(1)
            script.unload()
        else:
            interactive_debug(session)
    finally:
        session.detach()


if __name__ == "__main__":
    main()
