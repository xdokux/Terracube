//! Compiles pack programs to GL programs and runs the deferred/composite/final chain.
//!
//! Each pass draws one fullscreen quad. The quad convention is Iris's and packs depend on it
//! exactly: `gl_Vertex.xy` in `[0,1]` and `gl_MultiTexCoord0.xy` in `[0,1]`. Packs map it to clip
//! space themselves - Nostalgia's shared composite vertex shader is literally
//! `gl_Position = vec4(gl_Vertex.xy*2.0 - 1.0, 0.0, 1.0)` - so supplying anything else puts the
//! whole screen in the wrong place.
//!
//! Sampler uniforms are assigned explicitly rather than left to defaults. A pack declares
//! `uniform sampler2D colortex3;` with no binding qualifier, so without an explicit
//! `glUniform1i` every sampler would read texture unit 0 and every buffer would come back as
//! colortex0.

const std = @import("std");

const main = @import("main");
const c = main.c;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const List = main.ListManaged;

const glsl = @import("glsl.zig");
const pack = @import("pack.zig");
const targets = @import("targets.zig");
const flip = @import("flip.zig");
const uniforms = @import("uniforms.zig");
const prologue = @import("prologue.zig");
const blend = @import("blend.zig");
const packtextures = @import("packtextures.zig");
const images = @import("images.zig");
const customuniforms = @import("customuniforms.zig");

// MARK: fullscreen quad

/// The quad every composite pass draws, in Iris's `[0,1]` convention.
pub const Quad = struct {
	vao: c_uint = 0,
	vbo: c_uint = 0,

	const vertices = [_]f32{
		// x, y, u, v
		0, 0, 0, 0,
		1, 0, 1, 0,
		1, 1, 1, 1,
		0, 0, 0, 0,
		1, 1, 1, 1,
		0, 1, 0, 1,
	};

	pub fn init() Quad {
		var self = Quad{};
		c.glGenVertexArrays(1, &self.vao);
		c.glGenBuffers(1, &self.vbo);
		c.glBindVertexArray(self.vao);
		c.glBindBuffer(c.GL_ARRAY_BUFFER, self.vbo);
		c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, c.GL_STATIC_DRAW);
		c.glBindVertexArray(0);
		return self;
	}

	pub fn deinit(self: *Quad) void {
		c.glDeleteBuffers(1, &self.vbo);
		c.glDeleteVertexArrays(1, &self.vao);
	}

	/// Points the quad's attributes at whatever locations this program ended up with.
	///
	/// Locations are queried rather than forced with `glBindAttribLocation`, because the shim
	/// declares `cubyz_Vertex` and `cubyz_MultiTexCoord0` only when the shader actually uses
	/// them - a pass that ignores its UVs simply has no such attribute, and a fixed binding
	/// would then point at nothing.
	pub fn bindFor(self: *const Quad, program: c_uint) void {
		c.glBindVertexArray(self.vao);
		c.glBindBuffer(c.GL_ARRAY_BUFFER, self.vbo);

		const positionLocation = c.glGetAttribLocation(program, "cubyz_Vertex");
		if(positionLocation >= 0) {
			const index: c_uint = @intCast(positionLocation);
			c.glEnableVertexAttribArray(index);
			c.glVertexAttribPointer(index, 2, c.GL_FLOAT, c.GL_FALSE, 4*@sizeOf(f32), null);
		}
		const uvLocation = c.glGetAttribLocation(program, "cubyz_MultiTexCoord0");
		if(uvLocation >= 0) {
			const index: c_uint = @intCast(uvLocation);
			c.glEnableVertexAttribArray(index);
			c.glVertexAttribPointer(index, 2, c.GL_FLOAT, c.GL_FALSE, 4*@sizeOf(f32), @ptrFromInt(2*@sizeOf(f32)));
		}
	}

	pub fn draw(self: *const Quad) void {
		_ = self;
		c.glDrawArrays(c.GL_TRIANGLES, 0, 6);
	}
};


// MARK: depth restore

/// Writes the pack's scene depth into whatever framebuffer is bound, colour untouched.
///
/// Exists for one caller: the block selection outline, which draws onto the finished frame rather
/// than into the pack's G-buffer (see `renderer.renderWorld`). The default framebuffer's depth is
/// cleared every frame and Cubyz's own deferred pass never writes it, so an outline drawn there
/// passes the depth test everywhere - including on the six edges that belong *inside* the selected
/// block, which reads as an X-ray wireframe rather than a selection box.
///
/// A `glBlitFramebuffer` of `GL_DEPTH_BUFFER_BIT` would be the obvious way and is not available:
/// depth blits require the source and destination formats to match, and the pack's depth is
/// `DEPTH_COMPONENT32F` against the window's 24-bit buffer. Writing `gl_FragDepth` from a fullscreen
/// pass has no such constraint.
///
/// The values come from geometry drawn with the *pack's* projection while the outline is drawn with
/// Cubyz's, whose far planes differ (12288 against 65536). That is safe here rather than merely
/// convenient: for `far >> near` the normalised depth of a near surface is `1 - 2*near/distance` to
/// a very good approximation and barely depends on the far plane at all. At five blocks the two
/// conventions differ by about 2e-5, while one block of separation is 6.7e-3 - two orders of
/// magnitude more, so the occlusion decision is never in doubt.
pub const DepthRestore = struct {
	program: c_uint = 0,
	textureLocation: c_int = -1,

	const vertexSource =
		\\#version 460
		\\layout(location = 0) in vec2 inPos;
		\\out vec2 uv;
		\\void main() {
		\\    uv = inPos;
		\\    gl_Position = vec4(inPos*2.0 - 1.0, 0.0, 1.0);
		\\}
	;

	const fragmentSource =
		\\#version 460
		\\in vec2 uv;
		\\uniform sampler2D depthTexture;
		\\void main() {
		\\    gl_FragDepth = texture(depthTexture, uv).x;
		\\}
	;

	pub fn init() DepthRestore {
		var self = DepthRestore{};
		const vertexShader = compileStage(vertexSource, c.GL_VERTEX_SHADER, "depthRestore") orelse return self;
		defer c.glDeleteShader(vertexShader);
		const fragmentShader = compileStage(fragmentSource, c.GL_FRAGMENT_SHADER, "depthRestore") orelse return self;
		defer c.glDeleteShader(fragmentShader);

		const linked = c.glCreateProgram();
		c.glAttachShader(linked, vertexShader);
		c.glAttachShader(linked, fragmentShader);
		c.glLinkProgram(linked);

		var success: c_int = undefined;
		c.glGetProgramiv(linked, c.GL_LINK_STATUS, &success);
		if(success != c.GL_TRUE) {
			c.glDeleteProgram(linked);
			return self;
		}
		self.program = linked;
		self.textureLocation = c.glGetUniformLocation(linked, "depthTexture");
		return self;
	}

	pub fn deinit(self: *DepthRestore) void {
		if(self.program != 0) c.glDeleteProgram(self.program);
		self.program = 0;
	}

	/// Stamps `texture` into the bound framebuffer's depth attachment.
	pub fn draw(self: *const DepthRestore, quad: *const Quad, texture: c_uint) void {
		if(self.program == 0) return;
		c.glUseProgram(self.program);
		c.glActiveTexture(c.GL_TEXTURE0);
		c.glBindTexture(c.GL_TEXTURE_2D, texture);
		if(self.textureLocation >= 0) c.glUniform1i(self.textureLocation, 0);

		// Depth must be writable and the test must not reject the write itself - the buffer holds the
		// clear value, so `GL_LESS` against a fragment that is *further* than the clear would discard
		// exactly the samples this exists to place.
		c.glEnable(c.GL_DEPTH_TEST);
		c.glDepthFunc(c.GL_ALWAYS);
		c.glDepthMask(c.GL_TRUE);
		c.glDisable(c.GL_BLEND);
		c.glColorMask(c.GL_FALSE, c.GL_FALSE, c.GL_FALSE, c.GL_FALSE);

		c.glBindVertexArray(quad.vao);
		c.glBindBuffer(c.GL_ARRAY_BUFFER, quad.vbo);
		c.glEnableVertexAttribArray(0);
		c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, 4*@sizeOf(f32), null);
		quad.draw();

		// Back to what the rest of the frame expects. `GL_LESS` is Cubyz's own depth function, and
		// leaving `GL_ALWAYS` set would make the selection outline - the very next thing drawn -
		// ignore the depth this just wrote.
		c.glColorMask(c.GL_TRUE, c.GL_TRUE, c.GL_TRUE, c.GL_TRUE);
		c.glDepthFunc(c.GL_LESS);
		c.glBindVertexArray(0);
		c.glUseProgram(0);
	}
};

// MARK: standard macros

