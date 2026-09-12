//! `colortex0`-`colortex15` and the depth textures: allocation, framebuffer attachment, and
//! sampler binding.
//!
//! The ping-pong bookkeeping that decides which physical texture each pass reads and writes lives
//! in `flip.zig`, kept separate so it can be tested without a GL context. This file is the part
//! that necessarily touches OpenGL.

const std = @import("std");

const main = @import("main");
const c = main.c;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const List = main.ListManaged;

const pack = @import("pack.zig");
const images = @import("images.zig");
pub const flip = @import("flip.zig");

pub const colortexCount = flip.colortexCount;
pub const FlipState = flip.FlipState;
pub const Side = flip.Side;
pub const PassBindings = flip.PassBindings;
pub const resolveBindings = flip.resolveBindings;

// MARK: formats

/// GL internal format, upload format and type for a pack-declared buffer format.
///
/// Values follow Iris's `InternalTextureFormat`. The upload format/type only matter for the
/// initial allocation, since the contents are always written by rendering rather than uploaded.
pub const GlFormat = struct {
	internal: c_int,
	format: c_uint,
	dataType: c_uint,
};

pub fn glFormat(format: pack.TextureFormat) GlFormat {
	return switch(format) {
		.r8 => .{.internal = c.GL_R8, .format = c.GL_RED, .dataType = c.GL_UNSIGNED_BYTE},
		.rg8 => .{.internal = c.GL_RG8, .format = c.GL_RG, .dataType = c.GL_UNSIGNED_BYTE},
		.rgb8 => .{.internal = c.GL_RGB8, .format = c.GL_RGB, .dataType = c.GL_UNSIGNED_BYTE},
		.rgba8 => .{.internal = c.GL_RGBA8, .format = c.GL_RGBA, .dataType = c.GL_UNSIGNED_BYTE},
		.r16 => .{.internal = c.GL_R16, .format = c.GL_RED, .dataType = c.GL_UNSIGNED_SHORT},
		.rg16 => .{.internal = c.GL_RG16, .format = c.GL_RG, .dataType = c.GL_UNSIGNED_SHORT},
		.rgb16 => .{.internal = c.GL_RGB16, .format = c.GL_RGB, .dataType = c.GL_UNSIGNED_SHORT},
		.rgba16 => .{.internal = c.GL_RGBA16, .format = c.GL_RGBA, .dataType = c.GL_UNSIGNED_SHORT},
		.r16f => .{.internal = c.GL_R16F, .format = c.GL_RED, .dataType = c.GL_FLOAT},
		.rg16f => .{.internal = c.GL_RG16F, .format = c.GL_RG, .dataType = c.GL_FLOAT},
		.rgb16f => .{.internal = c.GL_RGB16F, .format = c.GL_RGB, .dataType = c.GL_FLOAT},
		.rgba16f => .{.internal = c.GL_RGBA16F, .format = c.GL_RGBA, .dataType = c.GL_FLOAT},
		.r32f => .{.internal = c.GL_R32F, .format = c.GL_RED, .dataType = c.GL_FLOAT},
		.rg32f => .{.internal = c.GL_RG32F, .format = c.GL_RG, .dataType = c.GL_FLOAT},
		.rgb32f => .{.internal = c.GL_RGB32F, .format = c.GL_RGB, .dataType = c.GL_FLOAT},
		.rgba32f => .{.internal = c.GL_RGBA32F, .format = c.GL_RGBA, .dataType = c.GL_FLOAT},
		.r11f_g11f_b10f => .{.internal = c.GL_R11F_G11F_B10F, .format = c.GL_RGB, .dataType = c.GL_FLOAT},
		.rgb10_a2 => .{.internal = c.GL_RGB10_A2, .format = c.GL_RGBA, .dataType = c.GL_UNSIGNED_INT_2_10_10_10_REV},
		.srgb8 => .{.internal = c.GL_SRGB8, .format = c.GL_RGB, .dataType = c.GL_UNSIGNED_BYTE},
		.srgb8_alpha8 => .{.internal = c.GL_SRGB8_ALPHA8, .format = c.GL_RGBA, .dataType = c.GL_UNSIGNED_BYTE},
		.r8_snorm => .{.internal = c.GL_R8_SNORM, .format = c.GL_RED, .dataType = c.GL_BYTE},
		.rg8_snorm => .{.internal = c.GL_RG8_SNORM, .format = c.GL_RG, .dataType = c.GL_BYTE},
		.rgb8_snorm => .{.internal = c.GL_RGB8_SNORM, .format = c.GL_RGB, .dataType = c.GL_BYTE},
		.rgba8_snorm => .{.internal = c.GL_RGBA8_SNORM, .format = c.GL_RGBA, .dataType = c.GL_BYTE},
		.r16_snorm => .{.internal = c.GL_R16_SNORM, .format = c.GL_RED, .dataType = c.GL_SHORT},
		.rg16_snorm => .{.internal = c.GL_RG16_SNORM, .format = c.GL_RG, .dataType = c.GL_SHORT},
		.rgb16_snorm => .{.internal = c.GL_RGB16_SNORM, .format = c.GL_RGB, .dataType = c.GL_SHORT},
		.rgba16_snorm => .{.internal = c.GL_RGBA16_SNORM, .format = c.GL_RGBA, .dataType = c.GL_SHORT},
		// Integer formats upload through the `_INTEGER` formats; the plain ones are an error.
		.r8i => .{.internal = c.GL_R8I, .format = c.GL_RED_INTEGER, .dataType = c.GL_BYTE},
		.rg8i => .{.internal = c.GL_RG8I, .format = c.GL_RG_INTEGER, .dataType = c.GL_BYTE},
		.rgb8i => .{.internal = c.GL_RGB8I, .format = c.GL_RGB_INTEGER, .dataType = c.GL_BYTE},
		.rgba8i => .{.internal = c.GL_RGBA8I, .format = c.GL_RGBA_INTEGER, .dataType = c.GL_BYTE},
		.r8ui => .{.internal = c.GL_R8UI, .format = c.GL_RED_INTEGER, .dataType = c.GL_UNSIGNED_BYTE},
		.rg8ui => .{.internal = c.GL_RG8UI, .format = c.GL_RG_INTEGER, .dataType = c.GL_UNSIGNED_BYTE},
		.rgb8ui => .{.internal = c.GL_RGB8UI, .format = c.GL_RGB_INTEGER, .dataType = c.GL_UNSIGNED_BYTE},
		.rgba8ui => .{.internal = c.GL_RGBA8UI, .format = c.GL_RGBA_INTEGER, .dataType = c.GL_UNSIGNED_BYTE},
		.r16i => .{.internal = c.GL_R16I, .format = c.GL_RED_INTEGER, .dataType = c.GL_SHORT},
		.rg16i => .{.internal = c.GL_RG16I, .format = c.GL_RG_INTEGER, .dataType = c.GL_SHORT},
		.rgb16i => .{.internal = c.GL_RGB16I, .format = c.GL_RGB_INTEGER, .dataType = c.GL_SHORT},
		.rgba16i => .{.internal = c.GL_RGBA16I, .format = c.GL_RGBA_INTEGER, .dataType = c.GL_SHORT},
		.r16ui => .{.internal = c.GL_R16UI, .format = c.GL_RED_INTEGER, .dataType = c.GL_UNSIGNED_SHORT},
		.rg16ui => .{.internal = c.GL_RG16UI, .format = c.GL_RG_INTEGER, .dataType = c.GL_UNSIGNED_SHORT},
		.rgb16ui => .{.internal = c.GL_RGB16UI, .format = c.GL_RGB_INTEGER, .dataType = c.GL_UNSIGNED_SHORT},
		.rgba16ui => .{.internal = c.GL_RGBA16UI, .format = c.GL_RGBA_INTEGER, .dataType = c.GL_UNSIGNED_SHORT},
		.r32i => .{.internal = c.GL_R32I, .format = c.GL_RED_INTEGER, .dataType = c.GL_INT},
		.rg32i => .{.internal = c.GL_RG32I, .format = c.GL_RG_INTEGER, .dataType = c.GL_INT},
		.rgb32i => .{.internal = c.GL_RGB32I, .format = c.GL_RGB_INTEGER, .dataType = c.GL_INT},
		.rgba32i => .{.internal = c.GL_RGBA32I, .format = c.GL_RGBA_INTEGER, .dataType = c.GL_INT},
		.r32ui => .{.internal = c.GL_R32UI, .format = c.GL_RED_INTEGER, .dataType = c.GL_UNSIGNED_INT},
		.rg32ui => .{.internal = c.GL_RG32UI, .format = c.GL_RG_INTEGER, .dataType = c.GL_UNSIGNED_INT},
		.rgb32ui => .{.internal = c.GL_RGB32UI, .format = c.GL_RGB_INTEGER, .dataType = c.GL_UNSIGNED_INT},
		.rgba32ui => .{.internal = c.GL_RGBA32UI, .format = c.GL_RGBA_INTEGER, .dataType = c.GL_UNSIGNED_INT},
		.rgb9_e5 => .{.internal = c.GL_RGB9_E5, .format = c.GL_RGB, .dataType = c.GL_UNSIGNED_INT_5_9_9_9_REV},
		.rgb5_a1 => .{.internal = c.GL_RGB5_A1, .format = c.GL_RGBA, .dataType = c.GL_UNSIGNED_SHORT_5_5_5_1},
		.r3_g3_b2 => .{.internal = c.GL_R3_G3_B2, .format = c.GL_RGB, .dataType = c.GL_UNSIGNED_BYTE_3_3_2},
	};
}

