/*
 * wv2probe: WebView2 だけを Wine で動かし、初期化のどの段階まで進むかを記録する試験プログラム。
 *
 *   wv2probe.exe hwnd [秒] [sta|mta|none]          通常の Controller(ウィンドウに直接表示)
 *   wv2probe.exe composition [秒] [sta|mta|none]   CompositionController(DirectComposition のビジュアルに載せる)
 *
 * 各段階で、API の即時の戻り値と、非同期の完了コールバックの HRESULT を時刻付きで標準出力に書く。
 * 時間切れになったら、そのときの段階を書いて終わる。表示には NavigateToString を使い、通信と認証を切り離す。
 * WebView2Loader.dll は、この exe と同じフォルダーから読み込む(WebView2 SDK 1.0.3179.45、BSD ライセンス)。
 *
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */

#define COBJMACROS
#define CINTERFACE
#include <stdarg.h>
#include <stdio.h>
#include <windows.h>
#include <objbase.h>
#include <dcomp.h>
#include "WebView2.h"

#ifndef ARRAY_SIZE
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#endif

/* Define only the IDs this program uses here; the rest come from uuid.lib. */
#include <initguid.h>
DEFINE_GUID(IID_IDCompositionDesktopDevice, 0x5f4633fe, 0x1e08, 0x4cb8, 0x8c, 0x75, 0xce, 0x24, 0x33, 0x3f, 0x56, 0x02);
DEFINE_GUID(IID_EnvCompleted,   0x4e8a3389, 0xc9d8, 0x4bd2, 0xb6, 0xb5, 0x12, 0x4f, 0xee, 0x6c, 0xc1, 0x4d);
DEFINE_GUID(IID_CtrlCompleted,  0x6c4819f3, 0xc9b7, 0x4260, 0x81, 0x27, 0xc9, 0xf5, 0xbd, 0xe7, 0xf6, 0x8c);
DEFINE_GUID(IID_CompCompleted,  0x02fab84b, 0x1428, 0x4fb7, 0xad, 0x45, 0x1b, 0x2e, 0x64, 0x73, 0x61, 0x84);
DEFINE_GUID(IID_Environment3,   0x80a22ae3, 0xbe7c, 0x4ce2, 0xaf, 0xe1, 0x5a, 0x50, 0x05, 0x6c, 0xde, 0xeb);
DEFINE_GUID(IID_NavCompleted,   0xd33a35bf, 0x1c49, 0x4f98, 0x93, 0xab, 0x00, 0x6e, 0x05, 0x33, 0xfe, 0x1c);
DEFINE_GUID(IID_ProcFailed,     0x79e0aea4, 0x990b, 0x42d9, 0xaa, 0x1d, 0x0f, 0xcc, 0x2e, 0x5b, 0xc7, 0xf1);
DEFINE_GUID(IID_Controller,     0x4d00c0d1, 0x9434, 0x4eb6, 0x80, 0x78, 0x86, 0x97, 0xa5, 0x60, 0x33, 0x4f);

typedef HRESULT (STDAPICALLTYPE *create_env_fn)(PCWSTR, PCWSTR, ICoreWebView2EnvironmentOptions *,
        ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *);
typedef HRESULT (STDAPICALLTYPE *get_version_fn)(PCWSTR, LPWSTR *);

static ULONGLONG start_tick;
static const char *stage = "start";
static BOOL composition_mode;
static HWND main_window;
static IDCompositionDesktopDevice *dcomp_device;
static IDCompositionTarget *dcomp_target;
static IDCompositionVisual2 *dcomp_root;
static ICoreWebView2Controller *controller;

static void logf_(const char *fmt, ...)
{
    va_list args;

    printf("[%6llu ms] ", GetTickCount64() - start_tick);
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    printf("\n");
    fflush(stdout);
}

static void set_stage(const char *name)
{
    stage = name;
    logf_("stage: %s", name);
}

/* ---- 汎用の完了ハンドラー: Invoke(this, HRESULT, IUnknown *) の形をした COM オブジェクト ---- */

struct handler;
typedef void (*handler_cb)(struct handler *, HRESULT, IUnknown *);

struct handler
{
    const void *vtbl;
    LONG refcount;
    const IID *iid;
    handler_cb cb;
};

