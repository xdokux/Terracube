//! The textures a pack expects the game to supply beyond the block atlas: `noisetex`, and the
//! LabPBR `normals` and `specular` maps.
//!
//! These matter more than their obscurity suggests. A sampler uniform that is never assigned reads
//! texture unit 0 - and during the terrain pass unit 0 is `colortex0`, which that very pass is
//! writing. So an unprovided `normals` sampler does not read black, it reads a feedback loop:
//! undefined values fed straight into the lighting maths. That is the difference between a scene
//! that looks unlit and a scene that looks wrong.
//!
//! `noisetex` is loaded from the pack, since packs ship their own and their effects are tuned to
//! it. `normals` and `specular` are neutral 1x1 constants, because Cubyz has no LabPBR material
//! data at all - that is an honest "no material information here" rather than an approximation of
//! one.

const std = @import("std");

const main = @import("main");
const c = main.c;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const List = main.ListManaged;

const pack = @import("pack.zig");
const targets = @import("targets.zig");
const cloudmask = @import("cloudmask.zig");
const images = @import("images.zig");

/// Units past everything the shaderpack format and Cubyz's own arrays already claim.
pub const noiseUnit: c_uint = targets.cubyzReflectivityTextureUnit + 1;
pub const normalsUnit: c_uint = noiseUnit + 1;
pub const specularUnit: c_uint = noiseUnit + 2;
/// One unit for the sun and moon sheets, bound in turn per draw of `gbuffers_skytextured`, past
/// the sixteen sampler views of the pack's images; the pack's `customTexture.<name>` samplers
/// follow it, one unit each.
pub const celestialUnit: c_uint = images.samplerUnitBase + images.maxImages;
pub const namedUnitBase: c_uint = celestialUnit + 1;
pub const maxNamed = 16;

/// The sun sheet's side and the moon sheet's cell: Minecraft's `sun.png` is 32 square and its
/// `moon_phases.png` four cells of 32 by two; the sun is drawn at twice that so its edge is soft.
pub const sunSize = 64;
pub const moonCell = 32;
pub const moonSheetWidth = moonCell*4;
pub const moonSheetHeight = moonCell*2;

/// The two bodies `gbuffers_skytextured` draws, each from its own sheet on `celestialUnit`.
pub const Body = enum {sun, moon};

/// The pipeline stages a `texture.<stage>.<sampler>` binding can name.
///
/// Iris scopes these per stage, so the same sampler can be a render target in one pass and a
/// pack-supplied image in another - Complementary binds `colortex3` to an image for `deferred`
/// while still writing it as a buffer elsewhere.
pub const Stage = enum {
	setup, begin, shadowcomp, prepare, gbuffers, deferred, composite,

	/// Iris's seven stage names, exactly (`TextureStage.parse`): `gbuffers` covers the shadow
	/// programs too and `composite` covers `final`. `texture.shadow.*` and `texture.final.*` are
	/// not stage names there - "Unknown texture stage, ignoring" - and the voxel packs'
	/// `texture.shadow.colortex9 = lib/textures/whiteNoise.png` is skipped here as Iris skips it,
	/// rather than honoured by a spelling Iris never reads.
	pub fn parse(name: []const u8) ?Stage {
		inline for(@typeInfo(Stage).@"enum".fields) |field| {
			if(std.mem.eql(u8, name, field.name)) return @enumFromInt(field.value);
		}
		return null;
	}

	/// The stage a post-chain program's bindings are scoped under, or null for a program kind
	/// whose overrides are applied from its own draw path.
	///
	/// Deliberately not the gbuffers and shadow programs: those run through `bridge.zig` rather
	/// than through `pipeline.runPass`, and naming them here would bind a pack's
	/// `texture.gbuffers.*` overrides during a composite pass - where that unit is a live render
	/// target the pass reads. `final` shares `composite`'s bindings, as Iris's
	/// `COMPOSITE_AND_FINAL` says.
	pub fn forProgramKind(kind: pack.ProgramKind) ?Stage {
		return switch(kind) {
			.setup => .setup,
			.begin => .begin,
			.shadowcomp => .shadowcomp,
			.prepare => .prepare,
			.deferred => .deferred,
			.composite, .final => .composite,
			else => null,
		};
	}
};

/// One `texture.<stage>.<sampler>` binding, resolved to the unit it overrides.
pub const Custom = struct {
	stage: Stage,
	unit: c_uint,
	id: c_uint = 0,
	/// `GL_TEXTURE_2D` for an image, `GL_TEXTURE_3D` for a raw volume.
	///
	/// Carried per binding rather than assumed, because both kinds land on the same texture units
	/// and the bind call has to name the right target. A 3D volume bound as 2D is not an error GL
	/// reports - it binds nothing useful and the sampler reads whatever the unit already held.
	target: c_uint = c.GL_TEXTURE_2D,
};

/// One `customTexture.<name>` declaration (`ShaderProperties.java:460-483`): a texture of the
/// pack's own under a sampler name of its own, bound in every program that declares the name.
/// Complementary's `cloudWaterTex` is one, read by its cloud shadows; until 2026-09-12 that
/// sampler sat on unit 0 and read whatever colortex0 held.
pub const Named = struct {
	name: []u8,
	unit: c_uint,
	id: c_uint = 0,
};

