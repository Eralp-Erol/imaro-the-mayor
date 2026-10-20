"""Start the vendored MCP-for-Blender socket server inside this Blender session.

Usage:  Blender [file.blend] --python tools/blender/start_mcp_blender.py

Loads tools/blender/mcp_addon/addon.py by file path, registers it for THIS
process only (nothing is written to Blender's user config, addons folder or
preferences) and starts the TCP server the same way the sidebar's
"Connect to Claude" button does (operator blendermcp.start_server).
Port: env BLENDER_PORT (default 9876), bound to localhost.
"""
import importlib.util
import os
import sys

import bpy

ADDON_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mcp_addon", "addon.py")
MODULE_NAME = "imaro_vendored_blender_mcp"

# Never let the addon self-update (it would overwrite the vendored file).
os.environ.setdefault("BLENDERMCP_NO_UPDATE_CHECK", "1")


def _load_addon():
    spec = importlib.util.spec_from_file_location(MODULE_NAME, ADDON_PATH)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[MODULE_NAME] = mod
    spec.loader.exec_module(mod)
    return mod


if bpy.app.background:
    print("start_mcp_blender: background mode cannot serve MCP (addon refuses); run with a GUI.")
else:
    addon = _load_addon()
    addon.register()
    # Defensive: the startup update check is a network GET and must stay off.
    if bpy.app.timers.is_registered(addon._addon_update_check_on_startup):
        bpy.app.timers.unregister(addon._addon_update_check_on_startup)

    _tries = {"n": 0}

    def _start():
        _tries["n"] += 1
        scene = getattr(bpy.context, "scene", None)
        if scene is None:
            return 0.5 if _tries["n"] < 40 else None
        port = os.environ.get("BLENDER_PORT")
        if port and port.isdigit():
            scene.blendermcp_port = int(port)
        bpy.ops.blendermcp.start_server()
        server = getattr(bpy.types, "blendermcp_server", None)
        if server is None or not server.running:
            return 1.0 if _tries["n"] < 40 else None
        if type(server).__module__ != MODULE_NAME:
            print("start_mcp_blender: WARNING - port is served by a DIFFERENT, separately installed "
                  "addon, not the vendored one. Start Blender with --factory-startup.", flush=True)
        print(f"start_mcp_blender: MCP server listening on {server.host}:{server.port} "
              f"(addon {ADDON_PATH})", flush=True)
        return None

    bpy.app.timers.register(_start, first_interval=1.0)