struct handler_vtbl
{
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(struct handler *, REFIID, void **);
    ULONG (STDMETHODCALLTYPE *AddRef)(struct handler *);
    ULONG (STDMETHODCALLTYPE *Release)(struct handler *);
    HRESULT (STDMETHODCALLTYPE *Invoke)(struct handler *, HRESULT, IUnknown *);
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
    h->cb(h, hr, result);
    return S_OK;
}

static const struct handler_vtbl handler_vtbl =
{
    handler_QueryInterface, handler_AddRef, handler_Release, handler_Invoke,
};

static struct handler *handler_new(const IID *iid, handler_cb cb)
{
    struct handler *h = calloc(1, sizeof(*h));

    h->vtbl = &handler_vtbl;
    h->refcount = 1; /* 試験プログラムが終わるまで解放しない */
    h->iid = iid;
    h->cb = cb;
    return h;
}

/* ---- 各段階 ---- */

static void on_navigation_completed(struct handler *h, HRESULT hr, IUnknown *args)
{
    BOOL success = FALSE;
    COREWEBVIEW2_WEB_ERROR_STATUS status = 0;

    ICoreWebView2NavigationCompletedEventArgs_get_IsSuccess((ICoreWebView2NavigationCompletedEventArgs *)args, &success);
    ICoreWebView2NavigationCompletedEventArgs_get_WebErrorStatus((ICoreWebView2NavigationCompletedEventArgs *)args, &status);
    set_stage("navigation completed");
    logf_("NavigationCompleted: success %d, web error status %d", success, status);
}

static void on_process_failed(struct handler *h, HRESULT hr, IUnknown *args)
{
    COREWEBVIEW2_PROCESS_FAILED_KIND kind = 0;

    ICoreWebView2ProcessFailedEventArgs_get_ProcessFailedKind((ICoreWebView2ProcessFailedEventArgs *)args, &kind);
    logf_("ProcessFailed: kind %d", kind);
}

static void start_navigation(void)
{
    static const WCHAR html[] = L"<html><body style='margin:0;background:#1d8a5a;color:#fff;"
            L"font:48px sans-serif;display:flex;align-items:center;justify-content:center;height:100vh'>"
            L"WebView2 OK</body></html>";
    ICoreWebView2 *webview = NULL;
    EventRegistrationToken token;
    RECT rect;
    HRESULT hr;

    GetClientRect(main_window, &rect);
    hr = ICoreWebView2Controller_put_Bounds(controller, rect);
    logf_("put_Bounds (%ld,%ld)-(%ld,%ld): hr %#lx", rect.left, rect.top, rect.right, rect.bottom, hr);
    hr = ICoreWebView2Controller_put_IsVisible(controller, TRUE);
    logf_("put_IsVisible: hr %#lx", hr);
    hr = ICoreWebView2Controller_get_CoreWebView2(controller, &webview);
    logf_("get_CoreWebView2: hr %#lx, webview %p", hr, webview);
    if (FAILED(hr) || !webview)
        return;

    ICoreWebView2_add_NavigationCompleted(webview,
            (ICoreWebView2NavigationCompletedEventHandler *)handler_new(&IID_NavCompleted, on_navigation_completed), &token);
    ICoreWebView2_add_ProcessFailed(webview,
            (ICoreWebView2ProcessFailedEventHandler *)handler_new(&IID_ProcFailed, on_process_failed), &token);

    set_stage("navigating");
    hr = ICoreWebView2_NavigateToString(webview, html);
    logf_("NavigateToString: hr %#lx", hr);
}

static void on_controller_created(struct handler *h, HRESULT hr, IUnknown *result)
{
    logf_("CreateCoreWebView2Controller completed: hr %#lx, controller %p", hr, result);
    if (FAILED(hr) || !result)
    {
        set_stage("controller failed");
        return;
    }
    set_stage("controller created");
    controller = (ICoreWebView2Controller *)result;
    ICoreWebView2Controller_AddRef(controller);
    start_navigation();
}

