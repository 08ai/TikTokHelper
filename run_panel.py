#!/usr/bin/env python3
"""
run_panel.py — 持久化运行 TikTok 操作面板
保持 Frida 连接不中断，按钮一直可用
Ctrl+C 退出

用法: python run_panel.py
"""
import frida, sys, io, time, codecs
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

import os
SCRIPT_PATH = os.path.join(os.path.dirname(__file__), 'tiktok_panel.js')

with codecs.open(SCRIPT_PATH, 'r', 'utf-8') as f:
    js_code = f.read()

device = frida.get_usb_device()
print(f'Device: {device.name}')

# Kill existing instance
try:
    device.kill('com.ss.iphone.ugc.Ame')
    time.sleep(1)
except: pass

pid = device.spawn(['com.ss.iphone.ugc.Ame'])
session = device.attach(pid)
print(f'Spawned TikTok (PID: {pid})')

script = session.create_script(js_code)

def on_message(msg, data):
    if msg['type'] == 'send':
        print(f'  {msg["payload"]}')
    elif msg['type'] == 'error':
        print(f'  ERR: {msg.get("description", "")[:200]}')

script.on('message', on_message)
script.load()
device.resume(pid)

print()
print('=' * 50)
print('  TikTok 操作面板已启动!')
print('  红色按钮 → 点击展开面板')
print('  Ctrl+C 退出')
print('=' * 50)
print()

# Keep running until Ctrl+C
print('按 Enter 退出...')
try:
    input()
except (KeyboardInterrupt, EOFError):
    pass

print('\n正在退出...')
session.detach()
print('Done.')
