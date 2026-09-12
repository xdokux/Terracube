//! The uniform set packs expect, sourced from Cubyz state.
//!
//! Field names in `Values` *are* the GLSL uniform names, so adding a uniform is one field plus one
//! line in `capture`. Locations are resolved once per program rather than looked up per frame -
//! a pack like Nostalgia has ~50 programs and this set has ~60 entries, and re-querying all of
//! them every frame is thousands of driver round-trips for values that never move.
//!
//! Where Cubyz genuinely has no equivalent (weather, potion effects, held items) the uniform is
//! given a documented constant rather than an invented one. A pack reading `rainStrength` will
//! see a believable "never raining" rather than noise, and the list of such stubs is written down
//! below instead of being buried in the code.

const std = @import("std");

const main = @import("main");
const c = main.c;
const game = main.game;
const renderer = main.renderer;
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec2f = vec.Vec2f;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;

const matrix = @import("matrix.zig");
const biomemap = @import("biomemap.zig");
const lightmap = @import("lightmap.zig");
const worldtime = @import("worldtime.zig");
const pack = @import("pack.zig");
const smoothing = @import("smoothing.zig");

/// One frame's worth of uniform values.
///
/// Every field name is a GLSL uniform name exactly as packs spell it.
pub const Values = struct {
	// Matrices. `gbufferModelView` carries the Z-up to Y-up basis change, so everything the pack
	// derives from it is already in Minecraft's world orientation.
	gbufferModelView: Mat4f = Mat4f.identity(),
	gbufferModelViewInverse: Mat4f = Mat4f.identity(),
	gbufferPreviousModelView: Mat4f = Mat4f.identity(),
	gbufferProjection: Mat4f = Mat4f.identity(),
	gbufferProjectionInverse: Mat4f = Mat4f.identity(),
	gbufferPreviousProjection: Mat4f = Mat4f.identity(),
	shadowModelView: Mat4f = Mat4f.identity(),
	shadowModelViewInverse: Mat4f = Mat4f.identity(),
	shadowProjection: Mat4f = Mat4f.identity(),
	shadowProjectionInverse: Mat4f = Mat4f.identity(),

	// Camera, in the pack's Y-up world space.
	cameraPosition: Vec3f = @splat(0),
	previousCameraPosition: Vec3f = @splat(0),
	eyeAltitude: f32 = 0,

	// Celestial, in view space, matching Iris's construction.
	sunPosition: Vec3f = @splat(0),
	moonPosition: Vec3f = @splat(0),
	shadowLightPosition: Vec3f = @splat(0),
	upPosition: Vec3f = @splat(0),
	/// The celestial frame's other two axes in view space, `matrix.celestialAxis` at `(1, 0, 0)`
	/// and `(0, 0, 1)`: the edges of the sun and moon quads `bridge.drawCelestialBodies` builds.
	/// Not a pack uniform - no program declares the name, so the upload skips it - but carried here
	/// because they are computed from the same clock as `sunPosition` and must never drift from it.
	cubyz_celestialX: Vec3f = .{1, 0, 0},
	cubyz_celestialZ: Vec3f = .{0, 0, 1},
	sunAngle: f32 = 0,
	shadowAngle: f32 = 0,

	// Time.
	frameTimeCounter: f32 = 0,
	frameTime: f32 = 0,
	frameCounter: i32 = 0,
	worldTime: i32 = 0,
	worldDay: i32 = 0,
	moonPhase: i32 = 0,

	// Viewport.
	viewWidth: f32 = 1,
	viewHeight: f32 = 1,
	aspectRatio: f32 = 1,
	near: f32 = 0.1,
	far: f32 = 1000,
	// Distant Horizons' planes and chunk radius, which Iris uploads whether or not that mod is
	// installed (`CommonUniforms.java:168-170`): both planes read 0.01 and the radius is the
	// vanilla render distance without it (`DHCompat.java:94-118`). Bliss reads the planes in helper
	// functions declared outside any `DISTANT_HORIZONS` guard, so the values a pack sees have to
	// be Iris's rather than an unbound zero. The DH matrices are not supplied: nothing in the 1.7.3
	// tree uploads a uniform under `dhProjection` or its siblings, so there is nothing to match.
	dhNearPlane: f32 = 0.01,
	dhFarPlane: f32 = 0.01,
	dhRenderDistance: i32 = 12,

	// Atmosphere.
	fogColor: Vec3f = @splat(0),
	skyColor: Vec3f = @splat(0),
	fogDensity: f32 = 0,
	fogStart: f32 = 0,
	fogEnd: f32 = 1000,
	fogMode: i32 = 0,

	// Player state.
	isEyeInWater: i32 = 0,
	// Iris's player-state set (`IrisExclusiveUniforms`, `CommonUniforms`). Sourced from Cubyz where
	// it has the concept - crouching, standing on ground, health - and documented constants where
	// it does not; the constants are listed in `unsupported`. Health and hunger are fractions of
	// their maxima, as Iris reports them; the maxima are raw.
	currentPlayerHealth: f32 = 1,
	maxPlayerHealth: f32 = 20,
	currentPlayerHunger: f32 = 1,
	maxPlayerHunger: f32 = 20,
	currentPlayerArmor: f32 = 0,
	maxPlayerArmor: f32 = 50,
	currentPlayerAir: f32 = 1,
	maxPlayerAir: f32 = 300,
	isSpectator: i32 = 0,
	is_sneaking: i32 = 0,
	is_sprinting: i32 = 0,
	is_hurt: i32 = 0,
	is_invisible: i32 = 0,
	is_burning: i32 = 0,
	is_on_ground: i32 = 0,
	// The biome under the player, by name equivalence to Minecraft's - see `biomemap.zig`. The
	// defaults are its plains fallback, which is neutral where an unsupplied zero reads as arctic.
	biome: i32 = -1,
	biome_category: i32 = @intFromEnum(biomemap.fallback.category),
	biome_precipitation: i32 = @intFromEnum(biomemap.fallback.precipitation),
	temperature: f32 = biomemap.fallback.temperature,
	rainfall: f32 = biomemap.fallback.downfall,
	// World information, at Minecraft's defaults: the pack's frame already puts sea level at 64,
	// so the matching bedrock and cloud heights are the ones its constants were tuned against.
	bedrockLevel: i32 = -64,
	heightLimit: i32 = 256,
	cloudHeight: f32 = 192,
	/// Camera-relative position of the nearest lightning bolt, `.w` nonzero while one exists.
	/// Cubyz has no weather, so this is the "none" value - and a real field rather than an
	/// absence, because photon smooths it into a flash term and an unbound uniform fails that
	/// expression outright.
	lightningBoltPosition: vec.Vec4f = @splat(0),
	/// The End's flash: an intensity over 0..1 and a camera-relative position. An Iris uniform
	/// newer than the 1.7.3 source in this tree, read by BSL, Complementary and Solas. Cubyz has no
	/// End, so both hold the "no flash" value - as fields rather than absences, because
	/// Complementary chains `min(endFlashIntensity, 0.5)` through three custom uniforms, and an
	/// unbound name fails that chain outright where a bound zero evaluates.
	endFlashIntensity: f32 = 0,
	endFlashPosition: Vec3f = @splat(0),
	eyeBrightness: vec.Vec2i = .{0, 0},
	eyeBrightnessSmooth: vec.Vec2i = .{0, 0},
	nightVision: f32 = 0,
	blindness: f32 = 0,
	darknessFactor: f32 = 0,
	/// Minecraft's brightness slider, which Iris supplies from `client.options.gamma()` over 0..1.
	///
	/// Minecraft's default is 0.5, and this was 1.0 - the top of the range. Cubyz has no
	/// brightness setting at all, so there is nothing to source it from and it is a documented
	/// constant like the rest of this block; the constant simply has to be the one a default install
	/// reports, not the maximum.
	///
	/// It was invisible to every check here, which is why it sat wrong: it is a `Values` field, so
	/// `coverage.zig` counts it as supplied, and it was missing from `unsupported`, so nothing
	/// flagged it as a stand-in either. Packs read it as an ordinary player setting and scale real
	/// lighting by it - Complementary alone uses it sixteen times through `vsBrightness`, where 1.0
	/// against 0.5 raises its minimum-lighting floor from 0.027 to 0.049, night ambient from 1.935 to
	/// 2.32, volumetric light by a third, and moves `composite3`'s depth-of-field focus term
	/// `pow2(vsBrightness)` from 0.25 to 1.0.
	screenBrightness: f32 = 0.5,
	hideGUI: i32 = 0,

	// Weather. Cubyz has none yet; see `unsupported` below.
	rainStrength: f32 = 0,
	wetness: f32 = 0,

	// Per-draw identity, overwritten by the gbuffers stage when it runs.
	entityId: i32 = 0,
	blockEntityId: i32 = 0,
	heldItemId: i32 = -1,
	heldItemId2: i32 = -1,
	heldBlockLightValue: i32 = 0,
	heldBlockLightValue2: i32 = 0,

	// MARK: filling Iris's set
	//
	// Everything below was found by `coverage.zig` rather than by reading packs: it enumerates the
	// uniforms each pack declares and subtracts what the bridge supplies. An unsupplied uniform
	// links cleanly and reads zero, so these were all rendering wrong in silence.

	/// Camera position split into integer and fractional parts.
	///
	/// Iris added these because `cameraPosition` is a float and loses sub-block precision a few tens
	/// of thousands of blocks out, which is exactly where voxel worlds get interesting. Cubyz already
	/// carries the same split internally - the chunk shader takes `playerPositionInteger` and
	/// `playerPositionFraction` for this very reason - so this is a rename rather than a conversion.
	cameraPositionInt: vec.Vec3i = .{0, 0, 0},
	cameraPositionFract: Vec3f = @splat(0),
	previousCameraPositionInt: vec.Vec3i = .{0, 0, 0},
	previousCameraPositionFract: Vec3f = @splat(0),

	/// Eye position in world space, and relative to the feet. Cubyz has both directly.
	eyePosition: Vec3f = @splat(0),
	relativeEyePosition: Vec3f = @splat(0),
	/// Where the camera is looking, in the pack's Y-up world space.
	playerLookVector: Vec3f = @splat(0),
	playerBodyVector: Vec3f = @splat(0),

	/// Size of one block texture. Cubyz's textures are array layers rather than an atlas, so this is
	/// the layer size - which is what packs actually use it for (texel-size maths for parallax and
	/// sharpening), not for locating a tile within a sheet.
	atlasSize: vec.Vec2i = .{0, 0},

	/// Scene depth at the centre of the screen, smoothed over time.
	///
	/// Packs drive depth-of-field focus and auto-exposure from this. Left at zero the focal plane
	/// sits on the near plane and every exposure estimate reads "looking at something infinitely
	/// close", which is one of the ways an image ends up uniformly washed out.
	centerDepthSmooth: f32 = 1,

	/// Damage/effect tint for the entity being drawn. Alpha 0 means "no tint", which is the value
	/// for everything Cubyz draws, since it has no entity damage flash.
	entityColor: vec.Vec4f = @splat(0),

	/// Which stage of the frame is being drawn. Packs branch on it to tell terrain from entities
	/// from the sky. Set per draw by `renderStageFor`, so it is a real value rather than a constant.
	renderStage: i32 = 0,

	/// The alpha below which the current draw's fragments are cut out.
	///
	/// Per draw rather than per frame, like `renderStage`, and set by whichever gbuffers bind is
	/// running - the default here is the opaque one, since that is what a post-chain pass would read
	/// and what a stage that forgets to set it should get.
	///
	/// A pack reads this and cuts its own fragments with it, so leaving it unsupplied is not a
	/// missing feature, it is the feature switched off: GL hands an unbound uniform zero, and
	/// `if(albedo.a < 0.0) discard` never fires. Sundial's `Terrain.frag:82` is exactly that line,
	/// unconditional in its main path, and 232 of Cubyz's 665 albedo textures carry fully
	/// transparent texels - so every leaf block would render as a solid cube. Iris supplies it under
	/// this name explicitly, commented "Optifine compatibility" (`IrisInternalUniforms:53`).
	///
	/// The values are Iris's own, from `ShaderKey`, and the alpha content of Cubyz's textures was
	/// measured against each rather than assumed:
	///
	/// - Opaque terrain: `TERRAIN_CUTOUT`, 0.1. Cubyz's opaque albedo is strictly binary - every
	///   texel is 0 or 255 across all 665 textures - so any threshold in `(0, 1)` behaves
	///   identically here and following Iris costs nothing. Minecraft splits solid (test off) from
	///   cutout (0.1) into two passes where Cubyz has one draw carrying both, and it is the *cutout*
	///   pass this stands in for, because Cubyz's own `chunk_fragment.frag` discards on alpha too.
	///   The value alone was never enough: the test itself is something Iris appends to the
	///   pack's fragment `main`, and the bridge does the same now - see `glsl.Options.alphaTest`.
	/// - Translucent: `TERRAIN_TRANSLUCENT`, 0.0001. The five textures with partial alpha are
	///   all `.transparent = true` - water at 0.42, resin 0.55, ice 0.64, amber 0.60 and 0.71 - so
	///   the opaque threshold here would discard water and resin entirely. This is the one place
	///   the number genuinely matters on this asset set.
	/// - Shadow: `SHADOW_TERRAIN_CUTOUT`, 0.1. Same binary set; at zero, leaves cast the shadow
	///   of a solid cube.
	alphaTestRef: f32 = 0.5,

	/// `pi`, because packs read it as a uniform rather than defining it.
	pi: f32 = std.math.pi,

	/// World shape. Cubyz has no dimension ceiling and does have a sky.
    hasCeiling: i32 = 0,
	hasSkylight: i32 = 1,
	/// Sea level, in the same frame as `cameraPosition` and `eyeAltitude`.
	///
	/// Cubyz's own sea level is z = 0, but positions are handed to the pack with `matrix.seaLevel`
	/// added so that altitudes read as absolute Minecraft heights. Reporting 0 here while shifting
	/// those would have the pack measuring height above a sea level 64 blocks below the one its
	/// terrain appears to sit on.
	seaLevel: i32 = @intFromFloat(matrix.seaLevel),
	ambientLight: f32 = 0,

	// Documented constants: Cubyz has no equivalent concept. Listed in `unsupported` below.
	darknessLightFactor: f32 = 0,
	thunderStrength: f32 = 0,
	playerMood: f32 = 0,
	constantMood: f32 = 0,
	currentRenderedItemId: i32 = -1,
	currentSelectedBlockId: i32 = 0,
	currentColorSpace: i32 = 0,
	fogShape: i32 = 0,
	isRightHanded: i32 = 1,
	firstPersonCamera: i32 = 1,
};