/// translate-c gives the GL constants `c_int`, so mixing them with computed `c_uint` indices
/// needs an explicit widening. Wrapped rather than repeated at each call site.
fn glEnum(value: anytype) c_uint {
	return @intCast(value);
}

// MARK: GPU resources

pub const Target = struct {
	main: c_uint = 0,
	alt: c_uint = 0,
	format: pack.TextureFormat = .rgba8,
	clear: bool = true,
	/// What `clear` fills the buffer with, from the pack's `colortexNClearColor` or Iris's default
	/// for the slot; see `defaultClearColor`.
	clearColor: [4]f32 = .{0, 0, 0, 0},
	/// The buffer's own size, or 0 meaning "follows the screen".
	///
	/// A pack that declares `size.buffer.colortex4 = 256 256` does its maths in that size, so the
	/// allocation has to match. Nostalgia renders a sky capture through a 256x256 directional
	/// projection and samples it back by direction; allocated at screen size instead, the capture
	/// lands in the wrong part of the wrong texture and the sky reconstructs as a flat wash with no
	/// gradient and no sun - with nothing wrong anywhere else.
	width: u31 = 0,
	height: u31 = 0,

	pub fn texture(self: Target, side: Side) c_uint {
		return switch(side) {
			.main => self.main,
			.alt => self.alt,
		};
	}
};

/// Iris's clear colour for a colortex slot with no `ClearColor` directive
/// (`ClearPassCreator.java:34-43`): colortex1 solid white, everything else transparent black.
/// colortex0 is cleared to Minecraft's fog colour there, with alpha 1; here it is black with alpha
/// 1, since what stands in for the vanilla sky is blitted over it before geometry draws
/// (`bridge.beginTerrain`) and a pack that draws its own sky covers it anyway.
///
/// The white default is not decorative. Iris's own comment calls it out separately, and a pack
/// that reads colortex1 where its geometry never wrote it gets white under Iris; cleared to zero,
/// Kappa's `colortex15` - asked for as `vec4(0.0, 1.0, 0.0, 0.0)`, its `.y` the ambient occlusion
/// term - read as fully occluded wherever nothing drew.
pub fn defaultClearColor(index: usize) [4]f32 {
	return switch(index) {
		0 => .{0, 0, 0, 1},
		1 => .{1, 1, 1, 1},
		else => .{0, 0, 0, 0},
	};
}

/// The depth textures a pack can sample.
///
/// `depthtex0` is the live depth buffer. `depthtex1` and `depthtex2` are snapshots taken at
/// points in the frame where Minecraft has drawn progressively less: `depthtex1` excludes
/// translucents, `depthtex2` also excludes the handheld item. Packs use the difference to detect
/// what is behind water. Cubyz's frame has an equivalent split point before transparent chunk
/// meshes are drawn, which is where the `depthtex1` copy is taken; it has no handheld item, so
/// `depthtex2` is a copy of `depthtex1` rather than a third distinct state.
pub const DepthKind = enum(u2) {all = 0, noTranslucent = 1, noHand = 2};

/// Whether a format's texels are integers, which GL samples only with a nearest filter.
pub fn isIntegerFormat(format: pack.TextureFormat) bool {
	const gl = glFormat(format);
	return gl.format == c.GL_RED_INTEGER or gl.format == c.GL_RG_INTEGER or gl.format == c.GL_RGB_INTEGER or gl.format == c.GL_RGBA_INTEGER;
}

