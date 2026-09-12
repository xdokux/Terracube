//! `blend.<program>` and `blend.<program>.colortex<N>` from `shaders.properties`.
//!
//! A pack controls blending per program, and - this is the part that matters - per *draw buffer*:
//!
//!     blend.gbuffers_terrain=off
//!     blend.gbuffers_water.colortex1=off
//!     blend.gbuffers_water.colortex2=off
//!     blend.gbuffers_water.colortex3=off
//!
//! Nostalgia's water declaration says exactly what a translucent G-buffer needs. `colortex0` keeps
//! ordinary alpha blending, because that is how water tints the scene behind it. `colortex1`-`3`
//! hold normals and material data, and those must be written, not blended - a half-transparent
//! surface whose normal is 40% mixed with the normal of whatever is behind it is not a normal, and
//! every deferred pass downstream reads it as though it were. Applying one blend mode across all
//! attachments corrupts the G-buffer in a way that looks like a lighting bug rather than a blending
//! one.
//!
//! Per-attachment blending is `glBlendFunci`/`glEnablei`, GL 4.0 and up; Cubyz already requires 4.6.
//!
//! The key names a colortex, while the GL call indexes a draw buffer slot. Those are only
//! the same when the program's `DRAWBUFFERS` happens to be in order, so the program's own draw
//! buffer list is what maps between them.
//!
//! This file is deliberately free of GL, like `flip.zig`, so the colortex-to-slot mapping - the
//! part that is actually easy to get wrong - can be tested without a context. `pipeline.zig` turns
//! the resulting state into GL calls.

const std = @import("std");

const main = @import("main");

const pack = @import("pack.zig");

/// OptiFine's blend factor names.
pub const Factor = enum {
	zero,
	one,
	srcColor,
	oneMinusSrcColor,
	dstColor,
	oneMinusDstColor,
	srcAlpha,
	oneMinusSrcAlpha,
	dstAlpha,
	oneMinusDstAlpha,
	constantColor,
	oneMinusConstantColor,
	constantAlpha,
	oneMinusConstantAlpha,
	srcAlphaSaturate,

	pub fn parse(text: []const u8) ?Factor {
		const table = .{
			.{"ZERO", Factor.zero},
			.{"ONE", Factor.one},
			.{"SRC_COLOR", Factor.srcColor},
			.{"ONE_MINUS_SRC_COLOR", Factor.oneMinusSrcColor},
			.{"DST_COLOR", Factor.dstColor},
			.{"ONE_MINUS_DST_COLOR", Factor.oneMinusDstColor},
			.{"SRC_ALPHA", Factor.srcAlpha},
			.{"ONE_MINUS_SRC_ALPHA", Factor.oneMinusSrcAlpha},
			.{"DST_ALPHA", Factor.dstAlpha},
			.{"ONE_MINUS_DST_ALPHA", Factor.oneMinusDstAlpha},
			.{"CONSTANT_COLOR", Factor.constantColor},
			.{"ONE_MINUS_CONSTANT_COLOR", Factor.oneMinusConstantColor},
			.{"CONSTANT_ALPHA", Factor.constantAlpha},
			.{"ONE_MINUS_CONSTANT_ALPHA", Factor.oneMinusConstantAlpha},
			.{"SRC_ALPHA_SATURATE", Factor.srcAlphaSaturate},
		};
		inline for(table) |entry| {
			if(std.mem.eql(u8, entry[0], text)) return entry[1];
		}
		return null;
	}

};

pub const Mode = union(enum) {
	off,
	on: struct {
		srcRgb: Factor,
		dstRgb: Factor,
		srcAlpha: Factor,
		dstAlpha: Factor,
	},
};

/// OptiFine's default for a gbuffers program, and what a pack that declares nothing expects.
pub const default = Mode{.on = .{
	.srcRgb = .srcAlpha,
	.dstRgb = .oneMinusSrcAlpha,
	.srcAlpha = .one,
	.dstAlpha = .oneMinusSrcAlpha,
}};