/// Iris's own alpha-test references, rather than literals at the call sites.
///
/// Spelled with Iris's names, not this bridge's, so each is greppable in `AlphaTests.java` and
/// the `ShaderKey` row that selects it can be checked rather than taken on trust. Which stage picks
/// which, and the measurement behind each, is on `Values.alphaTestRef`.
pub const alphaTest = struct {
	/// `AlphaTests.NON_ZERO_ALPHA` - `SKY_BASIC_COLOR`, `BASIC_COLOR`. Cuts genuinely empty
	/// texels and nothing else, which is what keeps Cubyz's 0.42-alpha water on screen. This is
	/// what the water draw reports; Iris's `TERRAIN_TRANSLUCENT` actually carries `AlphaTests.OFF`
	/// (`ShaderKey.java:28`), so no test is injected there and the value only reaches a pack that
	/// reads the uniform itself.
	pub const nonZeroAlpha: f32 = 0.0001;
	/// `AlphaTests.ONE_TENTH_ALPHA` - `TERRAIN_CUTOUT` and `SHADOW_TERRAIN_CUTOUT`
	/// (`ShaderKey.java:27`, `:67`). There is no half-alpha constant in Iris 1.7.3; an earlier
	/// `halfAlpha = 0.5` here cited one that does not exist, harmless only because Cubyz's opaque
	/// alpha is binary. Gone, so the claim cannot be re-read as a fact.
	pub const oneTenthAlpha: f32 = 0.1;
};

