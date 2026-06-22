const std = @import("std");
const miniaudio = @cImport(@cInclude("miniaudio.h"));

const tracks_state_path = "/tmp/daw-tracks-v2.txt";

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

fn parse_bool(value: []const u8) !bool {
    if (std.mem.eql(u8, value, "true")) return true;
    if (std.mem.eql(u8, value, "false")) return false;
    return error.InvalidTrackState;
}

fn parse_track_line(line: []const u8) !struct { index: usize, track: Track } {
    const colon_index = std.mem.indexOfScalar(u8, line, ':') orelse return error.InvalidTrackState;
    const index_text = std.mem.trim(u8, line[0..colon_index], " ");
    const rest = std.mem.trim(u8, line[colon_index + 1 ..], " ");

    var parts = std.mem.splitScalar(u8, rest, ' ');
    const volume_part = parts.next() orelse return error.InvalidTrackState;
    const muted_part = parts.next() orelse return error.InvalidTrackState;

    if (!std.mem.startsWith(u8, volume_part, "volume=")) return error.InvalidTrackState;
    if (!std.mem.startsWith(u8, muted_part, "muted=")) return error.InvalidTrackState;

    return .{
        .index = try std.fmt.parseInt(usize, index_text, 10),
        .track = .{
            .volume = try std.fmt.parseFloat(f32, volume_part["volume=".len..]),
            .muted = try parse_bool(muted_part["muted=".len..]),
        },
    };
}

fn parse_tracks(contents: []const u8, tracks: *[g_tracks.len]Track) !void {
    var parsed = [_]bool{false} ** g_tracks.len;
    var lines = std.mem.splitScalar(u8, contents, '\n');

    const header = lines.next() orelse return error.InvalidTrackState;
    if (!std.mem.eql(u8, std.mem.trim(u8, header, " \r"), "tracks")) return error.InvalidTrackState;

    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \r");
        if (line.len == 0) continue;

        const parsed_line = try parse_track_line(line);
        if (parsed_line.index == 0 or parsed_line.index > tracks.len) return error.InvalidTrackState;

        tracks[parsed_line.index - 1] = parsed_line.track;
        parsed[parsed_line.index - 1] = true;
    }

    for (parsed) |seen| {
        if (!seen) return error.InvalidTrackState;
    }
}

fn read_tracks(io: std.Io, allocator: std.mem.Allocator) ![g_tracks.len]Track {
    const contents = try std.Io.Dir.cwd().readFileAlloc(
        io,
        tracks_state_path,
        allocator,
        .limited(64 * 1024),
    );

    var tracks = g_tracks;
    try parse_tracks(contents, &tracks);
    return tracks;
}

fn load_tracks_from_disk(io: std.Io, allocator: std.mem.Allocator) !void {
    g_tracks = read_tracks(io, allocator) catch |err| switch (err) {
        error.FileNotFound => return,
        else => |e| return e,
    };
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
        try load_tracks_from_disk(io, std.heap.page_allocator);
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

fn print_track_one_volume(io: std.Io, allocator: std.mem.Allocator) !void {
    const tracks = read_tracks(io, allocator) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("DAW daemon track state not found. Run `make start` first.\n", .{});
            return error.DaemonNotRunning;
        },
        else => |e| return e,
    };

    std.debug.print("track 1 volume={d}\n", .{tracks[0].volume});
}

fn write_tracks(io: std.Io, tracks: [g_tracks.len]Track) !void {
    const previous_tracks = g_tracks;
    g_tracks = tracks;
    defer g_tracks = previous_tracks;

    try write_tracks_snapshot(io);
}

fn increase_track_one_volume(io: std.Io, allocator: std.mem.Allocator, percent_text: []const u8) !void {
    var tracks = read_tracks(io, allocator) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("DAW daemon track state not found. Run `make start` first.\n", .{});
            return error.DaemonNotRunning;
        },
        else => |e| return e,
    };

    const percent = try std.fmt.parseFloat(f32, percent_text);
    tracks[0].volume += percent / 100.0;
    if (tracks[0].volume < 0.0) tracks[0].volume = 0.0;

    try write_tracks(io, tracks);
    std.debug.print("track 1 volume={d}\n", .{tracks[0].volume});
}

fn print_usage() void {
    std.debug.print(
        \\Usage:
        \\  daw start
        \\  daw tracks list
        \\  daw tracks volume status
        \\  daw tracks volume increase <percent>
        \\
    , .{});
}

fn handle_tracks_command(io: std.Io, allocator: std.mem.Allocator, args: []const [:0]const u8) !void {
    if (args.len >= 3 and std.mem.eql(u8, args[2], "list")) {
        try list_tracks(io, allocator);
        return;
    }

    if (args.len >= 4 and std.mem.eql(u8, args[2], "volume")) {
        if (std.mem.eql(u8, args[3], "status")) {
            try print_track_one_volume(io, allocator);
            return;
        }

        if (std.mem.eql(u8, args[3], "increase") and args.len >= 5) {
            try increase_track_one_volume(io, allocator, args[4]);
            return;
        }
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