/// Reads one `blend.*` value.
///
/// Accepts `off`, two factors (RGB only, with alpha following it), or four. Two-factor form applies
/// the same pair to alpha, which is what OptiFine does.
pub fn parseMode(text: []const u8) ?Mode {
	const trimmed = std.mem.trim(u8, text, " \t\r");
	if(std.ascii.eqlIgnoreCase(trimmed, "off")) return .off;

	var factors: [4]Factor = undefined;
	var count: usize = 0;
	var parts = std.mem.tokenizeAny(u8, trimmed, " \t");
	while(parts.next()) |part| {
		if(count == 4) return null;
		factors[count] = Factor.parse(part) orelse return null;
		count += 1;
	}
	if(count == 2) return .{.on = .{.srcRgb = factors[0], .dstRgb = factors[1], .srcAlpha = factors[0], .dstAlpha = factors[1]}};
	if(count == 4) return .{.on = .{.srcRgb = factors[0], .dstRgb = factors[1], .srcAlpha = factors[2], .dstAlpha = factors[3]}};
	return null;
}

/// The blend mode of each draw buffer slot of one program.
///
/// `pipeline.applyBlendState` turns this into GL calls.
pub const State = struct {
	/// Indexed by draw buffer slot, not by colortex number.
	slots: [16]Mode = @splat(default),
	count: usize = 0,
};

/// Builds the per-slot blend state for a program from the pack's properties.
///
/// `drawBuffers` maps slot to colortex, which is the translation the per-buffer keys need: the pack
/// writes `blend.gbuffers_water.colortex1`, and GL wants the slot that colortex1 occupies in *this*
/// program's `DRAWBUFFERS`.
pub fn resolve(properties: *const pack.Properties, programName: []const u8, drawBuffers: []const u8) State {
	return resolveWith(properties, programName, drawBuffers, default);
}

/// Minecraft's blend for the sun and moon quads (`LevelRenderer.renderSky`,
/// `blendFuncSeparate(SRC_ALPHA, ONE, ONE, ZERO)`): additive, so the sun brightens the sky it is
/// drawn over rather than replacing it. The vanilla state `gbuffers_skytextured` runs under when
/// the pack declares no `blend.gbuffers_skytextured`.
pub const additive = Mode{.on = .{
	.srcRgb = .srcAlpha,
	.dstRgb = .one,
	.srcAlpha = .one,
	.dstAlpha = .zero,
}};

/// `resolve` with the vanilla state a program inherits when the pack declares nothing for it,
/// which is not the same for every program: terrain and water blend by alpha, the sun adds.
pub fn resolveWith(properties: *const pack.Properties, programName: []const u8, drawBuffers: []const u8, vanilla: Mode) State {
	var state = State{.count = drawBuffers.len};

	// The whole-program key first, then per-buffer keys refine it.
	var key: [64]u8 = undefined;
	const programKey = std.fmt.bufPrint(&key, "blend.{s}", .{programName}) catch return state;
	const base = if(properties.get(programKey)) |text| parseMode(text) orelse vanilla else vanilla;
	state.slots = @splat(base);

	for(drawBuffers, 0..) |colortex, slot| {
		var perBuffer: [64]u8 = undefined;
		const bufferKey = std.fmt.bufPrint(&perBuffer, "blend.{s}.colortex{}", .{programName, colortex}) catch continue;
		const text = properties.get(bufferKey) orelse continue;
		state.slots[slot] = parseMode(text) orelse continue;
	}
	return state;
}

// MARK: tests

const testing = std.testing;
const testingAllocator = main.heap.testingAllocator;

test "off and factor lists both parse" {
	try testing.expectEqual(Mode.off, parseMode("off").?);
	try testing.expectEqual(Mode.off, parseMode(" OFF ").?);

	const four = parseMode("SRC_ALPHA ONE ZERO ONE").?;
	try testing.expectEqual(Factor.srcAlpha, four.on.srcRgb);
	try testing.expectEqual(Factor.one, four.on.dstRgb);
	try testing.expectEqual(Factor.zero, four.on.srcAlpha);
	try testing.expectEqual(Factor.one, four.on.dstAlpha);

	// The two-factor form applies the same pair to alpha.
	const two = parseMode("SRC_ALPHA ONE_MINUS_SRC_ALPHA").?;
	try testing.expectEqual(Factor.srcAlpha, two.on.srcAlpha);
	try testing.expectEqual(Factor.oneMinusSrcAlpha, two.on.dstAlpha);
}

