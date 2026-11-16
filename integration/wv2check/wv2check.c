/*
 * wv2check: 指定した WebView2 ランタイムが、この Wine で動くかを確かめる。
 *
 *   wv2check.exe <ランタイムのフォルダ> [秒]
 *
 * ランタイムのフォルダ(msedgewebview2.exe のあるフォルダ)を使って WebView2 を作り、短いページを1枚表示する。
 * 表示が終わったら 0 を返す。うまくいかないときは、次の値を返す。
 *   1  WebView2Loader.dll やランタイムが見つからない、環境を作れない
 *   2  時間切れ(既定は 60 秒)
 *   3  表示に失敗した
 *   4  ブラウザのプロセスが異常終了した
 * ウィンドウは画面に出さない。WebView2Loader.dll は、この exe と同じフォルダから読み込む。
 *
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */

#define COBJMACROS
#define CINTERFACE
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>
#include <windows.h>
#include <objbase.h>
#include "WebView2.h"

#ifndef ARRAY_SIZE
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#endif

#include <initguid.h>
DEFINE_GUID(IID_EnvCompleted,  0x4e8a3389, 0xc9d8, 0x4bd2, 0xb6, 0xb5, 0x12, 0x4f, 0xee, 0x6c, 0xc1, 0x4d);
DEFINE_GUID(IID_CtrlCompleted, 0x6c4819f3, 0xc9b7, 0x4260, 0x81, 0x27, 0xc9, 0xf5, 0xbd, 0xe7, 0xf6, 0x8c);
DEFINE_GUID(IID_NavCompleted,  0xd33a35bf, 0x1c49, 0x4f98, 0x93, 0xab, 0x00, 0x6e, 0x05, 0x33, 0xfe, 0x1c);
DEFINE_GUID(IID_ProcFailed,    0x79e0aea4, 0x990b, 0x42d9, 0xaa, 0x1d, 0x0f, 0xcc, 0x2e, 0x5b, 0xc7, 0xf1);

typedef HRESULT (STDAPICALLTYPE *create_env_fn)(PCWSTR, PCWSTR, ICoreWebView2EnvironmentOptions *,
        ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *);
typedef HRESULT (STDAPICALLTYPE *get_version_fn)(PCWSTR, LPWSTR *);

enum { RESULT_OK = 0, RESULT_SETUP = 1, RESULT_TIMEOUT = 2, RESULT_NAVIGATION = 3, RESULT_PROCESS = 4 };

static HWND window;
static ICoreWebView2Controller *controller;

static void report(const char *fmt, ...)
{
    va_list args;

    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    putchar('\n');
    fflush(stdout);
}

static void finish(int result)
{
    PostQuitMessage(result);
}

/* ---- 完了を受け取る COM のオブジェクト(どのハンドラーも Invoke(HRESULT, IUnknown *) の形) ---- */

struct handler;
typedef void (*handler_cb)(HRESULT hr, IUnknown *result);
struct handler_vtbl
{
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(struct handler *, REFIID, void **);
    ULONG (STDMETHODCALLTYPE *AddRef)(struct handler *);
    ULONG (STDMETHODCALLTYPE *Release)(struct handler *);
    HRESULT (STDMETHODCALLTYPE *Invoke)(struct handler *, HRESULT, IUnknown *);
};
struct handler
{
    const struct handler_vtbl *vtbl;
    LONG refcount;
    const IID *iid;
    handler_cb cb;
};