/// Texture unit a sampler name occupies, or null if it is not one this pipeline binds.
///
/// The override replaces whatever the render targets put on that unit for the duration of the
/// stage, which is exactly Iris's semantics - the binding is per unit, so `gaux4` and `colortex7`
/// are the same slot and a pack overriding one overrides both.
///
/// Free of GL so the name-to-unit mapping can be tested; getting it wrong binds a real texture to
/// the wrong sampler, which reads as plausible garbage rather than as an error.
pub fn samplerUnit(name: []const u8) ?c_uint {
	// The legacy OptiFine aliases for colortex0-7, in order, as Iris's `LEGACY_RENDER_TARGETS`.
	const legacy = [_][]const u8{"gcolor", "gdepth", "gnormal", "composite", "gaux1", "gaux2", "gaux3", "gaux4"};
	for(legacy, 0..) |alias, index| {
		if(std.mem.eql(u8, name, alias)) return @intCast(index);
	}
	if(std.mem.startsWith(u8, name, "colortex")) {
		const index = std.fmt.parseInt(u8, name["colortex".len..], 10) catch return null;
		if(index >= targets.colortexCount) return null;
		return index;
	}
	if(std.mem.startsWith(u8, name, "depthtex")) {
		const index = std.fmt.parseInt(u8, name["depthtex".len..], 10) catch return null;
		if(index > 2) return null;
		return targets.depthTextureUnit + index;
	}
	// `texture.<stage>.noisetex=<path>` replaces the noise texture for that stage. Mellow declares
	// its noise this way and this way only - `texture.gbuffers.noisetex` and `texture.deferred.
	// noisetex`, both `/img/cloud_noise+normal.png`, no `texture.noise` - and until 2026-09-07 the
	// name matched nothing here, so the line was dropped and the pack ran its clouds, water
	// normals and lightmap flicker on the generated hash noise: a flat overcast sky where its
	// flat clouds averaged white noise into a uniform density, and water normals that were static.
	if(std.mem.eql(u8, name, "noisetex")) return noiseUnit;
	return null;
}

pub const Set = struct {
	noise: c_uint = 0,
	normals: c_uint = 0,
	specular: c_uint = 0,
	/// `texture.<stage>.<sampler>` bindings the pack declares, already loaded.
	///
	/// This was unimplemented, and it is not a cosmetic gap. Complementary declares
	/// `texture.gbuffers.gaux4=lib/textures/cloud-water.png` and samples that texture four times per
	/// water fragment to build its wave normals - `normalMed`, `normalSmall` and two octaves of
	/// `normalBig` in `lib/materials/specificMaterials/translucents/water.glsl`. Without it `gaux4`
	/// falls through to colortex7, the normals come out of an unrelated render target, and the water
	/// renders as a flat mirror with no surface detail at all.
	customs: []Custom = &.{},
	/// The pack's `customTexture.<name>` samplers, already loaded, each on a unit of its own.
	named: []Named = &.{},
	/// The sun and moon-phase sheets `gbuffers_skytextured` samples; see `sunTexel`, `moonTexel`.
	sun: c_uint = 0,
	moon: c_uint = 0,
	allocator: NeverFailingAllocator = undefined,

	pub fn deinit(self: *Set) void {
		c.glDeleteTextures(1, &self.noise);
		c.glDeleteTextures(1, &self.normals);
		c.glDeleteTextures(1, &self.specular);
		c.glDeleteTextures(1, &self.sun);
		c.glDeleteTextures(1, &self.moon);
		for(self.customs) |custom| {
			var id = custom.id;
			c.glDeleteTextures(1, &id);
		}
		if(self.customs.len != 0) self.allocator.free(self.customs);
		for(self.named) |entry| {
			var id = entry.id;
			c.glDeleteTextures(1, &id);
			self.allocator.free(entry.name);
		}
		if(self.named.len != 0) self.allocator.free(self.named);
	}

	/// Binds the pack's own textures over the render targets, for one stage.
	///
	/// Call after `targets.bindSamplers`, which binds the buffers this deliberately replaces.
	///
	/// `writtenBefore` is every colortex the chain has drawn to ahead of this pass, and an override
	/// on one of those is skipped. That is Iris's rule, not a convenience: `ProgramSamplers.java:244`
	/// deactivates the override for `colortexN` and its legacy alias once N has been flipped at
	/// least once, so a pack can use one name as a pack-supplied image early in the chain and as a
	/// real buffer after it starts writing there. Bliss does exactly that - `texture.composite.
	/// colortex6 = texture/blueNoise.png`, blue noise for its first composites, and from
	/// `composite4` (`DRAWBUFFERS:06`) on, colortex6 is its own data, read back by `composite5`
	/// and `composite8` through `composite11`. Binding the noise for the whole stage fed those
	/// passes a 512x512 noise tile in place of their input, which is a frame of fine speckle from
	/// edge to edge; the night screenshot of 2026-09-04 is that and nothing else.
	///
	/// The set is the caller's to scope: Iris restarts it per stage renderer and hands the
	/// gbuffers and shadow programs an empty one, see `bridge.zig` where passes are built.
	pub fn bindOverrides(self: *const Set, stage: Stage, writtenBefore: targets.flip.TargetSet) void {
		for(self.customs) |custom| {
			if(custom.stage != stage) continue;
			if(custom.unit < targets.colortexCount and writtenBefore.contains(@intCast(custom.unit))) continue;
			c.glActiveTexture(@as(c_uint, @intCast(c.GL_TEXTURE0)) + custom.unit);
			c.glBindTexture(custom.target, custom.id);
		}
		c.glActiveTexture(c.GL_TEXTURE0);
	}

	pub fn bind(self: *const Set) void {
		c.glActiveTexture(c.GL_TEXTURE0 + noiseUnit);
		c.glBindTexture(c.GL_TEXTURE_2D, self.noise);
		c.glActiveTexture(c.GL_TEXTURE0 + normalsUnit);
		c.glBindTexture(c.GL_TEXTURE_2D, self.normals);
		c.glActiveTexture(c.GL_TEXTURE0 + specularUnit);
		c.glBindTexture(c.GL_TEXTURE_2D, self.specular);
		for(self.named) |entry| {
			c.glActiveTexture(@as(c_uint, @intCast(c.GL_TEXTURE0)) + entry.unit);
			c.glBindTexture(c.GL_TEXTURE_2D, entry.id);
		}
		c.glActiveTexture(c.GL_TEXTURE0);
	}

	/// Points a program's samplers at these units.
	pub fn bindSamplerUniforms(self: *const Set, program: c_uint) void {
		const entries = [_]struct {name: [:0]const u8, unit: c_uint}{
			.{.name = "noisetex", .unit = noiseUnit},
			.{.name = "normals", .unit = normalsUnit},
			.{.name = "specular", .unit = specularUnit},
		};
		for(entries) |entry| {
			const location = c.glGetUniformLocation(program, entry.name.ptr);
			if(location >= 0) c.glUniform1i(location, @intCast(entry.unit));
		}
		var terminated: [128]u8 = undefined;
		for(self.named) |entry| {
			const name = std.fmt.bufPrintZ(&terminated, "{s}", .{entry.name}) catch continue;
			const location = c.glGetUniformLocation(program, name.ptr);
			if(location >= 0) c.glUniform1i(location, @intCast(entry.unit));
		}
	}

	/// Puts one body's sheet where the textured sky program samples its texture: on
	/// `celestialUnit`, under every spelling of the block-texture sampler a pack uses, since
	/// `gbuffers_skytextured` reads the sun and the moon through the same `gtexture` its terrain
	/// programs read the atlas through. The transformer has already renamed a legacy `texture`
	/// sampler to `gtexture`, as Iris does.
	pub fn bindCelestial(self: *const Set, program: c_uint, body: Body) void {
		c.glActiveTexture(c.GL_TEXTURE0 + celestialUnit);
		c.glBindTexture(c.GL_TEXTURE_2D, if(body == .sun) self.sun else self.moon);
		c.glActiveTexture(c.GL_TEXTURE0);
		for([_][:0]const u8{"gtexture", "gcolor", "tex", "texture0"}) |name| {
			const location = c.glGetUniformLocation(program, name.ptr);
			if(location >= 0) c.glUniform1i(location, @intCast(celestialUnit));
		}
	}
};