/// Uniforms deliberately reported as constants, because Cubyz has no equivalent concept.
///
/// Kept as a list so the gap is visible rather than implied. If Cubyz gains weather or status
/// effects, these are the entries to revisit.
pub const unsupported = [_][]const u8{
	"rainStrength", "wetness", "thunderStrength", // no weather system
	"nightVision", "blindness", "darknessFactor", "darknessLightFactor", // no status effects
	"screenBrightness", // no brightness/gamma setting in Cubyz; reported at Minecraft's default
	"heldItemId", "heldItemId2", "heldBlockLightValue", "heldBlockLightValue2", // held-item light is not modelled
	"playerMood", "constantMood", // no mood/cave-ambience timer
	"currentRenderedItemId", "currentSelectedBlockId", // no per-draw item identity yet
	"currentColorSpace", // output is always sRGB
	"fogShape", // Cubyz's fog is a density plus a height band, neither sphere nor cylinder
	"isRightHanded", "firstPersonCamera", // no third person or handedness setting
	"relativeEyePosition", // `playerPos` is already the eye, so the offset is not modelled
	"hideGUI",
	"currentPlayerHunger", "maxPlayerHunger", // no hunger
	"currentPlayerArmor", "maxPlayerArmor", // no armour
	"currentPlayerAir", "maxPlayerAir", // no drowning
	"isSpectator", "is_sprinting", "is_hurt", "is_invisible", "is_burning", // no such states
	"bedrockLevel", "heightLimit", "cloudHeight", // Minecraft's defaults, matching `seaLevel`
	"lightningBoltPosition", // no weather; the "no bolt" value
	"endFlashIntensity", "endFlashPosition", // no End dimension; the "no flash" value
	"dhNearPlane", "dhFarPlane", // no Distant Horizons; Iris's own values with the mod absent
};

const fields = @typeInfo(Values).@"struct".fields;

/// Uniform locations for one linked program, resolved once.
///
/// `-1` means the program does not use that uniform, which is the common case - most programs
/// touch a handful of the set - and uploading to `-1` is a no-op in GL, but skipping it avoids
/// the call entirely.
pub const Locations = struct {
	entries: [fields.len]c_int = @splat(-1),

	pub fn resolve(program: c_uint) Locations {
		var self = Locations{};
		inline for(fields, 0..) |field, index| {
			self.entries[index] = c.glGetUniformLocation(program, field.name.ptr);
		}
		return self;
	}
};

/// Uploads every uniform the program actually declares.
pub fn upload(values: *const Values, locations: *const Locations) void {
	inline for(fields, 0..) |field, index| {
		const location = locations.entries[index];
		if(location >= 0) {
			const value = @field(values, field.name);
			switch(field.type) {
				Mat4f => c.glUniformMatrix4fv(location, 1, c.GL_TRUE, @ptrCast(&value)),
				vec.Vec4f => c.glUniform4fv(location, 1, @ptrCast(&value)),
				Vec3f => c.glUniform3fv(location, 1, @ptrCast(&value)),
				Vec2f => c.glUniform2fv(location, 1, @ptrCast(&value)),
				vec.Vec3i => c.glUniform3iv(location, 1, @ptrCast(&value)),
				vec.Vec2i => c.glUniform2iv(location, 1, @ptrCast(&value)),
				f32 => c.glUniform1f(location, value),
				i32 => c.glUniform1i(location, value),
				else => @compileError("uniforms.Values has no upload rule for " ++ @typeName(field.type)),
			}
		}
	}
}

/// Uploads the fixed-function matrices the compatibility shim declares.
///
/// These are separate from `Values` because they are not shaderpack uniforms at all - no pack
/// names them. They are what `gl_ModelViewMatrix` and friends were rewritten into, so a pack that
/// writes `gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex` depends entirely on them. Left
/// unset they are zero, and every vertex collapses to the origin: geometry silently disappears
/// with no GL error and no compile failure.
/// The linear fog distances handed to packs, in blocks.
///
/// One definition, used by both the `fogStart`/`fogEnd` uniforms and the `gl_Fog` struct, so the two
/// cannot drift apart and describe different fog to the same shader.
///
/// Derived from the render distance because that is what it means: fog exists to hide the edge of
/// the loaded world, so it has to end where the world does. Cubyz's own `fogLower`/`fogHigher` are
/// altitudes and cannot answer this question at all.
fn fogDistances() struct {start: f32, end: f32} {
	const end: f32 = @floatFromInt(main.settings.renderDistance*main.chunk.chunkSize);
	return .{.start = end*0.75, .end = end};
}

