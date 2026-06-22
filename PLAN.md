Plan 1

- Reproduce the Zig build failure for `daw`.
- Move the C include path configuration from the compile step to the root module for Zig 0.16 compatibility.
- Add the miniaudio implementation translation unit required by the header-only library.
- Re-run `zig build` and address the next compile/link error if this exposes one.

Plan 2

- Make the daemon publish the current track list while it is running.
- Make `daw tracks list` print that track list instead of the placeholder message.
- Verify the flow with `make build`, `make start`, `./zig-out/bin/daw tracks list`, and `make stop`.

Plan 3

- Reduce the published track state to two tracks.
- Keep track 1 unmuted and track 2 muted.
- Verify `./zig-out/bin/daw tracks list` prints only those two tracks.

Plan 4

- Add `daw tracks volume status` for track 1 volume.
- Add `daw tracks volume increase <percent>` to raise track 1 volume by a percentage amount.
- Let the daemon reload the file-backed track state so CLI updates affect audio processing.
- Verify status, increase, and list output.
