//! Ping-pong bookkeeping for the colortex buffers.
//!
//! Every colortex is two textures, "main" and "alt", because a composite pass almost always
//! samples the buffer it is overwriting and must not read and write the same texture. Which of
//! the two is live is tracked per target, following Iris's `BufferFlipper`:
//!
//!     not flipped -> read main, write alt
//!     flipped     -> read alt,  write main
//!
//! and a target toggles each time a pass writes to it.
//!
//! The point worth stating plainly: the whole sequence follows from the ordered pass list alone,
//! so it is resolved once when the pipeline is built rather than re-derived each frame. Keeping
//! it in its own file, free of any GL dependency, is what lets the fiddliest logic in the
//! pipeline be tested without a graphics context.

const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub const colortexCount = 16;

/// Which colortex targets are currently flipped, as a bitmask over the 16 targets.
pub const FlipState = struct {
	flipped: u16 = 0,

	pub fn isFlipped(self: FlipState, target: u8) bool {
		std.debug.assert(target < colortexCount);
		return self.flipped & (@as(u16, 1) << @intCast(target)) != 0;
	}

	pub fn flip(self: *FlipState, target: u8) void {
		std.debug.assert(target < colortexCount);
		self.flipped ^= @as(u16, 1) << @intCast(target);
	}
};

/// Which of a target's two textures a pass touches.
pub const Side = enum {main, alt};

/// The shadow colour buffers, `shadowcolor0` to `shadowcolor7`: Iris's eight, of which a pack's
/// programs touch what they touch and the rest stay unallocated (`pack.shadowColorUsage`).
pub const shadowColorCount = @import("pack.zig").shadowColorCount;

/// Where every colortex is read from and written to, for one pass.
pub const PassBindings = struct {
	/// Side to sample for each colortex - recorded for all 16 whether the pass writes them or
	/// not, since a pass may declare `uniform sampler2D colortex7` and never draw to it.
	read: [colortexCount]Side = @splat(.main),
	/// Side to attach when the pass draws to that colortex.
	write: [colortexCount]Side = @splat(.alt),
	/// The same pair for the shadow colour buffers, which have their own short chain: the shadow
	/// pass always writes `main` (Iris's `createShadowFramebuffer(ImmutableSet.of(), ...)`), the
	/// `shadowcomp` passes ping-pong from there by the walk `resolveBindings` does, and everything
	/// after the chain reads the side it left (`ShadowRenderTargets.getColorTextureId`). With no
	/// `shadowcomp` pass both stay `main`, which is what every consumer read before the chain ran.
	shadowRead: [shadowColorCount]Side = @splat(.main),
	shadowWrite: [shadowColorCount]Side = @splat(.main),
};

/// Walks the pass list once, recording for each pass which side of each target it reads and writes.
///
/// The ordering is the subtle part: a pass's bindings come from the flip state *before* it runs,
/// and only afterwards do the buffers it wrote get flipped. That is precisely what makes the next
/// pass read what this one produced.
pub fn resolveBindings(allocator: NeverFailingAllocator, passDrawBuffers: []const []const u8) []PassBindings {
	var state = FlipState{};
	const result = allocator.alloc(PassBindings, passDrawBuffers.len);
	for(passDrawBuffers, result) |drawBuffers, *bindings| {
		bindings.* = .{};
		for(0..colortexCount) |index| {
			const target: u8 = @intCast(index);
			bindings.read[index] = if(state.isFlipped(target)) .alt else .main;
			bindings.write[index] = if(state.isFlipped(target)) .main else .alt;
		}
		for(drawBuffers) |target| {
			if(target >= colortexCount) continue;
			state.flip(target);
		}
	}
	return result;
}

/// The flip state left behind once every pass has run.
///
/// This is what decides which buffers need copying back at the end of the frame. A buffer written an
/// odd number of times ends flipped, meaning its newest contents sit in `alt` - but the next frame
/// starts from an unflipped state and reads `main`. Without a copy, everything a pack accumulates
/// across frames (TAA history, auto-exposure, any smoothed value) reads a texture nothing ever
/// wrote.
///
/// Iris does the same thing, in `FinalPassRenderer`'s swap passes, with the comment "we merely copy
/// it from alt to main".
pub fn finalState(passDrawBuffers: []const []const u8) FlipState {
	var state = FlipState{};
	for(passDrawBuffers) |drawBuffers| {
		for(drawBuffers) |target| {
			if(target >= colortexCount) continue;
			state.flip(target);
		}
	}
	return state;
}