/// A texel of the sun sheet. Minecraft's `sun.png` is a white glow in the middle of its quad,
/// brightest at the centre and gone well before the edge; this is that shape at twice the
/// resolution, opaque out to three tenths of the half-width and fading to nothing at two thirds.
/// The first cut fell off at the quad's edge and, over Minecraft's sixty-unit quad, drew a sun a
/// third of the screen tall (the screenshot of 2026-09-12); the vanilla disc reads at roughly a
/// third of that.
pub fn sunTexel(x: usize, y: usize) [4]u8 {
	const half: f32 = @as(f32, @floatFromInt(sunSize))/2.0;
	const dx = (@as(f32, @floatFromInt(x)) + 0.5 - half)/half;
	const dy = (@as(f32, @floatFromInt(y)) + 0.5 - half)/half;
	const distance = @sqrt(dx*dx + dy*dy);
	const alpha = std.math.clamp((0.65 - distance)/0.35, 0.0, 1.0);
	return .{255, 255, 255, @intFromFloat(@round(alpha*255.0))};
}

/// A texel of the moon-phase sheet. Minecraft's `moon_phases.png` is four cells by two, phase `p`
/// at column `p % 4` of row `p / 4`, each a disc lit as that phase: full at 0, waning to the
/// third quarter at 2 and new at 4, waxing through the first quarter at 6. The terminator is the
/// ellipse of half-width `cos(p*pi/4)` through the disc, lit on the left of it while waning and
/// on the right while waxing. The unlit part is transparent, as in the vanilla sheet, and the
/// additive blend adds nothing for it; the lit part is the pale grey the vanilla moon reads as.
pub fn moonTexel(x: usize, y: usize) [4]u8 {
	const phase = (y/moonCell)*4 + x/moonCell;
	const half: f32 = @as(f32, @floatFromInt(moonCell))/2.0;
	const dx = (@as(f32, @floatFromInt(x % moonCell)) + 0.5 - half)/half;
	const dy = (@as(f32, @floatFromInt(y % moonCell)) + 0.5 - half)/half;
	const distance = @sqrt(dx*dx + dy*dy);
	if(distance > 1.0) return .{0, 0, 0, 0};
	const theta = @as(f32, @floatFromInt(phase))*std.math.pi/4.0;
	const terminator = @cos(theta)*@sqrt(@max(1.0 - dy*dy, 0.0));
	const lit = if(phase <= 4) dx <= terminator else dx >= -terminator;
	if(!lit) return .{0, 0, 0, 0};
	// A soft rim, so the disc's edge is not a staircase at the size it is drawn.
	const alpha = std.math.clamp((1.0 - distance)/0.08, 0.0, 1.0);
	return .{230, 230, 220, @intFromFloat(@round(alpha*255.0))};
}

/// Uploads a generated sheet as a clamped, linearly filtered RGBA8 texture.
fn generateSheet(allocator: NeverFailingAllocator, width: usize, height: usize, comptime texel: fn (usize, usize) [4]u8) c_uint {
	const pixels = allocator.alloc(u8, width*height*4);
	defer allocator.free(pixels);
	for(0..height) |y| {
		for(0..width) |x| {
			const value = texel(x, y);
			@memcpy(pixels[(y*width + x)*4 ..][0..4], &value);
		}
	}
	var id: c_uint = undefined;
	c.glGenTextures(1, &id);
	c.glBindTexture(c.GL_TEXTURE_2D, id);
	c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA8, @intCast(width), @intCast(height), 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, pixels.ptr);
	c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
	c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
	c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
	c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
	c.glBindTexture(c.GL_TEXTURE_2D, 0);
	return id;
}