/// Iris feature flags this bridge implements, by the names packs use in `iris.features.required`
/// and `iris.features.optional`.
///
/// Iris's own list is `FeatureFlags.java`: separate hardware samplers, higher shadowcolor, custom
/// images, per-buffer blending, compute shaders, tessellation, translucent entities, reversed
/// culling, the block emission attribute, and SSBOs. Five exist here: the per-program shadow
/// sampler objects, `blend.<program>.colortexN`, and since 2026-09-11 the pack's own images
/// (`images.zig`), its storage buffers (same file, relocated past the engine's binding points),
/// and its `.csh` programs at every stage (`ComputePass`). Claiming any other would put a pack on
/// a code path with nothing behind it: `HIGHER_SHADOWCOLOR` is `shadowcolor2` to `7`, which the
/// shadow pass does not allocate, and the rest are entity, tessellation and vertex-format features
/// Cubyz's geometry path has no counterpart for.
pub const supportedFeatures = [_][]const u8{
	"SEPARATE_HARDWARE_SAMPLERS", "PER_BUFFER_BLENDING", "CUSTOM_IMAGES", "SSBO", "COMPUTE_SHADERS",
	// Since 2026-09-12: `at_midBlock.w` carries the block's light level (`blockids.emissionLevel`),
	// and the shadow colour set is Iris's eight rather than OptiFine's two (`pack.shadowColorCount`).
	// Still absent, and honestly so: `TESSELATION_SHADERS`, whose control and evaluation stages
	// need a patch primitive Cubyz's indirect triangle draws do not issue; `ENTITY_TRANSLUCENT`
	// and `REVERSED_CULLING`, which describe entity and shadow-culling paths this bridge has no
	// geometry for.
	"BLOCK_EMISSION_ATTRIBUTE", "HIGHER_SHADOWCOLOR",
};

pub fn isSupportedFeature(flag: []const u8) bool {
	for(supportedFeatures) |supported| {
		if(std.ascii.eqlIgnoreCase(flag, supported)) return true;
	}
	return false;
}

/// The program macro set: the standard macros plus `IRIS_FEATURE_<flag>` for each optional
/// feature the pack asked about that this bridge has. Iris adds these after `shaders.properties`
/// is read, so they reach the shaders and not the properties file - the same order as here.
///
/// The result is a fresh list, released with `freeMacros` like the one it extends.
pub fn withFeatureMacros(allocator: NeverFailingAllocator, base: []const []const u8, optional: ?[]const u8) [][]const u8 {
	var list = List([]const u8).init(allocator);
	for(base) |macro| list.append(allocator.dupe(u8, macro));
	if(optional) |flags| {
		var it = std.mem.tokenizeAny(u8, flags, " \t");
		while(it.next()) |flag| {
			if(!isSupportedFeature(flag)) continue;
			var macro = List(u8).init(allocator);
			macro.appendSlice("IRIS_FEATURE_");
			for(flag) |char| macro.append(std.ascii.toUpper(char));
			list.append(macro.toOwnedSlice());
		}
	}
	return list.toOwnedSlice();
}

/// The `MC_*`/`IRIS_*` macros OptiFine and Iris inject into every shader.
///
/// Packs treat these as always present - Nostalgia's shadow filter reads `MC_SHADOW_QUALITY`
/// directly with no `#ifdef` guard, so without them nearly every program fails to compile with
/// "undefined variable". The list follows Iris's `StandardMacros`.
///
/// `MC_VERSION` is a fiction here: Cubyz is not Minecraft. It is reported as a recent version
/// because packs gate features on it (`#if MC_VERSION >= 11300`), and claiming an old version
/// would silently route them down legacy paths.
pub fn standardMacros(allocator: NeverFailingAllocator) [][]const u8 {
	var list = List([]const u8).init(allocator);

	const fixed = [_][]const u8{
		"MC_VERSION 12100",
		"MC_GL_VERSION 460",
		"MC_GLSL_VERSION 460",
		"MC_MIPMAP_LEVEL 4",
		"MC_RENDER_QUALITY 1.0",
		"MC_SHADOW_QUALITY 1.0",
		"MC_HAND_DEPTH 0.125",
		"MC_NORMAL_MAP",
		"MC_SPECULAR_MAP",
		"MAX_COLOR_BUFFERS 16",
		// Packs branch on this to pick Iris-specific paths over OptiFine ones, and the Iris path
		// is the one this pipeline reproduces.
		"IS_IRIS",
		"IRIS_TAG_SUPPORT 2",
		// The lowest version that clears every threshold the corpus tests for a uniform this
		// bridge supplies: `>= 10800` is where packs start reading `cameraPositionFract`. Higher
		// thresholds in the corpus only pick between bug workarounds, and the older path is the
		// safe direction to fall. Features are advertised separately, through `IRIS_FEATURE_*`,
		// and only those that exist: none of the custom-image, higher-shadowcolor or chunk-fade
		// flags are defined, because none of those are implemented.
		"IRIS_VERSION 10800",
	};
	for(fixed) |macro| list.append(allocator.dupe(u8, macro));

	// `MC_RENDER_STAGE_*`, one per entry of Iris's `WorldRenderingPhase`, valued by ordinal - which
	// is exactly what `StandardMacros` does. Packs compare `renderStage` against these by name, so
	// without them a pack either fails to compile or, worse, compares against an undefined name that
	// some drivers treat as 0 and silently matches the wrong stage.
	for(renderStages, 0..) |stage, ordinal| {
		var macro = List(u8).init(allocator);
		macro.appendSlice("MC_RENDER_STAGE_");
		macro.appendSlice(stage);
		macro.print(" {}", .{ordinal});
		list.append(macro.toOwnedSlice());
	}
	// No option is injected as a macro here. An earlier stopgap appended
	// `#define ResolutionScale 1.0` to every program's define list; once the options system
	// existed - which rewrites the option's own declaring line, as Iris does - the injection
	// collided with the very line it used to stand in for: NVIDIA rejects the pair with
	// `C7101: Macro ResolutionScale redefined`, and that single error took down every program
	// in Nostalgia that includes the settings header, which is all of them but the sky.
	// Overrides belong in `shaderpacks/<pack>.options.txt`, nowhere else.

	switch(@import("builtin").os.tag) {
		.windows => list.append(allocator.dupe(u8, "MC_OS_WINDOWS")),
		.linux => list.append(allocator.dupe(u8, "MC_OS_LINUX")),
		.macos => list.append(allocator.dupe(u8, "MC_OS_MAC")),
		else => list.append(allocator.dupe(u8, "MC_OS_OTHER")),
	}

	// Packs use the vendor and renderer macros for driver-specific workarounds.
	appendGlStringMacro(allocator, &list, c.GL_VENDOR, "MC_GL_VENDOR_", &.{
		.{.needle = "NVIDIA", .suffix = "NVIDIA"},
		.{.needle = "ATI", .suffix = "ATI"},
		.{.needle = "AMD", .suffix = "AMD"},
		.{.needle = "Intel", .suffix = "INTEL"},
		.{.needle = "Mesa", .suffix = "MESA"},
	});
	appendGlStringMacro(allocator, &list, c.GL_RENDERER, "MC_GL_RENDERER_", &.{
		.{.needle = "GeForce", .suffix = "GEFORCE"},
		.{.needle = "Quadro", .suffix = "QUADRO"},
		.{.needle = "Radeon", .suffix = "RADEON"},
		.{.needle = "Intel", .suffix = "INTEL"},
		.{.needle = "llvmpipe", .suffix = "LLVMPIPE"},
	});

	return list.toOwnedSlice();
}

/// Iris's `WorldRenderingPhase`, in order - the ordinal *is* the value packs compare against, so
/// this list must not be reordered or pruned even where Cubyz never enters a stage.
pub const renderStages = [_][]const u8{
	"NONE",           "SKY",                   "SUNSET",     "CUSTOM_SKY",
	"SUN",            "MOON",                  "STARS",      "VOID",
	"TERRAIN_SOLID",  "TERRAIN_CUTOUT_MIPPED", "TERRAIN_CUTOUT", "ENTITIES",
	"BLOCK_ENTITIES", "DESTROY",               "OUTLINE",    "DEBUG",
	"HAND_SOLID",     "TERRAIN_TRANSLUCENT",   "TRIPWIRE",   "PARTICLES",
	"CLOUDS",         "RAIN_SNOW",             "WORLD_BORDER", "HAND_TRANSLUCENT",
};

/// The stages Cubyz actually enters, by name, so call sites read as the stage rather than a number.
pub const stages = struct {
	pub const none = indexOfStage("NONE");
	pub const sky = indexOfStage("SKY");
	pub const sun = indexOfStage("SUN");
	pub const moon = indexOfStage("MOON");
	pub const terrainSolid = indexOfStage("TERRAIN_SOLID");
	pub const terrainTranslucent = indexOfStage("TERRAIN_TRANSLUCENT");
};

fn indexOfStage(comptime name: []const u8) i32 {
	for(renderStages, 0..) |entry, index| {
		if(std.mem.eql(u8, entry, name)) return @intCast(index);
	}
	@compileError("unknown render stage " ++ name);
}

const MacroMatch = struct {needle: []const u8, suffix: []const u8};

