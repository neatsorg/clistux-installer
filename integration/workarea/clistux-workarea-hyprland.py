#!/usr/bin/env python3
# clistux: Hyprland の作業領域を、X11 の座標で求めて出力する(clistux-workarea.sh から呼ばれる)。
#
# 入力: 標準入力に `hyprctl monitors -j` の出力。
# 出力: _GTK_WORKAREAS_D0 に設定する値(「x, y, 幅, 高さ」をモニターの数だけ並べたもの)。求められなければ何も出さない。
#
# Hyprland の reserved(バーなどが占める幅: 左・上・右・下)は、論理ピクセル(倍率で割った値)で表される。
# 一方、Wine が見るのは XWayland のモニターの位置と大きさ(XRandR)で、倍率や xwayland:force_zero_scaling の設定によって
# 論理ピクセルとは違うことがある。そこで XRandR のモニターをモニター名で突き合わせ、その位置と大きさを基準に、
# reserved を同じ比率で換算する。XRandR が使えないときは、Hyprland の位置と論理ピクセルの大きさを使う
# (xwayland:force_zero_scaling が有効で倍率が 1 でないモニターがあると、X11 の座標と合わないので何も出さない)。
# XRandR は使えるのに名前が合わないモニターがあるときも、どの座標系かわからないので何も出さない。
#
# 引数: xwayland:force_zero_scaling の値(1 なら有効)。
import ctypes
import ctypes.util
import json
import sys


def x11_monitors():
    """XRandR のモニターを {名前: (x, y, 幅, 高さ)} で返す。使えなければ空。"""
    try:
        xlib = ctypes.CDLL(ctypes.util.find_library("X11") or "libX11.so.6")
        xrandr = ctypes.CDLL(ctypes.util.find_library("Xrandr") or "libXrandr.so.2")
    except OSError:
        return {}

    class MonitorInfo(ctypes.Structure):
        _fields_ = [("name", ctypes.c_ulong), ("primary", ctypes.c_int), ("automatic", ctypes.c_int),
                    ("noutput", ctypes.c_int), ("x", ctypes.c_int), ("y", ctypes.c_int),
                    ("width", ctypes.c_int), ("height", ctypes.c_int),
                    ("mwidth", ctypes.c_int), ("mheight", ctypes.c_int),
                    ("outputs", ctypes.POINTER(ctypes.c_ulong))]

    xlib.XOpenDisplay.restype = ctypes.c_void_p
    xlib.XOpenDisplay.argtypes = [ctypes.c_char_p]
    xlib.XDefaultRootWindow.restype = ctypes.c_ulong
    xlib.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
    xlib.XGetAtomName.restype = ctypes.c_void_p
    xlib.XGetAtomName.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
    xlib.XFree.argtypes = [ctypes.c_void_p]
    xlib.XCloseDisplay.argtypes = [ctypes.c_void_p]
    xrandr.XRRGetMonitors.restype = ctypes.POINTER(MonitorInfo)
    xrandr.XRRGetMonitors.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.POINTER(ctypes.c_int)]
    xrandr.XRRFreeMonitors.argtypes = [ctypes.POINTER(MonitorInfo)]

    display = xlib.XOpenDisplay(None)
    if not display:
        return {}
    result = {}
    try:
        count = ctypes.c_int()
        monitors = xrandr.XRRGetMonitors(display, xlib.XDefaultRootWindow(display), 1, ctypes.byref(count))
        if not monitors:
            return {}
        for i in range(count.value):
            m = monitors[i]
            name_ptr = xlib.XGetAtomName(display, m.name)
            if not name_ptr:
                continue
            name = ctypes.string_at(name_ptr).decode(errors="replace")
            xlib.XFree(name_ptr)
            result[name] = (m.x, m.y, m.width, m.height)
        xrandr.XRRFreeMonitors(monitors)
    finally:
        xlib.XCloseDisplay(display)
    return result


def main():
    try:
        monitors = json.load(sys.stdin)
    except ValueError:
        return
    monitors = [m for m in monitors if not m.get("disabled")]
    if not monitors:
        return
    zero_scaling = len(sys.argv) > 1 and sys.argv[1] == "1"
    x11 = x11_monitors()
    use_x11 = bool(x11)
    if use_x11 and not all(m.get("name") in x11 for m in monitors):
        return
    if not use_x11 and zero_scaling and any((m.get("scale") or 1) != 1 for m in monitors):
        return
    # Hyprland の位置で求めるとき: X11 のルートウィンドウの原点はモニター全体の左上なので、
    # Hyprland の位置が負のときに合わせて、いちばん左上を 0, 0 にずらす
    min_x = min(m["x"] for m in monitors)
    min_y = min(m["y"] for m in monitors)
    areas = []
    for m in monitors:
        scale = m.get("scale") or 1
        width, height = m["width"], m["height"]
        # transform が奇数(90°・270°、反転を含む)のときは縦と横が入れ替わる
        if m.get("transform", 0) % 2 == 1:
            width, height = height, width
        logical_w, logical_h = width / scale, height / scale
        left, top, right, bottom = (m.get("reserved") or [0, 0, 0, 0])[:4]

        if use_x11:
            x, y, w, h = x11[m["name"]]
            fx, fy = w / logical_w, h / logical_h
        else:
            x, y, w, h = m["x"] - min_x, m["y"] - min_y, round(logical_w), round(logical_h)
            fx = fy = 1
        areas.append((x + round(left * fx), y + round(top * fy),
                      w - round((left + right) * fx), h - round((top + bottom) * fy)))

    if not areas or any(w <= 0 or h <= 0 for _, _, w, h in areas):
        return
    print(", ".join(str(v) for area in sorted(areas) for v in area))


if __name__ == "__main__":
    main()