/// Appends the pack's `customTexture.<name>` sampler names, for the coverage report: a name the
/// bridge binds is not one nothing supplies. Borrows from the properties, which outlive the report.
pub fn appendNamedTextureNames(properties: *const pack.Properties, out: *List([]const u8)) void {
	var iterator = properties.entries.iterator();
	while(iterator.next()) |entry| {
		const key = entry.key_ptr.*;
		if(!std.mem.startsWith(u8, key, "customTexture.")) continue;
		const name = key["customTexture.".len..];
		if(name.len != 0) out.append(name);
	}
}

/// Loads the pack's `customTexture.<name>` declarations that name an image file in the pack.
///
/// The same three forms as `texture.<stage>.<sampler>`, with the same honesty about them: a game
/// asset is skipped and said so, a raw definition is logged as unsupported, and a PNG is loaded
/// tiling and mipmapped as the stage overrides are. Each gets a unit of its own after the image
/// views and the celestial sheet, capped at `maxNamed`.
fn loadNamedTextures(allocator: NeverFailingAllocator, shadersRoot: []const u8, properties: *const pack.Properties) []Named {
	var list = List(Named).init(allocator);
	var iterator = properties.entries.iterator();
	while(iterator.next()) |entry| {
		const key = entry.key_ptr.*;
		if(!std.mem.startsWith(u8, key, "customTexture.")) continue;
		const name = key["customTexture.".len..];
		if(name.len == 0) continue;
		const value = std.mem.trim(u8, entry.value_ptr.*, " \t");
		if(std.mem.indexOfScalar(u8, value, ':') != null) {
			std.log.info("irisbridge: {s} names a Minecraft asset Cubyz does not have, and is skipped", .{key});
			continue;
		}
		if(std.mem.indexOfAny(u8, value, " \t") != null) {
			std.log.info("irisbridge: {s} is a raw texture definition, which is not supported yet", .{key});
			continue;
		}
		if(list.items.len == maxNamed) {
			std.log.warn("irisbridge: {s} is past the {} named textures this bridge binds, and is skipped", .{key, maxNamed});
			continue;
		}

		var path = List(u8).init(allocator);
		defer path.deinit();
		path.appendSlice(shadersRoot);
		if(value.len != 0 and value[0] != '/') path.append('/');
		path.appendSlice(value);
		const image = main.graphics.Image.readFromFile(allocator, path.items, .{.orientation = .openGl}) catch {
			std.log.warn("irisbridge: {s} names {s}, which could not be read", .{key, value});
			continue;
		};
		defer image.deinit(allocator);

		var id: c_uint = undefined;
		c.glGenTextures(1, &id);
		c.glBindTexture(c.GL_TEXTURE_2D, id);
		c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA8, @intCast(image.width), @intCast(image.height), 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, image.imageData.ptr);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR_MIPMAP_LINEAR);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
		c.glGenerateMipmap(c.GL_TEXTURE_2D);

		const unit = namedUnitBase + @as(c_uint, @intCast(list.items.len));
		list.append(.{.name = allocator.dupe(u8, name), .unit = unit, .id = id});
		std.log.info("irisbridge: {s} -> {s} ({}x{}) on unit {}", .{key, value, image.width, image.height, unit});
	}
	c.glBindTexture(c.GL_TEXTURE_2D, 0);
	return list.toOwnedSlice();
}

/// A 1x1 texture of one constant colour.
fn constantTexture(r: u8, g: u8, b: u8, a: u8) c_uint {
	var id: c_uint = undefined;
	c.glGenTextures(1, &id);
	c.glBindTexture(c.GL_TEXTURE_2D, id);
	const pixel = [4]u8{r, g, b, a};
	c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA8, 1, 1, 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, &pixel);
	c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
	c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
	c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
	c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
	return id;
}