fn appendGlStringMacro(allocator: NeverFailingAllocator, list: *List([]const u8), name: c_uint, prefix: []const u8, matches: []const MacroMatch) void {
	const raw = c.glGetString(name) orelse return;
	const text = std.mem.span(raw);
	for(matches) |match| {
		if(std.mem.indexOf(u8, text, match.needle) == null) continue;
		var macro = List(u8).init(allocator);
		macro.appendSlice(prefix);
		macro.appendSlice(match.suffix);
		list.append(macro.toOwnedSlice());
	}
}

pub fn freeMacros(allocator: NeverFailingAllocator, macros: [][]const u8) void {
	for(macros) |macro| allocator.free(macro);
	allocator.free(macros);
}

// MARK: program compilation

/// Where generated GLSL is written when a stage fails to compile.
///
/// The driver reports line numbers into source that exists nowhere on disk - it is assembled from
/// the pack's files, the compatibility shim and the prologue. Without the actual text those line
/// numbers are unusable, so a failure dumps exactly what was submitted.
pub const dumpDirectory = "irisbridge_dump";

fn dumpSource(label: []const u8, stageName: []const u8, source: []const u8) void {
	var pathBuffer: [256]u8 = undefined;
	const path = std.fmt.bufPrint(&pathBuffer, "{s}/{s}.{s}.glsl", .{dumpDirectory, label, stageName}) catch return;
	main.files.cwd().makePath(dumpDirectory) catch {};
	main.files.cwd().write(path, source) catch |err| {
		std.log.warn("irisbridge: could not dump {s}: {s}", .{path, @errorName(err)});
		return;
	};
	std.log.info("irisbridge: wrote generated source to {s}", .{path});
}

fn compileStage(source: []const u8, stage: c_uint, label: []const u8) ?c_uint {
	const stageName = switch(stage) {
		c.GL_VERTEX_SHADER => "vert",
		c.GL_FRAGMENT_SHADER => "frag",
		c.GL_GEOMETRY_SHADER => "geom",
		c.GL_COMPUTE_SHADER => "comp",
		else => "other",
	};
	const shader = c.glCreateShader(stage);
	const length: c_int = @intCast(source.len);
	c.glShaderSource(shader, 1, &[_][*c]const u8{source.ptr}, &length);
	c.glCompileShader(shader);

	var success: c_int = undefined;
	c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &success);
	if(success != c.GL_TRUE) {
		var buffer: [8192]u8 = undefined;
		var written: c_int = 0;
		c.glGetShaderInfoLog(shader, buffer.len, &written, &buffer);
		std.log.err("irisbridge: {s} ({s}) failed to compile:\n{s}", .{
			label, stageName, buffer[0..@intCast(@max(written, 0))],
		});
		dumpSource(label, stageName, source);
		c.glDeleteShader(shader);
		return null;
	}
	return shader;
}

/// Asks the driver one question, once, and logs the answer.
///
/// This is a probe, not a feature, and it is meant to be deleted - either replaced by the fix it
/// enables or removed when the answer turns out to be no. It exists because the alternative is a
/// claim about GLSL that nothing has checked, and this project's history is a long list of those.
///
/// The question. The per-call-site sampler redirect rewrites `texture(gtexture, ...)` to
/// `cubyz_sampleArray(...)` by scanning tokens, and cannot see through a macro the pack defines
/// itself, because the transformer does not preprocess. photon writes
///
///     #define read_tex(x) texture(x, uv, lod_bias)
///     ...
///     vec4 base_color = read_tex(gtexture) * tint;
///
/// so the scan sees a call to `read_tex`, correctly leaves it alone, and the *driver* then expands
/// the macro - after `#define gtexture cubyz_blockTextures` - into
/// `texture(sampler2DArray, vec2, float)`, which is not a signature that exists. That is photon's
/// `gbuffers_terrain` failure exactly.
///
/// If a user function may *overload* a built-in name with a signature the built-in does not have,
/// the fix is a handful of declarations in the fragment prologue, resolved by the compiler after
/// preprocessing - precisely where the token scan cannot reach. If instead declaring one hides every
/// built-in of that name, the approach is dead and would take all four working packs with it.
///
/// So both halves are asked: that the overload is accepted, and that the built-ins still resolve
/// beside it.
pub fn probeBuiltinOverloadOnce() void {
	if(builtinOverloadProbed) return;
	builtinOverloadProbed = true;

	const probe =
		\\#version 460
		\\uniform sampler2DArray probeArray;
		\\uniform sampler2D probe2D;
		\\// Half one: may this be declared at all? `texture` is a built-in name, and
		\\// `(sampler2DArray, vec2)` is a signature it does not have. The body deliberately calls
		\\// `textureLod` rather than `texture`, so it cannot itself depend on the answer.
		\\vec4 texture(sampler2DArray s, vec2 c) {return textureLod(s, vec3(c, 0.0), 0.0);}
		\\layout(location = 0) out vec4 probeOut;
		\\void main() {
		\\    // Half two: do the built-ins still resolve? The first call must find the user overload,
		\\    // the second and third the built-in 2D and array forms.
		\\    probeOut = texture(probeArray, vec2(0.5))
		\\        + texture(probe2D, vec2(0.5))
		\\        + texture(probeArray, vec3(0.5));
		\\}
		\\
	;

	const shader = c.glCreateShader(c.GL_FRAGMENT_SHADER);
	defer c.glDeleteShader(shader);
	const length: c_int = @intCast(probe.len);
	c.glShaderSource(shader, 1, &[_][*c]const u8{probe.ptr}, &length);
	c.glCompileShader(shader);

	var success: c_int = undefined;
	c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &success);
	if(success == c.GL_TRUE) {
		std.log.info("irisbridge: driver accepts overloading a built-in sampling name — the macro case is reachable, see probeBuiltinOverloadOnce", .{});
		return;
	}
	var buffer: [2048]u8 = undefined;
	var written: c_int = 0;
	c.glGetShaderInfoLog(shader, buffer.len, &written, &buffer);
	std.log.info("irisbridge: driver rejects overloading a built-in sampling name, so a pack's own sampling macro cannot be redirected this way:\n{s}", .{
		buffer[0..@intCast(@max(written, 0))],
	});
}

var builtinOverloadProbed = false;

/// A pack program compiled and linked, with everything needed to run it resolved up front.
pub const Pass = struct {
	kind: pack.ProgramKind,
	index: u8,
	program: c_uint = 0,
	locations: uniforms.Locations = .{},
	drawBuffers: pack.DrawBuffers = .{},
	bindings: flip.PassBindings = .{},
	/// Every colortex some earlier pass in the chain has drawn to. A `texture.<stage>.<sampler>`
	/// override stops applying to a buffer once the chain has written it - see
	/// `packtextures.Set.bindOverrides` - and this is the set that decides it, resolved once at
	/// load like the flip bindings.
	writtenBefore: flip.TargetSet = .{},
	/// True for `final`, which draws to the screen rather than into a colortex.
	writesToScreen: bool = false,
	/// The pass's `colortexNMipmapEnabled` set, as a bitmask: the buffers to give a mipmap chain
	/// before it runs. See `targets.RenderTargets.setupMipmapping`.
	mipmappedBuffers: u16 = 0,
	/// Whether `shadowtex0`/`shadowtex1` want depth comparison, asked of the linked program
	/// rather than scanned from the source: a pack declares the same name both ways behind an
	/// `#ifdef`, and text cannot know which branch survived preprocessing. Binding a comparison
	/// sampler to a non-shadow sampler is undefined behaviour the driver warns about by the
	/// hundred.
	usesShadowComparison: [2]bool = @splat(false),
	/// Per-attachment blend state from the pack's own `blend.*` keys.
	///
	/// The per-buffer form is the part that matters: `colortex0` keeps alpha blending because that
	/// is how water tints the scene behind it, while the normal and material buffers must be
	/// *written, not blended* - a half-transparent surface whose normal is 40% mixed with whatever
	/// is behind it is not a normal, and every deferred pass downstream reads it as though it were.
	blendState: blend.State = .{},
	/// Which colortex buffers this pass's program actually declares a sampler for.
	readsColortex: u16 = 0,
	/// The `colorimgN`/`shadowcolorimgN` uniforms this program declares, and the pack's own images,
	/// bound per pass by `targets.bindImages`.
	images: targets.ImageBindings = .{},
	/// The program's `.csh` chain, dispatched in order before the draw. A pass may be nothing but
	/// this: `program` is then 0, it draws nothing and names no draw buffer, and its place in the
	/// chain is where Iris's `ComputeOnlyPass` sits (`CompositeRenderer.java:112-116`).
	computes: []ComputePass = &.{},
	/// True for a `shadowcomp` pass, which draws the shadow colour buffers at the shadow map's size
	/// rather than a colortex at the screen's.
	shadowComposite: bool = false,
	/// The pack's `alphaTest.<program>` reference, or null for the `ShaderKey` default the draw
	/// path supplies; what the program's `alphaTestRef` uniform reads either way.
	alphaTestRef: ?f32 = null,
	/// The pack's `scale.<program>`, the fraction of its target a composite-style pass draws into.
	viewportScale: pack.ViewportScale = .{},

	pub fn deinit(self: *Pass, allocator: NeverFailingAllocator) void {
		if(self.program != 0) c.glDeleteProgram(self.program);
		for(self.computes) |*compute| compute.deinit(allocator);
		if(self.computes.len != 0) allocator.free(self.computes);
		self.computes = &.{};
	}
};

