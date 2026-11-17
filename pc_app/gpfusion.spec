# -*- mode: python ; coding: utf-8 -*-

import os

# 真机预览用的 headless 仿真器（由 prepare_sim.sh 放进 gpfusion_wizard/bin/）。
# 存在才打包：缺了也能正常出包，只是预览退化为静态图。
_sim_names = ("libsim240", "libsim320", "libsim172")
_sim_suffix = ".dll" if os.name == "nt" else ".so"
_sim_binaries = [
    (f"gpfusion_wizard/bin/{name}{_sim_suffix}", "gpfusion_wizard/bin")
    for name in _sim_names
    if os.path.isfile(f"gpfusion_wizard/bin/{name}{_sim_suffix}")
]
if not _sim_binaries:
    print(f"[spec] 未找到 {', '.join(name + _sim_suffix for name in _sim_names)} —— 真机预览将不可用")

a = Analysis(
    ["main.py"],
    pathex=[],
    binaries=_sim_binaries,
    datas=[],
    hiddenimports=[
        "serial.tools.list_ports",
        "serial.tools.list_ports_posix",
        "serial.tools.list_ports_windows",
        "serial.tools.list_ports_linux",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    # 使用纯 ASCII 名称：Windows 上中文 exe 名可能被安全软件/启动器拦截
    name="GPFusionWizard",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name="GPFusionWizard",
)
