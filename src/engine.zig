const std = @import("std");

pub const Track = struct {
    volume: f32 = 1.0,
    reverb: f32 = 0.0,
    echo: f32 = 0.0,
    is_muted: bool = false,
};

// Global state: Pre-allocated for the audio thread
pub var g_tracks: [16]Track = .{.{}} ** 16;
pub var g_mutex = std.Thread.Mutex{}; // Use to protect state changes

pub fn process_audio(output: []f32) void {
    @memset(output, 0); // Clear buffer

    // Lockless access is better, but Mutex is fine for control-level updates
    g_mutex.lock();
    defer g_mutex.unlock();

    for (&g_tracks) |*track| {
        if (track.is_muted) continue;

        // --- YOUR DSP LOGIC HERE ---
        // For each track, apply volume, echo, reverb
        // Mix into the output buffer
    }
}