/// One compute program of a chain, linked and resolved, with what its dispatch needs.
pub const ComputePass = struct {
	program: c_uint = 0,
	locations: uniforms.Locations = .{},
	images: targets.ImageBindings = .{},
	usesShadowComparison: [2]bool = @splat(false),
	workGroups: pack.WorkGroups = .{},
	/// `layout(local_size_x = ...)`, asked of the linked program, for the relative and default
	/// group counts.
	localSize: [3]u32 = .{1, 1, 1},
	/// `composite1_a`, for the log.
	label: []u8,

	pub fn deinit(self: *ComputePass, allocator: NeverFailingAllocator) void {
		if(self.program != 0) c.glDeleteProgram(self.program);
		allocator.free(self.label);
	}

	/// Iris's `ComputeProgram.getWorkGroups`: the absolute count when declared, else the render
	/// size scaled by `workGroupsRender` and divided by the local size, else the render size at
	/// the local size, one group deep. Ceilings throughout, and never zero groups.
	pub fn groups(self: *const ComputePass, width: f32, height: f32) [3]u32 {
		if(self.workGroups.absolute) |absolute| return absolute;
		const scale = self.workGroups.relative orelse [2]f32{1, 1};
		const x = @ceil(@ceil(width*scale[0])/@as(f32, @floatFromInt(self.localSize[0])));
		const y = @ceil(@ceil(height*scale[1])/@as(f32, @floatFromInt(self.localSize[1])));
		return .{
			@max(1, @as(u32, @intFromFloat(@max(x, 0)))),
			@max(1, @as(u32, @intFromFloat(@max(y, 0)))),
			1,
		};
	}
};

/// What has to be made visible around a compute dispatch: image stores, storage buffer writes,
/// and what the next pass samples or draws through. Iris issues the first three before every
/// dispatch unless the pack sets `allowConcurrentCompute` (`ComputeProgram.dispatch`) and after
/// each pass's chain (`CompositeRenderer.java:245-247`); the framebuffer bit is this bridge's own
/// addition for the draw that follows, as in `imageBarrierBits`.
pub const computeBarrierBits: c_uint = c.GL_SHADER_IMAGE_ACCESS_BARRIER_BIT | c.GL_TEXTURE_FETCH_BARRIER_BIT | c.GL_SHADER_STORAGE_BARRIER_BIT | c.GL_FRAMEBUFFER_BARRIER_BIT;

/// Transforms, compiles and links one `.csh`.
///
/// Compute sources get the same treatment as a composite stage - the pack's version made core,
/// the macros, the legacy sampling shims and the clamp rewrite - plus the storage block relocation,
/// since a compute is where a pack's buffers are written most. Null on failure, and the chain
/// simply runs without that step, as a failed fragment stage drops its pass.
pub fn buildCompute(allocator: NeverFailingAllocator, compute: *const pack.ComputeSource, macros: []const []const u8, resources: *const images.Set) ?ComputePass {
	const source = glsl.transform(allocator, compute.source, .{
		.stage = .compute,
		.defines = macros,
		.storageBindingBase = images.storageBindingBase,
	});
	defer allocator.free(source);

	const shader = compileStage(source, c.GL_COMPUTE_SHADER, compute.name) orelse return null;
	defer c.glDeleteShader(shader);

	const linked = c.glCreateProgram();
	c.glAttachShader(linked, shader);
	c.glLinkProgram(linked);

	var success: c_int = undefined;
	c.glGetProgramiv(linked, c.GL_LINK_STATUS, &success);
	if(success != c.GL_TRUE) {
		var logLength: u32 = undefined;
		var buffer: [4096]u8 = undefined;
		c.glGetProgramInfoLog(linked, buffer.len, @ptrCast(&logLength), &buffer);
		std.log.err("irisbridge: {s} failed to link:\n{s}", .{compute.name, buffer[0..@min(logLength, buffer.len)]});
		c.glDeleteProgram(linked);
		return null;
	}

	if(unsupportedResources(allocator, linked, compute.name, resources)) {
		c.glDeleteProgram(linked);
		return null;
	}

	var localSize: [3]c_int = .{1, 1, 1};
	c.glGetProgramiv(linked, c.GL_COMPUTE_WORK_GROUP_SIZE, &localSize);

	return .{
		.program = linked,
		.locations = uniforms.Locations.resolve(linked),
		.images = targets.ImageBindings.resolve(linked, resources),
		.usesShadowComparison = resolveShadowComparison(linked),
		.workGroups = compute.workGroups,
		.localSize = .{
			@intCast(@max(localSize[0], 1)),
			@intCast(@max(localSize[1], 1)),
			@intCast(@max(localSize[2], 1)),
		},
		.label = allocator.dupe(u8, compute.name),
	};
}

/// Builds the enabled computes of a program's chain, in order; failures are dropped.
pub fn buildComputes(allocator: NeverFailingAllocator, program: *const pack.Program, macros: []const []const u8, resources: *const images.Set) []ComputePass {
	var list = List(ComputePass).init(allocator);
	for(program.computes) |*compute| {
		if(!program.computeEnabled(compute)) continue;
		if(buildCompute(allocator, compute, macros, resources)) |built| {
			list.append(built);
		} else {
			std.log.warn("irisbridge: {s} did not compile; the rest of the chain runs without it", .{compute.name});
		}
	}
	return list.toOwnedSlice();
}

/// Dispatches a compute chain with the bindings of the pass it belongs to.
///
/// Each program is bound with everything a draw program gets - the render targets, the shadow
/// samplers, the pack's textures and its stage overrides, the images, the frame's uniforms and the
/// custom set - and dispatched after the barrier Iris issues, with one more after the chain so
/// the draw or the next pass sees every store. `width` and `height` are Iris's render size for the
/// stage: the screen for every composite-style stage, `shadowcomp` included
/// (`ShadowCompositeRenderer.java:195-196`), the shadow map's side for the `shadow` chain, and
/// 1 by 1 for `setup`.
pub fn dispatchComputes(
	renderTargets: *targets.RenderTargets,
	packTextures: *const packtextures.Set,
	customImages: *const images.Set,
	custom: *const customuniforms.Set,
	computes: []const ComputePass,
	stage: ?packtextures.Stage,
	bindings: flip.PassBindings,
	writtenBefore: flip.TargetSet,
	values: *const uniforms.Values,
	width: f32,
	height: f32,
) void {
	if(computes.len == 0) return;
	for(computes) |*compute| {
		c.glUseProgram(compute.program);
		renderTargets.bindSamplers(bindings);
		renderTargets.bindShadowSamplers(compute.usesShadowComparison);
		bindSamplerUniforms(compute.program);
		packTextures.bind();
		packTextures.bindSamplerUniforms(compute.program);
		if(stage) |s| packTextures.bindOverrides(s, writtenBefore);
		customImages.bindSamplers();
		customImages.bindSamplerUniforms(compute.program);
		_ = renderTargets.bindImages(compute.images, bindings, customImages);
		uniforms.upload(values, &compute.locations);
		custom.upload(compute.program);

		c.glMemoryBarrier(computeBarrierBits);
		const groups = compute.groups(width, height);
		c.glDispatchCompute(groups[0], groups[1], groups[2]);
	}
	c.glMemoryBarrier(computeBarrierBits);
	c.glUseProgram(0);
}

/// The default vertex shader for a pass whose pack does not supply one.
///
/// Rare but legal: a pack may ship `composite3.fsh` alone. Written in the compat dialect so it
/// goes through the same transform as everything else rather than being a second code path.
const defaultVertexSource =
	\\#version 120
	\\varying vec2 texcoord;
	\\void main() {
	\\    gl_Position = vec4(gl_Vertex.xy*2.0 - 1.0, 0.0, 1.0);
	\\    texcoord = gl_MultiTexCoord0.xy;
	\\}
	\\
;

/// Transforms, compiles and links one pack program, its compute chain first.
///
/// Returns null on failure; the caller drops the pass rather than aborting the whole pipeline, so
/// one broken program costs that effect and not the entire pack. A program whose draw stage fails
/// but whose computes built keeps them as a compute-only pass, with no draw buffers so it flips
/// nothing; the computes are independent programs and Iris would have run them.
pub fn buildPass(allocator: NeverFailingAllocator, program: *const pack.Program, macros: []const []const u8, properties: *const pack.Properties, resources: *const images.Set) ?Pass {
	const computes = buildComputes(allocator, program, macros, resources);
	// A `setup.fsh` is read by Iris's program set and drawn by nothing - only `setup`'s computes
	// are ever dispatched (`IrisRenderingPipeline.java:489`, `:500-519`) - so it is not built here.
	const drawn = program.enabled and program.fragmentSource != null and program.kind != .setup;
	const built: ?Pass = if(drawn) buildDrawPass(allocator, program, macros, properties, resources) else null;
	if(built) |pass| {
		var withComputes = pass;
		withComputes.computes = computes;
		return withComputes;
	}
	if(computes.len == 0) return null;
	return .{
		.kind = program.kind,
		.index = program.index,
		.program = 0,
		.computes = computes,
		.drawBuffers = .{},
	};
}