static HRESULT STDMETHODCALLTYPE handler_QueryInterface(struct handler *h, REFIID iid, void **out)
{
    if (IsEqualGUID(iid, &IID_IUnknown) || IsEqualGUID(iid, h->iid))
    {
        InterlockedIncrement(&h->refcount);
        *out = h;
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}
static ULONG STDMETHODCALLTYPE handler_AddRef(struct handler *h) { return InterlockedIncrement(&h->refcount); }
static ULONG STDMETHODCALLTYPE handler_Release(struct handler *h) { return InterlockedDecrement(&h->refcount); }
static HRESULT STDMETHODCALLTYPE handler_Invoke(struct handler *h, HRESULT hr, IUnknown *result)
{
    h->cb(hr, result);
    return S_OK;
}
static const struct handler_vtbl handler_vtbl =
{
    handler_QueryInterface, handler_AddRef, handler_Release, handler_Invoke,
};

static void *handler_new(const IID *iid, handler_cb cb)
{
    struct handler *h = calloc(1, sizeof(*h));

    h->vtbl = &handler_vtbl;
    h->refcount = 1;   /* 終わるまで解放しない */
    h->iid = iid;
    h->cb = cb;
    return h;
}

/* ---- 各段階 ---- */

static void on_navigation_completed(HRESULT hr, IUnknown *args)
{
    BOOL success = FALSE;
    COREWEBVIEW2_WEB_ERROR_STATUS status = 0;

    ICoreWebView2NavigationCompletedEventArgs_get_IsSuccess((ICoreWebView2NavigationCompletedEventArgs *)args, &success);
    ICoreWebView2NavigationCompletedEventArgs_get_WebErrorStatus((ICoreWebView2NavigationCompletedEventArgs *)args, &status);
    report("navigation completed: success %d, web error status %d", success, status);
    finish(success ? RESULT_OK : RESULT_NAVIGATION);
}

static void on_process_failed(HRESULT hr, IUnknown *args)
{
    COREWEBVIEW2_PROCESS_FAILED_KIND kind = 0;

    ICoreWebView2ProcessFailedEventArgs_get_ProcessFailedKind((ICoreWebView2ProcessFailedEventArgs *)args, &kind);
    report("browser process failed: kind %d", kind);
    finish(RESULT_PROCESS);
}

static void on_controller_created(HRESULT hr, IUnknown *result)
{
    static const WCHAR html[] = L"<html><body>wv2check</body></html>";
    ICoreWebView2 *webview = NULL;
    EventRegistrationToken token;
    RECT rect = { 0, 0, 320, 240 };

    if (FAILED(hr) || !result)
    {
        report("controller failed: hr %#lx", hr);
        finish(RESULT_SETUP);
        return;
    }
    controller = (ICoreWebView2Controller *)result;
    ICoreWebView2Controller_AddRef(controller);
    ICoreWebView2Controller_put_Bounds(controller, rect);
    ICoreWebView2Controller_put_IsVisible(controller, TRUE);
    if (FAILED(hr = ICoreWebView2Controller_get_CoreWebView2(controller, &webview)) || !webview)
    {
        report("get_CoreWebView2 failed: hr %#lx", hr);
        finish(RESULT_SETUP);
        return;
    }
    ICoreWebView2_add_NavigationCompleted(webview, handler_new(&IID_NavCompleted, on_navigation_completed), &token);
    ICoreWebView2_add_ProcessFailed(webview, handler_new(&IID_ProcFailed, on_process_failed), &token);
    if (FAILED(hr = ICoreWebView2_NavigateToString(webview, html)))
    {
        report("NavigateToString failed: hr %#lx", hr);
        finish(RESULT_NAVIGATION);
    }
}

static void on_environment_created(HRESULT hr, IUnknown *result)
{
    ICoreWebView2Environment *env = (ICoreWebView2Environment *)result;

    if (FAILED(hr) || !env)
    {
        report("environment failed: hr %#lx", hr);
        finish(RESULT_SETUP);
        return;
    }
    hr = ICoreWebView2Environment_CreateCoreWebView2Controller(env, window,
            handler_new(&IID_CtrlCompleted, on_controller_created));
    if (FAILED(hr))
    {
        report("CreateCoreWebView2Controller failed: hr %#lx", hr);
        finish(RESULT_SETUP);
    }
}

static LRESULT CALLBACK wndproc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam)
{
    if (msg == WM_TIMER)
    {
        report("timeout");
        finish(RESULT_TIMEOUT);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wparam, lparam);
}

int wmain(int argc, WCHAR **argv)
{
    WCHAR loader_path[MAX_PATH], user_data[MAX_PATH], *p;
    WNDCLASSW wc = {0};
    get_version_fn get_version;
    create_env_fn create_env;
    LPWSTR version = NULL;
    unsigned int seconds = 60;
    HMODULE loader;
    HRESULT hr;
    MSG msg;

    if (argc < 2)
    {
        report("usage: wv2check.exe <runtime folder> [seconds]");
        return RESULT_SETUP;
    }
    if (argc > 2) seconds = _wtoi(argv[2]);
    CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);

    GetModuleFileNameW(NULL, loader_path, ARRAY_SIZE(loader_path));
    if ((p = wcsrchr(loader_path, '\\'))) *p = 0;
    wcscat(loader_path, L"\\WebView2Loader.dll");
    if (!(loader = LoadLibraryW(loader_path)))
    {
        report("cannot load WebView2Loader.dll: error %lu", GetLastError());
        return RESULT_SETUP;
    }
    get_version = (get_version_fn)GetProcAddress(loader, "GetAvailableCoreWebView2BrowserVersionString");
    create_env = (create_env_fn)GetProcAddress(loader, "CreateCoreWebView2EnvironmentWithOptions");
    if (!get_version || !create_env)
    {
        report("WebView2Loader.dll lacks the expected functions");
        return RESULT_SETUP;
    }
    hr = get_version(argv[1], &version);
    if (FAILED(hr) || !version)
    {
        report("no runtime in %ls: hr %#lx", argv[1], hr);
        return RESULT_SETUP;
    }
    report("runtime version %ls", version);

    wc.lpfnWndProc = wndproc;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.lpszClassName = L"wv2check";
    RegisterClassW(&wc);
    /* 画面には出さない(表示しないウィンドウの中でも、WebView2 はページを読み込む) */
    window = CreateWindowExW(WS_EX_TOOLWINDOW, L"wv2check", L"wv2check", WS_POPUP,
            0, 0, 320, 240, NULL, NULL, wc.hInstance, NULL);
    SetTimer(window, 1, seconds * 1000, NULL);

    /* 利用者のデータは一時フォルダに分ける(CSP のデータに触れない) */
    GetTempPathW(ARRAY_SIZE(user_data), user_data);
    wcscat(user_data, L"clistux-wv2check");
    hr = create_env(argv[1], user_data, NULL, handler_new(&IID_EnvCompleted, on_environment_created));
    if (FAILED(hr))
    {
        report("CreateCoreWebView2EnvironmentWithOptions failed: hr %#lx", hr);
        return RESULT_SETUP;
    }

    while (GetMessageW(&msg, NULL, 0, 0) > 0)
    {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    report("result %d", (int)msg.wParam);
    return (int)msg.wParam;
}
