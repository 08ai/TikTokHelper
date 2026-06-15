#!/usr/bin/env python3
"""
build_tiktok_ipa.py — 构建注入 FridaGadget + TikTokHelper.dylib 的 TikTok IPA

流程:
  1. 解压 TikTok IPA
  2. 编译 TikTokHelper.dylib (如果未编译)
  3. 复制 FridaGadget.dylib + FridaGadget.config + loader.js + TikTokHelper.dylib → .app
  4. Patch Mach-O (TikTok 主二进制) 注入 LC_LOAD_DYLIB → FridaGadget.dylib
  5. app 启动 → FridaGadget.dylib 加载 → 读取 FridaGadget.config → 执行 loader.js
  6. loader.js → Module.load("TikTokHelper.dylib") → __attribute__((constructor)) 执行
  7. 重新打包为 IPA

用法:
  python build_tiktok_ipa.py <TikTok.ipa> [--output injected.ipa]
"""
import os
import shutil
import struct
import sys
import tempfile
import zipfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DYLIB_SRC = SCRIPT_DIR / "TikTokHelper.dylib"
DYLIB_NAME = "TikTokHelper.dylib"
GADGET_NAME = "FridaGadget.dylib"
CONFIG_NAME = "FridaGadget.config"
LOADER_NAME = "tt_loader.js"

# FridaGadget.dylib 路径 (多个可能位置)
GADGET_CANDIDATES = [
    SCRIPT_DIR.parent.parent / "frida" / "FridaGadget.dylib",
    SCRIPT_DIR.parent.parent.parent / "frida" / "FridaGadget.dylib",
    SCRIPT_DIR / "FridaGadget.dylib",
]

LC_LOAD_DYLIB = 0xC


def find_gadget():
    for p in GADGET_CANDIDATES:
        if p.exists():
            return p
    raise SystemExit(
        "找不到 FridaGadget.dylib!\n"
        f"已搜索: {[str(p) for p in GADGET_CANDIDATES]}\n"
        "请下载 frida-gadget-ios-arm64.dylib 并放到 frida/ 目录下"
    )