fn buildDrawPass(allocator: NeverFailingAllocator, program: *const pack.Program, macros: []const []const u8, properties: *const pack.Properties, resources: *const images.Set) ?Pass {
	const fragmentSource = program.fragmentSource orelse return null;
	const drawBufferCount = @max(program.drawBuffers.count, 1);

	const fragment = glsl.transform(allocator, fragmentSource, .{
		.stage = .fragment,
		.fragDataCount = drawBufferCount,
		.defines = macros,
		// Complementary's and the voxel packs' `final` read the pack's buffers back.
		.storageBindingBase = images.storageBindingBase,
	});
	defer allocator.free(fragment);

	const vertex = glsl.transform(allocator, program.vertexSource orelse defaultVertexSource, .{
		.stage = .vertex,
		.defines = macros,
		.storageBindingBase = images.storageBindingBase,
	});
	defer allocator.free(vertex);

	var label = List(u8).init(allocator);
	defer label.deinit();
	label.appendSlice(program.kind.baseName());
	if(program.kind.isNumbered() and program.index != 0) label.print("{}", .{program.index});

	const vertexShader = compileStage(vertex, c.GL_VERTEX_SHADER, label.items) orelse return null;
	defer c.glDeleteShader(vertexShader);
	const fragmentShader = compileStage(fragment, c.GL_FRAGMENT_SHADER, label.items) orelse return null;
	defer c.glDeleteShader(fragmentShader);

	const linked = c.glCreateProgram();
	c.glAttachShader(linked, vertexShader);
	c.glAttachShader(linked, fragmentShader);
	c.glLinkProgram(linked);

	var success: c_int = undefined;
	c.glGetProgramiv(linked, c.GL_LINK_STATUS, &success);
	if(success != c.GL_TRUE) {
		var logLength: u32 = undefined;
		var buffer: [4096]u8 = undefined;
		c.glGetProgramInfoLog(linked, buffer.len, @ptrCast(&logLength), &buffer);
		std.log.err("irisbridge: {s} failed to link:\n{s}", .{label.items, buffer[0..@min(logLength, buffer.len)]});
		c.glDeleteProgram(linked);
		return null;
	}

	if(unsupportedResources(allocator, linked, label.items, resources)) {
		c.glDeleteProgram(linked);
		return null;
	}

	return .{
		.kind = program.kind,
		.index = program.index,
		.program = linked,
		.locations = uniforms.Locations.resolve(linked),
		.drawBuffers = program.drawBuffers,
		.writesToScreen = program.kind == .final,
		.shadowComposite = program.kind == .shadowcomp,
		.usesShadowComparison = resolveShadowComparison(linked),
		.images = targets.ImageBindings.resolve(linked, resources),
		// Resolved by the loader from the live view of the fragment source, as Iris's
		// `ProgramDirectives` reads its `const bool`s from the preprocessed text.
		.mipmappedBuffers = program.mipmappedBuffers,
		// Keyed by the name the pack writes, index included: `scale.composite1`.
		.viewportScale = blk: {
			var nameBuffer: [64]u8 = undefined;
			break :blk pack.scaleOverride(properties, pack.programName(program, &nameBuffer)) orelse .{};
		},
	};
}

/// Says what widths a pack declared its own attributes at, when they are not the `vec4` default.
///
/// `mc_Entity`, `mc_midTexCoord` and `at_tangent` are pack-declared names, and the corpus is split:
/// photon writes `attribute vec2 mc_midTexCoord;` where four other packs write `vec4`. The prologue
/// follows whatever the pack wrote, and that fix is invisible in the image by construction - the
/// program either compiles or it does not - so without this line "the fix worked" and "the fix did
/// nothing" read identically. `AttributeTypes.differFromDefault` exists for exactly this and had no
/// caller.
fn reportAttributeWidths(kind: pack.ProgramKind, attributes: prologue.AttributeTypes) void {
	if(!attributes.differFromDefault()) return;
	std.log.info("irisbridge: {s} declares mc_Entity {s}, mc_midTexCoord {s}, at_tangent {s}", .{
		@tagName(kind), attributes.entity, attributes.midTexCoord, attributes.tangent,
	});
}

/// Builds a gbuffers program that runs on Cubyz's own geometry.
///
/// Differs from a composite pass in three ways, all forced by Cubyz having no vertex buffer: the
/// vertex stage gets the SSBO-pull prologue, the pack's `main` is renamed so the prologue's `main`
/// can run setup first, and the attributes the prologue computes are stripped from the pack source
/// to avoid redeclaring them.
pub fn buildGbuffersPass(allocator: NeverFailingAllocator, program: *const pack.Program, macros: []const []const u8, properties: *const pack.Properties, tinted: bool, alphaTest: bool, resources: *const images.Set) ?Pass {
	const fragmentSource = program.fragmentSource orelse return null;
	const vertexSource = program.vertexSource orelse return null;
	const drawBufferCount = @max(program.drawBuffers.count, 1);

	// The pack's own `alphaTest.<program>` replaces the `ShaderKey` default outright, test and
	// reference both (`ShaderProperties.java:255`, `ProgramDirectives`): `off` switches the
	// injection off for a program that would otherwise get it, and a named function switches it
	// on for one that would not. The reference travels on the pass for the draw path to upload.
	const alphaTestOverride = pack.alphaTestOverride(properties, program.kind.baseName());
	const alphaTestFunction: glsl.AlphaTestFunction = if(alphaTestOverride) |override| override.function else .greater;
	const injectsAlphaTest = if(alphaTestOverride) |override| override.function != .always else alphaTest;

	const attributes = prologue.AttributeTypes.fromSource(allocator, vertexSource);
	reportAttributeWidths(program.kind, attributes);
	const vertexPrologue = prologue.terrainVertex(allocator, tinted, attributes, program.geometrySource != null);
	defer allocator.free(vertexPrologue);
	// The same flag on both halves: a program that draws the transparent meshes gets the fluid
	// tint in its vertex stage and the glass synthesis in its fragment stage.
	const fragmentPrologue = prologue.terrainFragment(allocator, tinted);
	defer allocator.free(fragmentPrologue);

	const vertex = glsl.transform(allocator, vertexSource, .{
		.stage = .vertex,
		.defines = macros,
		.version = 460,
		.prologue = vertexPrologue,
		.entryPointName = prologue.packEntryPoint,
		.strippedAttributes = &prologue.suppliedAttributes,
		.storageBindingBase = images.storageBindingBase,
	});
	defer allocator.free(vertex);

	const fragment = glsl.transform(allocator, fragmentSource, .{
		.stage = .fragment,
		.fragDataCount = drawBufferCount,
		.defines = macros,
		.version = 460,
		.prologue = fragmentPrologue,
		.storageBindingBase = images.storageBindingBase,
		// The pack's own declarations of the block-texture sampler must go. It writes
		// `uniform sampler2D gcolor;` (RRe36's spelling; others use `gtexture`/`tex`), and the
		// prologue `#define`s those names onto `cubyz_blockTextures` - so left in place the
		// declaration becomes `uniform sampler2D cubyz_blockTextures;`, conflicting with the
		// prologue's `sampler2DArray` declaration of the same name. `specular` is deliberately
		// *not* in this list: its redirect takes the pack's sampler as an argument it ignores,
		// so that declaration has to survive.
		.strippedAttributes = &prologue.suppliedSamplers,
		// Sampling calls are rewritten *by first argument*: `texture(gcolor, uv, bias)` becomes
		// `cubyz_sampleArray(...)`, which resolves the array layer exactly as
		// `chunk_fragment.frag` does. Renaming the sampler alone cannot work - packs pass a
		// two-component coordinate and no `texture(sampler2DArray, vec2)` overload exists
		// whatever the sampler is called.
		.arraySamplers = &prologue.arraySamplers,
		// A call inside the pack's *own* macro, where the sampler is the macro's parameter and
		// cannot be named, is dispatched by sampler type instead. Gbuffers fragment stages only:
		// the helpers live in the terrain fragment prologue.
		.macroDispatch = prologue.macroDispatch,
		// Iris's alpha test, for the programs whose `ShaderKey` carries one: terrain cutout and the
		// shadow pass at 0.1, translucents off (`ShaderKey.java:27-28`, `:67`). See `glsl.Options`.
		.alphaTest = injectsAlphaTest,
		.alphaTestFunction = alphaTestFunction,
		.entryPointName = if(injectsAlphaTest) prologue.packEntryPoint else null,
	});
	defer allocator.free(fragment);

	// The pack's own geometry stage, attached whenever it ships one, exactly as Iris does. It sits
	// between two stages this file writes prologues for, and the bridge's only business with it is
	// carrying the texture layer across - see `prologue.geometryPassthrough`.
	const geometry: ?[]u8 = if(program.geometrySource) |geometrySource| blk: {
		const passthrough = prologue.geometryPassthrough(allocator);
		defer allocator.free(passthrough);
		break :blk glsl.transform(allocator, geometrySource, .{
			.stage = .geometry,
			.defines = macros,
			.version = 460,
			.prologue = passthrough,
			.entryPointName = prologue.packEntryPoint,
			// The voxelising geometry stage is where a pack writes its buffers most.
			.storageBindingBase = images.storageBindingBase,
		});
	} else null;
	defer if(geometry) |source| allocator.free(source);

	var label = List(u8).init(allocator);
	defer label.deinit();
	label.appendSlice(program.kind.baseName());

	const vertexShader = compileStage(vertex, c.GL_VERTEX_SHADER, label.items) orelse return null;
	defer c.glDeleteShader(vertexShader);
	const fragmentShader = compileStage(fragment, c.GL_FRAGMENT_SHADER, label.items) orelse return null;
	defer c.glDeleteShader(fragmentShader);
	const geometryShader: ?c_uint = if(geometry) |source| (compileStage(source, c.GL_GEOMETRY_SHADER, label.items) orelse return null) else null;
	defer if(geometryShader) |shader| c.glDeleteShader(shader);

	const linked = c.glCreateProgram();
	c.glAttachShader(linked, vertexShader);
	c.glAttachShader(linked, fragmentShader);
	if(geometryShader) |shader| c.glAttachShader(linked, shader);
	c.glLinkProgram(linked);

	var success: c_int = undefined;
	c.glGetProgramiv(linked, c.GL_LINK_STATUS, &success);
	if(success != c.GL_TRUE) {
		var logLength: u32 = undefined;
		var buffer: [4096]u8 = undefined;
		c.glGetProgramInfoLog(linked, buffer.len, @ptrCast(&logLength), &buffer);
		std.log.err("irisbridge: {s} failed to link:\n{s}", .{label.items, buffer[0..@min(logLength, buffer.len)]});
		c.glDeleteProgram(linked);
		return null;
	}

	if(unsupportedResources(allocator, linked, label.items, resources)) {
		c.glDeleteProgram(linked);
		return null;
	}

	return .{
		.kind = program.kind,
		.index = program.index,
		.program = linked,
		.locations = uniforms.Locations.resolve(linked),
		.drawBuffers = program.drawBuffers,
		.usesShadowComparison = resolveShadowComparison(linked),
		.blendState = blend.resolve(properties, program.kind.baseName(), program.drawBuffers.slice()),
		.alphaTestRef = if(alphaTestOverride) |override| override.reference else null,
		.images = targets.ImageBindings.resolve(linked, resources),
	};
}

