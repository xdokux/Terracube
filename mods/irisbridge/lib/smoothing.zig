//! Exponential smoothing for the uniforms that fade rather than snap.
//!
//! Two of the values handed to packs are deliberately smoothed: `eyeBrightnessSmooth`, which decides
//! whether a pack thinks the player is in a cave, and `centerDepthSmooth`, which is a depth-of-field
//! focus pull. Minecraft fades both, and packs are written expecting that - stepping
//! `eyeBrightnessSmooth` instantly pops Nostalgia's entire volumetric fog volume the moment you
//! cross a cave mouth.
//!
//! Both used a fixed coefficient per frame, which makes the fade's duration a function of frame
//! rate. The same 0.95 per frame is a third of a second at 60 fps and a tenth of a second at 200,
//! so the cave-fog transition took six times longer to settle on a slow machine than a fast one -
//! and nothing said so, because at any single frame rate it looks like a working fade. Iris uses a
//! half-life for exactly this reason.
//!
//! The fix is one line of maths, and the reason it is a file of its own is the reason `lightmap.zig`
//! and `worldtime.zig` are: it is free of GL and of game state, so the properties that matter can be
//! asserted rather than argued. `uniforms.zig` cannot be, since it is most of the way a GL call.

const std = @import("std");

/// How far toward the target one step of `deltaTime` seconds travels, for a given time constant.
///
/// `1 - exp(-dt/tau)` is the exact solution to `dv/dt = (target - v)/tau` over one step, which is
/// what makes it frame-rate independent: the value after a second of smoothing is the same whether
/// that second arrived as 60 steps or 240.
///
/// The endpoints are the useful ones and both fall out rather than being special-cased. A
/// `deltaTime` of zero returns zero, holding the value; a long stall returns very nearly one,
/// snapping to the target rather than fading in from a state that is no longer related to anything.
/// A negative or NaN `deltaTime` returns zero - the comparison is written so NaN takes that branch.
pub fn factor(deltaTime: f32, timeConstant: f32) f32 {
	if(!(deltaTime > 0)) return 0;
	if(!(timeConstant > 0)) return 1;
	return 1.0 - @exp(-deltaTime/timeConstant);
}

/// Time constant for `eyeBrightnessSmooth`.
///
/// Chosen to reproduce the old fixed 0.95-per-frame coefficient at 60 fps: `-(1/60)/ln(0.95)`. That
/// is deliberate rather than incidental - the point of this change is to remove a frame-rate
/// dependence, not to retune a fade that nobody has complained about. 60 fps behaviour is unchanged
/// to three decimal places; every other frame rate now matches it instead of diverging.
pub const eyeBrightnessTimeConstant = 0.325;

/// Time constant for `centerDepthSmooth`, from the old 0.9 per frame at 60 fps: `-(1/60)/ln(0.9)`.
pub const centerDepthTimeConstant = 0.158;

// MARK: tests

const testing = std.testing;

/// Applies `count` steps of `step` seconds and returns where the value ends up.
fn smoothOver(start: f32, target: f32, timeConstant: f32, step: f32, count: usize) f32 {
	var value = start;
	for(0..count) |_| {
		value += (target - value)*factor(step, timeConstant);
	}
	return value;
}

test "the same elapsed time gives the same result at any frame rate" {
	// The whole property. One second of smoothing, delivered as 30, 60, 144 and 240 frames.
	const reference = smoothOver(0, 1, eyeBrightnessTimeConstant, 1.0/60.0, 60);
	for([_]struct {step: f32, count: usize}{
		.{.step = 1.0/30.0, .count = 30},
		.{.step = 1.0/144.0, .count = 144},
		.{.step = 1.0/240.0, .count = 240},
	}) |rate| {
		const result = smoothOver(0, 1, eyeBrightnessTimeConstant, rate.step, rate.count);
		try testing.expectApproxEqAbs(reference, result, 0.002);
	}
}

test "the old fixed coefficients did not have that property" {
	// The regression this fixes, asserted directly so the diagnosis cannot quietly rot. A fixed
	// 0.05 per frame reaches 0.95 after a second at 60 fps and 0.99999 at 240 - the same wall-clock
	// second, wildly different amounts of fade.
	var slow: f32 = 0;
	for(0..60) |_| slow += (1.0 - slow)*0.05;
	var fast: f32 = 0;
	for(0..240) |_| fast += (1.0 - fast)*0.05;
	try testing.expect(fast - slow > 0.04);
}

test "60 fps behaviour is unchanged, which is the point" {
	// Both constants exist to reproduce the coefficients that were there before, so that this change
	// removes a frame-rate dependence without also silently retuning two fades.
	try testing.expectApproxEqAbs(@as(f32, 0.05), factor(1.0/60.0, eyeBrightnessTimeConstant), 0.0005);
	try testing.expectApproxEqAbs(@as(f32, 0.10), factor(1.0/60.0, centerDepthTimeConstant), 0.0005);
}

test "a stall snaps and a zero step holds" {
	// A frame that took a whole second must not fade in from a location the player has since left.
	try testing.expect(factor(1.0, eyeBrightnessTimeConstant) > 0.95);
	// And a zero or negative delta must change nothing rather than producing a NaN or a jump.
	try testing.expectEqual(@as(f32, 0), factor(0, eyeBrightnessTimeConstant));
	try testing.expectEqual(@as(f32, 0), factor(-1, eyeBrightnessTimeConstant));
	try testing.expectEqual(@as(f32, 0), factor(std.math.nan(f32), eyeBrightnessTimeConstant));
}

test "the factor stays in range for every input" {
	// It multiplies a difference, so anything outside [0, 1] either overshoots the target or moves
	// away from it.
	for([_]f32{0, 0.0001, 1.0/240.0, 1.0/60.0, 0.5, 1, 100}) |deltaTime| {
		const value = factor(deltaTime, eyeBrightnessTimeConstant);
		try testing.expect(value >= 0 and value <= 1);
	}
	// A degenerate time constant means "no smoothing", not a division by zero.
	try testing.expectEqual(@as(f32, 1), factor(1.0/60.0, 0));
}
