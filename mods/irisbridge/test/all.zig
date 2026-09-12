//! Collects every irisbridge unit test into one module, so `zig build test` runs them alongside
//! the engine's own.
//!
//! Zig gathers tests from the root module and the files it `@import`s, but *not* across module
//! boundaries - `irisbridge` is its own module in the engine build, so its tests are invisible to
//! the engine's test artifact. Referencing each file here pulls them into one module that
//! `build.zig` points a second test artifact at.
//!
//! This supersedes running `test/run.bat`, which drives a separate `zig test` per file and produces
//! a fresh unsigned executable each time. `run.bat` is still there for iterating on one file
//! without linking the engine, but `zig build test` is the way to run the suite.
//!
//! Files that only wrap OpenGL calls are absent because they have nothing to assert without a
//! context: `targets.zig`, `packtextures.zig`, `blockids.zig` and `bridge.zig` are exercised by the
//! engine build rather than here. `blend.zig` is included precisely because its interesting part -
//! mapping a colortex name to a draw buffer slot - was deliberately kept free of GL.

test {
	_ = @import("../lib/glsl.zig");
	_ = @import("../lib/pack.zig");
	_ = @import("../lib/flip.zig");
	_ = @import("../lib/matrix.zig");
	_ = @import("../lib/expression.zig");
	_ = @import("../lib/options.zig");
	_ = @import("../lib/preprocess.zig");
	_ = @import("../lib/blockmap.zig");
	_ = @import("../lib/blend.zig");
}