/// Loads the pack's noise texture, or generates one if the pack ships none.
///
/// Packs tune their effects to their own noise, so the pack's file is preferred. The generated
/// fallback is a hash rather than anything structured, because the alternative - a constant - makes
/// every noise-driven effect degenerate into a flat offset.
fn loadNoise(allocator: NeverFailingAllocator, shadersRoot: []const u8, resolution: u32, declaredPath: []const u8) c_uint {
	var id: c_uint = undefined;
	c.glGenTextures(1, &id);
	c.glBindTexture(c.GL_TEXTURE_2D, id);

	// The pack's own `texture.noise` first. Guessing at conventional filenames only ever worked by
	// coincidence: Nostalgia happens to keep its noise at `image/noise2D.png`, but Complementary
	// declares `lib/textures/noise.png` and was therefore falling back to generated hash noise -
	// silently, since a pack shipping no noise at all is legitimate. Every noise-driven effect it
	// has, clouds and water included, was tuned against a texture it never received.
	//
	// A namespaced path (`minecraft:textures/...`) names a game asset rather than a pack file, and
	// Cubyz has no such asset to supply.
	const fromPack = if(declaredPath.len != 0 and std.mem.indexOfScalar(u8, declaredPath, ':') == null) declaredPath else "";
	var candidateStorage: [4][]const u8 = .{fromPack, "image/noise2D.png", "noise.png", "textures/noise.png"};
	const candidates: [][]const u8 = if(fromPack.len != 0) candidateStorage[0..] else candidateStorage[1..];

	for(candidates) |candidate| {
		var path = List(u8).init(allocator);
		defer path.deinit();
		path.appendSlice(shadersRoot);
		if(candidate.len != 0 and candidate[0] != '/') path.append('/');
		path.appendSlice(candidate);

		const image = main.graphics.Image.readFromFile(allocator, path.items, .{.orientation = .openGl}) catch continue;
		defer image.deinit(allocator);
		c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA8, @intCast(image.width), @intCast(image.height), 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, image.imageData.ptr);
		setNoiseParameters();
		std.log.info("irisbridge: loaded noise texture {s} ({}x{})", .{candidate, image.width, image.height});
		return id;
	}

	// Value-hash noise, so effects that sample it still get something decorrelated.
	//
	// Sized by the pack's `const int noiseTextureResolution`, because the pack divides by that
	// constant to derive its sampling coordinates - a texture of a different size makes every noise
	// lookup land somewhere other than intended, at a scale that is wrong by a constant factor.
	const size = resolution;
	const pixels = allocator.alloc(u8, size*size*4);
	defer allocator.free(pixels);
	var y: usize = 0;
	while(y < size) : (y += 1) {
		var x: usize = 0;
		while(x < size) : (x += 1) {
			// Every step wraps in `u32` on purpose. The products here run to ~9.5e10, which fits a
			// `usize` fine and then does *not* fit the `u32` this is cast to - so computing in
			// `usize` and narrowing afterwards panics on the very first pixel. A hash is supposed to
			// wrap; the width just has to be stated up front.
			var h: u32 = @as(u32, @intCast(x))*%374761393 +% @as(u32, @intCast(y))*%668265263;
			h = (h ^ (h >> 13)) *% 1274126177;
			const index = (y*size + x)*4;
			pixels[index + 0] = @truncate(h);
			pixels[index + 1] = @truncate(h >> 8);
			pixels[index + 2] = @truncate(h >> 16);
			pixels[index + 3] = 255;
		}
	}
	c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA8, @intCast(size), @intCast(size), 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, pixels.ptr);
	setNoiseParameters();
	std.log.info("irisbridge: pack ships no noise texture, generated one at {}x{}", .{size, size});
	return id;
}

/// The generated stand-in for Minecraft's cloud texture, uploaded the way the game holds the real
/// one: 256x256 RGBA8, nearest filtering (the clouds are blocky by design and packs step it texel
/// by texel), repeating on both axes.
fn vanillaCloudsTexture(allocator: NeverFailingAllocator) c_uint {
	const pixels = allocator.alloc(u8, cloudmask.byteCount);
	defer allocator.free(pixels);
	cloudmask.fill(pixels);

	var id: c_uint = undefined;
	c.glGenTextures(1, &id);
	c.glBindTexture(c.GL_TEXTURE_2D, id);
	c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA8, @intCast(cloudmask.size), @intCast(cloudmask.size), 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, pixels.ptr);
	c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
	c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
	c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
	c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
	c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAX_LEVEL, 0);
	c.glBindTexture(c.GL_TEXTURE_2D, 0);
	return id;
}

fn setNoiseParameters() void {
	// Noise is always tiled, so it must repeat rather than clamp.
	c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
	c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
	c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
	c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
}

/// Loads every `texture.<stage>.<sampler>` binding that names a plain image inside the pack.
///
/// Deliberately narrow. Three forms appear across the fixture packs and only one is honestly
/// supportable here:
///
/// - `lib/textures/cloud-water.png` - a file in the pack. Loaded.
/// - `minecraft:textures/environment/clouds.png` - a *game asset*. Cubyz has no such file, and
///   inventing one would be fabrication rather than a bridge, so it is skipped and counted.
/// - `image/curl3D.dat TEXTURE_3D RGB8 64 64 64 ...` - a raw volume with an explicit format, used by
///   Kappa and photon for cloud noise. A real feature, and a different one: it needs 3D texture
///   support and a binary reader. Skipped and counted, so the gap stays visible in the log rather
///   than looking like it worked.
/// One raw texture format, resolved from the directive's `<internal> ... <format> <type>` tokens.
const RawFormat = struct {
	internal: c_int,
	format: c_uint,
	pixelType: c_uint,
	/// How many bytes one texel occupies in the file, which is what makes the size check possible.
	bytesPerTexel: usize,
};

/// The `blur`/`clamp` pair a texture is filtered and wrapped by.
///
/// Both default to true for a raw definition and false for an image, which is Iris's rule in
/// `ShaderPack.java`: `boolean blur = definition instanceof TextureDefinition.RawDefinition;`. A
/// sibling `.mcmeta` overrides either. It is not a detail that can be guessed: a scattering LUT
/// wrapped with `GL_REPEAT` instead of clamped folds its horizon row onto its zenith row, which
/// reads as a hard band across the sky rather than as an obvious error.
const Filtering = struct {
	blur: bool = true,
	clamp: bool = true,
};

fn glInternalFormat(name: []const u8) ?c_int {
	const table = [_]struct {name: []const u8, value: c_int}{
		.{.name = "R8", .value = c.GL_R8}, .{.name = "RG8", .value = c.GL_RG8},
		.{.name = "RGB8", .value = c.GL_RGB8}, .{.name = "RGBA8", .value = c.GL_RGBA8},
		.{.name = "R16", .value = c.GL_R16}, .{.name = "RG16", .value = c.GL_RG16},
		.{.name = "RGB16", .value = c.GL_RGB16}, .{.name = "RGBA16", .value = c.GL_RGBA16},
		.{.name = "R16F", .value = c.GL_R16F}, .{.name = "RG16F", .value = c.GL_RG16F},
		.{.name = "RGB16F", .value = c.GL_RGB16F}, .{.name = "RGBA16F", .value = c.GL_RGBA16F},
		.{.name = "R32F", .value = c.GL_R32F}, .{.name = "RG32F", .value = c.GL_RG32F},
		.{.name = "RGB32F", .value = c.GL_RGB32F}, .{.name = "RGBA32F", .value = c.GL_RGBA32F},
	};
	for(table) |entry| {
		if(std.ascii.eqlIgnoreCase(entry.name, name)) return entry.value;
	}
	return null;
}

