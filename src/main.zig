const std = @import("std");
const miniaudio = @cImport(@cInclude("miniaudio.h"));

const tracks_state_path = "/tmp/daw-tracks.txt";

// Global Track State
pub const Track = struct { volume: f32 = 1.0, muted: bool = false };
var g_tracks = [_]Track{
    .{ .volume = 1.0, .muted = false },
    .{ .volume = 1.0, .muted = true },
};

// Audio Callback - The High-Priority Thread
fn data_callback(pDevice: [*c]miniaudio.ma_device, pOutput: ?*anyopaque, pInput: ?*const anyopaque, frameCount: u32) callconv(.c) void {
    _ = pDevice;

    const output: [*c]f32 = @ptrCast(@alignCast(pOutput orelse return));
    const input: [*c]const f32 = @ptrCast(@alignCast(pInput orelse {
        @memset(output[0..frameCount], 0);
        return;
    }));

    // Mix tracks into output
    for (0..frameCount) |i| {
        output[i] = input[i] * g_tracks[0].volume; // Simple volume control for track 1
    }
}

fn write_tracks_snapshot(io: std.Io) !void {
    var file = try std.Io.Dir.createFileAbsolute(io, tracks_state_path, .{});
    defer file.close(io);

    var buffer: [4096]u8 = undefined;
    var file_writer = file.writer(io, &buffer);
    const writer = &file_writer.interface;

    try writer.writeAll("tracks\n");
    for (g_tracks, 0..) |track, index| {
        try writer.print("{d}: volume={d} muted={}\n", .{
            index + 1,
            track.volume,
            track.muted,
        });
    }
    try writer.flush();
}

fn start_daemon(io: std.Io) !void {
    var device_config = miniaudio.ma_device_config_init(miniaudio.ma_device_type_duplex);
    device_config.dataCallback = data_callback;

    var device: miniaudio.ma_device = undefined;
    if (miniaudio.ma_device_init(null, &device_config, &device) != miniaudio.MA_SUCCESS) {
        return error.DeviceInitFailed;
    }
    defer miniaudio.ma_device_uninit(&device);

    if (miniaudio.ma_device_start(&device) != miniaudio.MA_SUCCESS) {
        return error.DeviceStartFailed;
    }
    std.debug.print("DAW Backend Running...\n", .{});

    try write_tracks_snapshot(io);

    while (true) {
        try io.sleep(.fromNanoseconds(std.time.ns_per_s), .awake);
        try write_tracks_snapshot(io);
    }
}

fn list_tracks(io: std.Io, allocator: std.mem.Allocator) !void {
    const contents = std.Io.Dir.cwd().readFileAlloc(
        io,
        tracks_state_path,
        allocator,
        .limited(64 * 1024),
    ) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("DAW daemon track state not found. Run `make start` first.\n", .{});
            return error.DaemonNotRunning;
        },
        else => |e| return e,
    };

    try std.Io.File.stdout().writeStreamingAll(io, contents);
}

fn print_usage() void {
    std.debug.print(
        \\Usage:
        \\  daw start
        \\  daw tracks list
        \\
    , .{});
}

fn handle_tracks_command(io: std.Io, allocator: std.mem.Allocator, args: []const [:0]const u8) !void {
    if (args.len >= 3 and std.mem.eql(u8, args[2], "list")) {
        try list_tracks(io, allocator);
        return;
    }

    print_usage();
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const args = try init.minimal.args.toSlice(arena.allocator());

    if (args.len < 2) return;

    if (std.mem.eql(u8, args[1], "start")) {
        try start_daemon(init.io);
    } else if (std.mem.eql(u8, args[1], "tracks")) {
        try handle_tracks_command(init.io, arena.allocator(), args);
    } else {
        print_usage();
    }
}
