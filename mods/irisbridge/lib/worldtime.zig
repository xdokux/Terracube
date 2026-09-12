//! Cubyz's day cycle on Minecraft's tick clock.
//!
//! Packs do not read the time of day as a fraction. They read `worldTime`, an absolute Minecraft
//! tick in [0, 24000), and key hard-coded thresholds off it. Nostalgia alone has
//! `(worldTime > 23000 || worldTime < 12900)` for "is the sun the light source", seven overlapping
//! `clamp(worldTime, a, b)` ramps driving its time-of-day palette, and - the consequential one -
//! the sun direction its entire sky capture is painted around, in `skyboxPrep.vsh`:
//!
//!     float ang = fract(worldTime / 24000.0 - 0.25);
//!     sunDir    = vec3(-sin(ang * tau), cos(ang * tau) * sunRotationData);
//!
//! Cubyz's cycle is 12000 units long and starts at noon. Minecraft's is 24000 ticks and starts
//! at dawn. Handing `DayTime.dayTime` straight across got both the rate and the phase wrong: the
//! painted sun swept half a revolution per Cubyz day, at half speed, starting a quarter-turn out.
//! At Cubyz noon, with the real sun straight overhead at `(-0.014, 0.906, 0.423)`, the capture put
//! its sun at `(1.0, 0.006, 0.003)` - flat on the horizon, 90 degrees away.
//!
//! That is two suns. The sky is painted around this one; `lightDir`, the shadow map, the
//! volumetrics and the lens flare all come from `sunPosition`, which was right all along. Which of
//! the two looked like "the sun" depended on which way the camera faced, and a painted sun pinned at
//! horizon level is why the first report of this bug said the light "moves to the ground in the
//! opposite direction".
//!
//! The conversion below puts `fract(worldTime/24000 - 0.25)` on the same clock as the sun that
//! `matrix.celestialWorldDirection` is handed, so the two suns agree. They do not coincide to the
//! degree, and must not: Minecraft's sun does not move at a constant rate. `skyAngle` below is
//! the curve Minecraft applies to the linear tick before anything reads it as an angle, and every
//! pack that derives a direction from `worldTime` has that curve baked in - BSL writes it out in
//! every one of its programs (`ang = (ang + (cos(ang*pi)*-0.5 + 0.5 - ang)/3)*tau`) and never reads
//! `sunPosition` at all, Nostalgia's `skyboxPrep.vsh` above uses the linear form and so its painted
//! sun sits up to 12.6 degrees from the lit one around dawn and dusk under Iris too. The test at
//! the bottom pins that discrepancy at Minecraft's own size rather than at zero.
//!
//! Free of GL and of game state, so it can be tested.

const std = @import("std");

/// Minecraft's day, in ticks.
///
/// Not a tunable. Packs divide by the literal 24000 and compare against literal tick counts, so
/// this is the number they have already committed to.
pub const ticksPerDay = 24000;

/// The Minecraft tick at which the sun is highest.
///
/// Minecraft's day starts at dawn, Cubyz's at noon, and this quarter-day is the whole of the
/// difference in phase.
pub const noonTick = ticksPerDay/4;

/// Cubyz's day cycle length, in the units `game.DayTime.dayTime` counts.
///
/// Mirrors `game.DayTime.dayCycleLength`, which is not public. Kept as a named constant rather than
/// a bare 12000 at the call site because it appears in a ratio with `ticksPerDay`, and the two are
/// easy to mistake for each other.
pub const cubyzDayLength = 12000;

/// Cubyz's monotonic game time as a Minecraft tick count, dawn-relative and never wrapping.
///
/// `worldTime` and `worldDay` are both slices of this, and deriving them from one running total is
/// what keeps them consistent: the pack's `worldAnimTime` is `worldDay % 48 + worldTime/24000.0`,
/// which is only the smooth ramp it is meant to be if the day counter ticks over on the same
/// instant the tick counter wraps.
pub fn toMinecraftTicks(gameTime: i64) i64 {
	return @divFloor(gameTime*ticksPerDay, cubyzDayLength) + noonTick;
}