fn glPixelFormat(name: []const u8) ?struct {value: c_uint, components: usize} {
	const table = [_]struct {name: []const u8, value: c_uint, components: usize}{
		.{.name = "RED", .value = c.GL_RED, .components = 1},
		.{.name = "RG", .value = c.GL_RG, .components = 2},
		.{.name = "RGB", .value = c.GL_RGB, .components = 3},
		.{.name = "RGBA", .value = c.GL_RGBA, .components = 4},
	};
	for(table) |entry| {
		if(std.ascii.eqlIgnoreCase(entry.name, name)) return .{.value = entry.value, .components = entry.components};
	}
	return null;
}

fn glPixelType(name: []const u8) ?struct {value: c_uint, size: usize} {
	const table = [_]struct {name: []const u8, value: c_uint, size: usize}{
		.{.name = "UNSIGNED_BYTE", .value = c.GL_UNSIGNED_BYTE, .size = 1},
		.{.name = "BYTE", .value = c.GL_BYTE, .size = 1},
		.{.name = "UNSIGNED_SHORT", .value = c.GL_UNSIGNED_SHORT, .size = 2},
		.{.name = "SHORT", .value = c.GL_SHORT, .size = 2},
		.{.name = "HALF_FLOAT", .value = c.GL_HALF_FLOAT, .size = 2},
		.{.name = "UNSIGNED_INT", .value = c.GL_UNSIGNED_INT, .size = 4},
		.{.name = "INT", .value = c.GL_INT, .size = 4},
		.{.name = "FLOAT", .value = c.GL_FLOAT, .size = 4},
	};
	for(table) |entry| {
		if(std.ascii.eqlIgnoreCase(entry.name, name)) return .{.value = entry.value, .size = entry.size};
	}
	return null;
}

/// Reads `blur` and `clamp` out of a sibling `.mcmeta`, leaving the raw defaults where it says
/// nothing.
///
/// A targeted scan rather than a JSON parser: the file is a fixed two-key shape written by pack
/// authors, and the only values that matter are the two booleans. An unreadable or unexpected file
/// leaves the defaults, which is the same thing Iris does with a malformed one.
fn readFiltering(allocator: NeverFailingAllocator, path: []const u8) Filtering {
	var result = Filtering{};
	var metaPath = List(u8).init(allocator);
	defer metaPath.deinit();
	metaPath.appendSlice(path);
	metaPath.appendSlice(".mcmeta");

	const text = main.files.cwd().read(allocator, metaPath.items) catch return result;
	defer allocator.free(text);

	inline for(.{"blur", "clamp"}) |key| {
		if(std.mem.indexOf(u8, text, "\"" ++ key ++ "\"")) |start| {
			const after = text[start + key.len + 2 ..];
			const value = std.mem.indexOfScalar(u8, after, ':');
			if(value) |colon| {
				const tail = std.mem.trimStart(u8, after[colon + 1 ..], " \t\r\n");
				if(std.mem.startsWith(u8, tail, "true")) @field(result, key) = true;
				if(std.mem.startsWith(u8, tail, "false")) @field(result, key) = false;
			}
		}
	}
	return result;
}

/// Uploads a raw volume from the pack, returning its texture name.
///
/// The size check is the important part and is not defensive padding: the file is read as bytes and
/// handed to the driver as `width*height*depth` texels, so a file shorter than the directive claims
/// would have GL read past the end of the buffer. A pack that ships a truncated volume, or a
/// directive whose dimensions are wrong, must be refused rather than trusted.
fn loadRawVolume(
	allocator: NeverFailingAllocator,
	filePath: []const u8,
	format: RawFormat,
	size: [3]usize,
	filtering: Filtering,
) ?c_uint {
	const bytes = main.files.cwd().read(allocator, filePath) catch return null;
	defer allocator.free(bytes);

	const expected = size[0]*size[1]*size[2]*format.bytesPerTexel;
	if(bytes.len < expected) {
		std.log.warn("irisbridge: {s} holds {} bytes but the directive describes {} — refusing to upload it", .{filePath, bytes.len, expected});
		return null;
	}

	var id: c_uint = undefined;
	c.glGenTextures(1, &id);
	c.glBindTexture(c.GL_TEXTURE_3D, id);
	// Rows in a raw volume are packed with no padding; the default of 4 would skew every row of a
	// single-channel or three-channel volume whose width is not a multiple of it.
	var previousAlignment: c_int = 4;
	c.glGetIntegerv(c.GL_UNPACK_ALIGNMENT, &previousAlignment);
	c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
	c.glTexImage3D(
		c.GL_TEXTURE_3D, 0, format.internal,
		@intCast(size[0]), @intCast(size[1]), @intCast(size[2]), 0,
		format.format, format.pixelType, bytes.ptr,
	);
	c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, previousAlignment);

	const filter: c_int = if(filtering.blur) c.GL_LINEAR else c.GL_NEAREST;
	const wrap: c_int = if(filtering.clamp) c.GL_CLAMP_TO_EDGE else c.GL_REPEAT;
	c.glTexParameteri(c.GL_TEXTURE_3D, c.GL_TEXTURE_MIN_FILTER, filter);
	c.glTexParameteri(c.GL_TEXTURE_3D, c.GL_TEXTURE_MAG_FILTER, filter);
	c.glTexParameteri(c.GL_TEXTURE_3D, c.GL_TEXTURE_WRAP_S, wrap);
	c.glTexParameteri(c.GL_TEXTURE_3D, c.GL_TEXTURE_WRAP_T, wrap);
	c.glTexParameteri(c.GL_TEXTURE_3D, c.GL_TEXTURE_WRAP_R, wrap);
	// No mipmaps, matching Iris's `GlTexture`, which pins MAX_LEVEL at 0 for every custom texture.
	// A LUT has no meaningful reduction and a `LINEAR_MIPMAP_*` filter over a chain that was never
	// generated samples an undefined level.
	c.glTexParameteri(c.GL_TEXTURE_3D, c.GL_TEXTURE_MAX_LEVEL, 0);
	c.glBindTexture(c.GL_TEXTURE_3D, 0);
	return id;
}