/// How far Cubyz actually renders, in blocks - the far plane and the `far` uniform.
///
/// Not `renderDistance*chunkSize`. That is only the LOD-0 radius, 384 blocks at the defaults.
/// `mesh_storage.freeOldMeshes` keeps meshes out to `renderDistance*chunkSize << lod` for every
/// level up to `highestLod`, so the world extends `2^highestLod` further than full detail does -
/// 12288 blocks against 384. Cubyz's long view is most of what the game looks like.
///
/// Using the LOD-0 radius cost that twice over. It was the pack's projection far plane, so every
/// LOD chunk past 384 blocks was clipped; and `getFog` is `dist/far` against `fogStart` 0.3, so
/// what survived was fogged out from 115 blocks. The horizon sat where full detail ended.
///
/// This is a correction to a correction. `far` was `renderer.zFar` (65536) once, which spread fog
/// over the whole numeric range and washed the frame flat; moving it to the render distance was
/// right, but it picked the wrong render distance. The invariant that mattered then still holds
/// now: this must be the same number as the far plane in `glProjection`, because `depthLinear`
/// reconstructs distance from a depth only that projection wrote.
fn renderDistanceBlocks() f32 {
	const lod0: u32 = @as(u32, main.settings.renderDistance)*main.chunk.chunkSize;
	return @floatFromInt(lod0 << main.settings.highestLod);
}

/// Uploads `cubyz_Fog`, the stand-in for the compat `gl_Fog` struct.
///
/// Cubyz models fog as a density plus a height band; Minecraft's fixed-function fog is linear
/// between a start and end distance. There is no exact conversion, so the linear range is taken
/// from the render distance - which is where Minecraft's own fog ends too - and the density and
/// colour pass through unchanged. Packs overwhelmingly read `.color` and compare depth against
/// `.start`/`.end`, and those stay meaningful under this mapping.
fn uploadFog(program: c_uint) void {
	const colorLocation = c.glGetUniformLocation(program, "cubyz_Fog.color");
	const densityLocation = c.glGetUniformLocation(program, "cubyz_Fog.density");
	const startLocation = c.glGetUniformLocation(program, "cubyz_Fog.start");
	const endLocation = c.glGetUniformLocation(program, "cubyz_Fog.end");
	const scaleLocation = c.glGetUniformLocation(program, "cubyz_Fog.scale");
	// A program that never mentions `gl_Fog` has none of these, and asking for one costs a driver
	// round trip, so the cheapest check gates the rest.
	if(colorLocation < 0 and densityLocation < 0 and startLocation < 0 and endLocation < 0 and scaleLocation < 0) return;

	const world = game.world orelse return;
	const fog = world.dayTime.fog;
	const range = fogDistances();
	const start = range.start;
	const end = range.end;

	if(colorLocation >= 0) c.glUniform4f(colorLocation, fog.fogColor[0], fog.fogColor[1], fog.fogColor[2], 1);
	if(densityLocation >= 0) c.glUniform1f(densityLocation, fog.density);
	if(startLocation >= 0) c.glUniform1f(startLocation, start);
	if(endLocation >= 0) c.glUniform1f(endLocation, end);
	// Fixed-function precomputed this, and packs divide by it rather than recomputing.
	if(scaleLocation >= 0) c.glUniform1f(scaleLocation, 1.0/@max(end - start, 1.0));
}

/// Cubyz's sky colour with its time-of-day *brightness* but not its time-of-day *hue*.
///
/// Minecraft's `skyColor` dims from day to night while staying blue; the orange of a sunset comes
/// from the pack's own blend, not from this uniform. Cubyz instead tints per channel -
/// `fog.skyColor = biomeFog.skyColor * getSkyColorFactor()`, and that factor drops blue first while
/// red and green hold, so it sweeps through `(fading, 1, 0)`: pure green. Handing that over made
/// Nostalgia apply a sunset to an already-sunset colour and land on a green sky.
///
/// Handing over the raw `biomeFog` colour instead fixed the hue but made the gradient abrupt: the
/// zenith then held full daylight brightness at dusk, so it never travelled far enough to meet the
/// horizon band and the two met in a hard edge rather than a wide blend.
///
/// So: the biome's hue, scaled by the strongest surviving channel of Cubyz's own factor. The
/// strongest rather than the mean or the luminance because it is the one that keeps full daylight at
/// exactly 1.0 - any average would dim noon slightly as soon as a single channel began to fall.
///
/// The factor is recovered by division rather than read directly because `getSkyColorFactor` is
/// private to `game.DayTime`; both colours it is derived from are public fields.
fn hueStableSky(biome: Vec3f, tinted: Vec3f) Vec3f {
	var brightness: f32 = 0;
	inline for(0..3) |channel| {
		if(biome[channel] > 1e-6) brightness = @max(brightness, tinted[channel]/biome[channel]);
	}
	return biome*@as(Vec3f, @splat(std.math.clamp(brightness, 0, 1)));
}

/// Maps the fullscreen quad's `[0,1]` corners onto clip space: `(x, y) -> (2x - 1, 2y - 1)`.
///
/// This is what Minecraft has bound while a composite pass draws. The pass is a fullscreen blit, not
/// world rendering, so the fixed-function matrices at that moment describe the *quad*, and Iris binds
/// `gl_ModelViewMatrix` from `RenderSystem.getModelViewMatrix()` - whatever Minecraft currently has -
/// rather than from the world camera.
pub const fullscreenQuadProjection = Mat4f{.rows = .{
	.{2, 0, 0, -1},
	.{0, 2, 0, -1},
	.{0, 0, 1, 0},
	.{0, 0, 0, 1},
}};

const fullscreenQuadProjectionInverse = Mat4f{.rows = .{
	.{0.5, 0, 0, 0.5},
	.{0, 0.5, 0, 0.5},
	.{0, 0, 1, 0},
	.{0, 0, 0, 1},
}};

/// The eight `gl_TextureMatrix` slots as Minecraft leaves them: identity everywhere except the
/// lightmap's, which is `lightmap.lightmapTextureMatrix` - the prologue emits the raw 0..240
/// coordinate that matrix is written for.
fn uploadTextureMatrices(program: c_uint) void {
	const location = c.glGetUniformLocation(program, "cubyz_TextureMatrix");
	if(location < 0) return;
	var matrices: [8]Mat4f = @splat(Mat4f.identity());
	matrices[1] = lightmap.lightmapTextureMatrix;
	c.glUniformMatrix4fv(location, matrices.len, c.GL_TRUE, @ptrCast(&matrices));
}