/// The `worldTime` uniform: Minecraft ticks since dawn, in [0, 24000).
pub fn worldTime(gameTime: i64) i32 {
	return @intCast(@mod(toMinecraftTicks(gameTime), ticksPerDay));
}

/// The `worldDay` uniform: whole Minecraft days elapsed, incrementing at dawn.
pub fn worldDay(gameTime: i64) i32 {
	return @intCast(@divFloor(toMinecraftTicks(gameTime), ticksPerDay));
}

/// The `moonPhase` uniform: Minecraft's eight-night lunar cycle, 0 a full moon at day 0, 4 a new
/// moon (`DimensionType.moonPhase`: `dayTime / 24000 % 8`; Iris reports `level.getMoonPhase()`).
///
/// This used to be a constant 0, listed as "no lunar cycle", which made every night a full moon:
/// photon draws its moon as a fully lit disc at `moon_luminance` 10 with `moon_phase_brightness`
/// at 1.0 and lights the world by it, BSL scales `lightNight` by `moonPhaseMultiplier[moonPhase]`,
/// and Kappa and Nostalgia read the phase too. In Minecraft that night comes once in eight; the
/// bridge served it every night, and the user read the disc as the sun. The cycle is a function of
/// the day counter the bridge already keeps, so there was never a reason to hold it at zero.
pub fn moonPhase(gameTime: i64) i32 {
	return @intCast(@mod(worldDay(gameTime), 8));
}

/// Minecraft's sky angle for the current tick, as a fraction of a turn: 0 with the sun overhead,
/// 0.5 at midnight, and 0.25 with the sun on the western horizon.
///
/// The tick is linear; the angle is not. `DimensionType.timeOfDay` takes the linear fraction
/// `d = fract(dayTime/24000 - 0.25)` and returns `(2*d + 0.5 - cos(d*pi)/2)/3`, which is what every
/// consumer of the sun's position reads: Iris builds `sunPosition`, `sunAngle`, `shadowLightPosition`
/// and the shadow camera from it (`CelestialUniforms.getSkyAngle`, `ShadowMatrices`). The curve
/// leaves noon and midnight where the linear clock puts them and moves dawn and dusk by 12.4
/// degrees: at tick 0 the sun is 12.4 degrees below the eastern horizon, at tick 12000 still 12.4
/// above the western one, and it crosses the horizon at ticks 23214 and 12786. The gap between
/// the curve and the line peaks at 12.6 degrees a little before each of those.
///
/// Packs are calibrated to those numbers. BSL switches its light vector from sun to moon at
/// `timeAngle` 0.5325 and 0.9675 (ticks 12780 and 23220) and fades its shadows out around them;
/// Nostalgia lights its clouds by the sun for `worldTime < 12900`. Fed a sun that sets at tick
/// 12000, all of that fires 780 ticks late, and a pack that derives the sun from `worldTime`
/// itself, as BSL does in every program, shades with a sun up to 12.4 degrees from the one the
/// bridge cast the shadow map from. That is a shadow that does not line up with the face it falls
/// from, and it is worst at exactly the low sun angles where shadows are longest.
pub fn skyAngle(gameTime: i64) f32 {
	const ticks = @as(f32, @floatFromInt(@mod(toMinecraftTicks(gameTime), ticksPerDay)));
	const raw = ticks/@as(f32, ticksPerDay) - 0.25;
	const linear = raw - @floor(raw);
	const eased = 0.5 - @cos(linear*std.math.pi)/2.0;
	return (linear*2.0 + eased)/3.0;
}

const testing = std.testing;
const matrix = @import("matrix.zig");

test "the four cardinal times land on Minecraft's ticks for them" {
	// Cubyz's cycle starts at noon and midnight is at half of it, per `game.DayTime`.
	try testing.expectEqual(@as(i32, 6000), worldTime(0)); // noon
	try testing.expectEqual(@as(i32, 12000), worldTime(cubyzDayLength/4)); // sunset
	try testing.expectEqual(@as(i32, 18000), worldTime(cubyzDayLength/2)); // midnight
	try testing.expectEqual(@as(i32, 0), worldTime(cubyzDayLength*3/4)); // dawn
}