/// Which colortex targets a group of passes draws to at all, regardless of how many times.
///
/// Distinct from `finalState`, which counts parity: a buffer written twice is *not* flipped but has
/// still been written. The question this answers is "did the pack put anything here", which parity
/// cannot express.
pub fn writtenTargets(passDrawBuffers: []const []const u8) TargetSet {
	var set = TargetSet{};
	for(passDrawBuffers) |drawBuffers| {
		for(drawBuffers) |target| {
			if(target >= colortexCount) continue;
			set.add(target);
		}
	}
	return set;
}

/// A set of colortex targets, as a bitmask over the 16.
pub const TargetSet = struct {
	targets: u16 = 0,

	pub fn contains(self: TargetSet, target: u8) bool {
		std.debug.assert(target < colortexCount);
		return self.targets & (@as(u16, 1) << @intCast(target)) != 0;
	}

	pub fn add(self: *TargetSet, target: u8) void {
		std.debug.assert(target < colortexCount);
		self.targets |= @as(u16, 1) << @intCast(target);
	}
};

// MARK: tests

const testing = std.testing;
const testingAllocator = main.heap.testingAllocator;

test "flip state toggles per target" {
	var state = FlipState{};
	try testing.expect(!state.isFlipped(0));
	state.flip(0);
	try testing.expect(state.isFlipped(0));
	try testing.expect(!state.isFlipped(1));
	state.flip(0);
	try testing.expect(!state.isFlipped(0));
}

test "a pass reads what the previous pass wrote" {
	// Three passes all writing colortex0, as a composite chain does.
	const drawBuffers = [_][]const u8{&.{0}, &.{0}, &.{0}};
	const bindings = resolveBindings(testingAllocator, &drawBuffers);
	defer testingAllocator.free(bindings);

	// Pass 0 reads main, writes alt.
	try testing.expectEqual(Side.main, bindings[0].read[0]);
	try testing.expectEqual(Side.alt, bindings[0].write[0]);
	// Pass 1 must read the alt that pass 0 wrote, and write back to main.
	try testing.expectEqual(Side.alt, bindings[1].read[0]);
	try testing.expectEqual(Side.main, bindings[1].write[0]);
	// Pass 2 reads main again.
	try testing.expectEqual(Side.main, bindings[2].read[0]);
	try testing.expectEqual(Side.alt, bindings[2].write[0]);
}

test "a pass that never runs must not be in the sequence" {
	// The caller's obligation, stated as a test because getting it wrong is invisible: this resolves
	// whatever list it is handed, and a program that failed to compile still *has* draw buffers. Its
	// phantom writes then flip the parity for everything after it, and those passes are pointed at a
	// side nothing ever writes.
	//
	// photon hit this exactly. `composite1` wrote colortex0, `composite2` and `composite3` failed to
	// compile, `composite4` was told to read the side they would have written - which held
	// `deferred4`'s output, so `composite1`'s work was discarded and stale content bled through.
	// Three declared passes writing colortex0, of which the middle one does not compile. One phantom
	// write is enough - and one is what photon has, since only one of its two dropped programs names
	// colortex0. An even number would cancel and hide the whole thing, which is part of why this
	// class of bug surfaces so unpredictably.
	const asDeclared = [_][]const u8{&.{0}, &.{0}, &.{0}};
	const declared = resolveBindings(testingAllocator, &asDeclared);
	defer testingAllocator.free(declared);
	try testing.expectEqual(Side.main, declared[2].read[0]);

	// The same chain with the middle pass gone, which is what actually runs.
	const asRun = [_][]const u8{&.{0}, &.{0}};
	const run = resolveBindings(testingAllocator, &asRun);
	defer testingAllocator.free(run);
	try testing.expectEqual(Side.alt, run[1].read[0]);

	// The two answers differ, which is the whole point: resolving over the declared list rather
	// than the running one is not a near-miss, it selects the other texture entirely.
	try testing.expect(declared[2].read[0] != run[1].read[0]);
}