/// The `gl_*` fixed-function matrices for a post-chain pass.
///
/// Composite, deferred, prepare and final passes draw one fullscreen quad, and packs are split on how
/// they position it. Nostalgia and Kappa write the mapping out by hand -
/// `gl_Position = vec4(gl_Vertex.xy*2.0 - 1.0, 0.0, 1.0)` - and never touch a matrix. Complementary
/// writes `gl_Position = ftransform()` in every one of its post-chain vertex stages, which is
/// `gl_ModelViewProjectionMatrix * gl_Vertex` and only produces a fullscreen quad if those matrices
/// describe the quad.
///
/// Handing a composite pass the world camera instead - which is what this bridge did - projects
/// the unit square as a one-block quad sitting at the world origin. The pack's entire post-chain then
/// renders into a small quadrilateral that swings around with the player's view, over a screen still
/// showing Cubyz's own output where nothing was drawn. Measured on a recording: a hard vertical edge
/// at exactly `width/2`, stable across 300 frames of camera motion, with the shape changing every
/// frame.
///
/// The `gbufferModelView`/`gbufferProjection` *uniforms* are untouched by this and must be: those are
/// how a composite pass reconstructs world positions from depth, and they are correct already. It is
/// only the compat `gl_` pair, which in a fullscreen blit means something else entirely.
pub fn uploadFullscreenMatrices(program: c_uint, values: *const Values) void {
	// Kept in the signature to match `uploadCompatMatrices`, so the two are interchangeable at a call
	// site and choosing between them is a deliberate one-word edit rather than a rewrite.
	_ = values;
	uploadFog(program);

	const identity = Mat4f.identity();
	setMatrix(program, "cubyz_ModelViewMatrix", identity);
	setMatrix(program, "cubyz_ModelViewMatrixInverse", identity);
	setMatrix(program, "cubyz_ProjectionMatrix", fullscreenQuadProjection);
	setMatrix(program, "cubyz_ProjectionMatrixInverse", fullscreenQuadProjectionInverse);
	setMatrix(program, "cubyz_ModelViewProjectionMatrix", fullscreenQuadProjection);

	const normalLocation = c.glGetUniformLocation(program, "cubyz_NormalMatrix");
	if(normalLocation >= 0) {
		const normal = [9]f32{1, 0, 0, 0, 1, 0, 0, 0, 1};
		c.glUniformMatrix3fv(normalLocation, 1, c.GL_TRUE, &normal);
	}

	uploadTextureMatrices(program);
}

pub fn uploadCompatMatrices(program: c_uint, values: *const Values) void {
	uploadFog(program);
	const modelView = values.gbufferModelView;
	const projection = values.gbufferProjection;

	setMatrix(program, "cubyz_ModelViewMatrix", modelView);
	setMatrix(program, "cubyz_ProjectionMatrix", projection);
	setMatrix(program, "cubyz_ModelViewProjectionMatrix", projection.mul(modelView));
	setMatrix(program, "cubyz_ModelViewMatrixInverse", values.gbufferModelViewInverse);
	setMatrix(program, "cubyz_ProjectionMatrixInverse", values.gbufferProjectionInverse);

	// The normal matrix is the inverse transpose of the model-view 3x3. The view matrix is a rigid
	// transform, so that is just its rotation part - but it is uploaded as a mat3, which GL will
	// not accept from a mat4.
	const normalLocation = c.glGetUniformLocation(program, "cubyz_NormalMatrix");
	if(normalLocation >= 0) {
		const r = modelView.rows;
		const normal = [9]f32{
			r[0][0], r[0][1], r[0][2],
			r[1][0], r[1][1], r[1][2],
			r[2][0], r[2][1], r[2][2],
		};
		c.glUniformMatrix3fv(normalLocation, 1, c.GL_TRUE, &normal);
	}

	// Packs index `gl_TextureMatrix[0]` for the block texture, identity, and `[1]` for the
	// lightmap, which is Minecraft's lightmap transform and not identity - see
	// `lightmap.lightmapTextureMatrix`.
	uploadTextureMatrices(program);
}

fn setMatrix(program: c_uint, name: [:0]const u8, value: Mat4f) void {
	const location = c.glGetUniformLocation(program, name.ptr);
	if(location >= 0) c.glUniformMatrix4fv(location, 1, c.GL_TRUE, @ptrCast(&value));
}

comptime {
	_ = &uploadCompatMatrices;
	// Zig analyses function bodies lazily, and nothing calls these until the pass chain is wired
	// up. Referencing them here forces the type checking now - in particular the `@compileError`
	// in `upload`'s switch, which is the guard against adding a `Values` field whose type has no
	// upload rule. Without this, that guard would sit dormant until much later.
	_ = &upload;
	_ = &Locations.resolve;
}

/// Carried between frames so the `Previous` matrices and camera position are real rather than
/// copies of the current ones - packs use the difference for motion blur and temporal reprojection,
/// and feeding them identical values silently disables both.
var previous: struct {
	modelView: Mat4f = Mat4f.identity(),
	projection: Mat4f = Mat4f.identity(),
	cameraPosition: Vec3f = @splat(0),
	cameraPositionInt: vec.Vec3i = .{0, 0, 0},
	cameraPositionFract: Vec3f = @splat(0),
	valid: bool = false,
} = .{};

/// The smoothed half of the eye-brightness pair.
///
/// Minecraft fades this rather than snapping it, and packs rely on that: `eyeBrightnessSmooth`
/// drives Nostalgia's `caveMult`, which switches volumetric fog between "sunlit outdoors" and
/// "unlit cave". Stepping it instantly would pop the whole fog volume the moment you crossed a cave
/// mouth, which is the artefact the smoothing exists to prevent.
pub const eyeBrightness = struct {
	var value: vec.Vec2f = .{0, 240};

	/// Equivalent to the old fixed 0.95 per frame at 60 fps: `-(1/60)/ln(0.95)`.
	const timeConstant = 0.325;

	pub fn smooth(target: vec.Vec2i, deltaTime: f32) vec.Vec2i {
		const wanted = vec.Vec2f{@floatFromInt(target[0]), @floatFromInt(target[1])};
		const factor: vec.Vec2f = @splat(smoothing.factor(deltaTime, timeConstant));
		value += (wanted - value)*factor;
		return .{@intFromFloat(@round(value[0])), @intFromFloat(@round(value[1]))};
	}

	/// Drops the fade, so a teleport or world change does not fade in from the old location's light.
	pub fn reset() void {
		value = .{0, 240};
	}
};