test "one Cubyz cycle is one Minecraft day" {
	try testing.expectEqual(worldTime(0), worldTime(cubyzDayLength));
	try testing.expectEqual(@as(i32, 0), worldDay(0));
	// The day counter turns over at dawn, where `worldTime` wraps, not at Cubyz's noon.
	try testing.expectEqual(@as(i32, 0), worldDay(cubyzDayLength*3/4 - 1));
	try testing.expectEqual(@as(i32, 1), worldDay(cubyzDayLength*3/4));
}

test "worldAnimTime is monotonic across the wrap" {
	// `uniform.float.worldAnimTime = worldDay % 48 + worldTime / 24000.0`. A backwards step here is a
	// visible jolt in every cloud animation, and is what an unshifted day counter produces.
	var previous: f32 = -1;
	var gameTime: i64 = 0;
	while(gameTime < cubyzDayLength*2) : (gameTime += 37) {
		const value = @as(f32, @floatFromInt(@mod(worldDay(gameTime), 48))) +
			@as(f32, @floatFromInt(worldTime(gameTime)))/@as(f32, ticksPerDay);
		try testing.expect(value > previous);
		previous = value;
	}
}

/// The Cubyz game time at which `worldTime` reads the given Minecraft tick.
fn gameTimeAtTick(tick: i64) i64 {
	return @mod(@divFloor((tick - noonTick)*cubyzDayLength, ticksPerDay), cubyzDayLength);
}

test "the moon runs Minecraft's eight-night cycle from the day counter" {
	// Unwrapped game time for an absolute tick, since the cycle spans eight days.
	const at = struct {
		fn tick(absolute: i64) i64 {
			return @divFloor((absolute - noonTick)*cubyzDayLength, ticksPerDay);
		}
	};
	// Day 0 is a full moon, and the phase turns over where `worldDay` does: at dawn.
	try testing.expectEqual(@as(i32, 0), moonPhase(at.tick(6000)));
	try testing.expectEqual(@as(i32, 0), moonPhase(at.tick(23998)));
	try testing.expectEqual(@as(i32, 1), moonPhase(at.tick(24000)));
	try testing.expectEqual(@as(i32, 4), moonPhase(at.tick(4*ticksPerDay + 18000)));
	try testing.expectEqual(@as(i32, 7), moonPhase(at.tick(7*ticksPerDay)));
	try testing.expectEqual(@as(i32, 0), moonPhase(at.tick(8*ticksPerDay)));
}

test "the sky angle is Minecraft's curve, pinned to Iris's own numbers" {
	// `ShadowMatrices.Tests` in the Iris source: "When DayTime=0, skyAngle = 282 degrees. Thus,
	// sunAngle = shadowAngle = 0.03451777f". A linear clock would put dawn at 270 degrees exactly.
	const dawn = skyAngle(gameTimeAtTick(0));
	try testing.expectApproxEqAbs(@as(f32, 282.4264), dawn*360.0, 0.01);
	try testing.expectApproxEqAbs(@as(f32, 0.03451777), @mod(dawn + 0.25, 1.0), 1e-5);
	// Noon and midnight are where the linear clock has them; the curve only moves the transitions.
	try testing.expectApproxEqAbs(@as(f32, 0.0), skyAngle(gameTimeAtTick(6000)), 1e-6);
	try testing.expectApproxEqAbs(@as(f32, 0.5), skyAngle(gameTimeAtTick(18000)), 1e-6);
	// Dusk: the sun is still 12.4 degrees up at tick 12000 and sets at 12786, which is why BSL
	// hands the light over to the moon at `timeAngle` 0.5325 rather than at 0.5.
	try testing.expectApproxEqAbs(@as(f32, 77.5736), skyAngle(gameTimeAtTick(12000))*360.0, 0.01);
	try testing.expectApproxEqAbs(@as(f32, 90.0), skyAngle(gameTimeAtTick(12786))*360.0, 0.05);
	try testing.expectApproxEqAbs(@as(f32, 270.0), skyAngle(gameTimeAtTick(23214))*360.0, 0.05);
}