test "an unrecognised factor rejects the whole declaration" {
	// Better than silently substituting a default: a typo in a pack should keep OptiFine's default
	// rather than produce a blend mode nobody wrote.
	try testing.expectEqual(@as(?Mode, null), parseMode("SRC_ALPHA NOT_A_FACTOR"));
	try testing.expectEqual(@as(?Mode, null), parseMode("ONE"));
	try testing.expectEqual(@as(?Mode, null), parseMode("ONE ZERO ONE"));
}

test "per-buffer keys are resolved against the program's own DRAWBUFFERS" {
	// The property this exists for: the key names colortex1, but GL needs the *slot* colortex1
	// occupies. Here DRAWBUFFERS is 0,3,1 - so colortex1 is slot 2, not slot 1.
	var properties = pack.parseProperties(testingAllocator,
		\\blend.gbuffers_water.colortex1=off
		\\
	);
	defer properties.deinit();

	const state = resolve(&properties, "gbuffers_water", &.{0, 3, 1});
	try testing.expectEqual(@as(usize, 3), state.count);
	try testing.expectEqual(Mode.off, state.slots[2]);
	// Everything else keeps the default alpha blend, which is how water tints the scene behind it.
	try testing.expectEqual(Factor.srcAlpha, state.slots[0].on.srcRgb);
	try testing.expectEqual(Factor.srcAlpha, state.slots[1].on.srcRgb);
}

test "a whole-program declaration covers every slot" {
	var properties = pack.parseProperties(testingAllocator, "blend.gbuffers_terrain=off\n");
	defer properties.deinit();

	const state = resolve(&properties, "gbuffers_terrain", &.{0, 1, 2});
	for(0..3) |slot| try testing.expectEqual(Mode.off, state.slots[slot]);
}

test "a per-buffer key refines the whole-program one" {
	var properties = pack.parseProperties(testingAllocator,
		\\blend.gbuffers_water=off
		\\blend.gbuffers_water.colortex0=SRC_ALPHA ONE_MINUS_SRC_ALPHA
		\\
	);
	defer properties.deinit();

	const state = resolve(&properties, "gbuffers_water", &.{0, 1});
	try testing.expectEqual(Factor.srcAlpha, state.slots[0].on.srcRgb);
	try testing.expectEqual(Mode.off, state.slots[1]);
}

test "a pack that declares nothing gets OptiFine's default" {
	var properties = pack.parseProperties(testingAllocator, "");
	defer properties.deinit();

	const state = resolve(&properties, "gbuffers_water", &.{0});
	try testing.expectEqual(Factor.srcAlpha, state.slots[0].on.srcRgb);
	try testing.expectEqual(Factor.oneMinusSrcAlpha, state.slots[0].on.dstRgb);
	try testing.expectEqual(Factor.one, state.slots[0].on.srcAlpha);
}

test "Nostalgia's real water declaration keeps colour blended and material unblended" {
	// Transcribed from the fixture. colortex1-3 carry normals and material data; blending those
	// against what is behind the water produces values that are not normals at all, and every
	// deferred pass downstream reads them as though they were.
	var properties = pack.parseProperties(testingAllocator,
		\\blend.gbuffers_water.colortex1=off
		\\blend.gbuffers_water.colortex2=off
		\\blend.gbuffers_water.colortex3=off
		\\
	);
	defer properties.deinit();

	const state = resolve(&properties, "gbuffers_water", &.{0, 1, 2, 3});
	try testing.expectEqual(Factor.srcAlpha, state.slots[0].on.srcRgb);
	try testing.expectEqual(Mode.off, state.slots[1]);
	try testing.expectEqual(Mode.off, state.slots[2]);
	try testing.expectEqual(Mode.off, state.slots[3]);
}