fn loadCustomTextures(allocator: NeverFailingAllocator, shadersRoot: []const u8, properties: *const pack.Properties) []Custom {
	var list = List(Custom).init(allocator);
	var skippedAssets: usize = 0;
	var skippedVolumes: usize = 0;

	var iterator = properties.entries.iterator();
	while(iterator.next()) |entry| {
		const key = entry.key_ptr.*;
		if(!std.mem.startsWith(u8, key, "texture.")) continue;
		const rest = key["texture.".len..];
		const dot = std.mem.indexOfScalar(u8, rest, '.') orelse continue; // `texture.noise` has no stage.
		const stage = Stage.parse(rest[0..dot]) orelse continue;
		// `texture.deferred.colortex6.1` names a mip level; the base image is what matters here.
		var samplerName = rest[dot + 1 ..];
		if(std.mem.indexOfScalar(u8, samplerName, '.')) |second| samplerName = samplerName[0..second];
		const unit = samplerUnit(samplerName) orelse continue;

		const value = std.mem.trim(u8, entry.value_ptr.*, " \t");
		if(std.mem.indexOfScalar(u8, value, ':') != null) {
			// The one game asset packs bind is the vanilla cloud texture, read as a tiling mask
			// by Mellow's blocky clouds (over colortex3) and photon's vanilla cloud style (over
			// depthtex2). Skipping it left the sampler on the render target that shares the unit,
			// so a generated mask of the same size, values and tiling stands in; see `cloudmask`.
			if(std.mem.eql(u8, value, cloudmask.minecraftPath)) {
				const id = vanillaCloudsTexture(allocator);
				list.append(.{.stage = stage, .unit = unit, .id = id, .target = c.GL_TEXTURE_2D});
				std.log.info("irisbridge: {s} -> generated stand-in for {s} ({}x{}) on unit {}", .{key, value, cloudmask.size, cloudmask.size, unit});
				continue;
			}
			skippedAssets += 1;
			continue;
		}

		// A trailing format spec means a raw binary volume rather than an image file. Iris's grammar
		// is `<path> <type> <internal> <sizes...> <format> <pixelType>`, with six, seven or eight
		// tokens for 1D, 2D and 3D respectively.
		var tokens = std.mem.tokenizeAny(u8, value, " \t");
		var parts: [8][]const u8 = undefined;
		var partCount: usize = 0;
		while(tokens.next()) |token| {
			if(partCount == parts.len) {
				partCount = parts.len + 1; // Too many; falls through to the unsupported branch below.
				break;
			}
			parts[partCount] = token;
			partCount += 1;
		}
		if(partCount == 0) continue;

		var path = List(u8).init(allocator);
		defer path.deinit();
		path.appendSlice(shadersRoot);
		if(parts[0].len != 0 and parts[0][0] != '/') path.append('/');
		path.appendSlice(parts[0]);

		if(partCount != 1) {
			// Only the 3D form appears in any pack here, and it is the one that matters: photon binds
			// its atmospheric scattering LUT over `depthtex0` and its cloud noise over colortex6/7,
			// while Kappa uses the same mechanism for cloud shape. Without them a pack's sky, clouds
			// and fog all sample an unrelated 2D render target through a `sampler3D` declaration.
			if(partCount != 8 or !std.ascii.eqlIgnoreCase(parts[1], "TEXTURE_3D")) {
				std.log.info("irisbridge: {s} is a raw {s} binding, which is not supported yet", .{key, if(partCount > 1) parts[1] else "texture"});
				skippedVolumes += 1;
				continue;
			}
			const internal = glInternalFormat(parts[2]) orelse {
				std.log.warn("irisbridge: {s} names an unrecognised internal format '{s}'", .{key, parts[2]});
				skippedVolumes += 1;
				continue;
			};
			const pixelFormat = glPixelFormat(parts[6]) orelse {
				std.log.warn("irisbridge: {s} names an unrecognised pixel format '{s}'", .{key, parts[6]});
				skippedVolumes += 1;
				continue;
			};
			const pixelType = glPixelType(parts[7]) orelse {
				std.log.warn("irisbridge: {s} names an unrecognised pixel type '{s}'", .{key, parts[7]});
				skippedVolumes += 1;
				continue;
			};
			var size: [3]usize = undefined;
			var sizesParsed = true;
			for(0..3) |axis| {
				size[axis] = std.fmt.parseInt(usize, parts[3 + axis], 10) catch blk: {
					sizesParsed = false;
					break :blk 0;
				};
			}
			if(!sizesParsed or size[0] == 0 or size[1] == 0 or size[2] == 0) {
				std.log.warn("irisbridge: {s} has unreadable dimensions", .{key});
				skippedVolumes += 1;
				continue;
			}

			const filtering = readFiltering(allocator, path.items);
			const id = loadRawVolume(allocator, path.items, .{
				.internal = internal,
				.format = pixelFormat.value,
				.pixelType = pixelType.value,
				.bytesPerTexel = pixelFormat.components*pixelType.size,
			}, size, filtering) orelse {
				skippedVolumes += 1;
				continue;
			};

			list.append(.{.stage = stage, .unit = unit, .id = id, .target = c.GL_TEXTURE_3D});
			std.log.info("irisbridge: {s} -> {s} ({}x{}x{} {s}) on unit {}{s}", .{
				key, parts[0], size[0], size[1], size[2], parts[2], unit,
				if(filtering.clamp) " clamped" else " repeating",
			});
			continue;
		}

		const image = main.graphics.Image.readFromFile(allocator, path.items, .{.orientation = .openGl}) catch {
			std.log.warn("irisbridge: {s} names {s}, which could not be read", .{key, value});
			continue;
		};
		defer image.deinit(allocator);

		var id: c_uint = undefined;
		c.glGenTextures(1, &id);
		c.glBindTexture(c.GL_TEXTURE_2D, id);
		c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA8, @intCast(image.width), @intCast(image.height), 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, image.imageData.ptr);
		// Repeat and mipmapped, because these are tiling noise sampled at several scales at once -
		// Complementary's water reads its wave map at 0.05x, 0.25x, 1x and 4x in the same fragment.
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR_MIPMAP_LINEAR);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
		c.glGenerateMipmap(c.GL_TEXTURE_2D);

		list.append(.{.stage = stage, .unit = unit, .id = id});
		std.log.info("irisbridge: {s} -> {s} ({}x{}) on unit {}", .{key, value, image.width, image.height, unit});
	}
	c.glBindTexture(c.GL_TEXTURE_2D, 0);

	if(skippedAssets != 0) {
		std.log.info("irisbridge: {} texture binding(s) name Minecraft assets Cubyz does not have, and are skipped", .{skippedAssets});
	}
	if(skippedVolumes != 0) {
		std.log.info("irisbridge: {} texture binding(s) are raw 3D volumes, which are not supported yet", .{skippedVolumes});
	}
	return list.toOwnedSlice();
}