/// Builds a sky gbuffers program, run over a synthesised fullscreen triangle.
///
/// Differs from `buildGbuffersPass` in what it deliberately does not do. There is no fragment
/// prologue and no sampler redirect: a sky program's `gtexture` is a genuine 2D texture - the sun and
/// moon discs, the star sheet - not Cubyz's block array, so pointing it at a `sampler2DArray` would
/// be wrong in a way that only shows up on the packs that draw those. The vertex attributes are still
/// stripped and supplied, because a pack is free to declare `mc_Entity` in a shared header its sky
/// program includes.
///
/// `textured` builds the same program over the sun and moon quads instead of the fullscreen
/// triangle (`prologue.skyTexturedVertex`), with Minecraft's additive blend as its default: that
/// is `gbuffers_skytextured`, whose `gtexture` is bound to the bridge's sun or moon sheet per draw.
pub fn buildSkyPass(allocator: NeverFailingAllocator, program: *const pack.Program, macros: []const []const u8, properties: *const pack.Properties, resources: *const images.Set, textured: bool) ?Pass {
	const fragmentSource = program.fragmentSource orelse return null;
	const vertexSource = program.vertexSource orelse return null;
	const drawBufferCount = @max(program.drawBuffers.count, 1);

	const attributes = prologue.AttributeTypes.fromSource(allocator, vertexSource);
	reportAttributeWidths(program.kind, attributes);
	const vertexPrologue = if(textured) prologue.skyTexturedVertex(allocator, attributes) else prologue.skyVertex(allocator, attributes);
	defer allocator.free(vertexPrologue);

	const vertex = glsl.transform(allocator, vertexSource, .{
		.stage = .vertex,
		.defines = macros,
		.version = 460,
		.prologue = vertexPrologue,
		.entryPointName = prologue.packEntryPoint,
		.strippedAttributes = &prologue.suppliedAttributes,
	});
	defer allocator.free(vertex);

	const fragment = glsl.transform(allocator, fragmentSource, .{
		.stage = .fragment,
		.fragDataCount = drawBufferCount,
		.defines = macros,
	});
	defer allocator.free(fragment);

	var label = List(u8).init(allocator);
	defer label.deinit();
	label.appendSlice(program.kind.baseName());

	const vertexShader = compileStage(vertex, c.GL_VERTEX_SHADER, label.items) orelse return null;
	defer c.glDeleteShader(vertexShader);
	const fragmentShader = compileStage(fragment, c.GL_FRAGMENT_SHADER, label.items) orelse return null;
	defer c.glDeleteShader(fragmentShader);

	const linked = c.glCreateProgram();
	c.glAttachShader(linked, vertexShader);
	c.glAttachShader(linked, fragmentShader);
	c.glLinkProgram(linked);

	var success: c_int = undefined;
	c.glGetProgramiv(linked, c.GL_LINK_STATUS, &success);
	if(success != c.GL_TRUE) {
		var logLength: u32 = undefined;
		var buffer: [4096]u8 = undefined;
		c.glGetProgramInfoLog(linked, buffer.len, @ptrCast(&logLength), &buffer);
		std.log.err("irisbridge: {s} failed to link:\n{s}", .{label.items, buffer[0..@min(logLength, buffer.len)]});
		c.glDeleteProgram(linked);
		return null;
	}

	if(unsupportedResources(allocator, linked, label.items, resources)) {
		c.glDeleteProgram(linked);
		return null;
	}

	return .{
		.kind = program.kind,
		.index = program.index,
		.program = linked,
		.locations = uniforms.Locations.resolve(linked),
		.drawBuffers = program.drawBuffers,
		.usesShadowComparison = resolveShadowComparison(linked),
		.blendState = blend.resolveWith(properties, program.kind.baseName(), program.drawBuffers.slice(), if(textured) blend.additive else blend.default),
		.images = targets.ImageBindings.resolve(linked, resources),
	};
}

/// Which of `shadowtex0`/`shadowtex1` this program declared as `sampler2DShadow`.
///
/// Asked of the linked program rather than inferred from the source, because the source is not
/// a reliable answer and this project already paid for assuming it was. Packs declare the same name
/// both ways behind a conditional - Complementary's `lib/uniforms.glsl` is
///
///     uniform sampler2DShadow shadowtex1;
///     #ifdef COMPOSITE1
///         uniform sampler2D shadowtex0;
///     #else
///         uniform sampler2DShadow shadowtex0;
///     #endif
///
/// so a text scan sees both forms and has no way to know which survives. The driver does: it has
/// already run the preprocessor by the time the program links, and `glGetActiveUniform` reports the
/// type that actually exists.
///
/// Getting it wrong is not a silent mistake either. Binding a comparison sampler object to a unit a
/// shader reads with a plain `sampler2D` is undefined behaviour, and the driver says so -
/// 897 messages in one run before this was fixed:
///
///     The current GL state uses a sampler that has depth comparisons enabled, with a texture object
///     with a depth format, by a shader that samples it with a non-shadow sampler.
///
/// Resolved per sampler, not per program. The previous version OR-ed the two names together and bound
/// one sampler object to both units, which cannot express a pack that wants comparison on one and raw
/// depth on the other - and that is the common case, not an exotic one.
/// Whether a linked program uses resources nothing supplies: an image uniform that is neither a
/// buffer view nor one of the pack's declared images, or a shader storage block at a binding no
/// pack buffer was bound to.
///
/// A program using such a thing is not merely short of data. An image unit with nothing bound
/// makes every `imageStore`/`imageAtomic*` undefined, and a storage block at a binding nothing was
/// bound to - or one the engine *does* use - is a write into memory that is not the pack's. So the
/// program is refused, with one line saying exactly what it asked for; that is the stance the
/// README takes on `COLORED_LIGHTING`: advertising a feature and binding nothing behind it is
/// worse than declining it. Until 2026-09-11 every pack image and every pack buffer fell under
/// this, which is what kept the two voxel packs out and Solas's shadow program dark; now the pack's
/// own declarations (`images.Set`) are what a program may name, and the message says which
/// declaration is missing when it names something else.
///
/// Asked of the linked binary, so only resources that survived preprocessing count - a declaration
/// behind an `#ifdef` the pack's options switched off is not a reason to refuse anything. The
/// block's binding is asked of the binary too, after the transformer's relocation, so the number
/// in the message is the pack's own `bufferObject.N`.
fn unsupportedResources(allocator: NeverFailingAllocator, program: c_uint, label: []const u8, resources: *const images.Set) bool {
	var found = List(u8).init(allocator);
	defer found.deinit();

	var uniformCount: c_int = 0;
	c.glGetProgramiv(program, c.GL_ACTIVE_UNIFORMS, &uniformCount);
	var index: c_uint = 0;
	while(index < uniformCount) : (index += 1) {
		var name: [128]u8 = undefined;
		var length: c_int = 0;
		var size: c_int = 0;
		var kind: c_uint = 0;
		c.glGetActiveUniform(program, index, name.len, &length, &size, &kind, &name);
		if(length <= 0 or !isImageType(kind)) continue;
		const declared = name[0..@intCast(length)];
		// The colortex and shadowcolor buffers viewed as images are supplied - see
		// `targets.bindImages` - and so is every image the pack declared.
		if(isBufferImageName(declared)) continue;
		if(resources.imageIndex(declared) != null) continue;
		if(found.items.len != 0) found.appendSlice(", ");
		found.print("image {s} (no image.{s} in shaders.properties)", .{declared, declared});
	}

	var blockCount: c_int = 0;
	c.glGetProgramInterfaceiv(program, c.GL_SHADER_STORAGE_BLOCK, c.GL_ACTIVE_RESOURCES, &blockCount);
	index = 0;
	while(index < blockCount) : (index += 1) {
		var name: [128]u8 = undefined;
		var length: c_int = 0;
		c.glGetProgramResourceName(program, c.GL_SHADER_STORAGE_BLOCK, index, name.len, &length, &name);
		if(length <= 0) continue;
		const declared = name[0..@intCast(length)];
		// The vertex prologue's own pull from Cubyz's chunk buffers, which the engine binds.
		if(std.mem.startsWith(u8, declared, "_cubyz")) continue;
		var property: c_uint = c.GL_BUFFER_BINDING;
		var binding: c_int = -1;
		var written: c_int = 0;
		c.glGetProgramResourceiv(program, c.GL_SHADER_STORAGE_BLOCK, index, 1, &property, 1, &written, &binding);
		const point: ?c_uint = if(binding >= 0) @intCast(binding) else null;
		if(point != null and resources.hasBufferBinding(point.?)) continue;
		if(found.items.len != 0) found.appendSlice(", ");
		if(point != null and point.? >= images.storageBindingBase) {
			found.print("buffer {s} (no bufferObject.{} in shaders.properties)", .{declared, point.? - images.storageBindingBase});
		} else {
			found.print("buffer {s} at binding {}", .{declared, binding});
		}
	}

	if(found.items.len == 0) return false;
	std.log.warn("irisbridge: {s} uses resources nothing supplies, so the program is disabled: {s}", .{label, found.items});
	return true;
}