static void on_composition_controller_created(struct handler *h, HRESULT hr, IUnknown *result)
{
    ICoreWebView2CompositionController *comp = (ICoreWebView2CompositionController *)result;

    logf_("CreateCoreWebView2CompositionController completed: hr %#lx, controller %p", hr, result);
    if (FAILED(hr) || !result)
    {
        set_stage("composition controller failed");
        return;
    }
    set_stage("composition controller created");

    set_stage("attach root visual");
    hr = ICoreWebView2CompositionController_put_RootVisualTarget(comp, (IUnknown *)dcomp_root);
    logf_("put_RootVisualTarget(visual %p): hr %#lx", dcomp_root, hr);
    hr = IDCompositionDesktopDevice_Commit(dcomp_device);
    logf_("IDCompositionDevice::Commit: hr %#lx", hr);

    hr = IUnknown_QueryInterface(result, &IID_Controller, (void **)&controller);
    logf_("QueryInterface(ICoreWebView2Controller): hr %#lx", hr);
    if (SUCCEEDED(hr))
        start_navigation();
}

static void setup_dcomp(void)
{

    HRESULT (WINAPI *create_device2)(IUnknown *, REFIID, void **);
    HRESULT hr;

    set_stage("dcomp setup");
    create_device2 = (void *)GetProcAddress(LoadLibraryW(L"dcomp.dll"), "DCompositionCreateDevice2");
    if (!create_device2)
    {
        logf_("dcomp.dll: DCompositionCreateDevice2 not found");
        return;
    }
    hr = create_device2(NULL, &IID_IDCompositionDesktopDevice, (void **)&dcomp_device);
    logf_("DCompositionCreateDevice2: hr %#lx, device %p", hr, dcomp_device);
    if (FAILED(hr)) return;
    hr = IDCompositionDesktopDevice_CreateTargetForHwnd(dcomp_device, main_window, TRUE, &dcomp_target);
    logf_("CreateTargetForHwnd: hr %#lx", hr);
    hr = IDCompositionDesktopDevice_CreateVisual(dcomp_device, &dcomp_root);
    logf_("CreateVisual: hr %#lx", hr);
    if (dcomp_target && dcomp_root)
    {
        hr = IDCompositionTarget_SetRoot(dcomp_target, (IDCompositionVisual *)dcomp_root);
        logf_("SetRoot: hr %#lx", hr);
    }
    hr = IDCompositionDesktopDevice_Commit(dcomp_device);
    logf_("Commit: hr %#lx", hr);
}

static void on_environment_created(struct handler *h, HRESULT hr, IUnknown *result)
{
    ICoreWebView2Environment *env = (ICoreWebView2Environment *)result;
    ICoreWebView2Environment3 *env3;

    logf_("CreateCoreWebView2EnvironmentWithOptions completed: hr %#lx, environment %p", hr, result);
    if (FAILED(hr) || !result)
    {
        set_stage("environment failed");
        return;
    }
    set_stage("environment created");
    {
        /* Environment のメソッド表の各関数の位置を、WebView2 の DLL の先頭からの差で書き出す(デバッガ用) */
        void **vtbl = *(void ***)env;
        HMODULE module = NULL;
        unsigned int i;

        GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                (LPCWSTR)vtbl[3], &module);
        logf_("environment vtable %p, module %p", vtbl, module);
        for (i = 0; i < 24; ++i)
            logf_("  vtbl[%2u] = %p (module + %#llx)", i, vtbl[i],
                    (unsigned long long)((char *)vtbl[i] - (char *)module));
    }

    {
        /* デバッガで確かめるために、Controller の作成の前で待てるようにする(環境変数 WV2PROBE_DELAY_MS) */
        char delay[16];

        if (GetEnvironmentVariableA("WV2PROBE_DELAY_MS", delay, sizeof(delay)))
        {
            set_stage("delay before controller");
            Sleep(atoi(delay));
        }
    }

    if (!composition_mode)
    {
        set_stage("creating controller");
        hr = ICoreWebView2Environment_CreateCoreWebView2Controller(env, main_window,
                (ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *)handler_new(&IID_CtrlCompleted,
                on_controller_created));
        logf_("CreateCoreWebView2Controller: immediate hr %#lx", hr);
        return;
    }

    setup_dcomp();
    hr = ICoreWebView2Environment_QueryInterface(env, &IID_Environment3, (void **)&env3);
    logf_("QueryInterface(ICoreWebView2Environment3): hr %#lx", hr);
    if (FAILED(hr)) return;
    set_stage("creating composition controller");
    hr = ICoreWebView2Environment3_CreateCoreWebView2CompositionController(env3, main_window,
            (ICoreWebView2CreateCoreWebView2CompositionControllerCompletedHandler *)handler_new(&IID_CompCompleted,
            on_composition_controller_created));
    logf_("CreateCoreWebView2CompositionController: immediate hr %#lx", hr);
}