test "the sky angle advances monotonically through the day" {
	// The angle wraps at noon, where it is zero, so the walk starts there.
	var previous = skyAngle(gameTimeAtTick(noonTick));
	try testing.expectEqual(@as(f32, 0.0), previous);
	var elapsed: i64 = 2;
	while(elapsed < ticksPerDay) : (elapsed += 2) {
		const value = skyAngle(gameTimeAtTick(noonTick + elapsed));
		try testing.expect(value > previous);
		previous = value;
	}
	// One full turn per day, no more and no less.
	try testing.expect(previous < 1.0);
	try testing.expect(previous > 0.999);
}

test "the sky capture's sun matches the sun everything else is lit by, to Minecraft's own tolerance" {
	// The invariant the whole file exists for. `skyboxPrep.vsh` paints its sky around a sun derived
	// linearly from `worldTime`; `matrix.celestialWorldDirection` is what `lightDir`, the shadow
	// camera and `sunPosition` come from, through `skyAngle`. They are independent chains, so the
	// pack's formula is reproduced here verbatim and compared directly. Under Iris the two differ
	// by Minecraft's easing curve, nothing at noon and midnight and 12.4 degrees at dawn and dusk,
	// and that is the tolerance here: tighter would demand a sun Iris does not deliver either,
	// and looser would let the 90 degree error the header describes back in.
	const sunPathRotationDegrees: f32 = -25.0; // Nostalgia's default, and the tilt is the hard part
	const toRadians = std.math.pi/180.0;
	const sunRotationData = [2]f32{
		@cos(sunPathRotationDegrees*toRadians),
		-@sin(sunPathRotationDegrees*toRadians),
	};

	var widest: f32 = 0;
	var gameTime: i64 = 0;
	while(gameTime < cubyzDayLength) : (gameTime += 13) {
		const lit = matrix.celestialWorldDirection(sunPathRotationDegrees, skyAngle(gameTime)*360.0);

		// `float ang = fract(worldTime / 24000.0 - 0.25);` then `ang * tau`.
		const raw = @as(f32, @floatFromInt(worldTime(gameTime)))/@as(f32, ticksPerDay) - 0.25;
		const angle = (raw - @floor(raw))*std.math.tau;
		const painted = [3]f32{
			-@sin(angle),
			@cos(angle)*sunRotationData[0],
			@cos(angle)*sunRotationData[1],
		};

		const cosine = std.math.clamp(lit[0]*painted[0] + lit[1]*painted[1] + lit[2]*painted[2], -1.0, 1.0);
		const separation = std.math.acos(cosine)/toRadians;
		// The curve is 12.4 degrees from the line at ticks 0 and 12000 and peaks at 12.6 a little
		// before each, where `sin(d*pi) = 2/pi`.
		try testing.expect(separation < 12.7);
		widest = @max(widest, separation);

		// Exact where Minecraft is exact.
		const tick = worldTime(gameTime);
		if(tick == 6000 or tick == 18000) try testing.expect(separation < 0.05);
	}
	// And the discrepancy is real, not a rounding artefact: the curve is being applied.
	try testing.expect(widest > 12.5);
}

test "the unfixed conversion is the 90 degree error that was observed" {
	// Guards the diagnosis rather than the fix: if this ever stops holding, the reasoning in the
	// header no longer describes the code and the header is the thing to correct.
	const raw = @as(f32, 0)/@as(f32, ticksPerDay) - 0.25; // worldTime = DayTime.dayTime = 0 at noon
	const angle = (raw - @floor(raw))*std.math.tau;
	try testing.expectApproxEqAbs(@as(f32, 1.0), -@sin(angle), 1e-3); // painted sun on the horizon
	// ...while the sun everything else uses is directly overhead.
	try testing.expectApproxEqAbs(@as(f32, 0.906), matrix.celestialWorldDirection(-25.0, 0)[1], 1e-3);
}