/// Scene depth at the centre of the screen, smoothed over time.
///
/// Packs focus depth-of-field and drive auto-exposure from this, and all three fixture packs read
/// it.
pub const centerDepth = struct {
	pub var value: f32 = 1;

	/// Equivalent to the old fixed 0.9 per frame at 60 fps: `-(1/60)/ln(0.9)`.
	const timeConstant = 0.158;

	/// Reads the centre texel of whatever depth buffer is currently bound for reading.
	///
	/// One pixel, once per frame. Iris downsamples into a 1x1 texture instead; that avoids the sync
	/// entirely but needs a second program and target, and this is measurable only against a
	/// readback far larger than one texel.
	///
	/// This is a synchronous readback of the depth the current frame has just written, taken at
	/// the pre-translucent split where the opaque depth buffer is complete. `capture` reads the
	/// result at the *start* of the next frame, so what a pack sees is one frame stale - which is
	/// harmless for a value that exists to be smoothed. An earlier version of this comment claimed
	/// the sample came from the previous frame's buffer and therefore avoided a pipeline stall; the
	/// latency is real, the reason given for it was not.
	pub fn sample(width: u31, height: u31, deltaTime: f32) void {
		var depth: f32 = 1;
		c.glReadPixels(@divTrunc(width, 2), @divTrunc(height, 2), 1, 1, c.GL_DEPTH_COMPONENT, c.GL_FLOAT, &depth);
		if(!std.math.isFinite(depth)) return;
		value += (depth - value)*smoothing.factor(deltaTime, timeConstant);
	}
};

var frameCounter: i32 = 0;
var frameTimeCounter: f32 = 0;

