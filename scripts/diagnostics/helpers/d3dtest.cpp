// Minimal D3D11 program for compile_check.sh: opens a window, creates a device and a swap
// chain and presents frames for N seconds, so an injected ReShade (as dxgi.dll) starts up,
// compiles every effect it finds and writes ReShade.log. It draws nothing of interest.
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <cstdlib>

static LRESULT CALLBACK window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == WM_DESTROY) {
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcA(window, message, wparam, lparam);
}

int WINAPI WinMain(HINSTANCE instance, HINSTANCE, LPSTR command_line, int) {
    const int seconds = (command_line && *command_line) ? atoi(command_line) : 60;

    WNDCLASSA window_class = {};
    window_class.lpfnWndProc = window_proc;
    window_class.hInstance = instance;
    window_class.lpszClassName = "compile_check";
    RegisterClassA(&window_class);
    HWND window = CreateWindowA("compile_check", "ReShade compile check", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                                0, 0, 1280, 720, nullptr, nullptr, instance, nullptr);

    DXGI_SWAP_CHAIN_DESC desc = {};
    desc.BufferCount = 2;
    desc.BufferDesc.Width = 1280;
    desc.BufferDesc.Height = 720;
    desc.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    desc.OutputWindow = window;
    desc.SampleDesc.Count = 1;
    desc.Windowed = TRUE;
    desc.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    IDXGISwapChain *swap_chain = nullptr;
    ID3D11Device *device = nullptr;
    ID3D11DeviceContext *context = nullptr;
    D3D_FEATURE_LEVEL level;
    if (FAILED(D3D11CreateDeviceAndSwapChain(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, nullptr, 0,
                                             D3D11_SDK_VERSION, &desc, &swap_chain, &device, &level, &context))) {
        return 2;
    }

    ID3D11Texture2D *back_buffer = nullptr;
    ID3D11RenderTargetView *target = nullptr;
    swap_chain->GetBuffer(0, __uuidof(ID3D11Texture2D), reinterpret_cast<void **>(&back_buffer));
    device->CreateRenderTargetView(back_buffer, nullptr, &target);

    const DWORD end = GetTickCount() + static_cast<DWORD>(seconds) * 1000;
    MSG message;
    while (GetTickCount() < end) {
        while (PeekMessageA(&message, nullptr, 0, 0, PM_REMOVE)) {
            TranslateMessage(&message);
            DispatchMessageA(&message);
        }
        const float colour[4] = {0.3f, 0.5f, 0.7f, 1.0f};
        context->OMSetRenderTargets(1, &target, nullptr);
        context->ClearRenderTargetView(target, colour);
        swap_chain->Present(1, 0);
    }
    return 0;
}