def compile_dylib():
    """如果没有编译好的 dylib，尝试编译"""
    src = SCRIPT_DIR / "TikTokHelper.m"
    if not src.exists():
        raise SystemExit(f"源码不存在: {src}")

    if DYLIB_SRC.exists():
        age = os.path.getmtime(DYLIB_SRC) - os.path.getmtime(str(src))
        if age > 0:
            print(f"  TikTokHelper.dylib 已是最新 ({os.path.getsize(str(DYLIB_SRC))} bytes)")
            return

    print("  编译 TikTokHelper.dylib ...")
    import subprocess
    sdk_path = None
    try:
        sdk_path = subprocess.check_output(
            ["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True
        ).strip()
    except Exception:
        pass

    cmd = [
        "clang", "-arch", "arm64", "-dynamiclib",
        "-framework", "Foundation", "-framework", "UIKit",
        "-fobjc-arc",
        "-miphoneos-version-min=14.0",
        "-o", str(DYLIB_SRC),
        str(src),
    ]
    if sdk_path:
        cmd.extend(["-isysroot", sdk_path])

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  编译失败:\n{result.stderr}")
        raise SystemExit("dylib 编译失败，请检查 Xcode 是否安装")
    print(f"  编译成功: {os.path.getsize(str(DYLIB_SRC))} bytes")


def find_app_dir(payload_dir):
    for item in os.listdir(payload_dir):
        if item.endswith(".app"):
            return os.path.join(payload_dir, item)
    raise SystemExit("No .app found in Payload")


def find_app_binary(app_dir):
    """从 Info.plist 读取 CFBundleExecutable 找到主二进制"""
    import plistlib
    info_plist = os.path.join(app_dir, "Info.plist")
    with open(info_plist, "rb") as f:
        plist = plistlib.load(f)
    binary_name = plist.get("CFBundleExecutable", "")
    binary_path = os.path.join(app_dir, binary_name)
    if os.path.exists(binary_path):
        return binary_path
    raise SystemExit(f"找不到主二进制: {binary_name}")


def patch_macho(binary_path, dylib_path="@executable_path/FridaGadget.dylib"):
    """
    在 arm64 Mach-O 中注入 LC_LOAD_DYLIB。
    使用 zero-padding 注入，支持 FAT 和 thin binary。
    """
    with open(binary_path, "rb") as f:
        data = bytearray(f.read())

    magic = struct.unpack_from("<I", data, 0)[0]

    if magic == 0xFEEDFACF:       # MH_MAGIC_64 (thin arm64)
        return _patch_slice(data, binary_path, dylib_path, False)
    elif magic in (0xCAFEBABE, 0xBEBAFECA):  # FAT binary
        return _patch_fat(data, binary_path, dylib_path)
    else:
        raise SystemExit(f"不支持的 Mach-O magic: 0x{magic:08X}")


def _patch_fat(data, binary_path, dylib_path):
    """处理 FAT/Universal binary，只 patch arm64 slice"""
    endian = "<" if struct.unpack_from(">I", data, 0)[0] == 0xBEBAFECA else ">"
    nfat = struct.unpack_from(endian + "I", data, 4)[0]

    for i in range(nfat):
        off = 8 + i * 20
        cpu, _, arch_off, arch_size, _ = struct.unpack_from(
            endian + "IIIII", data, off
        )
        if cpu == 0x0100000C:  # CPU_TYPE_ARM64
            slice_data = data[arch_off:arch_off + arch_size]
            if _patch_slice_bytes(slice_data, dylib_path):
                data[arch_off:arch_off + arch_size] = slice_data
                bak = binary_path + ".orig"
                if not os.path.exists(bak):
                    shutil.copy2(binary_path, bak)
                with open(binary_path, "wb") as f:
                    f.write(data)
                print(f"    Patched arm64 slice in FAT binary ✓")
                return True
    print("    No arm64 slice found in FAT binary")
    return False


def _patch_slice(data, binary_path, dylib_path, _is_slice=True):
    """Patch thin arm64 binary"""
    if not _patch_slice_bytes(data, dylib_path):
        return False
    bak = binary_path + ".orig"
    if not os.path.exists(bak):
        shutil.copy2(binary_path, bak)
    with open(binary_path, "wb") as f:
        f.write(data)
    print(f"    Patched thin arm64 binary ✓")
    return True


def _patch_slice_bytes(data, dylib_path):
    """在 arm64 slice 中注入 LC_LOAD_DYLIB"""
    ncmds, sizeofcmds = struct.unpack_from("<II", data, 16)

    # 检查是否已经注入
    pos = 32
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, pos)
        if cmd == LC_LOAD_DYLIB:
            path_off = pos + 24
            end = pos + cmdsize
            path_bytes = bytes(data[path_off:end]).rstrip(b"\x00")
            if b"FridaGadget" in path_bytes:
                print("    FridaGadget LC_LOAD_DYLIB 已存在，跳过 patch")
                return False
        pos += cmdsize

    # 构建 LC_LOAD_DYLIB command
    path_bytes = dylib_path.encode() + b"\x00"
    path_padded = path_bytes + b"\x00" * ((8 - len(path_bytes) % 8) % 8)
    cmdsize = 24 + len(path_padded)

    lc = struct.pack("<III", LC_LOAD_DYLIB, cmdsize, 24)
    lc += struct.pack("<III", 2, 0, 0)
    lc += path_padded

    # 找到 zero-padding 位置插入
    insert_off = 32 + sizeofcmds
    existing = data[insert_off:insert_off + cmdsize]
    if any(b != 0 for b in existing):
        # 搜索足够长的零填充区域
        for i in range(insert_off, min(insert_off + 8192, len(data))):
            if all(b == 0 for b in data[i:i + cmdsize]):
                insert_off = i
                break
        else:
            raise SystemExit(
                f"二进制中无足够零填充区域 (需要 {cmdsize} 字节)\n"
                f"二进制太小，尝试: python -c \"import struct; ...\" 手动处理"
            )

    if insert_off + cmdsize > len(data):
        raise SystemExit("注入会溢出 Mach-O 数据")

    data[insert_off:insert_off + cmdsize] = lc
    struct.pack_into("<II", data, 16, ncmds + 1, sizeofcmds + cmdsize)
    print(f"    Injected LC_LOAD_DYLIB: ncmds={ncmds}→{ncmds+1}, sizeofcmds={sizeofcmds}→{sizeofcmds+cmdsize} ✓")
    return True