pub fn init(allocator: NeverFailingAllocator, shadersRoot: []const u8, noiseResolution: u32, declaredNoisePath: []const u8, properties: *const pack.Properties) Set {
	return .{
		.allocator = allocator,
		.customs = loadCustomTextures(allocator, shadersRoot, properties),
		.named = loadNamedTextures(allocator, shadersRoot, properties),
		.sun = generateSheet(allocator, sunSize, sunSize, sunTexel),
		.moon = generateSheet(allocator, moonSheetWidth, moonSheetHeight, moonTexel),
		.noise = loadNoise(allocator, shadersRoot, @max(noiseResolution, 1), declaredNoisePath),
		// LabPBR flat normal: (0.5, 0.5) is a zero tangent-space XY, and the blue and alpha
		// channels are unused by the encoding.
		.normals = constantTexture(128, 128, 255, 255),
		// LabPBR specular: red 0 is fully rough, green 0 is non-metallic, and the rest is unused.
		// Reads as "ordinary matte surface" rather than as missing data.
		.specular = constantTexture(0, 0, 0, 0),
	};
}

// MARK: tests

const testing = std.testing;

test "the sun sheet is opaque at its centre and gone at its edge" {
	try testing.expectEqual(@as(u8, 255), sunTexel(sunSize/2, sunSize/2)[3]);
	try testing.expectEqual(@as(u8, 0), sunTexel(0, 0)[3]);
	try testing.expectEqual(@as(u8, 0), sunTexel(sunSize - 1, sunSize/2)[3]);
	// Inside three tenths of the half-width it is still fully opaque; past two thirds it is gone,
	// so the disc sits well inside its sixty-unit quad as the vanilla one does.
	try testing.expectEqual(@as(u8, 255), sunTexel(sunSize/2 + sunSize/8, sunSize/2)[3]);
	try testing.expectEqual(@as(u8, 0), sunTexel(sunSize/2 + (sunSize*3)/8, sunSize/2)[3]);
}

test "the moon sheet lights each phase's disc on the side Minecraft's sheet does" {
	const centre = moonCell/2;
	const left = moonCell/4;
	const right = moonCell - moonCell/4 - 1;
	// Phase 0, the full moon, in the first cell: lit across.
	try testing.expect(moonTexel(left, centre)[3] != 0);
	try testing.expect(moonTexel(right, centre)[3] != 0);
	// Phase 2, the third quarter: the left half. Phase 6, the first quarter: the right half.
	try testing.expect(moonTexel(2*moonCell + left, centre)[3] != 0);
	try testing.expect(moonTexel(2*moonCell + right, centre)[3] == 0);
	try testing.expect(moonTexel(2*moonCell + left, moonCell + centre)[3] != 0);
	try testing.expect(moonTexel(2*moonCell + right, moonCell + centre)[3] == 0);
	// Phase 4, the new moon, in the second row's first cell: nothing lit.
	try testing.expect(moonTexel(centre, moonCell + centre)[3] == 0);
	// Outside every disc is transparent, and the lit colour is the pale grey.
	try testing.expect(moonTexel(0, 0)[3] == 0);
	try testing.expectEqual([4]u8{230, 230, 220, 255}, moonTexel(centre, centre));
}
