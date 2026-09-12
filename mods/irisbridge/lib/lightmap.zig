//! Collapsing Cubyz's light onto Minecraft's lightmap scalars.
//!
//! Cubyz carries two RGB triples - sun and block - where Minecraft has two numbers. Every place
//! that hands light to a pack has to make the same reduction, and the reductions have to agree:
//! the vertex prologue's `lmcoord` and the `eyeBrightness` uniform describe the same light, and a
//! pack comparing them against each other gets nonsense if they disagree.
//!
//! The awkward part, and the reason this is its own file with tests: the two sources are on
//! different scales. The prologue reads `cubyzLightData`, an SSBO that packs each channel into
//! five bits (0-31). `mesh_storage.getLight` reads the lighting data directly, a byte per channel
//! (0-255). They describe the same quantity and differ by a factor of eight, with nothing in either
//! type to say so.
//!
//! Free of GL and of game state, so it can be tested.

const std = @import("std");

/// Minecraft's lightmap ceiling: 15 levels of 16.
pub const eyeBrightnessMax = 240;

/// Cubyz's byte-per-channel light range, as `mesh_storage.getLight` reports it.
pub const lightChannelMax = 255;

/// One of Cubyz's 0-255 light channels on Minecraft's 0-240 `eyeBrightness` scale.
///
/// Clamped rather than merely scaled. Packs normalise this by dividing by 240 and feeding the
/// result to something shaped like `linStep(x, 0.1, 0.9)`, which saturates silently for any x above
/// 1 - so a value that overshoots the ceiling does not look wrong, it looks like a *constant*. That
/// is precisely how an eightfold scaling error here hid behind the very symptom it was meant to fix:
/// Nostalgia's `caveMult` stayed pinned at "open sky" either way.
pub fn toEyeBrightness(channel: u8) i32 {
	const scaled = @divTrunc(@as(i32, channel)*eyeBrightnessMax, lightChannelMax);
	return @min(scaled, eyeBrightnessMax);
}

/// Cubyz sun light above which a position counts as fully sky-exposed.
///
/// The two engines mean different things by "sky light" and a linear map between them is wrong at
/// the top of the range. Minecraft's is *sky access*: it stays at 15 straight down an open shaft and
/// in a shaded pit, dropping only once the position is genuinely enclosed. Cubyz's sun light
/// propagates and attenuates like any other light source, so eight blocks down an open pit it reads
/// about 199 of 255 - plainly "can see the sky", but not the plateau Minecraft would report.
///
/// Packs test that plateau exactly. Nostalgia's `caveMult` is `linStep(eyeBrightnessSmooth.y/240,
/// 0.1, 0.9)`, which only reaches 1.0 at `y >= 216`; below that its volumetric fog mixes air density
/// toward 250 - its valley haze, meant for deep ravines. At a linear 199 that leaves density ~35
/// permanently, everywhere, which is a sunlit haze the scene never escapes.
/// Three quarters of Cubyz's range. Chosen from measurement rather than taste: eight blocks down an
/// open pit reads 199, and 192 is the round number below that which still leaves a genuinely
/// enclosed cave - where sun light falls away toward zero - well down the ramp.
pub const skyExposureFull = 192;

/// Cubyz's sun-light channel on Minecraft's sky-light scale, saturating at full exposure.
///
/// Deliberately not the linear `toEyeBrightness`: this is a *semantic* conversion between two
/// different quantities, not a change of units. Compressing the top of Cubyz's range onto
/// Minecraft's plateau is an approximation, but it is an approximation of the right thing - below
/// the threshold the value still falls off smoothly, so entering a real cave still ramps cave fog in.
pub fn toSkyExposure(channel: u8) i32 {
	if(channel >= skyExposureFull) return eyeBrightnessMax;
	// Cubed, not linear. The plateau alone is not enough: packs also need the value to *collapse*
	// once sky access is lost, and Cubyz's sun light does not - it propagates like an ordinary light
	// and reaches far into a cave that Minecraft would report as pitch dark for sky.
	//
	// That difference is what keeps a sunbeam alive indoors. Nostalgia guards against exactly this
	// with `sunlight *= cave` (its UseLightleakPrevention), but the guard is proportional: at a
	// measured `cave` of 0.906 it removes 9% of the sunlight, where Minecraft would remove all of it.
	// A plateau plus a steep falloff reproduces both ends of Minecraft's behaviour, where a straight
	// scale reproduces neither.
	const normalised = @as(f32, @floatFromInt(channel))/@as(f32, skyExposureFull);
	return @intFromFloat(@round(normalised*normalised*normalised*@as(f32, eyeBrightnessMax)));
}