pub const RenderTargets = struct {
	width: u31 = 0,
	height: u31 = 0,
	color: [colortexCount]Target = @splat(.{}),
	/// Buffers whose read side was given a mipmap chain and filter this frame, for
	/// `resetMipmapping`.
	mipmappedThisFrame: u16 = 0,
	/// Set by `updateSize`, consumed by the next `clear`: every buffer is cleared once after it is
	/// (re)allocated, `colortexNClear = false` ones included. `glTexImage2D` with no data leaves
	/// whatever the driver had in that memory, and Iris clears it all on creation and on every
	/// resize (`IrisRenderingPipeline.java:951-956`, `isFullClearRequired`, with the `fullClear`
	/// variant of `ClearPassCreator`). Without it Bliss's colortex1 - its G-buffer, never cleared
	/// by the pack - opened as a red screen on the first load and stayed that way until a window
	/// resize happened to hand it fresh memory.
	fullClearPending: bool = false,
	/// The `size.buffer.<name>` declarations, resolved per resize rather than at load - Iris's rule
	/// is per axis, and a value containing a `.` is a *fraction of the screen* rather than pixels.
	declaredSize: [colortexCount]?[2]pack.BufferAxis = @splat(null),
	depth: [3]c_uint = @splat(0),
	/// Depth textures for `shadowtex0`/`shadowtex1`, with comparison sampling enabled.
	///
	/// Allocated even though no shadow pass renders into them yet. A pack declares
	/// `uniform sampler2DShadow shadowtex0;` unconditionally, and leaving it bound to whatever
	/// occupies unit 0 means a shadow sampler reading a colour texture, which the driver calls
	/// out as undefined behaviour. Cleared to depth 1.0 so every lookup reports "unoccluded",
	/// which is the correct stand-in for "no shadow map yet".
	/// Side length of the shadow textures, from the pack's `const int shadowMapResolution`.
	shadowResolution: c_int = defaultShadowResolution,
	shadow: [2]c_uint = @splat(0),
	/// `shadowcolor0` to `shadowcolor7`, each a main and alt pair like a colortex, because a
	/// `shadowcomp` pass samples the buffer it draws - Kappa's caustics read `shadowcolor0` and
	/// write it back. The shadow pass writes `main`; which side a later program reads is
	/// `PassBindings.shadowRead`, resolved over the `shadowcomp` chain at load.
	shadowColor: [flip.shadowColorCount]c_uint = @splat(0),
	shadowColorAlt: [flip.shadowColorCount]c_uint = @splat(0),
	/// Which of the eight exist. Iris allocates a shadow colour buffer on first use
	/// (`ShadowRenderTargets.getOrCreate`), and so does this: `pack.shadowColorUsage` names the
	/// ones the pack's sources mention, the loader stamps it here before the first `updateSize`,
	/// and the other pairs are never given storage, cleared, or bound. The first two are always on.
	shadowColorUsed: [flip.shadowColorCount]bool = .{true, true} ++ .{false} ** (flip.shadowColorCount - 2),
	/// From the pack's `shadowcolorNFormat`. A pack storing positions or normals in its shadow
	/// colour buffer asks for a float format, and RGBA8 quantises those to eight bits per channel.
	shadowColorFormat: [flip.shadowColorCount]pack.TextureFormat = @splat(.rgba8),
	/// Whether each shadow colour buffer is cleared before the shadow pass, and to what. Iris
	/// clears each to opaque white every frame unless `shadowcolorNClear`/`shadowcolorNClearColor`
	/// say otherwise, and the pack's `shadow.fsh` then writes the caster's colour over that.
	/// Until 2026-09-07 these were neither cleared nor attached, so a pack reading `shadowcolor0`
	/// for its coloured shadows got memory nothing had ever written.
	shadowColorClear: [flip.shadowColorCount]bool = @splat(true),
	shadowColorClearColor: [flip.shadowColorCount][4]f32 = @splat(.{1, 1, 1, 1}),
	/// `GL_MAX_IMAGE_UNITS`. Image units are separate from texture units and there are fewer of
	/// them, so `bindImages` hands them out to the images a program actually declares.
	maxImageUnits: c_uint = 8,
	/// Two sampler objects over the same shadow textures: one doing depth comparison, one not.
	///
	/// A single pack declares `shadowtex0` both ways in different programs - Nostalgia has
	/// `uniform sampler2D shadowtex0;` in some and `uniform sampler2DShadow shadowtex0;` in others
	/// - and a texture has only one `GL_TEXTURE_COMPARE_MODE`. Sampler objects override texture
	/// sampling state at bind time, so the choice can be made per program instead, which is how
	/// Iris handles it.
	shadowSamplerCompare: c_uint = 0,
	shadowSamplerPlain: c_uint = 0,
	/// `GL_MAX_COLOR_ATTACHMENTS`, which is 8 on most desktop drivers even though the shaderpack
	/// format allows 16 colortex buffers. Touching an attachment past the limit is an error, not
	/// a no-op, so every loop over attachments is clamped to this.
	maxColorAttachments: usize = 8,
	/// Reused for every pass; contents rewritten per pass by `bindForPass`.
	framebuffer: c_uint = 0,

	pub fn init(settings: *const pack.Settings) RenderTargets {
		var self = RenderTargets{};
		self.declaredSize = settings.colortexSize;
		// The shadow map follows the pack, clamped so a request the hardware cannot meet degrades
		// instead of silently failing to allocate.
		var maxTexture: c_int = 4096;
		c.glGetIntegerv(c.GL_MAX_TEXTURE_SIZE, &maxTexture);
		self.shadowResolution = @min(@as(c_int, @intCast(settings.shadowMapResolution)), maxTexture);
		var limit: c_int = 8;
		c.glGetIntegerv(c.GL_MAX_COLOR_ATTACHMENTS, &limit);
		self.maxColorAttachments = @intCast(@max(limit, 1));
		var imageUnits: c_int = 8;
		c.glGetIntegerv(c.GL_MAX_IMAGE_UNITS, &imageUnits);
		self.maxImageUnits = @intCast(@max(imageUnits, 0));
		self.shadowColorFormat = settings.shadowcolorFormat;
		self.shadowColorClear = settings.shadowcolorClear;
		for(settings.shadowcolorClearColor, 0..) |declared, index| {
			// Opaque white is Iris's default for every shadow colour buffer
			// (`PackShadowDirectives.SamplingSettings`), not colortex1's white-and-black split.
			self.shadowColorClearColor[index] = declared orelse .{1, 1, 1, 1};
		}
		c.glGenFramebuffers(1, &self.framebuffer);

		c.glGenSamplers(1, &self.shadowSamplerCompare);
		c.glSamplerParameteri(self.shadowSamplerCompare, c.GL_TEXTURE_COMPARE_MODE, c.GL_COMPARE_REF_TO_TEXTURE);
		c.glSamplerParameteri(self.shadowSamplerCompare, c.GL_TEXTURE_COMPARE_FUNC, c.GL_LEQUAL);
		c.glSamplerParameteri(self.shadowSamplerCompare, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
		c.glSamplerParameteri(self.shadowSamplerCompare, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
		c.glSamplerParameteri(self.shadowSamplerCompare, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
		c.glSamplerParameteri(self.shadowSamplerCompare, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);

		c.glGenSamplers(1, &self.shadowSamplerPlain);
		c.glSamplerParameteri(self.shadowSamplerPlain, c.GL_TEXTURE_COMPARE_MODE, c.GL_NONE);
		c.glSamplerParameteri(self.shadowSamplerPlain, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
		c.glSamplerParameteri(self.shadowSamplerPlain, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
		c.glSamplerParameteri(self.shadowSamplerPlain, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
		c.glSamplerParameteri(self.shadowSamplerPlain, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
		for(&self.color, 0..) |*target, index| {
			target.format = settings.colortexFormat[index];
			target.clear = settings.colortexClear[index];
			target.clearColor = settings.colortexClearColor[index] orelse defaultClearColor(index);
			c.glGenTextures(1, &target.main);
			c.glGenTextures(1, &target.alt);
		}
		for(&self.depth) |*texture| {
			c.glGenTextures(1, texture);
		}
		for(&self.shadow) |*texture| {
			c.glGenTextures(1, texture);
		}
		for(&self.shadowColor) |*texture| {
			c.glGenTextures(1, texture);
		}
		for(&self.shadowColorAlt) |*texture| {
			c.glGenTextures(1, texture);
		}
		return self;
	}

	pub fn deinit(self: *RenderTargets) void {
		for(&self.color) |*target| {
			c.glDeleteTextures(1, &target.main);
			c.glDeleteTextures(1, &target.alt);
		}
		for(&self.depth) |*texture| {
			c.glDeleteTextures(1, texture);
		}
		for(&self.shadow) |*texture| {
			c.glDeleteTextures(1, texture);
		}
		for(&self.shadowColor) |*texture| {
			c.glDeleteTextures(1, texture);
		}
		for(&self.shadowColorAlt) |*texture| {
			c.glDeleteTextures(1, texture);
		}
		c.glDeleteSamplers(1, &self.shadowSamplerCompare);
		c.glDeleteSamplers(1, &self.shadowSamplerPlain);
		c.glDeleteFramebuffers(1, &self.framebuffer);
	}

	/// (Re)allocates every texture at the given size. Cheap to call on resize only.
	pub fn updateSize(self: *RenderTargets, width: u31, height: u31) void {
		if(width == self.width and height == self.height) return;
		self.width = @max(width, 1);
		self.height = @max(height, 1);

		for(&self.color, 0..) |*target, index| {
			const format = glFormat(target.format);
			// Zero keeps the "screen-sized" reading everywhere else in this file.
			if(self.declaredSize[index]) |axes| {
				target.width = axes[0].resolve(self.width);
				target.height = axes[1].resolve(self.height);
			} else {
				target.width = 0;
				target.height = 0;
			}
			const targetWidth = if(target.width != 0) target.width else self.width;
			const targetHeight = if(target.height != 0) target.height else self.height;
			// Integer texels can only be sampled nearest; a linear filter leaves the texture
			// incomplete and every read returns zero, which Iris's `RenderTarget` avoids the same way.
			const plainFilter: c_int = if(isIntegerFormat(target.format)) c.GL_NEAREST else c.GL_LINEAR;
			for([_]c_uint{target.main, target.alt}) |texture| {
				c.glBindTexture(c.GL_TEXTURE_2D, texture);
				c.glTexImage2D(c.GL_TEXTURE_2D, 0, format.internal, targetWidth, targetHeight, 0, format.format, format.dataType, null);
				// Packs assume clamped, non-repeating buffers; a repeat wrap makes screen-space
				// effects smear the opposite edge into view.
				c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, plainFilter);
				c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, plainFilter);
				c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
				c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
			}
		}

		for(&self.depth) |texture| {
			c.glBindTexture(c.GL_TEXTURE_2D, texture);
			c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_DEPTH_COMPONENT32F, self.width, self.height, 0, c.GL_DEPTH_COMPONENT, c.GL_FLOAT, null);
			c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
			c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
			c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
			c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
		}
		for(&self.shadow) |texture| {
			c.glBindTexture(c.GL_TEXTURE_2D, texture);
			c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_DEPTH_COMPONENT32F, self.shadowResolution, self.shadowResolution, 0, c.GL_DEPTH_COMPONENT, c.GL_FLOAT, null);
			c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
			c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
			c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
			c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
			// Compare mode is left off here on purpose; the bound sampler object decides, so a
			// texture-level setting would only be a second source of truth.
			c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_COMPARE_MODE, c.GL_NONE);
		}
		for(0..self.shadowColor.len) |index| {
			if(!self.shadowColorUsed[index]) continue;
			const format = glFormat(self.shadowColorFormat[index]);
			const plainFilter: c_int = if(isIntegerFormat(self.shadowColorFormat[index])) c.GL_NEAREST else c.GL_LINEAR;
			for([_]c_uint{self.shadowColor[index], self.shadowColorAlt[index]}) |texture| {
				c.glBindTexture(c.GL_TEXTURE_2D, texture);
				c.glTexImage2D(c.GL_TEXTURE_2D, 0, format.internal, self.shadowResolution, self.shadowResolution, 0, format.format, format.dataType, null);
				c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, plainFilter);
				c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, plainFilter);
				c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
				c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
			}
		}
		c.glBindTexture(c.GL_TEXTURE_2D, 0);
		self.clearShadow();
		self.fullClearPending = true;
	}

	/// One of a shadow colour buffer's two textures.
	pub fn shadowColorTexture(self: *const RenderTargets, index: usize, side: Side) c_uint {
		return switch(side) {
			.main => self.shadowColor[index],
			.alt => self.shadowColorAlt[index],
		};
	}

	/// Fills the shadow map with "nothing occludes", so lookups behave until a real shadow pass
	/// writes into it.
	fn clearShadow(self: *RenderTargets) void {
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.framebuffer);
		for(&self.shadow) |texture| {
			c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_TEXTURE_2D, texture, 0);
			c.glDrawBuffers(0, null);
			c.glClearDepth(1.0);
			c.glDepthMask(c.GL_TRUE);
			c.glClear(c.GL_DEPTH_BUFFER_BIT);
		}
		c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_TEXTURE_2D, 0, 0);
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
		// A fresh allocation is undefined memory whatever the pack's `Clear` flag says, as for the
		// colortex set (`fullClearPending`).
		self.clearShadowColor(true);
	}

	/// Clears the shadow colour buffers the pack asked to have cleared, to the colours it asked for.
	///
	/// Iris does this before every shadow pass (`ShadowRenderer.renderShadows` runs the clear passes
	/// `ClearPassCreator` built for the shadow targets), and a pack's `shadow.fsh` writes the caster
	/// over the cleared value. `everything` overrides a `shadowcolorNClear = false`, for the one
	/// clear after allocation.
	pub fn clearShadowColor(self: *RenderTargets, everything: bool) void {
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.framebuffer);
		c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_TEXTURE_2D, 0, 0);
		// Every other colour slot goes too, or the clear is sized by whatever the last pass left
		// there - the same intersection rule `importSky` pays for.
		self.detachAllBut(c.GL_FRAMEBUFFER, 0);
		for(0..self.shadowColor.len) |index| {
			if(!self.shadowColorUsed[index]) continue;
			if(!self.shadowColorClear[index] and !everything) continue;
			// The per-frame clear is of `main`, the side the shadow pass draws; the one clear after
			// allocation takes `alt` as well, which is otherwise undefined until a `shadowcomp` pass
			// writes it.
			const both = [_]Side{.main, .alt};
			const sides: []const Side = if(everything) &both else both[0..1];
			for(sides) |side| {
				c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_TEXTURE_2D, self.shadowColorTexture(index, side), 0);
				c.glDrawBuffers(1, &[_]c_uint{c.GL_COLOR_ATTACHMENT0});
				const colour = self.shadowColorClearColor[index];
				c.glClearColor(colour[0], colour[1], colour[2], colour[3]);
				c.glClear(c.GL_COLOR_BUFFER_BIT);
			}
		}
		c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_TEXTURE_2D, 0, 0);
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
	}

	/// Clears the buffers the pack asked to have cleared. Targets with `colortexNClear = false`
	/// persist across frames, which is how packs accumulate temporal data - except on the first
	/// frame after an allocation, when everything is cleared once; see `fullClearPending`.
	pub fn clear(self: *RenderTargets) void {
		const clearEverything = self.fullClearPending;
		self.fullClearPending = false;
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.framebuffer);

		// All three depth textures, not just the one terrain draws into. `depthtex1`/`depthtex2` are
		// filled by `captureDepthSnapshots` partway through the frame, but a pack samples them in
		// passes that can run before that - and an unwritten depth texture is undefined memory, not
		// zeroes. Nostalgia's TAA compares `depthtex2` against the scene depth to decide whether to
		// apply camera translation to its reprojection, so garbage there silently drops translation
		// and smears the whole screen whenever the camera moves.
		c.glDepthMask(c.GL_TRUE);
		c.glClearDepth(1.0);
		for(&self.depth) |texture| {
			c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_TEXTURE_2D, texture, 0);
			c.glClear(c.GL_DEPTH_BUFFER_BIT);
		}
		c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_TEXTURE_2D, self.depth[0], 0);
		for(&self.color) |*target| {
			if(!target.clear and !clearEverything) continue;
			// Both sides need clearing, otherwise the first flip exposes last frame's contents.
			for([_]Side{.main, .alt}) |side| {
				c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_TEXTURE_2D, target.texture(side), 0);
				c.glDrawBuffers(1, &[_]c_uint{c.GL_COLOR_ATTACHMENT0});
				c.glClearColor(target.clearColor[0], target.clearColor[1], target.clearColor[2], target.clearColor[3]);
				c.glClear(c.GL_COLOR_BUFFER_BIT);
			}
		}
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
	}

	/// The render area for a pass: the extent of the first buffer it draws into.
	///
	/// The viewport has to follow the buffer, not the screen. A pack that declares
	/// `size.buffer.colortex4 = 256 256` does its maths in that size - Nostalgia renders a sky
	/// capture into it through a directional projection and `prepare1` samples it back with
	/// `projectSky(direction)`. Drawn under a full-screen viewport instead, the capture lands in one
	/// corner of its own texture and the rest keeps whatever it held; the pack then reconstructs its
	/// sky from a region largely never written, which reads as a flat grey wash with a seam where
	/// the written area ends rather than as anything obviously broken.
	///
	/// Only the first draw buffer is consulted, which is what makes this well defined: a framebuffer
	/// whose attachments differ in size renders only into their intersection anyway, and
	/// `bindForPass` detaches every slot the pass does not use so that intersection *is* this extent.
	///
	/// A zero size on the target means "follows the screen", which is the common case.
	pub fn viewportFor(self: *const RenderTargets, drawBuffers: []const u8) [2]u31 {
		if(drawBuffers.len != 0 and drawBuffers[0] < colortexCount) {
			const target = self.color[drawBuffers[0]];
			if(target.width != 0 and target.height != 0) return .{target.width, target.height};
		}
		return .{self.width, self.height};
	}

	/// Points the shared framebuffer at the write side of each buffer this pass draws to, and
	/// sets the draw-buffer mapping so the shader's `gl_FragData[N]` reaches `drawBuffers[N]`.
	pub fn bindForPass(self: *RenderTargets, drawBuffers: []const u8, bindings: PassBindings, withDepth: bool) void {
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.framebuffer);

		// Geometry passes need somewhere to put depth. Without an attachment the depth test has
		// nothing to work against, and - worse - `depthtex0` stays at the far plane, which every
		// composite pass reads as "this pixel is sky". Composite passes attach nothing, since they
		// only ever read depth.
		c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_TEXTURE_2D, if(withDepth) self.depth[0] else 0, 0);

		// Every slot this pass does not use is detached, not merely left out of `glDrawBuffers`.
		//
		// A framebuffer whose attachments differ in size renders only into their *intersection*,
		// anchored at the origin - and that is decided by what is attached, not by what the draw
		// buffer list names. Leaving a previous pass's attachment in place therefore silently clips
		// every later pass to it, with no GL error and a perfectly complete framebuffer.
		//
		// Kappa declares `size.buffer.colortex12=1024 512` and `colortex13=1024 512`, and its
		// `composite1` draws to exactly those two. The next pass, `composite2`, draws to colortex0
		// alone - but inherited colortex13 on slot 1, so it rendered into the bottom-left 1024x512 of
		// a screen-sized buffer and left the rest holding whatever was there before. That is a hard
		// edged rectangle in the corner of the frame, and every pass downstream carries it because
		// they read colortex0.
		//
		// `viewportFor` already assumes the render area is the extent of the buffers the pass writes.
		// This is what makes that assumption true.
		var attachments: [colortexCount]c_uint = @splat(c.GL_NONE);
		for(0..self.maxColorAttachments) |slot| {
			const attachment: c_uint = glEnum(c.GL_COLOR_ATTACHMENT0) + @as(c_uint, @intCast(slot));
			const target: ?u8 = if(slot < drawBuffers.len and drawBuffers[slot] < colortexCount) drawBuffers[slot] else null;
			if(target) |index| {
				c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, attachment, c.GL_TEXTURE_2D, self.color[index].texture(bindings.write[index]), 0);
				attachments[slot] = attachment;
			} else {
				c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, attachment, c.GL_TEXTURE_2D, 0, 0);
			}
		}
		// Clamped for the same reason the loop is: naming more draw buffers than the driver has is an
		// error rather than a truncation.
		c.glDrawBuffers(@intCast(@min(drawBuffers.len, self.maxColorAttachments)), &attachments);
	}

	/// Binds every colortex and depthtex to the texture unit its conventional sampler name uses.
	///
	/// Unit assignment matches OptiFine's fixed layout, which is what packs expect when they
	/// declare `uniform sampler2D colortex3` without a binding qualifier.
	pub fn bindSamplers(self: *RenderTargets, bindings: PassBindings) void {
		for(&self.color, 0..) |*target, index| {
			c.glActiveTexture(glEnum(c.GL_TEXTURE0) + @as(c_uint, @intCast(index)));
			c.glBindTexture(c.GL_TEXTURE_2D, target.texture(bindings.read[index]));
		}
		// Minecraft's split between the two is by *transparency*: `shadowtex0` holds every shadow
		// caster, `shadowtex1` only the opaque ones, and packs read the difference to tint a shadow
		// cast through stained glass or water. `shadow[0]` is what the shadow pass renders into,
		// both layers; `shadow[1]` is the copy `captureShadowDepth` takes of it between the opaque
		// and the translucent layer, exactly as `ShadowRenderTargets.copyPreTranslucentDepth` does.
		//
		// Until 2026-09-11 the pass drew opaque terrain only and `shadow[0]` was bound on both
		// units. That was the right aliasing for that pass, and the *wrong* thing to replace it
		// with is the cleared texture: `shadow[1]` at its cleared 1.0 does not mean "no transparent
		// occluders", it means "nothing occludes", and packs do not sample these symmetrically.
		// Nostalgia's volumetric march is
		//
		//     float shadow0 = texture(shadowtex0, coord);   // real map: occluded
		//     float shadow  = 1.0;
		//     if (shadow0 < 1.0) shadow = texture(shadowtex1, coord);   // empty map: LIT
		//
		// so with an unwritten `shadowtex1` every sample `shadowtex0` reported as occluded came back
		// fully lit, and the fog was never shadowed anywhere, solid rock included. The copy keeps
		// the unit meaningful whether or not a pack asks for translucent casters at all.
		for(self.shadow, 0..) |texture, index| {
			c.glActiveTexture(glEnum(c.GL_TEXTURE0) + shadowTextureUnit + @as(c_uint, @intCast(index)));
			c.glBindTexture(c.GL_TEXTURE_2D, texture);
		}
		for(0..self.shadowColor.len) |index| {
			c.glActiveTexture(glEnum(c.GL_TEXTURE0) + shadowColorTextureUnit + @as(c_uint, @intCast(index)));
			// An unallocated pair leaves its unit empty; no program names it, by construction.
			c.glBindTexture(c.GL_TEXTURE_2D, if(self.shadowColorUsed[index]) self.shadowColorTexture(index, bindings.shadowRead[index]) else 0);
		}
		for(&self.depth, 0..) |texture, index| {
			c.glActiveTexture(glEnum(c.GL_TEXTURE0) + depthTextureUnit + @as(c_uint, @intCast(index)));
			c.glBindTexture(c.GL_TEXTURE_2D, texture);
		}
	}

	/// Binds the shadow sampler object matching how this program declared its shadow samplers.
	/// Binds the sampler object each shadow unit needs, decided per sampler.
	///
	/// `useComparison[i]` is whether this program declared `shadowtexI` as `sampler2DShadow`, as
	/// reported by the linked program itself - see `pipeline.resolveShadowComparison`. Packs routinely
	/// want comparison on one and raw depth on the other in the same program, and the previous
	/// signature took a single flag for both, so it could not express that. Binding the wrong one is
	/// undefined behaviour that the driver reports by the hundred rather than a silent wrong pixel.
	pub fn bindShadowSamplers(self: *RenderTargets, useComparison: [2]bool) void {
		for(0..self.shadow.len) |index| {
			const sampler = if(useComparison[index]) self.shadowSamplerCompare else self.shadowSamplerPlain;
			c.glBindSampler(shadowTextureUnit + @as(c_uint, @intCast(index)), sampler);
		}
	}

	/// Binds each buffer the program accesses as an image onto its own image unit.
	///
	/// Iris exposes every colortex a second way, as `colorimgN`, for `imageLoad`/`imageStore` and
	/// the atomics - Nostalgic Red Voxels validates its reprojection with `imageAtomicMin` on an
	/// `R32UI` buffer and writes material data back through `imageStore`. Left unbound, those
	/// operations are undefined rather than no-ops.
	///
	/// The image is the buffer's **read** side, the same texture the pass's `colortexN` sampler
	/// sees. An image write does not advance the flip - only a draw buffer does - so a value stored
	/// through `colorimg9` in one pass has to be found by `imageLoad(colorimg9)` and
	/// `texture(colortex9)` in the next, and that only holds if all three name one texture.
	///
	/// The pack's own images (`image.<name>`) follow, bound whole: `layered` is true so a 3D volume
	/// exposes every slice, as Iris's `ImageBinding.update` binds them, and a 1D or 2D image is
	/// unaffected by the flag.
	///
	/// Returns whether anything was bound, so the caller can issue the memory barrier that makes
	/// image writes visible to what runs next.
	pub fn bindImages(self: *RenderTargets, bindings: ImageBindings, sides: PassBindings, customImages: *const images.Set) bool {
		var unit: c_uint = 0;
		for(bindings.colortex, 0..) |location, index| {
			if(location < 0) continue;
			if(unit >= self.maxImageUnits) {
				std.log.warn("irisbridge: program declares more image bindings than the {} image units available; the rest read nothing", .{self.maxImageUnits});
				break;
			}
			const target = self.color[index];
			c.glBindImageTexture(unit, target.texture(sides.read[index]), 0, c.GL_FALSE, 0, c.GL_READ_WRITE, glEnum(glFormat(target.format).internal));
			c.glUniform1i(location, @intCast(unit));
			unit += 1;
		}
		for(bindings.shadowColor, 0..) |location, index| {
			if(location < 0) continue;
			if(unit >= self.maxImageUnits) break;
			c.glBindImageTexture(unit, self.shadowColorTexture(index, sides.shadowRead[index]), 0, c.GL_FALSE, 0, c.GL_READ_WRITE, glEnum(glFormat(self.shadowColorFormat[index]).internal));
			c.glUniform1i(location, @intCast(unit));
			unit += 1;
		}
		for(bindings.custom, 0..) |location, index| {
			if(location < 0) continue;
			if(index >= customImages.images.len) break;
			if(unit >= self.maxImageUnits) {
				std.log.warn("irisbridge: program declares more image bindings than the {} image units available; the rest read nothing", .{self.maxImageUnits});
				break;
			}
			const image = &customImages.images[index];
			c.glBindImageTexture(unit, image.id, 0, c.GL_TRUE, 0, c.GL_READ_WRITE, glEnum(image.format.internal));
			c.glUniform1i(location, @intCast(unit));
			unit += 1;
		}
		return unit != 0;
	}

	/// Points the shared framebuffer at the shadow colour buffers a `shadowcomp` pass draws, on
	/// the side its bindings say, with no depth: the pass is a fullscreen quad over the shadow
	/// map's square, `shadowResolution` on each side, and depth would only reject it.
	pub fn bindShadowCompositeFramebuffer(self: *RenderTargets, drawBuffers: []const u8, bindings: PassBindings) void {
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.framebuffer);
		c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_TEXTURE_2D, 0, 0);
		var attachments: [colortexCount]c_uint = @splat(c.GL_NONE);
		for(0..self.maxColorAttachments) |slot| {
			const attachment: c_uint = glEnum(c.GL_COLOR_ATTACHMENT0) + @as(c_uint, @intCast(slot));
			const target: ?u8 = if(slot < drawBuffers.len and drawBuffers[slot] < self.shadowColor.len and self.shadowColorUsed[drawBuffers[slot]]) drawBuffers[slot] else null;
			if(target) |index| {
				c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, attachment, c.GL_TEXTURE_2D, self.shadowColorTexture(index, bindings.shadowWrite[index]), 0);
				attachments[slot] = attachment;
			} else {
				c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, attachment, c.GL_TEXTURE_2D, 0, 0);
			}
		}
		c.glDrawBuffers(@intCast(@min(drawBuffers.len, self.maxColorAttachments)), &attachments);
	}

	/// Releases the sampler objects, so Cubyz's own rendering is not affected by them.
	pub fn unbindShadowSamplers(self: *RenderTargets) void {
		for(0..self.shadow.len) |index| {
			c.glBindSampler(shadowTextureUnit + @as(c_uint, @intCast(index)), 0);
		}
	}

	/// Copies the live depth buffer into one of the snapshot textures.
	/// Seeds the chain with what Cubyz rendered: world colour into `colortex0`, depth into all
	/// three depth textures.
	///
	/// This stands in for the gbuffers stage until pack gbuffers programs run on Cubyz geometry.
	/// The source is Cubyz's `worldFrameBuffer`, which holds the lit world in RGB16F before its
	/// own fog and tonemap pass - the closest equivalent to what Minecraft's gbuffers leave
	/// behind, and the right input for a pack that expects to do its own tonemapping.
	///
	/// All three depth textures get the same contents because Cubyz has no handheld item and the
	/// capture happens after transparents; `depthtex1`/`depthtex2` differing from `depthtex0` is
	/// what lets packs detect water surfaces, so this is a real limitation rather than a shortcut.
	pub fn importWorld(self: *RenderTargets, sourceFramebuffer: c_uint, bindings: PassBindings, copyColor: bool) void {
		c.glBindFramebuffer(c.GL_READ_FRAMEBUFFER, sourceFramebuffer);
		c.glBindFramebuffer(c.GL_DRAW_FRAMEBUFFER, self.framebuffer);
		// Skipped once a gbuffers program is drawing terrain: it has already written colortex0 with
		// the pack's own albedo, and blitting Cubyz's finished render over the top would destroy
		// exactly the G-buffer the deferred passes are about to read.
		if(copyColor) {
			// As in `importSky`: sized by the one attachment, not by whatever was left attached.
			self.detachAllBut(c.GL_DRAW_FRAMEBUFFER, 0);
			c.glFramebufferTexture2D(c.GL_DRAW_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_TEXTURE_2D, self.color[0].texture(bindings.read[0]), 0);
			c.glDrawBuffers(1, &[_]c_uint{c.GL_COLOR_ATTACHMENT0});
			c.glBlitFramebuffer(0, 0, self.width, self.height, 0, 0, self.width, self.height, c.GL_COLOR_BUFFER_BIT, c.GL_NEAREST);
		}

		// `glCopyTexSubImage2D` on a depth-formatted texture takes the read framebuffer's depth
		// attachment, which is still bound from the blit above.
		//
		// Skipped entirely when a gbuffers program drew the terrain: it wrote `depthtex0` directly,
		// and Cubyz's own framebuffer no longer holds terrain depth, so copying would replace real
		// depth with an empty buffer and make every composite pass see nothing but sky.
		if(copyColor) {
			c.glActiveTexture(c.GL_TEXTURE0);
			for(&self.depth) |texture| {
				c.glBindTexture(c.GL_TEXTURE_2D, texture);
				c.glCopyTexSubImage2D(c.GL_TEXTURE_2D, 0, 0, 0, 0, 0, self.width, self.height);
			}
		}

		c.glBindFramebuffer(c.GL_READ_FRAMEBUFFER, 0);
		c.glBindFramebuffer(c.GL_DRAW_FRAMEBUFFER, 0);
	}

	/// Binds the framebuffer with only the shadow depth texture attached.
	/// Points the shared framebuffer at the shadow depth map and at whichever shadow colour buffers
	/// the pack's shadow program draws into, in the order its `DRAWBUFFERS` names them.
	///
	/// The indices are shadowcolor indices, 0 and 1, not colortex ones. Every other colour slot is
	/// detached: the colortex set is screen-sized, and a framebuffer mixing those with a square
	/// shadow-resolution depth texture is incomplete.
	pub fn bindShadowFramebuffer(self: *RenderTargets, drawBuffers: []const u8) void {
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.framebuffer);
		var attachments: [colortexCount]c_uint = @splat(c.GL_NONE);
		for(0..self.maxColorAttachments) |slot| {
			const attachment: c_uint = glEnum(c.GL_COLOR_ATTACHMENT0) + @as(c_uint, @intCast(slot));
			const target: ?u8 = if(slot < drawBuffers.len and drawBuffers[slot] < self.shadowColor.len and self.shadowColorUsed[drawBuffers[slot]]) drawBuffers[slot] else null;
			if(target) |index| {
				c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, attachment, c.GL_TEXTURE_2D, self.shadowColor[index], 0);
				attachments[slot] = attachment;
			} else {
				c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, attachment, c.GL_TEXTURE_2D, 0, 0);
			}
		}
		c.glDrawBuffers(@intCast(@min(drawBuffers.len, self.maxColorAttachments)), &attachments);
		c.glReadBuffer(c.GL_NONE);
		c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_TEXTURE_2D, self.shadow[0], 0);
	}

	/// Blits one colortex straight to the default framebuffer, which is how a chain with no `final`
	/// reaches the screen.
	pub fn blitToScreen(self: *RenderTargets, index: usize, bindings: PassBindings, screenWidth: u31, screenHeight: u31) void {
		if(index >= colortexCount) return;
		c.glBindFramebuffer(c.GL_READ_FRAMEBUFFER, self.framebuffer);
		c.glFramebufferTexture2D(c.GL_READ_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_TEXTURE_2D, self.color[index].texture(bindings.read[index]), 0);
		c.glReadBuffer(c.GL_COLOR_ATTACHMENT0);
		c.glBindFramebuffer(c.GL_DRAW_FRAMEBUFFER, 0);
		// The buffer's own extent, since a `size.buffer` target is smaller than the screen and
		// reading a screen-sized rect from it would show mostly nothing.
		const source = self.color[index];
		const sourceWidth = if(source.width != 0) source.width else self.width;
		const sourceHeight = if(source.height != 0) source.height else self.height;
		c.glBlitFramebuffer(0, 0, sourceWidth, sourceHeight, 0, 0, screenWidth, screenHeight, c.GL_COLOR_BUFFER_BIT, c.GL_NEAREST);
		c.glBindFramebuffer(c.GL_READ_FRAMEBUFFER, 0);
		c.glBindFramebuffer(c.GL_DRAW_FRAMEBUFFER, 0);
	}


	/// Seeds the colour buffer geometry is about to draw into with Cubyz's rendered sky.
	///
	/// Minecraft draws its sky *as geometry* during the gbuffers stage, so by the time a pack's
	/// deferred passes run, colortex0 already holds sky wherever no terrain covers it. Cubyz draws
	/// its skybox too - but into its own framebuffer, which the pack never sees once a
	/// `gbuffers_terrain` program takes over the terrain draw. The result was a colortex0 that was
	/// pure black everywhere the terrain did not reach, and a composite chain dutifully applying
	/// atmospheric scattering to black: a flat, fog-coloured sky with no gradient and no sun.
	///
	/// Blitting Cubyz's sky in before the terrain draw restores the invariant packs are written
	/// against. Terrain then draws over it exactly as Minecraft's does.
	pub fn importSky(self: *RenderTargets, sourceFramebuffer: c_uint, drawBuffers: []const u8, bindings: PassBindings) void {
		// Only the first draw buffer is the albedo target; the rest carry material data that a sky
		// colour would corrupt.
		const target = if(drawBuffers.len != 0) drawBuffers[0] else 0;
		if(target >= colortexCount) return;

		c.glBindFramebuffer(c.GL_READ_FRAMEBUFFER, sourceFramebuffer);
		c.glReadBuffer(c.GL_COLOR_ATTACHMENT0);
		c.glBindFramebuffer(c.GL_DRAW_FRAMEBUFFER, self.framebuffer);
		// The blit inherits whatever the last user of the shared framebuffer left attached, and
		// that is the shadow pass: its 512 to 4096 pixel depth map. A framebuffer's extent is the
		// intersection of its attachments, so with a shadow map smaller than the screen the copy
		// landed only in the bottom-left square that map spans - a 512x512 corner for Mellow, whose
		// `shadowMapResolution` is 512 - and nowhere else. Every attachment but the target goes.
		self.detachAllBut(c.GL_DRAW_FRAMEBUFFER, 0);
		c.glFramebufferTexture2D(c.GL_DRAW_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_TEXTURE_2D, self.color[target].texture(bindings.write[target]), 0);
		c.glDrawBuffers(1, &[_]c_uint{c.GL_COLOR_ATTACHMENT0});
		c.glBlitFramebuffer(0, 0, self.width, self.height, 0, 0, self.width, self.height, c.GL_COLOR_BUFFER_BIT, c.GL_NEAREST);
		c.glBindFramebuffer(c.GL_READ_FRAMEBUFFER, 0);
		c.glBindFramebuffer(c.GL_DRAW_FRAMEBUFFER, 0);
	}

	/// Detaches every colour slot except `keep` and the depth attachment from the framebuffer
	/// bound at `target`, so a blit or clear is sized by the one attachment it means to touch.
	fn detachAllBut(self: *RenderTargets, target: c_uint, keep: usize) void {
		for(0..self.maxColorAttachments) |slot| {
			if(slot == keep) continue;
			c.glFramebufferTexture2D(target, glEnum(c.GL_COLOR_ATTACHMENT0) + @as(c_uint, @intCast(slot)), c.GL_TEXTURE_2D, 0, 0);
		}
		c.glFramebufferTexture2D(target, c.GL_DEPTH_ATTACHMENT, c.GL_TEXTURE_2D, 0, 0);
	}

	/// Leaves the shared framebuffer with nothing attached, for the end of the shadow pass.
	///
	/// The next user attaches what it needs, but a blit sizes itself by everything attached, and
	/// the shadow pass attaches textures no other pass shares a size with.
	pub fn releaseShadowFramebuffer(self: *RenderTargets) void {
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.framebuffer);
		self.detachAllBut(c.GL_FRAMEBUFFER, self.maxColorAttachments);
		c.glDrawBuffers(0, null);
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
	}

	/// Copies each buffer that ends the frame flipped back from `alt` to `main`.
	///
	/// Without this, nothing a pack accumulates across frames survives. A buffer written once per
	/// frame reads `main` and writes `alt`, every frame, forever - so its history buffer reads a
	/// texture that is never written. TAA history, auto-exposure and every smoothed value are
	/// affected, and the visible result is an exposure that can never settle: it recomputes from
	/// nothing each frame and swings with whatever is on screen.
	///
	/// Buffers the pack asked to have cleared are skipped, since their contents are discarded at the
	/// start of the next frame anyway.
	///
	/// This is Iris's `FinalPassRenderer` swap pass, down to the direction of the copy - its own
	/// comment reads "we merely copy it from alt to main".
	/// Builds the mipmap chain of each named buffer's read side and samples it through one, for
	/// the pass about to run.
	///
	/// Iris's `CompositeRenderer.setupMipmapping`, applied to a pass's `colortexNMipmapEnabled`
	/// set just before it draws (`:255-260`): the chain is regenerated every time, only the side
	/// the pass reads is touched, and the filter stays until `resetMipmapping` at the end of the
	/// frame. The directive had been parsed since the reconstruction and acted on by nothing -
	/// `pack.parseMipmapEnabled` had no caller - so a `textureLod(colortex4, uv, 6.0)` read level
	/// 0: Bliss's ambient light, taken from its sky map at level 6, was the unblurred sky, and
	/// Complementary's bloom tiles were built from full-resolution samples.
	pub fn setupMipmapping(self: *RenderTargets, buffers: u16, bindings: PassBindings) void {
		if(buffers == 0) return;
		c.glActiveTexture(c.GL_TEXTURE0);
		for(&self.color, 0..) |*target, index| {
			if(buffers & (@as(u16, 1) << @intCast(index)) == 0) continue;
			c.glBindTexture(c.GL_TEXTURE_2D, target.texture(bindings.read[index]));
			c.glGenerateMipmap(c.GL_TEXTURE_2D);
			c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, if(isIntegerFormat(target.format)) c.GL_NEAREST_MIPMAP_NEAREST else c.GL_LINEAR_MIPMAP_LINEAR);
			self.mipmappedThisFrame |= @as(u16, 1) << @intCast(index);
		}
		// Unit 0 is colortex0's; put back what `bindSamplers` had there.
		c.glBindTexture(c.GL_TEXTURE_2D, self.color[0].texture(bindings.read[0]));
	}

	/// Puts the plain filters back at the end of the frame, as Iris's `FinalPassRenderer` does
	/// before its swap passes (`:274-277`), so a chain built for one pass is not sampled by the
	/// next frame's geometry until a pass asks again.
	pub fn resetMipmapping(self: *RenderTargets) void {
		if(self.mipmappedThisFrame == 0) return;
		c.glActiveTexture(c.GL_TEXTURE0);
		for(&self.color, 0..) |*target, index| {
			if(self.mipmappedThisFrame & (@as(u16, 1) << @intCast(index)) == 0) continue;
			const plainFilter: c_int = if(isIntegerFormat(target.format)) c.GL_NEAREST else c.GL_LINEAR;
			for([_]c_uint{target.main, target.alt}) |texture| {
				c.glBindTexture(c.GL_TEXTURE_2D, texture);
				c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, plainFilter);
			}
		}
		c.glBindTexture(c.GL_TEXTURE_2D, 0);
		self.mipmappedThisFrame = 0;
	}

	pub fn swapFlippedBuffers(self: *RenderTargets, finalFlip: FlipState) void {
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.framebuffer);
		c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_TEXTURE_2D, 0, 0);
		c.glActiveTexture(c.GL_TEXTURE0);

		for(&self.color, 0..) |*target, index| {
			if(target.clear) continue;
			if(!finalFlip.isFlipped(@intCast(index))) continue;

			// `glCopyTexSubImage2D` takes its pixels from the read buffer of the bound framebuffer,
			// so the source is attached and named rather than blitted.
			c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_TEXTURE_2D, target.alt, 0);
			c.glReadBuffer(c.GL_COLOR_ATTACHMENT0);
			c.glBindTexture(c.GL_TEXTURE_2D, target.main);
			// The target's own size, since a fixed-size buffer is smaller than the screen and copying
			// a screen-sized region would read past what was actually rendered.
			//
			// `Target.width` is 0 for a screen-sized buffer - that is its documented meaning, and
			// every other reader in this file falls back to the screen. This one did not, so the copy
			// was `glCopyTexSubImage2D(..., 0, 0)`: a zero-by-zero region, silently copying nothing. So
			// the only buffers that carried anything between frames were the ones with a declared
			// `size.buffer`, and every screen-sized history buffer - TAA, the SSPT accumulation, auto
			// exposure - read a texture nothing ever wrote, exactly as before this function existed.
			const width = if(target.width != 0) target.width else self.width;
			const height = if(target.height != 0) target.height else self.height;
			c.glCopyTexSubImage2D(c.GL_TEXTURE_2D, 0, 0, 0, 0, 0, width, height);
		}

		c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_TEXTURE_2D, 0, 0);
		c.glBindTexture(c.GL_TEXTURE_2D, 0);
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
	}

	/// Fills `depthtex1`/`depthtex2` from the live depth buffer.
	///
	/// Call once per frame at the point Minecraft's own split falls: after opaque geometry, before
	/// translucents. That is what those textures *mean* - `depthtex1` is the depth excluding
	/// translucents, and packs subtract it from `depthtex0` to find water surfaces and to tell world
	/// geometry from the handheld item.
	///
    /// Both get the same contents because Cubyz has no handheld item, so there is no third state to
	/// distinguish. That is a real limitation rather than a shortcut, but it is a far smaller one
	/// than leaving them unwritten: before this existed they held undefined memory, and a pack
	/// comparing against them got an answer that was not merely wrong but different every frame.
	pub fn captureDepthSnapshots(self: *RenderTargets) void {
		c.glBindFramebuffer(c.GL_READ_FRAMEBUFFER, self.framebuffer);
		// Attached explicitly rather than assumed: the copy reads the framebuffer's *depth
		// attachment*, and which pass last bound it is not something this call should depend on.
		c.glFramebufferTexture2D(c.GL_READ_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_TEXTURE_2D, self.depth[0], 0);
		c.glActiveTexture(c.GL_TEXTURE0);
		for(self.depth[1..]) |texture| {
			c.glBindTexture(c.GL_TEXTURE_2D, texture);
			c.glCopyTexSubImage2D(c.GL_TEXTURE_2D, 0, 0, 0, 0, 0, self.width, self.height);
		}
		c.glBindFramebuffer(c.GL_READ_FRAMEBUFFER, 0);
	}

	/// Fills `shadowtex1` from the shadow map as it stands, which is the opaque casters alone when
	/// called between the two layers of the shadow pass.
	///
	/// The shadow-pass counterpart of `captureDepthSnapshots`, taken at the same point in that pass
	/// where Iris takes its copy (`ShadowRenderer.java:528`, `copyPreTranslucentDepth`, before the
	/// translucent layer draws). Reads the shared framebuffer's depth attachment, which
	/// `bindShadowFramebuffer` set to `shadow[0]`; attached again here so the copy does not depend on
	/// which bind came last.
	pub fn captureShadowDepth(self: *RenderTargets) void {
		c.glBindFramebuffer(c.GL_READ_FRAMEBUFFER, self.framebuffer);
		c.glFramebufferTexture2D(c.GL_READ_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_TEXTURE_2D, self.shadow[0], 0);
		c.glActiveTexture(c.GL_TEXTURE0);
		c.glBindTexture(c.GL_TEXTURE_2D, self.shadow[1]);
		c.glCopyTexSubImage2D(c.GL_TEXTURE_2D, 0, 0, 0, 0, 0, self.shadowResolution, self.shadowResolution);
		c.glBindTexture(c.GL_TEXTURE_2D, 0);
	}

	/// The caller must have the source framebuffer bound as `GL_READ_FRAMEBUFFER`; the copy
	/// takes its pixels from there rather than from a texture id.
	pub fn captureDepth(self: *RenderTargets, kind: DepthKind) void {
		c.glActiveTexture(c.GL_TEXTURE0);
		c.glBindTexture(c.GL_TEXTURE_2D, self.depth[@intFromEnum(kind)]);
		c.glCopyTexSubImage2D(c.GL_TEXTURE_2D, 0, 0, 0, 0, 0, self.width, self.height);
	}
};

