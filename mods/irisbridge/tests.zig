//! Collects every irisbridge unit test into one module, so `zig build test` runs them alongside the
//! engine's own.
//!
//! Zig gathers tests from the root module and the files it `@import`s, but not across module
//! boundaries - `irisbridge` is its own module in the engine build, so its tests are invisible to
//! the engine's test artifact. Referencing each file here pulls them into one module that
//! `build.zig` points a second test artifact at.
//!
//! It lives at the mod root rather than beside the other test files because a module can only
//! import files at or below its root source file's directory; from `test/` the `lib/` sources are
//! "outside module path".
//!
//! `zig build test` is the way to run these. `test/run.bat` still drives a `zig test` per file for
//! iterating on one of them without linking the engine, but it produces a fresh standalone
//! executable each time, which this machine's security settings decline to launch.
//!
//! Files that only wrap OpenGL calls are absent because they have nothing to assert without a
//! context: `targets.zig`, `packtextures.zig`, `blockids.zig` and `bridge.zig` are covered by the
//! engine build compiling them. `blend.zig` is included precisely because its interesting part -
//! mapping a colortex name to a draw buffer slot - was deliberately kept free of GL.

test {
	_ = @import("lib/glsl.zig");
	_ = @import("lib/pack.zig");
	_ = @import("lib/flip.zig");
	_ = @import("lib/matrix.zig");
	_ = @import("lib/expression.zig");
	_ = @import("lib/options.zig");
	_ = @import("lib/preprocess.zig");
	_ = @import("lib/blockmap.zig");
	_ = @import("lib/blend.zig");
	_ = @import("lib/lightmap.zig");
	_ = @import("lib/smoothing.zig");
	_ = @import("lib/worldtime.zig");
	_ = @import("lib/prologue.zig");
	_ = @import("lib/biomemap.zig");
	_ = @import("lib/cloudmask.zig");
}