def main():
    import argparse
    parser = argparse.ArgumentParser(
        description="构建 TikTok + FridaGadget + TikTokHelper.dylib 的注入 IPA"
    )
    parser.add_argument("input_ipa", help="TikTok .ipa 文件路径")
    parser.add_argument("--output", "-o", default=None, help="输出 IPA 路径")
    parser.add_argument("--gadget", "-g", default=None, help="FridaGadget.dylib 路径 (可选)")
    parser.add_argument("--dylib", "-d", default=None, help="TikTokHelper.dylib 路径 (可选)")
    parser.add_argument("--skip-compile", action="store_true", help="跳过 dylib 编译")
    args = parser.parse_args()

    input_ipa = Path(args.input_ipa)
    if not input_ipa.exists():
        raise SystemExit(f"IPA 不存在: {input_ipa}")

    # 确定输出路径
    output_ipa = Path(args.output) if args.output else SCRIPT_DIR / f"TikTok_{input_ipa.stem}_injected.ipa"

    # 查找 FridaGadget
    gadget_src = Path(args.gadget) if args.gadget else find_gadget()
    if not gadget_src.exists():
        raise SystemExit(f"FridaGadget 不存在: {gadget_src}")

    # 查找/编译 dylib
    dylib_src = Path(args.dylib) if args.dylib else DYLIB_SRC
    if not args.skip_compile:
        compile_dylib()
    if not dylib_src.exists():
        raise SystemExit(f"dylib 不存在: {dylib_src}\n请先编译: bash build_dylib.sh")

    print(f"\n{'='*60}")
    print(f"TikTok IPA 注入构建")
    print(f"{'='*60}")
    print(f"输入 IPA:     {input_ipa} ({os.path.getsize(str(input_ipa))/1024/1024:.1f} MB)")
    print(f"输出 IPA:     {output_ipa}")
    print(f"FridaGadget:  {gadget_src} ({os.path.getsize(str(gadget_src))/1024/1024:.1f} MB)")
    print(f"Dylib:        {dylib_src} ({os.path.getsize(str(dylib_src))} bytes)")
    print(f"{'='*60}\n")

    with tempfile.TemporaryDirectory(prefix="tiktok_ipa_") as work:
        # [1/7] 解压 IPA
        print("[1/7] 解压 IPA ...")
        with zipfile.ZipFile(input_ipa, "r") as zf:
            zf.extractall(work)

        app_dir = find_app_dir(os.path.join(work, "Payload"))
        app_name = os.path.basename(app_dir)
        print(f"  App: {app_name}")

        # [2/7] 清理旧注入文件
        print("[2/7] 清理旧注入文件 ...")
        for fn in os.listdir(app_dir):
            if any(k in fn for k in ["FridaGadget", "TikTokHelper", "tt_loader", ".orig"]):
                fp = os.path.join(app_dir, fn)
                if os.path.isfile(fp):
                    os.remove(fp)
                    print(f"  删除: {fn}")
            # 恢复 .orig 备份
            if fn.endswith(".orig"):
                orig = os.path.join(app_dir, fn[:-5])  # remove .orig
                fp = os.path.join(app_dir, fn)
                if os.path.exists(orig):
                    shutil.copy2(fp, orig)
                    os.remove(fp)
                    print(f"  恢复: {orig} ← {fn}")

        # [3/7] 复制 FridaGadget.dylib
        print("[3/7] 复制 FridaGadget.dylib ...")
        gadget_dst = os.path.join(app_dir, GADGET_NAME)
        shutil.copy2(str(gadget_src), gadget_dst)
        print(f"  {GADGET_NAME} → {app_name}/ ({os.path.getsize(gadget_dst)/1024/1024:.1f} MB)")

        # [4/7] 复制 TikTokHelper.dylib
        print("[4/7] 复制 TikTokHelper.dylib ...")
        dylib_dst = os.path.join(app_dir, DYLIB_NAME)
        shutil.copy2(str(dylib_src), dylib_dst)
        print(f"  {DYLIB_NAME} → {app_name}/ ({os.path.getsize(dylib_dst)} bytes)")

        # [5/7] 创建 loader.js (FridaGadget 启动脚本)
        print("[5/7] 创建 tt_loader.js ...")
        loader_js = '''// tt_loader.js — FridaGadget 自动加载 TikTokHelper.dylib
console.log("[TT_LOADER] Starting...");

// 等待 dlopen 可用
const dlopen = Module.findExportByName(null, "dlopen");
const dlerror = Module.findExportByName(null, "dlerror");

if (dlopen && dlerror) {
    const dlopenFunc = new NativeFunction(dlopen, "pointer", ["pointer", "int"]);
    const dlerrorFunc = new NativeFunction(dlerror, "pointer", []);

    // dylib 路径 (和 executable 同目录)
    const RTLD_NOW = 2;
    const paths = [
        "@executable_path/TikTokHelper.dylib",
        "/var/containers/Bundle/Application/*/TikTok.app/TikTokHelper.dylib",
    ];

    let loaded = false;
    for (const p of paths) {
        try {
            const pathPtr = Memory.allocUtf8String(p);
            const handle = dlopenFunc(pathPtr, RTLD_NOW);
            if (!handle.isNull()) {
                console.log("[TT_LOADER] ✓ Loaded: " + p);
                loaded = true;
                break;
            }
        } catch(e) {
            // try next
        }
    }

    if (loaded) {
        console.log("[TT_LOADER] TikTokHelper.dylib loaded successfully!");
    } else {
        // 尝试直接用文件名（已经在 @executable_path 中）
        try {
            const pathPtr = Memory.allocUtf8String("TikTokHelper.dylib");
            const handle = dlopenFunc(pathPtr, RTLD_NOW);
            if (!handle.isNull()) {
                console.log("[TT_LOADER] ✓ Loaded by filename: TikTokHelper.dylib");
                loaded = true;
            }
        } catch(e) {}
    }

    if (!loaded) {
        const err = dlerrorFunc();
        const errMsg = err.isNull() ? "unknown" : err.readUtf8String();
        console.log("[TT_LOADER] ✗ Failed: " + errMsg);
    }
} else {
    console.log("[TT_LOADER] ✗ dlopen/dlerror not found");
}

// 完成后不退出 — FridaGadget 保持运行
console.log("[TT_LOADER] Loader done.");
'''
        loader_dst = os.path.join(app_dir, LOADER_NAME)
        with open(loader_dst, "w") as f:
            f.write(loader_js)
        print(f"  {LOADER_NAME} → {app_name}/ ({os.path.getsize(loader_dst)} bytes)")

        # [6/7] 创建 FridaGadget.config
        print("[6/7] 创建 FridaGadget.config ...")
        config = (
            '{\n'
            '  "interaction": {\n'
            '    "type": "script",\n'
            f'    "path": "./{LOADER_NAME}",\n'
            '    "on_change": "reload"\n'
            '  }\n'
            '}\n'
        )
        config_dst = os.path.join(app_dir, CONFIG_NAME)
        with open(config_dst, "w") as f:
            f.write(config)
        print(f"  {CONFIG_NAME} → {app_name}/")

        # [7/7] Patch Mach-O
        print("[7/7] Patch Mach-O 注入 LC_LOAD_DYLIB ...")
        binary = find_app_binary(app_dir)
        print(f"  主二进制: {os.path.basename(binary)} ({os.path.getsize(binary)} bytes)")

        try:
            patch_macho(binary)
        except SystemExit as e:
            print(f"\n  ⚠ Mach-O patch 失败: {e}")
            print(f"  尝试替代方案: 用 insert_dylib 工具 ...")
            import subprocess
            result = subprocess.run(
                ["insert_dylib", "@executable_path/FridaGadget.dylib", binary,
                 "--all-yes", "--inplace"],
                capture_output=True, text=True
            )
            if result.returncode != 0:
                print(f"  insert_dylib 也失败了: {result.stderr}")
                raise SystemExit("无法注入 LC_LOAD_DYLIB，请手动使用 optool 或 insert_dylib")
            print(f"  insert_dylib 成功 ✓")

        # 打包 IPA
        print(f"\n{'='*60}")
        print("打包 IPA ...")
        if output_ipa.exists():
            output_ipa.unlink()

        with zipfile.ZipFile(str(output_ipa), "w", zipfile.ZIP_DEFLATED) as zf:
            for root, dirs, files in os.walk(work):
                for fn in files:
                    fpath = os.path.join(root, fn)
                    arcname = os.path.relpath(fpath, work)
                    zf.write(fpath, arcname)

        ipa_size = os.path.getsize(str(output_ipa))
        print(f"\n{'='*60}")
        print(f"✓ 完成!")
        print(f"  {output_ipa} ({ipa_size/1024/1024:.1f} MB)")
        print(f"{'='*60}")
        print(f"\n安装方式:")
        print(f"  1. TrollStore: 直接安装 {output_ipa.name}")
        print(f"  2. AltStore/Sideloadly: 侧载 {output_ipa.name}")
        print(f"  3. Xcode: ios-deploy --bundle Payload/TikTok.app")
        print(f"\n启动后 FridaGadget 自动加载 TikTokHelper.dylib")
        print(f"TikTok 界面上会出现'展开'浮动按钮")


if __name__ == "__main__":
    main()