/// The vertex path does not use `toSkyExposure`'s curve. Making `lmcoord` agree with
/// `eyeBrightness` outright was tried and reverted: cubing collapses the band shaded ground lives in
/// - a raw 0.2 goes from 51/255 to 5/255, a raw 0.05 to exactly 0 - so shaded surfaces lost their
/// lightmap and rendered black. The two are not the same kind of quantity. `eyeBrightness` is a
/// per-frame *classifier* ("is the player in a cave"); `lmcoord` is a per-vertex value the pack both
/// shades from *and* gates direct sunlight on.
///
/// It still needs the sky-*access* semantics, though, just without the collapse. See
/// `skyAccessFull` below.

/// Cubyz sun light at which a surface counts as having full sky access, on the vertex path's 0..1
/// scale.
///
/// Chosen from a measurement, not from taste. `world0/deferred1.fsh` gates direct sunlight with
///
///     directSunlight *= sstep(unpack2x8(tex1.z).y, 0.1, 0.2);
///
/// so any surface whose sky lightmap reads below 0.2 loses its sunlight entirely - the shadow map
/// never gets a say. In Minecraft that guard never fires outdoors, because sky lightmap there is sky
/// *access* and sits at 15/15 in open shade; it only falls once a surface is genuinely enclosed.
/// Cubyz's sun light is attenuated *intensity*, so ordinary outdoor shade drops under the threshold
/// and goes black.
///
/// Decoding `colortex1.z` from a logged session showed the gate is the whole story, with no
/// exceptions across 32 surfaces:
///
///     sky 0.094-0.102 -> gate 0.000 -> lit/albedo 0.0020    (dead black)
///     sky 0.114-0.157 -> gate 0.05-0.60 -> lit/albedo 0.0054-0.0098
///     sky 0.243-0.965 -> gate 1.000 -> lit/albedo 0.038-4.68
///
/// Shaded-but-open surfaces measured 0.094 to 0.157. Saturating at 0.3 lifts those to 0.31-0.52,
/// clear of the gate with margin, while a torch-lit surface at 0.016 and a genuinely enclosed one at
/// 0 stay below it - so the guard still does the job it exists for.
pub const skyAccessFull = 0.3;

/// Cubyz sun light as Minecraft-style sky *access*: linear, saturating at `skyAccessFull`.
///
/// Deliberately a plateau with a linear ramp rather than the cube `toSkyExposure` uses. The cube
/// was the mistake last time: it crushed exactly the mid-range this needs to lift.
pub fn skyAccess(raw: f32) f32 {
	return @min(1.0, raw/skyAccessFull);
}

/// The strongest of an RGB triple.
///
/// Minecraft's lightmap is one scalar per source, so the colour has to go somewhere. Taking the
/// maximum is what the vertex prologue does for `lmcoord`, and keeping the two consistent matters
/// more than which reduction is chosen.
pub fn strongestChannel(rgb: [3]u8) u8 {
	return @max(rgb[0], @max(rgb[1], rgb[2]));
}

/// Minecraft's raw lightmap coordinate ceiling: light level 15 times 16, what `gl_MultiTexCoord1`
/// holds for a fully lit vertex under Iris (`VanillaTransformer.java:45`, `vec4(iris_UV2, 0, 1)`).
pub const rawLightmapMax: f32 = 240.0;

/// `gl_TextureMatrix[1]`, the lightmap matrix: Minecraft's `LightTexture` transform, which Iris
/// uploads as `iris_LightmapTextureMatrix` for every program that names `gl_TextureMatrix[1]`
/// (`BuiltinReplacementUniforms.java:12`, `VanillaTransformer.java:113`). Scale by 1/256 and add
/// 1/32, so the raw 0..240 coordinate lands on the texel centres of the 16x16 lightmap, 1/32 to
/// 31/32.
///
/// The prologue emits the raw coordinate and `uniforms.zig` uploads this. Packs split on which half
/// of the pair they use: Kappa, Nostalgia, BSL, Complementary and Solas multiply by the matrix,
/// while Bliss (`all_solid.vsh:215`, `/ 240.0`) and photon (`gbuffers_all_solid.vsh:97`,
/// `* rcp(240.0)`) read the raw value as a light level. Only the raw range with this matrix serves
/// both; identity with the centred coordinate emitted instead was right for the first group and
/// 240 times too small for the second, which read a world with no sky light anywhere.
pub const lightmapTextureMatrix = @import("main").vec.Mat4f{.rows = .{
	.{1.0/256.0, 0, 0, 1.0/32.0},
	.{0, 1.0/256.0, 0, 1.0/32.0},
	.{0, 0, 1.0/256.0, 1.0/32.0},
	.{0, 0, 0, 1},
}};

// MARK: tests

const testing = std.testing;

test "the lightmap matrix puts the raw range on Minecraft's texel centres" {
	const centred = lightmapTextureMatrix.mulVec(.{rawLightmapMax, rawLightmapMax, 0, 1});
	try testing.expectApproxEqAbs(@as(f32, 0.96875), centred[0], 1e-6);
	try testing.expectApproxEqAbs(@as(f32, 0.96875), centred[1], 1e-6);
	const dark = lightmapTextureMatrix.mulVec(.{0, 0, 0, 1});
	try testing.expectApproxEqAbs(@as(f32, 0.03125), dark[0], 1e-6);
	try testing.expectApproxEqAbs(@as(f32, 0.03125), dark[1], 1e-6);
}