/// `colorimgN` or `shadowcolorimgN`, with nothing but digits after the prefix.
fn isBufferImageName(name: []const u8) bool {
	for([_][]const u8{"colorimg", "shadowcolorimg"}) |prefix| {
		if(!std.mem.startsWith(u8, name, prefix)) continue;
		const rest = name[prefix.len..];
		if(rest.len == 0) return false;
		for(rest) |char| if(!std.ascii.isDigit(char)) return false;
		return true;
	}
	return false;
}

fn isImageType(kind: c_uint) bool {
	return switch(kind) {
		c.GL_IMAGE_1D, c.GL_IMAGE_2D, c.GL_IMAGE_3D, c.GL_IMAGE_2D_ARRAY, c.GL_IMAGE_1D_ARRAY, c.GL_IMAGE_CUBE, c.GL_IMAGE_BUFFER,
		c.GL_INT_IMAGE_1D, c.GL_INT_IMAGE_2D, c.GL_INT_IMAGE_3D, c.GL_INT_IMAGE_2D_ARRAY, c.GL_INT_IMAGE_1D_ARRAY, c.GL_INT_IMAGE_CUBE, c.GL_INT_IMAGE_BUFFER,
		c.GL_UNSIGNED_INT_IMAGE_1D, c.GL_UNSIGNED_INT_IMAGE_2D, c.GL_UNSIGNED_INT_IMAGE_3D, c.GL_UNSIGNED_INT_IMAGE_2D_ARRAY, c.GL_UNSIGNED_INT_IMAGE_1D_ARRAY, c.GL_UNSIGNED_INT_IMAGE_CUBE, c.GL_UNSIGNED_INT_IMAGE_BUFFER,
		=> true,
		else => false,
	};
}

fn resolveShadowComparison(program: c_uint) [2]bool {
	var result = [2]bool{false, false};
	var count: c_int = 0;
	c.glGetProgramiv(program, c.GL_ACTIVE_UNIFORMS, &count);

	var index: c_uint = 0;
	while(index < count) : (index += 1) {
		var name: [64]u8 = undefined;
		var length: c_int = 0;
		var size: c_int = 0;
		var kind: c_uint = 0;
		c.glGetActiveUniform(program, index, name.len, &length, &size, &kind, &name);
		if(length <= 0 or kind != c.GL_SAMPLER_2D_SHADOW) continue;

		const declared = name[0..@intCast(length)];
		if(std.mem.eql(u8, declared, "shadowtex1")) {
			result[1] = true;
		} else if(std.mem.eql(u8, declared, "shadowtex0") or
			// OptiFine's older aliases name the same texture unit as `shadowtex0`.
			std.mem.eql(u8, declared, "shadow") or
			std.mem.eql(u8, declared, "watershadow") or
			std.mem.eql(u8, declared, "shadowtex"))
		{
			result[0] = true;
		}
	}
	return result;
}

/// Assigns each sampler uniform the texture unit `targets.bindSamplers` binds it to.
pub fn bindSamplerUniforms(program: c_uint) void {
	var name: [32]u8 = undefined;
	for(0..targets.colortexCount) |index| {
		const written = std.fmt.bufPrintZ(&name, "colortex{}", .{index}) catch continue;
		const location = c.glGetUniformLocation(program, written.ptr);
		if(location >= 0) c.glUniform1i(location, @intCast(index));
	}
	for(0..3) |index| {
		const written = std.fmt.bufPrintZ(&name, "depthtex{}", .{index}) catch continue;
		const location = c.glGetUniformLocation(program, written.ptr);
		if(location >= 0) c.glUniform1i(location, @intCast(targets.depthTextureUnit + index));
	}
	// OptiFine's older aliases for the same buffers, still used by many packs.
	const aliases = [_]struct {name: [:0]const u8, unit: c_int}{
		.{.name = "gcolor", .unit = 0},
		.{.name = "gdepth", .unit = 1},
		.{.name = "gnormal", .unit = 2},
		.{.name = "composite", .unit = 3},
		.{.name = "gaux1", .unit = 4},
		.{.name = "gaux2", .unit = 5},
		.{.name = "gaux3", .unit = 6},
		.{.name = "gaux4", .unit = 7},
	};
	for(aliases) |alias| {
		const location = c.glGetUniformLocation(program, alias.name.ptr);
		if(location >= 0) c.glUniform1i(location, alias.unit);
	}
	// The shadow set too, or it reads the albedo. A sampler uniform nobody assigns reads unit
	// 0 - which during the post chain holds colortex0, a non-depth RGBA16F texture. A
	// `sampler2DShadow` pointed there is the driver warning that filled a ten-megabyte log
	// ("sampler (0) ... comparisons disabled ... texture object with a non-depth format ...
	// shadow sampler"), and it means every shadow lookup in the pack was comparing against the
	// scene's own colour buffer.
	const shadowSet = [_]struct {name: [:0]const u8, unit: c_uint}{
		.{.name = "shadowtex0", .unit = targets.shadowTextureUnit},
		.{.name = "shadowtex1", .unit = targets.shadowTextureUnit + 1},
		// OptiFine's older alias: `watershadow` present makes `shadowtex0` the all-casters map.
		// Cubyz's two maps are the same buffer, so the alias simply lands on the same unit.
		.{.name = "watershadow", .unit = targets.shadowTextureUnit},
		// The two oldest aliases. Bliss declares `uniform sampler2DShadow shadow;` in every pass
		// that reads the map, and with neither name here the sampler sat on unit 0 - colortex0,
		// a colour texture under a shadow sampler, which the driver reported as undefined behaviour
		// 396 times in one run. `resolveShadowComparison` already knew both names; this table did not.
		.{.name = "shadow", .unit = targets.shadowTextureUnit},
		.{.name = "shadowtex", .unit = targets.shadowTextureUnit},
		.{.name = "shadowcolor", .unit = targets.shadowColorTextureUnit},
	};
	for(shadowSet) |entry| {
		const location = c.glGetUniformLocation(program, entry.name.ptr);
		if(location >= 0) c.glUniform1i(location, @intCast(entry.unit));
	}
	// `shadowcolor0` to `shadowcolor7`, one unit each after the first; a program can only name
	// the ones `pack.shadowColorUsage` had allocated, since that scan is over the same sources.
	inline for(0..flip.shadowColorCount) |index| {
		const alias = std.fmt.comptimePrint("shadowcolor{}", .{index});
		const location = c.glGetUniformLocation(program, alias.ptr);
		if(location >= 0) c.glUniform1i(location, @intCast(targets.shadowColorTextureUnit + index));
	}
}