/// Reads the current Cubyz state into a full uniform set.
///
/// Call once per frame, after `game.camera.updateViewMatrix()` and before running any pass.
///
/// `playerPos` must be the very value the frame's geometry is positioned against, not a fresh
/// sample. The prologue subtracts it to place vertices, so it *is* the origin of the world space
/// the pack sees; a second `getEyePosBlocking()` call would race the physics thread and put
/// `cameraPosition` a fraction of a block away from where the chunks actually are. Every temporal
/// effect compares those two across frames, so a mismatch that changes each frame shows up as
/// jitter that never settles.
pub fn capture(deltaTime: f32, playerPos: main.vec.Vec3d, settings: *const pack.Settings) Values {
	var values = Values{};

	const modelView = matrix.gbufferModelView(game.camera.viewMatrix);
	// Packs read this matrix's individual entries, so it has to be a real GL perspective matrix
	// rather than Cubyz's Z-up variant, which stores its terms in different slots entirely.
	// The far plane matches the `far` uniform rather than Cubyz's `zFar`, because `depthLinear` -
	// which packs use to turn a depth sample back into a distance - is `(2*near)/(far+near-d*(far-near))`
	// and only agrees with the depth actually written when the two are the same number. Splitting them
	// would fix the ray lengths and silently corrupt every distance reconstructed from depth instead.
	//
	// Geometry past that plane clips, so it has to be where Cubyz genuinely stops drawing - the
	// LOD-extended distance, not the LOD-0 radius. See `renderDistanceBlocks`.
	const projection = matrix.glProjection(game.projectionMatrix, renderer.zNear, renderDistanceBlocks());

	values.gbufferModelView = modelView;
	values.gbufferModelViewInverse = matrix.inverse(modelView) orelse Mat4f.identity();
	values.gbufferProjection = projection;
	values.gbufferProjectionInverse = matrix.inverse(projection) orelse Mat4f.identity();

	// On the first frame there is no previous state; using the current one avoids a one-frame
	// smear across the whole screen.
	values.gbufferPreviousModelView = if(previous.valid) previous.modelView else modelView;
	values.gbufferPreviousProjection = if(previous.valid) previous.projection else projection;

	const playerPosition = playerPos;
	// `positionToYUp`, not `toYUp`: a position also needs the sea-level offset, because packs read
	// altitude as an absolute Minecraft height. Without it Nostalgia's atmosphere puts every Cubyz
	// player 64 blocks underground and pins air density at its valley-haze maximum of 250, which
	// reads as a sun-shaped glow over the whole screen that survives through solid rock.
	const cameraPosition = matrix.positionToYUp(.{
		@floatCast(playerPosition[0]),
		@floatCast(playerPosition[1]),
		@floatCast(playerPosition[2]),
	});
	values.cameraPosition = cameraPosition;
	values.previousCameraPosition = if(previous.valid) previous.cameraPosition else cameraPosition;
	// Height is the Y component once the world is Y-up.
	values.eyeAltitude = cameraPosition[1];

	// The integer/fraction split, computed from the *double* position rather than by decomposing
	// the float above - decomposing a float that has already lost precision would hand the pack a
	// fractional part that is quantised to the same grid, which is the problem these exist to avoid.
	// Carries the same sea-level offset as `cameraPosition`, or the pair stops summing back to it -
	// packs reconstruct a precise world position as int + fract and would land 64 blocks out.
	const yUpDouble = Vec3d{playerPos[0], playerPos[2] + matrix.seaLevel, -playerPos[1]};
	values.cameraPositionInt = .{
		@intFromFloat(@floor(yUpDouble[0])),
		@intFromFloat(@floor(yUpDouble[1])),
		@intFromFloat(@floor(yUpDouble[2])),
	};
	values.cameraPositionFract = .{
		@floatCast(yUpDouble[0] - @floor(yUpDouble[0])),
		@floatCast(yUpDouble[1] - @floor(yUpDouble[1])),
		@floatCast(yUpDouble[2] - @floor(yUpDouble[2])),
	};
	values.previousCameraPositionInt = if(previous.valid) previous.cameraPositionInt else values.cameraPositionInt;
	values.previousCameraPositionFract = if(previous.valid) previous.cameraPositionFract else values.cameraPositionFract;

	values.eyePosition = cameraPosition;
	values.is_sneaking = if(game.Player.crouching) 1 else 0;
	values.is_on_ground = if(game.Player.onGround) 1 else 0;
	// As Iris reports them: the current value as a fraction of the maximum, the maximum raw.
	values.maxPlayerHealth = game.Player.super.maxHealth;
	values.currentPlayerHealth = game.Player.super.health/@max(game.Player.super.maxHealth, 1);
	// The biome the client already tracks for its own fog, matched to Minecraft's by family name.
	// An unmatched family keeps the plains defaults rather than reporting anything colder.
	if(game.world) |world| {
		const biome = world.playerBiome.load(.monotonic);
		if(biomemap.equivalent(biome.id)) |entry| {
			values.biome = biomemap.idOf(entry.name) orelse -1;
			values.biome_category = @intFromEnum(entry.category);
			values.biome_precipitation = @intFromEnum(entry.precipitation);
			values.temperature = entry.temperature;
			values.rainfall = entry.downfall;
		}
	}
	// Cubyz's camera is the eye, and `playerPos` is already the eye position, so the offset from the
	// body origin is not separately modelled. Reported as zero rather than invented.
	values.relativeEyePosition = @splat(0);
	// `game.camera.direction` is a Z-up unit vector; the pack's world is Y-up.
	values.playerLookVector = matrix.toYUp(game.camera.direction);
	values.playerBodyVector = values.playerLookVector;

	values.centerDepthSmooth = centerDepth.value;

	// One layer of Cubyz's block texture array, which is what packs use this for. Queried through
	// the direct-state-access entry point so it costs no bind and cannot disturb whatever texture
	// unit the caller had set up.
	var atlasWidth: c_int = 0;
	var atlasHeight: c_int = 0;
	c.glGetTextureLevelParameteriv(main.blocks.meshes.blockTextureArray.textureID, 0, c.GL_TEXTURE_WIDTH, &atlasWidth);
	c.glGetTextureLevelParameteriv(main.blocks.meshes.blockTextureArray.textureID, 0, c.GL_TEXTURE_HEIGHT, &atlasHeight);
	values.atlasSize = .{atlasWidth, atlasHeight};

	values.viewWidth = @floatFromInt(renderer.lastWidth);
	values.viewHeight = @floatFromInt(renderer.lastHeight);
	values.aspectRatio = values.viewWidth/@max(values.viewHeight, 1);
	values.near = renderer.zNear;
	// Not `renderer.zFar`. In Minecraft `far` is the render distance in blocks, because that is
	// where Minecraft puts its projection's far plane - so the same number answers both "how far does
	// the world extend" and "what normalises depth", and packs use it for both interchangeably.
	//
	// Cubyz separates them: `zFar` is 65536, chosen to avoid z-fighting rather than to describe the
	// world. Handing that across told every pack the world was 65 km deep. Nostalgia's volumetric ray
	// runs to `min(fogClipDist, far)`, so it marched tens of thousands of blocks - far outside the
	// 128-block shadow map, where every sample reads "nothing occludes" - accumulating in-scattered
	// sunlight the whole way. That is the beam of light lying across solid rock.
	//
	// The far plane above uses the same number, so the pack's ray limits and its depth linearisation
	// agree about where the world ends - the property Minecraft gets for free by construction.
	//
	// `fogStart`/`fogEnd` deliberately do *not* follow it. They are separate uniforms in Minecraft
	// too, and Cubyz's fog should still hide the edge of full detail rather than being pushed out to
	// the LOD horizon. What does follow `far` is the pack's own `getFog`, which is `dist/far` against
	// a `fogStart` fraction - so this being the LOD-0 radius fogged the world out from 115 blocks.
	values.far = renderDistanceBlocks();
	// The setting itself, in chunks, as Iris reports the vanilla one; not the LOD-extended radius
	// `far` carries, which is a distance in blocks and a different quantity.
	values.dhRenderDistance = main.settings.renderDistance;

	frameCounter +%= 1;
	frameTimeCounter = @mod(frameTimeCounter + deltaTime, 3600.0);
	values.frameCounter = frameCounter;
	values.frameTime = deltaTime;
	values.frameTimeCounter = frameTimeCounter;

	if(game.world) |world| {
		const dayTime = &world.dayTime;
		// One clock for everything a pack reads about the sun. `worldTime` below is the linear
		// tick; the angle the sun sits at is Minecraft's eased function of it, `worldtime.skyAngle`,
		// which is what Iris derives `sunPosition`, `sunAngle` and the shadow camera from. This
		// used to take `dayTime.getDayProgress()` straight, a linear angle on the same clock, and
		// the two agree only at noon and midnight: up to 12.6 degrees apart around dawn and dusk,
		// with the sun setting at tick 12000 here and 12786 there. BSL never reads `sunPosition` - it
		// recomputes the sun from `worldTime` with Minecraft's curve in every program - so it shaded
		// with one sun and sampled a shadow map cast by another. Cubyz's progress is 0 at noon and
		// 0.5 at midnight, which is the convention the raw celestial angle uses, so no offset.
		const gameTime = world.gameTime.load(.monotonic);
		const rawAngleDegrees = worldtime.skyAngle(gameTime)*360.0;

		values.sunPosition = matrix.celestialPosition(modelView, settings.sunPathRotation, rawAngleDegrees, 100);
		values.moonPosition = matrix.celestialPosition(modelView, settings.sunPathRotation, rawAngleDegrees, -100);
		values.cubyz_celestialX = matrix.celestialAxis(modelView, settings.sunPathRotation, rawAngleDegrees, .{1, 0, 0});
		values.cubyz_celestialZ = matrix.celestialAxis(modelView, settings.sunPathRotation, rawAngleDegrees, .{0, 0, 1});
		values.upPosition = matrix.upPosition(modelView);

		// The brighter body is the one that casts shadows.
		//
		// From the world-space sun, not `sunPosition[1]`. `sunPosition` is the sun in *view*
		// space, so its `.y` is how far up the *screen* the sun sits - a camera-dependent number.
		// Testing it made "is it daytime" a function of where the player was looking: pitch across
		// the threshold and the light flipped to the moon, `lightDirection` negated, and the whole
		// shadow map inverted between frames. Measured, the basis alternated between
		// `(0.613, -0.716, -0.334)` and `(-0.629, 0.704, 0.328)` - exactly negated - with frame
		// brightness switching with it, on an unchanged chunk set of 3341 chunks.
		//
		// This is the same class as `worldTime` and `far` before it: a value that is supplied, and
		// wrong, because it was read in the wrong frame.
		const isDay = matrix.isDaytime(settings.sunPathRotation, rawAngleDegrees);
		values.shadowLightPosition = if(isDay) values.sunPosition else values.moonPosition;

		// The `sunAngle` uniform is the raw angle plus 90 degrees, wrapped - Iris exposes it that
		// way, so a sun directly overhead reads 0.25 rather than 0.
		values.sunAngle = @mod(rawAngleDegrees + 90.0, 360.0)/360.0;
		values.shadowAngle = if(isDay) values.sunAngle else @mod(values.sunAngle + 0.5, 1.0);

		// Shadow camera, built as Iris builds it: 100 blocks up the ray of whichever body is
		// brighter, its origin snapped to the pack's interval grid, over a depth range of
		// [0.05, 256] blocks unless the pack declares its own. In world space, not from the
		// view-space `shadowLightPosition`, because the map is built independently of where the
		// player looks. `matrix.shadowModelView` says why the range is not a tunable: every pack's
		// depth bias and depth-scale constant is written against Iris's, and the previous ortho,
		// two shadow distances either side of the player, made each of them stand for two to four
		// times the distance its author meant - a shadow detached from the block casting it.
		const lightAngleDegrees = if(isDay) rawAngleDegrees else rawAngleDegrees + 180.0;
		const gridSnap = matrix.shadowGridSnap(cameraPosition, settings.shadowIntervalSize);
		values.shadowModelView = matrix.shadowModelView(settings.sunPathRotation, lightAngleDegrees, gridSnap);
		values.shadowModelViewInverse = matrix.inverse(values.shadowModelView) orelse Mat4f.identity();
		// A negative plane is Iris's "use the render distance", which without Distant Horizons is
		// the vanilla setting in chunks (`DHCompat.getRenderDistance`). Kept literally rather than
		// improved on: no pack in the corpus asks for it outside a Distant Horizons build, and a
		// better number here would be a divergence with nothing to check it against.
		const renderDistanceChunks: f32 = @floatFromInt(main.settings.renderDistance);
		const shadowNear = if(settings.shadowNearPlane < 0) -renderDistanceChunks else settings.shadowNearPlane;
		const shadowFar = if(settings.shadowFarPlane < 0) renderDistanceChunks else settings.shadowFarPlane;
		values.shadowProjection = matrix.ortho(settings.shadowDistance, shadowNear, shadowFar);
		values.shadowProjectionInverse = matrix.inverse(values.shadowProjection) orelse Mat4f.identity();

		// Not `dayTime.dayTime`. Packs read `worldTime` as an absolute Minecraft tick - 24000 to the
		// day, dawn at 0 - and Cubyz's counter is 12000 to the day starting at noon, so passing it
		// straight across is wrong in both rate and phase. See `worldtime.zig`; it is the reason the
		// sky capture painted its sun 90 degrees away from the one the world was lit by.
		values.worldTime = worldtime.worldTime(gameTime);
		values.worldDay = worldtime.worldDay(gameTime);
		// Minecraft's eight-night cycle off the same counter. Held at zero until 2026-09-07, which
		// made every night a full moon; see `worldtime.moonPhase`.
		values.moonPhase = worldtime.moonPhase(gameTime);

		values.fogColor = dayTime.fog.fogColor;
		// `biomeFog`, not `fog` - the biome's own sky colour, before Cubyz tints it for the time
		// of day. `fog.skyColor` is `biomeFog.skyColor * getSkyColorFactor()`, and that factor fades
		// the channels at *different* rates around dawn and dusk: blue drops first, red and green
		// hold, so it passes through `(fading, 1, 0)` - pure green.
		//
		// Minecraft's `skyColor` changes brightness with the time of day but keeps a stable blue
		// hue; sunset orange comes from the pack's own blend, not from this uniform. Nostalgia takes
		// it as `linearSky` and runs it through `daytimeColor(sunrise, noon, sunset, night)` itself,
		// with an explicit hardcoded colour for night. Handing over the already-tinted value applied
		// the sunset twice, and the second application landed on Cubyz's green.
		values.skyColor = hueStableSky(dayTime.biomeFog.skyColor, dayTime.fog.skyColor);
		values.fogDensity = dayTime.fog.density;

		// `fogStart`/`fogEnd` are distances from the camera, and Cubyz's `fogLower`/`fogHigher`
		// are altitudes - its fog is a height band, not a linear ramp along the view ray. Passing
		// one as the other is a unit error, not an approximation: packs compute
		//
		//     mix(albedo, fogColor, (dist - fogStart)/(fogEnd - fogStart))
		//
		// which Sildur's does in twenty-four files. Fed 100 and 1000, everything past a hundred
		// blocks began dissolving into fog colour and the sky, being furthest of all, went to solid
		// fog - the same flat wash the missing skybox produced, arriving by a different route.
		//
		// The honest substitute is the render distance, which is where Minecraft's own fog ends too.
		const fogRange = fogDistances();
		values.fogStart = fogRange.start;
		values.fogEnd = fogRange.end;
		// A valid GL fog mode, since linear start/end are what is being supplied. Zero is not one,
		// and a pack switching on it would match nothing.
		values.fogMode = c.GL_LINEAR;

		// How exposed the eye is to sky and to block light, on Minecraft's 0-240 scale.
		//
		// This is a *position* query, not a time-of-day one, and the difference is the whole point.
		// Minecraft's `eyeBrightness.y` is the sky-light level where the player is standing - 240
		// under open sky, day or night, and 0 deep underground. Packs use it to decide whether the
		// player is in a cave: Nostalgia derives `caveMult` from it and, with it wrong, fills a cave
		// with fully sunlit volumetric fog. It read the day/night ambient scalar before, which is
		// 1.0 at noon *everywhere including underground*, so every cave was lit as open sky.
		//
		// The sun channel is deliberately not multiplied by the time-of-day factor: Cubyz applies
		// that separately when shading, exactly as Minecraft does, and packs expect the raw exposure.
		const eyeBlock = [3]i32{
			@intFromFloat(@floor(playerPosition[0])),
			@intFromFloat(@floor(playerPosition[1])),
			@intFromFloat(@floor(playerPosition[2])),
		};
		if(renderer.mesh_storage.getLight(eyeBlock[0], eyeBlock[1], eyeBlock[2])) |light| {
			// `LightValue` is a byte per channel, so these are 0-255 - not the 0-31 the vertex
			// prologue sees. The prologue reads the SSBO, which packs each channel down to five bits;
			// this reads the lighting data directly, uncompressed. Getting that wrong is invisible
			// rather than loud: the value comes out ~8x too large, every pack's `x/240.0`
			// normalisation clamps to 1, and the result is indistinguishable from the "always open
			// sky" bug it was meant to fix.
			//
			// Collapsed to the strongest channel, as the prologue does for `lmcoord`.
			const sky = lightmap.strongestChannel(.{light[0], light[1], light[2]});
			const block = lightmap.strongestChannel(.{light[3], light[4], light[5]});
			values.eyeBrightness = .{
				// Block light is a genuine unit conversion; sky light is a semantic one between two
				// different quantities. See `lightmap.toSkyExposure`.
				lightmap.toEyeBrightness(block),
				lightmap.toSkyExposure(sky),
			};
		} else {
			// No mesh there yet - at startup, or beyond the loaded region. Open sky is the safe
			// default: guessing "underground" would drop a cave-fog wall over the world for the
			// first frames after a load.
			values.eyeBrightness = .{0, 240};
		}
		values.eyeBrightnessSmooth = eyeBrightness.smooth(values.eyeBrightness, deltaTime);

		const playerBlock = renderer.mesh_storage.getBlockFromAnyLodFromRenderThread(eyeBlock[0], eyeBlock[1], eyeBlock[2]);
		// Cubyz has no water/lava distinction exposed here, so any fog-producing block the eye is
		// inside reports as water - the value packs branch on for underwater rendering.
		values.isEyeInWater = if(main.blocks.meshes.hasFog(playerBlock)) 1 else 0;
	}

	previous = .{
		.modelView = modelView,
		.projection = projection,
		.cameraPosition = cameraPosition,
		.cameraPositionInt = values.cameraPositionInt,
		.cameraPositionFract = values.cameraPositionFract,
		.valid = true,
	};
	return values;
}

/// Forgets the previous frame, so the next one does not reproject across a discontinuity.
///
/// Worth calling on teleport or world change: without it, one frame of motion blur smears the
/// entire screen as the reprojection tries to connect two unrelated camera positions.
pub fn resetHistory() void {
	previous.valid = false;
	eyeBrightness.reset();
}