test "sky access clears the pack's sunlight gate for shaded-but-open surfaces" {
	// `sstep(x, 0.1, 0.2)` in `world0/deferred1.fsh`. Measured surfaces are the test cases.
	const gate = struct {
		fn at(x: f32) f32 {
			const t = std.math.clamp((x - 0.1)/0.1, 0, 1);
			return t*t*(3 - 2*t);
		}
	};
	// Outdoor shade, measured at 0.094 to 0.157, must come out fully lit.
	try testing.expectApproxEqAbs(@as(f32, 1.0), gate.at(skyAccess(0.094)), 0.001);
	try testing.expectApproxEqAbs(@as(f32, 1.0), gate.at(skyAccess(0.157)), 0.001);
	// Genuinely enclosed must still be gated off, or the guard stops guarding.
	try testing.expectEqual(@as(f32, 0.0), gate.at(skyAccess(0.016)));
	try testing.expectEqual(@as(f32, 0.0), gate.at(skyAccess(0.0)));
	// Full daylight saturates rather than overshooting.
	try testing.expectEqual(@as(f32, 1.0), skyAccess(0.965));
	try testing.expectEqual(@as(f32, 1.0), skyAccess(1.0));
}

test "sky access never crushes the low end, unlike the cube that was reverted" {
	// The property whose absence caused the regression: monotonic, and never *below* the raw value.
	var previous: f32 = -1;
	var step: f32 = 0;
	while(step <= 1.0) : (step += 1.0/64.0) {
		const mapped = skyAccess(step);
		try testing.expect(mapped >= previous);
		try testing.expect(mapped >= step);
		previous = mapped;
	}
}

test "the scale ends at Minecraft's ceiling, not past it" {
	try testing.expectEqual(@as(i32, 0), toEyeBrightness(0));
	try testing.expectEqual(@as(i32, eyeBrightnessMax), toEyeBrightness(255));
}

test "no input can overshoot the ceiling" {
	// The property that would have caught the original bug. A pack's `x/240.0` normalisation
	// saturates above 1, so an out-of-range value is indistinguishable from a constant.
	for(0..256) |channel| {
		const converted = toEyeBrightness(@intCast(channel));
		try testing.expect(converted >= 0);
		try testing.expect(converted <= eyeBrightnessMax);
	}
}

test "sky exposure saturates where Minecraft would plateau" {
	// The property the linear map got wrong: an open pit reads ~199 in Cubyz and 240 in Minecraft.
	// Nostalgia needs >= 216 for caveMult to reach 1.0 and switch its valley haze off.
	try testing.expect(toSkyExposure(199) >= 216);
	try testing.expectEqual(@as(i32, eyeBrightnessMax), toSkyExposure(255));
	try testing.expectEqual(@as(i32, eyeBrightnessMax), toSkyExposure(skyExposureFull));
	// Still falls off below the plateau, so entering a real cave ramps cave fog in rather than
	// snapping between two states.
	// Steep below the plateau: sky access lost must collapse toward zero, not decay gently, or a
	// pack's cave guard has nothing to bite on.
	try testing.expect(toSkyExposure(120) < 70);
	try testing.expect(toSkyExposure(158) < 140);
	try testing.expectEqual(@as(i32, 0), toSkyExposure(0));
	// Never above the ceiling, whatever comes in.
	for(0..256) |channel| {
		const converted = toSkyExposure(@intCast(channel));
		try testing.expect(converted >= 0 and converted <= eyeBrightnessMax);
	}
}

test "a half-lit block reads as about half" {
	// Being merely *proportional* is not enough - it has to land in range, which is the difference
	// between the 0-255 source scale and the prologue's 0-31 one.
	const half = toEyeBrightness(128);
	try testing.expect(half > 110 and half < 130);
}

test "the five-bit scale would overshoot by about eight" {
	// Documents the mistake rather than just fixing it: scaling a 0-255 value as though it were the
	// SSBO's 0-31 one is the error that hid, and this states its size.
	const wrong = @divTrunc(@as(i32, 255)*eyeBrightnessMax, 31);
    try testing.expect(wrong > eyeBrightnessMax*7);
	try testing.expectEqual(@as(i32, eyeBrightnessMax), toEyeBrightness(255));
}

test "the strongest channel wins" {
	try testing.expectEqual(@as(u8, 9), strongestChannel(.{9, 3, 5}));
	try testing.expectEqual(@as(u8, 9), strongestChannel(.{3, 9, 5}));
	try testing.expectEqual(@as(u8, 9), strongestChannel(.{3, 5, 9}));
	try testing.expectEqual(@as(u8, 0), strongestChannel(.{0, 0, 0}));
}