/// Where a program's `colorimgN` and `shadowcolorimgN` uniforms live, resolved once from the
/// linked program so no bind has to look names up per frame.
///
/// `-1` is "not declared", which is nearly every entry of nearly every program.
pub const ImageBindings = struct {
	colortex: [colortexCount]c_int = @splat(-1),
	shadowColor: [flip.shadowColorCount]c_int = @splat(-1),
	/// The pack's `image.<name>` declarations, by their index in `images.Set`.
	custom: [images.maxImages]c_int = @splat(-1),

	pub fn resolve(program: c_uint, customImages: *const images.Set) ImageBindings {
		var self = ImageBindings{};
		var name: [128]u8 = undefined;
		for(&self.colortex, 0..) |*location, index| {
			const text = std.fmt.bufPrintZ(&name, "colorimg{}", .{index}) catch unreachable;
			location.* = c.glGetUniformLocation(program, text.ptr);
		}
		for(&self.shadowColor, 0..) |*location, index| {
			const text = std.fmt.bufPrintZ(&name, "shadowcolorimg{}", .{index}) catch unreachable;
			location.* = c.glGetUniformLocation(program, text.ptr);
		}
		for(customImages.images, 0..) |*image, index| {
			if(index >= self.custom.len) break;
			const text = std.fmt.bufPrintZ(&name, "{s}", .{image.declaration.name}) catch continue;
			self.custom[index] = c.glGetUniformLocation(program, text.ptr);
		}
		return self;
	}
};