test "anything standing in for the gbuffers stage must take prepare's side, not the first pass's" {
	// The second caller obligation, the one `bridge.Pipeline.gbuffersBindings` exists to state. The
	// gbuffers stage is not part of this sequence: it draws *over* what `prepare` left, so its side
	// is `bindings[prepareCount]` - the state the first post-geometry pass reads.
	//
	// `bindings[0]` is the tempting shorthand and it is a different texture. Anything that stands in
	// for that stage and reaches for it lands on the side nothing reads - the world import when the
	// pack's terrain program failed to compile did exactly that.
	//
	// One `prepare` pass writing colortex0 is enough, and Nostalgia's `skyboxApply.fsh` is exactly
	// that. An even number would cancel and hide it, which is why this only shows up on some packs.
	const prepareCount = 1;
	const passes = [_][]const u8{&.{0}, &.{0}, &.{0}};
	const bindings = resolveBindings(testingAllocator, &passes);
	defer testingAllocator.free(bindings);

	try testing.expectEqual(Side.main, bindings[0].read[0]);
	try testing.expectEqual(Side.alt, bindings[prepareCount].read[0]);
	// They differ, which is the whole point: reaching for the wrong one is not a near-miss, it
	// selects the other texture.
	try testing.expect(bindings[0].read[0] != bindings[prepareCount].read[0]);

	// And the rule that makes `bindings[prepareCount]` the right answer rather than merely a
	// different one: the side geometry uses is the side the last `prepare` pass *wrote*.
	try testing.expectEqual(bindings[0].write[0], bindings[prepareCount].read[0]);
}

test "targets a pass does not write keep their side" {
	const drawBuffers = [_][]const u8{&.{0}, &.{1}, &.{ 0, 1 }};
	const bindings = resolveBindings(testingAllocator, &drawBuffers);
	defer testingAllocator.free(bindings);

	try testing.expectEqual(Side.main, bindings[0].read[1]);
	// Pass 1 reads colortex0's alt (pass 0 flipped it) but colortex1 is still untouched.
	try testing.expectEqual(Side.alt, bindings[1].read[0]);
	try testing.expectEqual(Side.main, bindings[1].read[1]);
	// By pass 2 both have been flipped exactly once.
	try testing.expectEqual(Side.alt, bindings[2].read[0]);
	try testing.expectEqual(Side.alt, bindings[2].read[1]);
}

test "a target written twice by one pass ends up back where it started" {
	// Degenerate but legal: `/* DRAWBUFFERS:00 */`. Two flips cancel, so the next pass reads the
	// same side this one did - which is the honest outcome, since the pass wrote both textures.
	const drawBuffers = [_][]const u8{&.{ 0, 0 }, &.{0}};
	const bindings = resolveBindings(testingAllocator, &drawBuffers);
	defer testingAllocator.free(bindings);
	try testing.expectEqual(Side.main, bindings[1].read[0]);
}

test "the shadow colour pair takes the same walk, and rests on main when nothing composites it" {
	// Kappa's shape: one `shadowcomp` pass drawing shadowcolor0 over what the shadow pass wrote.
	// It reads `main`, writes `alt`, and every consumer afterwards reads the `alt` it left.
	const drawBuffers = [_][]const u8{&.{0}};
	const bindings = resolveBindings(testingAllocator, &drawBuffers);
	defer testingAllocator.free(bindings);
	try testing.expectEqual(Side.main, bindings[0].read[0]);
	try testing.expectEqual(Side.alt, bindings[0].write[0]);
	try testing.expect(finalState(&drawBuffers).isFlipped(0));
	try testing.expect(!finalState(&drawBuffers).isFlipped(1));
	// The defaults every other pass carries, and the bridge's answer with no chain at all.
	const untouched = PassBindings{};
	try testing.expectEqual(Side.main, untouched.shadowRead[0]);
	try testing.expectEqual(Side.main, untouched.shadowWrite[1]);
}

test "an empty pass list resolves to nothing" {
	const bindings = resolveBindings(testingAllocator, &.{});
	defer testingAllocator.free(bindings);
	try testing.expectEqual(@as(usize, 0), bindings.len);
}

test "a texture override lapses once the chain has written its buffer, and not before" {
	// Bliss's shape: `texture.composite.colortex6` is blue noise for the first composites, then
	// `composite4` draws to colortex6 and every later pass expects its own data there. The prefix
	// of the chain ahead of each pass is what decides it (`ProgramSamplers.java:244`).
	const drawBuffers = [_][]const u8{&.{0}, &.{0}, &.{ 0, 6 }, &.{0}, &.{6}};
	try testing.expect(!writtenTargets(drawBuffers[0..2]).contains(6)); // composite4 itself still reads the noise
	try testing.expect(writtenTargets(drawBuffers[0..3]).contains(6)); // the pass after it reads the buffer
	try testing.expect(writtenTargets(drawBuffers[0..5]).contains(6));
	// A buffer written twice is still written, which is what parity alone would get wrong.
	try testing.expect(!finalState(drawBuffers[0..5]).isFlipped(6));
	try testing.expect(writtenTargets(drawBuffers[0..5]).contains(6));
}