// MARK: blend state

fn blendFactorToGl(factor: blend.Factor) c_uint {
	return switch(factor) {
		.zero => c.GL_ZERO,
		.one => c.GL_ONE,
		.srcColor => c.GL_SRC_COLOR,
		.oneMinusSrcColor => c.GL_ONE_MINUS_SRC_COLOR,
		.dstColor => c.GL_DST_COLOR,
		.oneMinusDstColor => c.GL_ONE_MINUS_DST_COLOR,
		.srcAlpha => c.GL_SRC_ALPHA,
		.oneMinusSrcAlpha => c.GL_ONE_MINUS_SRC_ALPHA,
		.dstAlpha => c.GL_DST_ALPHA,
		.oneMinusDstAlpha => c.GL_ONE_MINUS_DST_ALPHA,
		.constantColor => c.GL_CONSTANT_COLOR,
		.oneMinusConstantColor => c.GL_ONE_MINUS_CONSTANT_COLOR,
		.constantAlpha => c.GL_CONSTANT_ALPHA,
		.oneMinusConstantAlpha => c.GL_ONE_MINUS_CONSTANT_ALPHA,
		.srcAlphaSaturate => c.GL_SRC_ALPHA_SATURATE,
	};
}

/// Applies a program's per-attachment blend state.
pub fn applyBlendState(state: *const blend.State) void {
	// A program that declares no draw buffers still rasterises to attachment 0.
	const slots = @max(state.count, 1);
	for(0..slots) |slot| {
		const index: c_uint = @intCast(slot);
		switch(state.slots[slot]) {
			.off => c.glDisablei(c.GL_BLEND, index),
			.on => |factors| {
				c.glEnablei(c.GL_BLEND, index);
				c.glBlendFuncSeparatei(
					index,
					blendFactorToGl(factors.srcRgb),
					blendFactorToGl(factors.dstRgb),
					blendFactorToGl(factors.srcAlpha),
					blendFactorToGl(factors.dstAlpha),
				);
			},
		}
	}
}

/// Clears the per-attachment blend state the pack set, so Cubyz's own pipelines are unaffected.
///
/// `glEnable(GL_BLEND)` alone does not undo `glDisablei`: the indexed enables are separate state,
/// and a `glDisablei(GL_BLEND, 1)` left behind would silently switch off blending on attachment 1
/// for everything the engine draws afterwards.
pub fn resetBlendState() void {
	var maxDrawBuffers: c_int = 8;
	c.glGetIntegerv(c.GL_MAX_DRAW_BUFFERS, &maxDrawBuffers);
	for(0..@intCast(@max(maxDrawBuffers, 1))) |slot| {
		c.glEnablei(c.GL_BLEND, @intCast(slot));
	}
}

// MARK: execution

/// Runs one pass: its compute chain, then its draw.
///
/// `screenWidth` and `screenHeight` are the render size the computes are dispatched against and
/// the viewport a `final` pass draws into; a `setup` pass is given 1 by 1, as Iris dispatches it.
pub fn runPass(
	quad: *const Quad,
	renderTargets: *targets.RenderTargets,
	packTextures: *const packtextures.Set,
	customImages: *const images.Set,
	custom: *const customuniforms.Set,
	pass: *const Pass,
	values: *const uniforms.Values,
	screenWidth: u31,
	screenHeight: u31,
) void {
	const stage = packtextures.Stage.forProgramKind(pass.kind);
	dispatchComputes(renderTargets, packTextures, customImages, custom, pass.computes, stage, pass.bindings, pass.writtenBefore, values, @floatFromInt(screenWidth), @floatFromInt(screenHeight));
	// A compute-only pass draws nothing.
	if(pass.program == 0) return;

	c.glUseProgram(pass.program);

	if(pass.writesToScreen) {
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
		c.glViewport(0, 0, screenWidth, screenHeight);
	} else if(pass.shadowComposite) {
		// The shadow colour buffers on the side the chain resolved, over the map's square.
		renderTargets.bindShadowCompositeFramebuffer(pass.drawBuffers.slice(), pass.bindings);
		c.glViewport(0, 0, renderTargets.shadowResolution, renderTargets.shadowResolution);
	} else {
		renderTargets.bindForPass(pass.drawBuffers.slice(), pass.bindings, false);
		// The buffer's extent, not the screen's - a pass writing a declared-size target under a
		// full-screen viewport fills one corner of it and leaves the rest stale. Then the pack's
		// `scale.<program>`, applied as `CompositeRenderer.java:263-267` does: the viewport is the
		// declared fraction of that extent, starting at the declared offsets into it.
		const extent = renderTargets.viewportFor(pass.drawBuffers.slice());
		const scale = pass.viewportScale;
		const width: f32 = @floatFromInt(extent[0]);
		const height: f32 = @floatFromInt(extent[1]);
		c.glViewport(@intFromFloat(width*scale.x), @intFromFloat(height*scale.y), @intFromFloat(width*scale.scale), @intFromFloat(height*scale.scale));
	}

	renderTargets.bindSamplers(pass.bindings);
	// Before the overrides, which may replace unit 0 for this pass.
	renderTargets.setupMipmapping(pass.mipmappedBuffers, pass.bindings);
	// The comparison state is per *program*, asked of the linked binary: a pack declares
	// `shadowtex0` as `sampler2DShadow` in one pass and plain `sampler2D` in the next, and binding
	// the wrong sampler object either way is undefined behaviour the driver warns about per draw.
	renderTargets.bindShadowSamplers(pass.usesShadowComparison);
	bindSamplerUniforms(pass.program);
	packTextures.bind();
	packTextures.bindSamplerUniforms(pass.program);
	// After `bindSamplers`, which binds the render targets this deliberately replaces on the same
	// units. `texture.<stage>.<sampler>` is scoped per stage, so `gaux4` can be a pack image here
	// and colortex7 in the next pass.
	if(stage) |s| packTextures.bindOverrides(s, pass.writtenBefore);
	customImages.bindSamplers();
	customImages.bindSamplerUniforms(pass.program);
	const boundImages = renderTargets.bindImages(pass.images, pass.bindings, customImages);
	uniforms.upload(values, &pass.locations);
	// The pack's own expression uniforms, before the draw: set afterwards they would reach the
	// next frame's pass instead, which for `taaOffset` is a jitter that never cancels.
	custom.upload(pass.program);
	// The compat `gl_*` matrices, which in a fullscreen blit describe the quad rather than the
	// world camera. Nostalgia and Kappa map the quad by hand and never read them; Complementary
	// writes `gl_Position = ftransform()` in every post-chain vertex stage, and against the zero a
	// never-uploaded matrix holds that collapses its whole chain to a point.
	uniforms.uploadFullscreenMatrices(pass.program, values);

	// Composite passes are pure image processing: depth testing and blending would only let
	// leftover state from world rendering discard or blend fragments the pack expects to land.
	c.glDisable(c.GL_DEPTH_TEST);
	c.glDisable(c.GL_BLEND);
	c.glDepthMask(c.GL_FALSE);

	quad.bindFor(pass.program);
	quad.draw();
	c.glBindVertexArray(0);

	// Image stores are not ordered against the next pass's texture reads or image loads unless a
	// barrier says so; without it a later pass can read the buffer as it was before this one ran.
	if(boundImages) c.glMemoryBarrier(imageBarrierBits);
}

/// What has to be made visible after a pass that wrote through images: subsequent sampling,
/// subsequent image access, and the framebuffer path a later pass may draw the buffer through.
pub const imageBarrierBits: c_uint = c.GL_SHADER_IMAGE_ACCESS_BARRIER_BIT | c.GL_TEXTURE_FETCH_BARRIER_BIT | c.GL_FRAMEBUFFER_BARRIER_BIT;

/// Whether a pass runs *before* the gbuffers stage.
///
/// Iris's order is begin -> shadow -> prepare -> gbuffers -> deferred -> composite -> final, so
/// `begin` and `prepare` fall on the near side of geometry - `begin` at the top of the frame,
/// before the shadow map (`IrisRenderingPipeline.beginLevelRendering`), `prepare` after it. Getting
/// this wrong is quietly destructive rather than obviously broken: a pack whose `prepare` writes the
/// sky into colortex0 expects terrain to paint over it, and running those passes afterwards paints
/// the sky across the albedo instead. `setup` runs once at load and `shadowcomp` inside the shadow
/// pass; neither is part of this chain.
pub fn runsBeforeGeometry(kind: pack.ProgramKind) bool {
	return kind == .begin or kind == .prepare;
}

pub fn isPostChainKind(kind: pack.ProgramKind) bool {
	return switch(kind) {
		.begin, .prepare, .deferred, .composite, .final => true,
		else => false,
	};
}

/// Sorts passes into execution order: begin, prepare, deferred, composite, final, each group by
/// ascending index.
pub fn passOrder(kind: pack.ProgramKind) u8 {
	return switch(kind) {
		.begin => 0,
		.prepare => 1,
		.deferred => 2,
		.composite => 3,
		.final => 4,
		else => 5,
	};
}