/// First texture unit used for `depthtex0`-`depthtex2`, just past the 16 colortex units.
pub const depthTextureUnit: c_uint = colortexCount;
pub const shadowTextureUnit: c_uint = depthTextureUnit + 3;
pub const shadowColorTextureUnit: c_uint = shadowTextureUnit + 2;

/// Cubyz's own texture arrays, on units past everything the shaderpack format claims.
///
/// They cannot share units with `colortex0`-`colortex2`: a program that declares both a
/// `sampler2D colortex0` and the `sampler2DArray` block texture on the same unit is invalid usage,
/// and the driver rejects the draw rather than picking one.
pub const cubyzBlockTextureUnit: c_uint = shadowColorTextureUnit + flip.shadowColorCount;
pub const cubyzEmissionTextureUnit: c_uint = cubyzBlockTextureUnit + 1;
pub const cubyzReflectivityTextureUnit: c_uint = cubyzBlockTextureUnit + 2;

/// Placeholder shadow map size until the pack's `shadowMapResolution` drives a real shadow pass.
/// Fallback shadow map size for a pack that declares none.
///
/// The live size is `RenderTargets.shadowResolution`, taken from the pack's own
/// `const int shadowMapResolution`. That is not a quality knob the host gets to pick: the pack
/// compiles the same constant into its shaders and divides by it to get a texel size, so allocating
/// a different size than it asked for makes every filter radius and depth-bias wrong - shadow acne
/// on some surfaces, over-blurring on others. Nostalgia's profiles ask for 1024, 2048 or 4096.
pub const defaultShadowResolution: c_int = 1024;
