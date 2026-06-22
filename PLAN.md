Plan 1

- Reproduce the Zig build failure for `daw`.
- Move the C include path configuration from the compile step to the root module for Zig 0.16 compatibility.
- Add the miniaudio implementation translation unit required by the header-only library.
- Re-run `zig build` and address the next compile/link error if this exposes one.

Plan 2

- Make the daemon publish the current track list while it is running.
- Make `daw tracks list` print that track list instead of the placeholder message.
- Verify the flow with `make build`, `make start`, `./zig-out/bin/daw tracks list`, and `make stop`.