static LRESULT CALLBACK wndproc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam)
{
    switch (msg)
    {
    case WM_TIMER:
        logf_("timeout: still at stage \"%s\"", stage);
        PostQuitMessage(2);
        return 0;
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wparam, lparam);
}

int main(int argc, char **argv)
{
    WCHAR exe_dir[MAX_PATH], loader_path[MAX_PATH], user_data[MAX_PATH], *p;
    WNDCLASSW wc = {0};
    get_version_fn get_version;
    create_env_fn create_env;
    LPWSTR version = NULL;
    unsigned int seconds = 60;
    HMODULE loader;
    HRESULT hr;
    MSG msg;

    start_tick = GetTickCount64();
    composition_mode = argc > 1 && !strcmp(argv[1], "composition");
    if (argc > 2) seconds = atoi(argv[2]);
    logf_("wv2probe: mode %s, timeout %u s", composition_mode ? "composition" : "hwnd", seconds);

    /* 3番目の引数で COM の初期化を変えられる: sta(既定)、mta、none */
    if (argc > 3 && !strcmp(argv[3], "mta"))
    {
        hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
        logf_("CoInitializeEx(MTA): hr %#lx", hr);
    }
    else if (argc > 3 && !strcmp(argv[3], "none"))
    {
        logf_("COM is not initialized");
    }
    else
    {
        hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
        logf_("CoInitializeEx(STA): hr %#lx", hr);
    }

    GetModuleFileNameW(NULL, exe_dir, ARRAY_SIZE(exe_dir));
    if ((p = wcsrchr(exe_dir, '\\'))) *p = 0;
    swprintf(loader_path, ARRAY_SIZE(loader_path), L"%s\\WebView2Loader.dll", exe_dir);
    set_stage("load loader");
    if (!(loader = LoadLibraryW(loader_path)))
    {
        logf_("LoadLibrary(WebView2Loader.dll) failed: error %lu", GetLastError());
        return 1;
    }
    get_version = (get_version_fn)GetProcAddress(loader, "GetAvailableCoreWebView2BrowserVersionString");
    create_env = (create_env_fn)GetProcAddress(loader, "CreateCoreWebView2EnvironmentWithOptions");

    set_stage("find runtime");
    hr = get_version(NULL, &version);
    logf_("GetAvailableCoreWebView2BrowserVersionString: hr %#lx, version %ls", hr, version ? version : L"(none)");

    wc.lpfnWndProc = wndproc;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.hCursor = LoadCursorW(NULL, (LPCWSTR)IDC_ARROW);
    wc.lpszClassName = L"wv2probe";
    RegisterClassW(&wc);
    main_window = CreateWindowExW(composition_mode ? WS_EX_NOREDIRECTIONBITMAP : 0, L"wv2probe",
            composition_mode ? L"wv2probe (composition)" : L"wv2probe (hwnd)",
            WS_OVERLAPPEDWINDOW | WS_VISIBLE, 100, 100, 800, 500, NULL, NULL, wc.hInstance, NULL);
    logf_("main window %p", main_window);
    SetTimer(main_window, 1, seconds * 1000, NULL);

    GetTempPathW(ARRAY_SIZE(user_data), user_data);
    wcscat(user_data, composition_mode ? L"wv2probe-composition" : L"wv2probe-hwnd");
    set_stage("creating environment");
    hr = create_env(NULL, user_data, NULL,
            (ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *)handler_new(&IID_EnvCompleted,
            on_environment_created));
    logf_("CreateCoreWebView2EnvironmentWithOptions(user data %ls): immediate hr %#lx", user_data, hr);

    while (GetMessageW(&msg, NULL, 0, 0) > 0)
    {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    logf_("exit: last stage \"%s\"", stage);
    return msg.message == WM_QUIT ? (int)msg.wParam : 0;
}
