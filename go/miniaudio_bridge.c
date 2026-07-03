// go/miniaudio_bridge.c
#include "../miniaudio_impl.c"
#include <stdlib.h>

void goAudioCallback(void* pOutput, void* pInput, ma_uint32 frameCount);

void maAudioCallback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
    // Pass NULL for input since we are focusing on playback stream stability
    goAudioCallback(pOutput, NULL, frameCount);
}

static ma_context g_audio_context;
static ma_bool32 g_context_initialized = MA_FALSE;

ma_device* initDeviceInC() {
    if (!g_context_initialized) {
        if (ma_context_init(NULL, 0, NULL, &g_audio_context) != MA_SUCCESS) {
            return NULL;
        }
        g_context_initialized = MA_TRUE;
    }

    ma_device* device = (ma_device*)malloc(sizeof(ma_device));
    if (device == NULL) return NULL;

    // ✅ FIX 1: Use playback-only mode. Bypasses macOS terminal Microphone privacy blocks.
    ma_device_config deviceConfig = ma_device_config_init(ma_device_type_playback);
    deviceConfig.dataCallback    = maAudioCallback;
    
    // ✅ FIX 2: standard hardware expectations for CoreAudio pass-through
    deviceConfig.playback.format   = ma_format_f32;
    deviceConfig.playback.channels = 2;              // Standard Stereo
    deviceConfig.sampleRate        = 44100;          // Standard audio clock rate

    if (ma_device_init(&g_audio_context, &deviceConfig, device) != MA_SUCCESS) {
        free(device);
        return NULL;
    }
    return device;
}

void freeDeviceInC(ma_device* device) {
    if (device != NULL) {
        ma_device_uninit(device);
        free(device);
    }
    if (g_context_initialized) {
        ma_context_uninit(&g_audio_context);
        g_context_initialized = MA_FALSE;
    }
}