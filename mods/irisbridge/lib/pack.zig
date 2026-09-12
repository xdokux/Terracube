//! Reads an OptiFine/Iris shaderpack: `shaders.properties`, `#include` resolution, the `const`
//! configuration declarations packs hide in their shader source, and the `DRAWBUFFERS` directive.
//!
//! Everything here that parses is a pure function over a string, and file access goes through
//! `SourceProvider`. That split is deliberate: it lets the whole loader be tested against an
//! in-memory pack without touching a disk or a GL context, which matters because the failure mode
//! this code has to get right - a pack whose `#include` graph is subtly wrong - is tedious to
//! reproduce any other way.

const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const List = main.ListManaged;

/// Re-exported so callers get the same instance rather than declaring a second module over the
/// same file, which Zig rejects.
pub const glsl = @import("glsl.zig");
/// Re-exported for the conformance harness, which transforms the terrain programs with the same
/// sampler redirects and dispatch the real gbuffers builder uses, so a pack helper that takes the
/// block texture as a parameter is exercised without a driver.
pub const prologue = @import("prologue.zig");
/// Re-exported for the same reason as `glsl`: the conformance harness lives in another module and
/// has to build an `Overrides` to call `loadPrograms`.
pub const options = @import("options.zig");
/// Re-exported likewise: `loadPrograms` reads every directive from the preprocessed view of a
/// program, and callers hand it the macro table that view is evaluated against.
pub const preprocess = @import("preprocess.zig");

// MARK: source access

/// Supplies file contents by shaders-root-relative path (always starting with `/`).
///
/// Indirection rather than direct `std.fs` use, so a pack can come from a directory, a `.zip`, or
/// a test fixture without the parsers knowing the difference.
pub const SourceProvider = struct {
	ptr: *anyopaque,
	readFn: *const fn(ptr: *anyopaque, path: []const u8) ?[]const u8,

	pub fn read(self: SourceProvider, path: []const u8) ?[]const u8 {
		return self.readFn(self.ptr, path);
	}
};

/// Resolves an `#include` target against the directory of the including file.
///
/// OptiFine's rule: a leading `/` is relative to the shaders root, anything else is relative to
/// the file doing the including. `.` and `..` segments are folded here so the resulting key is
/// canonical - otherwise `/lib/../lib/x.glsl` and `/lib/x.glsl` would look like different files
/// to the cycle detector and get included twice.
pub fn resolvePath(allocator: NeverFailingAllocator, currentDir: []const u8, target: []const u8) []u8 {
	var segments = List([]const u8).init(allocator);
	defer segments.deinit();

	if(!std.mem.startsWith(u8, target, "/")) {
		var it = std.mem.tokenizeAny(u8, currentDir, "/\\");
		while(it.next()) |segment| segments.append(segment);
	}
	var it = std.mem.tokenizeAny(u8, target, "/\\");
	while(it.next()) |segment| {
		if(std.mem.eql(u8, segment, ".")) continue;
		if(std.mem.eql(u8, segment, "..")) {
			if(segments.items.len != 0) segments.items.len -= 1;
			continue;
		}
		segments.append(segment);
	}

	var out = List(u8).init(allocator);
	for(segments.items) |segment| {
		out.append('/');
		out.appendSlice(segment);
	}
	if(out.items.len == 0) out.append('/');
	return out.toOwnedSlice();
}

/// Directory portion of a resolved path, e.g. `/lib/util.glsl` -> `/lib`.
fn dirOf(path: []const u8) []const u8 {
	const index = std.mem.lastIndexOfScalar(u8, path, '/') orelse return "/";
	if(index == 0) return "/";
	return path[0..index];
}

pub const IncludeError = error{TooDeep, Cycle, Missing};

/// Splices every `#include` into one translation unit.
///
/// Guards against both runaway depth and cycles. A cycle is a hard error rather than a silent
/// skip: packs use include guards, so a genuine cycle means the pack is malformed and silently
/// dropping the second include would produce a confusing compile error much further downstream.
pub fn resolveIncludes(
	allocator: NeverFailingAllocator,
	rootPath: []const u8,
	provider: SourceProvider,
	diagnostics: ?*List(u8),
) IncludeError![]u8 {
	var stack = List([]const u8).init(allocator);
	defer {
		for(stack.items) |entry| allocator.free(entry);
		stack.deinit();
	}
	var out = List(u8).init(allocator);
	errdefer out.deinit();

	const rootCopy = allocator.dupe(u8, rootPath);
	defer allocator.free(rootCopy);
	try expand(allocator, rootCopy, provider, &stack, &out, diagnostics);
	return out.toOwnedSlice();
}

const maxIncludeDepth = 64;

fn expand(
	allocator: NeverFailingAllocator,
	path: []const u8,
	provider: SourceProvider,
	stack: *List([]const u8),
	out: *List(u8),
	diagnostics: ?*List(u8),
) IncludeError!void {
	if(stack.items.len >= maxIncludeDepth) {
		if(diagnostics) |d| d.print("include nesting deeper than {} at {s}\n", .{maxIncludeDepth, path});
		return error.TooDeep;
	}
	for(stack.items) |entry| {
		if(std.mem.eql(u8, entry, path)) {
			if(diagnostics) |d| d.print("include cycle at {s}\n", .{path});
			return error.Cycle;
		}
	}
	const source = provider.read(path) orelse {
		if(diagnostics) |d| d.print("missing include target {s}\n", .{path});
		return error.Missing;
	};

	stack.append(allocator.dupe(u8, path));
	defer allocator.free(stack.pop());

	const tokens = glsl.tokenize(allocator, source);
	defer allocator.free(tokens);

	var i: usize = 0;
	while(i < tokens.len) : (i += 1) {
		const token = tokens[i];
		if(token.directive != .include) {
			out.appendSlice(token.text);
			continue;
		}
		// Consume the whole directive, then splice the target in its place. The trailing newline
		// is kept so the following line does not join onto the included file's last line.
		var target: ?[]const u8 = null;
		while(i < tokens.len and tokens[i].kind != .newline) : (i += 1) {
			if(tokens[i].kind == .string and tokens[i].text.len >= 2) {
				target = tokens[i].text[1 .. tokens[i].text.len - 1];
			}
		}
		if(target) |relative| {
			const resolved = resolvePath(allocator, dirOf(path), relative);
			defer allocator.free(resolved);
			try expand(allocator, resolved, provider, stack, out, diagnostics);
		}
		// Swallow the directive's own newline when the spliced file already supplied one,
		// so a chain of includes does not accumulate a blank line per level.
		const endedWithNewline = out.items.len != 0 and out.items[out.items.len - 1] == '\n';
		if(i < tokens.len and !endedWithNewline) out.appendSlice(tokens[i].text);
	}
}

// MARK: shaders.properties

/// Key/value pairs from `shaders.properties`, kept as raw strings.
///
/// No interpretation happens here. The file mixes several unrelated namespaces (`program.*`,
/// `blend.*`, `scale.*`, option declarations, screen layout) and each consumer wants a different
/// slice of it, so this stays a flat map and the meaning is applied where it is needed.
pub const Properties = struct {
	entries: std.StringHashMapUnmanaged([]const u8) = .empty,
	arena: std.heap.ArenaAllocator,

	pub fn deinit(self: *Properties) void {
		self.entries.deinit(self.arena.allocator());
		self.arena.deinit();
	}

	pub fn get(self: *const Properties, key: []const u8) ?[]const u8 {
		return self.entries.get(key);
	}

	pub fn getBool(self: *const Properties, key: []const u8, default: bool) bool {
		const value = self.get(key) orelse return default;
		if(std.mem.eql(u8, value, "true")) return true;
		if(std.mem.eql(u8, value, "false")) return false;
		return default;
	}
};

pub fn parseProperties(allocator: NeverFailingAllocator, source: []const u8) Properties {
	var result = Properties{.arena = std.heap.ArenaAllocator.init(allocator.allocator)};
	const arena = result.arena.allocator();

	var logical = List(u8).init(allocator);
	defer logical.deinit();

	var lines = std.mem.splitScalar(u8, source, '\n');
	while(lines.next()) |rawLine| {
		const line = std.mem.trimEnd(u8, rawLine, "\r");
		// A trailing backslash continues onto the next line; packs use it for long option lists.
		if(std.mem.endsWith(u8, line, "\\")) {
			logical.appendSlice(line[0 .. line.len - 1]);
			continue;
		}
		logical.appendSlice(line);
		defer logical.clearRetainingCapacity();

		const trimmed = std.mem.trim(u8, logical.items, " \t");
		if(trimmed.len == 0) continue;
		if(trimmed[0] == '#') continue;

		const separator = std.mem.indexOfAny(u8, trimmed, "=:") orelse continue;
		const key = std.mem.trim(u8, trimmed[0..separator], " \t");
		const value = std.mem.trim(u8, trimmed[separator + 1 ..], " \t");
		if(key.len == 0) continue;

		const keyCopy = arena.dupe(u8, key) catch unreachable;
		const valueCopy = arena.dupe(u8, value) catch unreachable;
		result.entries.put(arena, keyCopy, valueCopy) catch unreachable;
	}
	return result;
}

// MARK: draw buffers

/// Which colortex attachment each `gl_FragData` slot writes to.
///
/// The pack declares this as a comment, and the mapping is realised on the CPU with
/// `glDrawBuffers` - the shader itself just writes consecutive slots.
pub const DrawBuffers = struct {
	targets: [16]u8 = @splat(0),
	count: u8 = 0,

	pub fn slice(self: *const DrawBuffers) []const u8 {
		return self.targets[0..self.count];
	}
};

fn digitToTarget(c: u8) ?u8 {
	if(c >= '0' and c <= '9') return c - '0';
	if(c >= 'a' and c <= 'f') return c - 'a' + 10;
	if(c >= 'A' and c <= 'F') return c - 'A' + 10;
	return null;
}

/// Reads `/* DRAWBUFFERS:0231 */` or the newer `/* RENDERTARGETS: 0,2,3,1 */`.
///
/// Scanning tokenized comments rather than the raw text avoids matching the directive inside a
/// string or a stretch of code that merely mentions it.
///
/// The last directive in the text wins, not the first. Iris says so outright, in
/// `CommentDirectiveParser.findDirective`:
///
///     // Search for the last occurrence of the directive within the text, since those take
///     // precedence.
///     int indexOfPrefix = haystack.lastIndexOf(prefix);
///
/// A pack may carry several directives in one file behind `#if`s, declaring a small set up front
/// and a wider one inside a conditional. Complementary's `gbuffers_terrain` is that shape:
///
///     /* DRAWBUFFERS:06 */
///     gl_FragData[0] = color;
///     gl_FragData[1] = vec4(smoothnessD, materialMask, skyLightFactor, 1.0);
///     #if ...
///         /* DRAWBUFFERS:064 */
///         gl_FragData[2] = vec4(mat3(gbufferModelViewInverse) * normalM, 1.0);
///     #endif
///
/// Taking the first directive mapped two slots, so the shader's third output - the normals -
/// was written and then thrown away by `glDrawBuffers`. The deferred pass then lit every surface
/// with no normal and returned black, which is most of a screen rendering as untextured sky.
///
/// What "last" is measured over matters as much as the rule. Iris reads the directive from the
/// *preprocessed* source (`ShaderPack.java:286`), in which only the live branch of each `#if`
/// remains; an earlier version of this file said Iris did not evaluate the conditionals, and that
/// was wrong. Over the raw text, last-wins also picks up a directive in a branch the pack's options
/// have switched off - Complementary's `composite4` declares `DRAWBUFFERS:3` and then
/// `DRAWBUFFERS:30` under `#if MOTION_BLUR_EFFECT == 1`, off by default - and attaches a buffer to
/// an output the shader never writes. So `loadProgram` hands this function the live view of the
/// source (`liveView`), and the raw text only as a fallback when that view has no directive at all.
pub fn parseDrawBuffers(allocator: NeverFailingAllocator, source: []const u8) ?DrawBuffers {
	const tokens = glsl.tokenize(allocator, source);
	defer allocator.free(tokens);

	var last: ?DrawBuffers = null;
	for(tokens) |token| {
		if(token.kind != .comment) continue;

		if(std.mem.indexOf(u8, token.text, "RENDERTARGETS")) |index| {
			const rest = token.text[index + "RENDERTARGETS".len ..];
			const colon = std.mem.indexOfScalar(u8, rest, ':') orelse continue;
			var result = DrawBuffers{};
			var it = std.mem.tokenizeAny(u8, rest[colon + 1 ..], ", \t*/");
			var usable = true;
			while(it.next()) |entry| {
				const value = std.fmt.parseInt(u8, entry, 10) catch break;
				// A directive naming a target this host cannot provide is rejected whole, not
				// truncated at the offending entry.
				//
				// Indices above 15 are Iris *custom images*, which a pack gates on
				// `IRIS_FEATURE_CUSTOM_IMAGES`, a flag this bridge never defines, so with the live
				// view such a directive is normally already gone. It is still rejected whole here
				// rather than trusted: this function also runs over the raw text as a fallback, where
				// every branch is present and the last may be for a feature we do not implement.
				// Complementary's `deferred1` carries six, ending in `RENDERTARGETS: 0,5,19,18`, with
				// `DRAWBUFFERS:054` as the branch that actually compiles here.
				//
				// Truncating instead - the previous behaviour - silently produced `{0, 5}` and dropped
				// that program's third output, which is the same defect the last-wins rule was added to
				// fix, reintroduced by it.
				if(value > 15 or result.count >= 16) {
					usable = false;
					break;
				}
				result.targets[result.count] = value;
				result.count += 1;
			}
			if(usable and result.count != 0) last = result;
			continue;
		}

		if(std.mem.indexOf(u8, token.text, "DRAWBUFFERS")) |index| {
			const rest = token.text[index + "DRAWBUFFERS".len ..];
			const colon = std.mem.indexOfScalar(u8, rest, ':') orelse continue;
			var result = DrawBuffers{};
			for(rest[colon + 1 ..]) |c| {
				if(c == ' ' or c == '\t') continue;
				const value = digitToTarget(c) orelse break;
				if(result.count >= 16) break;
				result.targets[result.count] = value;
				result.count += 1;
			}
			if(result.count != 0) last = result;
		}
	}
	return last;
}

// MARK: const configuration

/// Internal formats a pack may request for a colortex attachment.
///
/// This is the OptiFine list, not every GL format. A pack naming something outside it is a pack
/// bug, and falling back to `rgba8` keeps the rest of the chain loadable so the user sees one
/// wrong buffer rather than a black screen.
pub const TextureFormat = enum {
	r8, rg8, rgb8, rgba8,
	r16, rg16, rgb16, rgba16,
	r16f, rg16f, rgb16f, rgba16f,
	r32f, rg32f, rgb32f, rgba32f,
	r11f_g11f_b10f,
	rgb10_a2,
	srgb8, srgb8_alpha8,
	// Signed-normalised and integer formats, following Iris's `InternalTextureFormat`. A pack
	// that asks for one of these and gets RGBA8 instead does not error: Nostalgic Red Voxels keeps
	// scaled depth in an `R32UI` buffer for `imageAtomicMin`, and an atomic on an 8-bit normalised
	// texture is not a wrong number, it is undefined.
	r8_snorm, rg8_snorm, rgb8_snorm, rgba8_snorm,
	r16_snorm, rg16_snorm, rgb16_snorm, rgba16_snorm,
	r8i, rg8i, rgb8i, rgba8i,
	r8ui, rg8ui, rgb8ui, rgba8ui,
	r16i, rg16i, rgb16i, rgba16i,
	r16ui, rg16ui, rgb16ui, rgba16ui,
	r32i, rg32i, rgb32i, rgba32i,
	r32ui, rg32ui, rgb32ui, rgba32ui,
	rgb9_e5, rgb5_a1, r3_g3_b2,

	pub fn parse(name: []const u8) ?TextureFormat {
		inline for(@typeInfo(TextureFormat).@"enum".fields) |field| {
			if(std.ascii.eqlIgnoreCase(field.name, name)) return @enumFromInt(field.value);
		}
		return null;
	}
};

/// Pack-wide settings that live as `const` declarations inside shader source rather than in
/// `shaders.properties`, which is where OptiFine put them.
pub const Settings = struct {
	colortexFormat: [16]TextureFormat = @splat(.rgba8),
	colortexClear: [16]bool = @splat(true),
	/// `const vec4 colortexNClearColor = vec4(r, g, b, a);` - what a cleared buffer holds where
	/// nothing draws. Null is Iris's default for that slot, resolved in `targets.defaultClearColor`:
	/// colortex1 solid white, colortex2 onwards transparent black, and colortex0 the vanilla fog
	/// colour at alpha 1 (`ClearPassCreator.java:34-43`), for which this bridge stands in opaque
	/// black - the sky import lands on the same buffer, and photon, the one pack here without a
	/// `gbuffers_skybasic`, declares its own `vec4(0.0)`. Kappa asks for `vec4(0.0, 1.0, 0.0, 0.0)`
	/// on colortex15 and reads its `.y` as the ambient occlusion term, so a sky pixel cleared to
	/// zero there is fully occluded rather than open.
	colortexClearColor: [16]?[4]f32 = @splat(null),
	shadowcolorFormat: [shadowColorCount]TextureFormat = @splat(.rgba8),
	/// `shadowcolorNClear` and `shadowcolorNClearColor`, the shadow buffers' counterparts of the
	/// colortex pair. Iris clears every shadow colour buffer to opaque white unless told otherwise
	/// (`PackShadowDirectives.SamplingSettings`, `clearColor = new Vector4f(1.0F)`); photon asks for
	/// transparent black on `shadowcolor0` and reads it back as a translucency mask.
	shadowcolorClear: [shadowColorCount]bool = @splat(true),
	shadowcolorClearColor: [shadowColorCount]?[4]f32 = @splat(null),
	shadowMapResolution: u32 = 1024,
	shadowDistance: f32 = 160.0,
	shadowMapFov: f32 = 90.0,
	/// `const float shadowNearPlane`/`shadowFarPlane`: the shadow ortho's depth range, Iris's
	/// `[0.05, 256]` unless the pack says otherwise (`matrix.shadowNearDefault`, `shadowFarDefault`).
	/// A negative value is Iris's "the render distance", which without Distant Horizons is the
	/// vanilla setting in chunks (`DHCompat.getRenderDistance`); in this corpus only Bliss asks for
	/// it, and only under `DISTANT_HORIZONS_SHADOWMAP`.
	shadowNearPlane: f32 = 0.05,
	shadowFarPlane: f32 = 256.0,
	/// `const float shadowIntervalSize`: the grid the shadow camera's origin snaps to, in blocks
	/// (`matrix.shadowGridSnap`). Iris's default is 2; Kappa, Nostalgia and photon declare it.
	shadowIntervalSize: f32 = 2.0,
	noiseTextureResolution: u32 = 256,
	/// Whether the pack asked for a hardware comparison sampler on the shadow map.
	shadowHardwareFiltering: bool = false,
	sunPathRotation: f32 = 0.0,
	ambientOcclusionLevel: f32 = 1.0,
	/// Fixed sizes for colortex buffers, from `size.buffer.colortexN = W H`.
	///
	/// Null means "follow the screen", which is the default and the common case. A pack declares a
	/// fixed size when the buffer is not an image of the scene at all: Nostalgia's `colortex4` is a
	/// 256x256 *sky capture*, written by `prepare` through a directional projection and sampled by
	/// `prepare1` with `projectSky(direction)`. Allocated at screen size instead, the projection
	/// lands on the wrong aspect and the sky it reconstructs is wrong everywhere.
	colortexSize: [16]?[2]BufferAxis = @splat(null),
};

/// Reads `size.buffer.colortexN = W H` out of `shaders.properties`.
///
/// Separate from `parseSettings` because these live in the properties file rather than in `const`
/// directives inside the shader sources.
/// One axis of a `size.buffer` declaration.
///
/// Iris's rule, verbatim from `gl/texture/TextureScaleOverride.java`: a value containing a `.` is a
/// fraction of the screen, anything else is an absolute pixel count, and the two are decided
/// per axis rather than per buffer.
///
///     if (xValue.contains(".")) { relativeX = Float.parseFloat(xValue); isXRelative = true; }
///     else                      { sizeX = Integer.parseInt(xValue); }
///     getX(originalX) = isXRelative ? (int) (originalX * relativeX) : sizeX;
///
/// The relative form is not a curiosity. Complementary declares
/// `size.buffer.colortex1 = REFLECTION_RES REFLECTION_RES` with `#define REFLECTION_RES 0.5`, so it
/// wants its reflection buffers at half the screen in each axis, and it addresses them with maths
/// that assumes exactly that. Allocating them full-screen instead - which is what an integer-only
/// parser does, silently, because `parseInt("0.5")` simply fails - leaves the pack writing into a
/// quarter of each buffer and every later pass reading the wrong region. Measured as a frame whose
/// content stopped at exactly half the width and half the height.
pub const BufferAxis = union(enum) {
	absolute: u31,
	relative: f32,

	pub fn resolve(self: BufferAxis, screen: u31) u31 {
		return switch(self) {
			.absolute => |value| value,
			// Truncated rather than rounded, as Iris's `(int)` cast does. Never zero: a zero-sized
			// attachment makes the whole framebuffer render nothing, which is a far worse failure
			// than being one texel out.
			.relative => |factor| @max(1, @as(u31, @intFromFloat(@as(f32, @floatFromInt(screen))*factor))),
		};
	}
};

/// A name the pack defines, for resolving `size.buffer` values that are written as a macro.
pub const Macro = struct {name: []const u8, value: []const u8};

/// Reads one axis of a `size.buffer` value, resolving a macro name against the pack's own options.
///
/// Packs write the value as a `#define`d name rather than a literal, and Iris resolves it because it
/// preprocesses `shaders.properties` against the pack's option values. `REFLECTION_RES` is declared
/// on Complementary's own settings screen, so its current value - after any user override, since the
/// options are discovered from already-rewritten source - is what the buffer must be sized by.
fn parseBufferAxis(text: []const u8, macros: []const Macro) ?BufferAxis {
	var resolved = text;
	for(macros) |macro| {
		if(std.mem.eql(u8, macro.name, text)) {
			resolved = macro.value;
			break;
		}
	}

	if(std.mem.indexOfScalar(u8, resolved, '.') != null) {
		const factor = std.fmt.parseFloat(f32, resolved) catch return null;
		if(!std.math.isFinite(factor) or factor <= 0) return null;
		return .{.relative = factor};
	}
	const value = std.fmt.parseInt(u31, resolved, 10) catch return null;
	if(value == 0) return null;
	return .{.absolute = value};
}

pub fn applyBufferSizes(properties: *const Properties, settings: *Settings, macros: []const Macro) void {
	var key: [32]u8 = undefined;
	for(0..16) |index| {
		const name = std.fmt.bufPrint(&key, "size.buffer.colortex{}", .{index}) catch continue;
		const value = properties.get(name) orelse continue;

		var parts = std.mem.tokenizeAny(u8, value, " \t");
		const widthText = parts.next() orelse continue;
		const heightText = parts.next() orelse continue;
		const width = parseBufferAxis(widthText, macros) orelse continue;
		const height = parseBufferAxis(heightText, macros) orelse continue;
		settings.colortexSize[index] = .{width, height};
	}
}

/// Directives this parser reads but the pipeline cannot act on, and why.
///
/// Kept as a list for the same reason `uniforms.unsupported` is: a value that is parsed and then
/// quietly ignored is worse than one that is missing, because the parsing code looks complete and
/// nothing anywhere says the value went nowhere. Three settings were in exactly that state before
/// this list existed - `shadowMapResolution`, `shadowcolorFormat` and `noiseTextureResolution` -
/// and each was producing wrong output that looked like a general rendering flaw.
///
/// If a directive here becomes supportable, delete its entry as part of the same change.
pub const unsupportedDirectives = [_]struct {name: []const u8, reason: []const u8}{
	.{
		.name = "shadowMapFov",
		// OptiFine switches the shadow camera to a perspective projection when this is set. The
		// shadow pass here is orthographic, which is what every fixture pack expects anyway.
		.reason = "the shadow camera is orthographic; perspective shadow maps are not implemented",
	},
	.{
		.name = "shadowHardwareFiltering",
		// Not a gap: the choice is made per program from how it declared `shadowtex0`, which handles
		// packs that declare it both ways in one pack. See `targets.bindShadowSamplers`.
		.reason = "superseded by per-program sampler objects, which handle packs that declare shadowtex both ways",
	},
	.{
		.name = "ambientOcclusionLevel",
		// Iris applies this to Minecraft's *baked per-vertex* AO. Cubyz's per-vertex light has no
		// separable occlusion term to scale - light and AO arrive as one value from the mesher - so
		// honouring it would mean changing how chunks are meshed, not how they are shaded.
		.reason = "Cubyz's per-vertex light has no separable occlusion term to scale",
	},
};

/// Logs the entries above that this pack actually set, with the reason each goes nowhere.
///
/// The list alone does not keep the gap visible - that is the whole claim its doc comment makes,
/// and nothing was reading it, so a pack asking for a perspective shadow camera got silence. Only
/// values that differ from the default are reported: a pack that never mentions a directive is not
/// being ignored, and listing all three every load would be noise nobody reads.
pub fn reportUnsupportedDirectives(packName: []const u8, settings: Settings) void {
	const defaults = Settings{};
	for(unsupportedDirectives) |entry| {
		const declared = if(std.mem.eql(u8, entry.name, "shadowMapFov"))
			settings.shadowMapFov != defaults.shadowMapFov
		else if(std.mem.eql(u8, entry.name, "shadowHardwareFiltering"))
			settings.shadowHardwareFiltering != defaults.shadowHardwareFiltering
		else if(std.mem.eql(u8, entry.name, "ambientOcclusionLevel"))
			settings.ambientOcclusionLevel != defaults.ambientOcclusionLevel
		else
			false;
		if(!declared) continue;
		std.log.warn("irisbridge: {s} sets `{s}`, which this bridge cannot honour: {s}", .{packName, entry.name, entry.reason});
	}
}

/// Scans `const <type> <name> = <value>;` declarations, one line at a time.
///
/// Line-based and comment-blind on purpose. That looks wrong until you meet a real pack: Nostalgia
/// wraps its entire buffer-format block in `/* ... */` so the declarations never reach the GLSL
/// compiler, and reads them back out of the comment. Iris does the same - `ConstDirectiveParser`
/// splits on newlines and tests each trimmed line, with no notion of comments at all - so a
/// token-aware parser that "correctly" skips comments finds nothing and every buffer silently
/// falls back to RGBA8.
///
/// Deliberately tolerant otherwise: unknown names are ignored, since packs declare plenty of
/// their own constants and only a fixed set means anything to the pipeline.
/// Which colortex buffers a program asks to have a mipmap chain built for, as a bitmask.
///
/// From `const bool <buffer>MipmapEnabled = true;`. Scanned line by line with no notion of
/// comments, the way Iris's `ConstDirectiveParser` reads every other `const` directive - Nostalgia
/// wraps a whole block of them in `/* ... */` and still means them.
///
/// Keyed on the declared value, not on the declaration existing. A pack writes `= false` for
/// the buffers it does not mipmap, so treating presence as opt-in would build a chain for every
/// buffer it merely mentions. A later declaration overrides an earlier one, which is what lets a
/// pack turn one back off inside a conditional.
pub fn parseMipmapEnabled(source: []const u8) u16 {
	const suffix = "MipmapEnabled";
	var result: u16 = 0;
	var lines = std.mem.splitScalar(u8, source, '\n');
	while(lines.next()) |raw| {
		const line = std.mem.trim(u8, raw, " \t\r");
		if(!std.mem.startsWith(u8, line, "const bool ")) continue;
		const rest = line["const bool ".len..];

		const nameEnd = std.mem.indexOf(u8, rest, suffix) orelse continue;
		// The suffix has to *end* the name rather than merely appear inside it.
		const after = std.mem.trimStart(u8, rest[nameEnd + suffix.len ..], " \t");
		if(after.len == 0 or after[0] != '=') continue;
		const target = colortexIndexForName(rest[0..nameEnd]) orelse continue;

		const value = std.mem.trim(u8, after[1..], " \t;");
		const bit = @as(u16, 1) << @intCast(target);
		if(std.mem.eql(u8, value, "true")) {
			result |= bit;
		} else {
			result &= ~bit;
		}
	}
	return result;
}

/// A buffer name as a colortex index, accepting OptiFine's older aliases.
///
/// `LEGACY_RENDER_TARGETS` in Iris: gcolor, gdepth, gnormal, composite and gaux1-gaux4 are
/// colortex0-colortex7. Packs mix the two spellings freely, sometimes within one file.
fn colortexIndexForName(name: []const u8) ?u8 {
	const legacy = [_][]const u8{"gcolor", "gdepth", "gnormal", "composite", "gaux1", "gaux2", "gaux3", "gaux4"};
	for(legacy, 0..) |alias, index| {
		if(std.mem.eql(u8, name, alias)) return @intCast(index);
	}
	if(!std.mem.startsWith(u8, name, "colortex")) return null;
	const number = std.fmt.parseInt(u8, name["colortex".len..], 10) catch return null;
	// Past the 16 real targets the name is not a buffer at all, whatever it looks like.
	if(number >= 16) return null;
	return number;
}

pub fn parseSettings(allocator: NeverFailingAllocator, source: []const u8, settings: *Settings) void {
	_ = allocator;
	var lines = std.mem.splitAny(u8, source, "\r\n");
	while(lines.next()) |rawLine| {
		// Cheap rejection first; the overwhelming majority of lines fail this.
		if(std.mem.indexOf(u8, rawLine, "const") == null) continue;
		if(std.mem.indexOfScalar(u8, rawLine, '=') == null) continue;
		if(std.mem.indexOfScalar(u8, rawLine, ';') == null) continue;

		var line = std.mem.trim(u8, rawLine, " \t");
		if(!std.mem.startsWith(u8, line, "const")) continue;
		line = line["const".len..];
		if(line.len == 0 or (line[0] != ' ' and line[0] != '\t')) continue;
		line = std.mem.trimStart(u8, line, " \t");

		const types = [_][]const u8{"int", "float", "vec2", "ivec3", "vec4", "bool"};
		var matchedType = false;
		for(types) |typeName| {
			if(!std.mem.startsWith(u8, line, typeName)) continue;
			const rest = line[typeName.len..];
			if(rest.len == 0 or (rest[0] != ' ' and rest[0] != '\t')) continue;
			line = std.mem.trimStart(u8, rest, " \t");
			matchedType = true;
			break;
		}
		if(!matchedType) continue;

		var nameLength: usize = 0;
		while(nameLength < line.len and (std.ascii.isAlphanumeric(line[nameLength]) or line[nameLength] == '_')) nameLength += 1;
		if(nameLength == 0) continue;
		const name = line[0..nameLength];

		line = std.mem.trimStart(u8, line[nameLength..], " \t");
		if(line.len == 0 or line[0] != '=') continue;
		line = std.mem.trimStart(u8, line[1..], " \t");

		const semicolon = std.mem.indexOfScalar(u8, line, ';') orelse continue;
		applySetting(name, std.mem.trim(u8, line[0..semicolon], " \t"), settings);
	}
}

fn applySetting(name: []const u8, value: []const u8, settings: *Settings) void {
	if(std.mem.startsWith(u8, name, "colortex") and std.mem.endsWith(u8, name, "Format")) {
		const digits = name["colortex".len .. name.len - "Format".len];
		const index = std.fmt.parseInt(u8, digits, 10) catch return;
		if(index > 15) return;
		settings.colortexFormat[index] = TextureFormat.parse(value) orelse {
			// Silently falling back is the class of bug this file keeps finding: the pack's
			// maths assumes the format it asked for, and nothing anywhere said it was not granted.
			std.log.warn("irisbridge: unknown buffer format '{s}' for {s}; allocating RGBA8", .{value, name});
			return;
		};
		return;
	}
	if(std.mem.startsWith(u8, name, "shadowcolor") and std.mem.endsWith(u8, name, "Format")) {
		const digits = name["shadowcolor".len .. name.len - "Format".len];
		const index = std.fmt.parseInt(u8, digits, 10) catch return;
		if(index >= shadowColorCount) return;
		settings.shadowcolorFormat[index] = TextureFormat.parse(value) orelse {
			std.log.warn("irisbridge: unknown buffer format '{s}' for {s}; allocating RGBA8", .{value, name});
			return;
		};
		return;
	}
	if(std.mem.startsWith(u8, name, "shadowcolor") and std.mem.endsWith(u8, name, "ClearColor")) {
		const digits = name["shadowcolor".len .. name.len - "ClearColor".len];
		const index = std.fmt.parseInt(u8, digits, 10) catch return;
		if(index >= shadowColorCount) return;
		settings.shadowcolorClearColor[index] = parseVec4(value) orelse {
			std.log.warn("irisbridge: unreadable clear colour '{s}' for {s}; keeping the default", .{value, name});
			return;
		};
		return;
	}
	if(std.mem.startsWith(u8, name, "shadowcolor") and std.mem.endsWith(u8, name, "Clear")) {
		const digits = name["shadowcolor".len .. name.len - "Clear".len];
		const index = std.fmt.parseInt(u8, digits, 10) catch return;
		if(index >= shadowColorCount) return;
		settings.shadowcolorClear[index] = std.mem.eql(u8, value, "true");
		return;
	}
	if(std.mem.startsWith(u8, name, "colortex") and std.mem.endsWith(u8, name, "ClearColor")) {
		const digits = name["colortex".len .. name.len - "ClearColor".len];
		const index = std.fmt.parseInt(u8, digits, 10) catch return;
		if(index > 15) return;
		settings.colortexClearColor[index] = parseVec4(value) orelse {
			std.log.warn("irisbridge: unreadable clear colour '{s}' for {s}; keeping the default", .{value, name});
			return;
		};
		return;
	}
	if(std.mem.startsWith(u8, name, "colortex") and std.mem.endsWith(u8, name, "Clear")) {
		const digits = name["colortex".len .. name.len - "Clear".len];
		const index = std.fmt.parseInt(u8, digits, 10) catch return;
		if(index > 15) return;
		settings.colortexClear[index] = std.mem.eql(u8, value, "true");
		return;
	}
	if(std.mem.eql(u8, name, "shadowMapResolution")) {
		settings.shadowMapResolution = std.fmt.parseInt(u32, value, 10) catch return;
	} else if(std.mem.eql(u8, name, "shadowDistance")) {
		settings.shadowDistance = std.fmt.parseFloat(f32, value) catch return;
	} else if(std.mem.eql(u8, name, "shadowMapFov")) {
		settings.shadowMapFov = std.fmt.parseFloat(f32, value) catch return;
	} else if(std.mem.eql(u8, name, "shadowNearPlane")) {
		settings.shadowNearPlane = std.fmt.parseFloat(f32, value) catch return;
	} else if(std.mem.eql(u8, name, "shadowFarPlane")) {
		settings.shadowFarPlane = std.fmt.parseFloat(f32, value) catch return;
	} else if(std.mem.eql(u8, name, "shadowIntervalSize")) {
		settings.shadowIntervalSize = std.fmt.parseFloat(f32, value) catch return;
	} else if(std.mem.eql(u8, name, "noiseTextureResolution")) {
		settings.noiseTextureResolution = std.fmt.parseInt(u32, value, 10) catch return;
	} else if(std.mem.eql(u8, name, "shadowHardwareFiltering")) {
		settings.shadowHardwareFiltering = std.mem.eql(u8, value, "true");
	} else if(std.mem.eql(u8, name, "sunPathRotation")) {
		settings.sunPathRotation = std.fmt.parseFloat(f32, value) catch return;
	} else if(std.mem.eql(u8, name, "ambientOcclusionLevel")) {
		settings.ambientOcclusionLevel = std.fmt.parseFloat(f32, value) catch return;
	}
}

/// Reads `vec4(r, g, b, a)`, the one value shape the clear-colour directives take.
fn parseVec4(value: []const u8) ?[4]f32 {
	const trimmed = std.mem.trim(u8, value, " \t");
	if(!std.mem.startsWith(u8, trimmed, "vec4")) return null;
	const open = std.mem.indexOfScalar(u8, trimmed, '(') orelse return null;
	const close = std.mem.lastIndexOfScalar(u8, trimmed, ')') orelse return null;
	if(close <= open) return null;
	var result: [4]f32 = undefined;
	var count: usize = 0;
	var parts = std.mem.splitScalar(u8, trimmed[open + 1 .. close], ',');
	while(parts.next()) |part| {
		if(count == 4) return null;
		result[count] = std.fmt.parseFloat(f32, std.mem.trim(u8, part, " \t")) catch return null;
		count += 1;
	}
	// `vec4(0.0)` is legal GLSL and means all four.
	if(count == 1) return .{result[0], result[0], result[0], result[0]};
	if(count != 4) return null;
	return result;
}

// MARK: custom images and buffer objects

/// The texture an `image.<name>` declaration allocates: Iris picks 1D, 2D or 3D by how many size
/// tokens follow, and the relative form is a 2D image sized as a fraction of the screen
/// (`ShaderProperties.java:510-540`).
pub const ImageShape = enum {oneD, twoD, threeD, relative};

/// One `image.<name> = <sampler> <format> <internalFormat> <pixelType> <clear> <relative> <w> <h>
/// [<d>]` line of `shaders.properties`, an Iris custom image.
///
/// `samplerName` is the name programs sample the image through, or null for Iris's `none`, which
/// declares an image only ever reached with `imageLoad`/`imageStore`. The pixel format and pixel
/// type tokens are read past rather than kept: the allocation and the clear follow the internal
/// format alone (`targets.glFormat`), which is the pairing Iris's own `InternalTextureFormat`
/// makes, and an image only ever holds what shaders wrote into it.
pub const ImageDeclaration = struct {
	name: []const u8,
	samplerName: ?[]const u8,
	format: TextureFormat,
	/// Cleared to zero before every frame (`IrisRenderingPipeline.beginLevelRendering`), as
	/// against once at allocation.
	clear: bool,
	shape: ImageShape,
	width: u32 = 0,
	height: u32 = 0,
	depth: u32 = 0,
	relativeWidth: f32 = 0,
	relativeHeight: f32 = 0,
};

/// Iris refuses a seventeenth image (`ShaderProperties.java:489`).
pub const maxImages = 16;

/// The value of a size token, resolving a `#define`d name the way `parseBufferAxis` does: the
/// properties file is preprocessed for its conditionals only, and Complementary writes
/// `COLORED_LIGHTING 64 COLORED_LIGHTING` for its voxel volume, which Iris's JCPP expands.
fn macroValue(text: []const u8, macros: []const Macro) []const u8 {
	for(macros) |macro| {
		if(std.mem.eql(u8, macro.name, text)) return macro.value;
	}
	return text;
}

fn parseImageSize(text: []const u8, macros: []const Macro) ?u32 {
	const value = std.fmt.parseInt(u32, macroValue(text, macros), 10) catch return null;
	if(value == 0) return null;
	return value;
}

/// Reads every `image.<name>` declaration out of `shaders.properties`, in name order.
///
/// Strings are copied, so the result outlives the properties it came from; release it with
/// `freeImages`. Malformed lines are logged and skipped rather than half-allocated, since a
/// program that names a skipped image is then refused with the image's name in the log.
pub fn parseImages(allocator: NeverFailingAllocator, properties: *const Properties, macros: []const Macro) []ImageDeclaration {
	var list = List(ImageDeclaration).init(allocator);
	var iterator = properties.entries.iterator();
	while(iterator.next()) |entry| {
		const key = entry.key_ptr.*;
		if(!std.mem.startsWith(u8, key, "image.")) continue;
		const name = key["image.".len..];
		if(name.len == 0) continue;

		var parts: [9][]const u8 = undefined;
		var count: usize = 0;
		var tokens = std.mem.tokenizeAny(u8, entry.value_ptr.*, " \t");
		var overflow = false;
		while(tokens.next()) |token| {
			if(count == parts.len) {
				overflow = true;
				break;
			}
			parts[count] = token;
			count += 1;
		}
		if(overflow or count < 7) {
			std.log.warn("irisbridge: {s} has {s} tokens where Iris expects 7 to 9; skipped", .{key, if(overflow) "too many" else "too few"});
			continue;
		}
		if(list.items.len >= maxImages) {
			std.log.warn("irisbridge: {s} is a seventeenth custom image, which Iris refuses; skipped", .{key});
			continue;
		}

		// Iris maps a plain `RGBA` to `RGBA8` for images (`ProgramImages.java:59-62`).
		const format = if(std.ascii.eqlIgnoreCase(parts[2], "RGBA")) TextureFormat.rgba8 else TextureFormat.parse(parts[2]) orelse {
			std.log.warn("irisbridge: {s} names an unrecognised internal format '{s}'; skipped", .{key, parts[2]});
			continue;
		};
		var declaration = ImageDeclaration{
			.name = allocator.dupe(u8, name),
			.samplerName = if(std.mem.eql(u8, parts[0], "none")) null else allocator.dupe(u8, parts[0]),
			.format = format,
			.clear = std.ascii.eqlIgnoreCase(parts[4], "true"),
			.shape = .twoD,
		};
		var usable = true;
		if(std.ascii.eqlIgnoreCase(parts[5], "true")) {
			declaration.shape = .relative;
			if(count < 8) {
				usable = false;
			} else {
				declaration.relativeWidth = std.fmt.parseFloat(f32, macroValue(parts[6], macros)) catch 0;
				declaration.relativeHeight = std.fmt.parseFloat(f32, macroValue(parts[7], macros)) catch 0;
				if(!(declaration.relativeWidth > 0) or !(declaration.relativeHeight > 0)) usable = false;
			}
		} else {
			declaration.shape = switch(count) {
				7 => .oneD,
				8 => .twoD,
				else => .threeD,
			};
			declaration.width = parseImageSize(parts[6], macros) orelse 0;
			if(count >= 8) declaration.height = parseImageSize(parts[7], macros) orelse 0;
			if(count >= 9) declaration.depth = parseImageSize(parts[8], macros) orelse 0;
			usable = declaration.width != 0 and (count < 8 or declaration.height != 0) and (count < 9 or declaration.depth != 0);
		}
		if(!usable) {
			std.log.warn("irisbridge: {s} has unreadable dimensions; skipped", .{key});
			allocator.free(declaration.name);
			if(declaration.samplerName) |sampler| allocator.free(sampler);
			continue;
		}
		list.append(declaration);
	}
	// Hash order is not a stable order, and the sampler units and log lines follow the index.
	std.mem.sort(ImageDeclaration, list.items, {}, imageLessThan);
	return list.toOwnedSlice();
}

fn imageLessThan(_: void, a: ImageDeclaration, b: ImageDeclaration) bool {
	return std.mem.order(u8, a.name, b.name) == .lt;
}

pub fn freeImages(allocator: NeverFailingAllocator, declarations: []ImageDeclaration) void {
	for(declarations) |declaration| {
		allocator.free(declaration.name);
		if(declaration.samplerName) |sampler| allocator.free(sampler);
	}
	if(declarations.len != 0) allocator.free(declarations);
}

/// One `bufferObject.N` line: a shader storage buffer of `size` bytes, or, in the four-token
/// form, `size` bytes per texel of a screen-relative area (`ShaderProperties.java:362-414`).
pub const BufferObject = struct {
	size: u64,
	relative: bool = false,
	scaleX: f32 = 0,
	scaleY: f32 = 0,
};

/// Iris refuses an index above 8: "SSBO's cannot use buffer numbers higher than 8, they're
/// reserved!"
pub const maxBufferObjects = 9;

/// Reads every `bufferObject.N` declaration, by index.
///
/// A size under 1 is Iris's way of switching a buffer off, and is left null here as there.
pub fn parseBufferObjects(properties: *const Properties) [maxBufferObjects]?BufferObject {
	var result: [maxBufferObjects]?BufferObject = @splat(null);
	var iterator = properties.entries.iterator();
	while(iterator.next()) |entry| {
		const key = entry.key_ptr.*;
		if(!std.mem.startsWith(u8, key, "bufferObject.")) continue;
		const index = std.fmt.parseInt(usize, key["bufferObject.".len..], 10) catch {
			std.log.warn("irisbridge: {s} is not a buffer index; skipped", .{key});
			continue;
		};
		if(index >= maxBufferObjects) {
			std.log.warn("irisbridge: {s} is above Iris's limit of bufferObject.8; skipped", .{key});
			continue;
		}
		var parts: [4][]const u8 = undefined;
		var count: usize = 0;
		var tokens = std.mem.tokenizeAny(u8, entry.value_ptr.*, " \t");
		while(tokens.next()) |token| {
			if(count == parts.len) break;
			parts[count] = token;
			count += 1;
		}
		if(count == 0) continue;
		const size = std.fmt.parseInt(u64, parts[0], 10) catch {
			std.log.warn("irisbridge: {s} has an unreadable size '{s}'; skipped", .{key, parts[0]});
			continue;
		};
		if(size < 1) continue;
		if(count == 1) {
			result[index] = .{.size = size};
			continue;
		}
		if(count != 4) {
			std.log.warn("irisbridge: {s} has {} tokens where Iris expects 1 or 4; skipped", .{key, count});
			continue;
		}
		const scaleX = std.fmt.parseFloat(f32, parts[2]) catch 0;
		const scaleY = std.fmt.parseFloat(f32, parts[3]) catch 0;
		const relative = std.ascii.eqlIgnoreCase(parts[1], "true");
		if(relative and (!(scaleX > 0) or !(scaleY > 0))) {
			std.log.warn("irisbridge: {s} has an unreadable scale; skipped", .{key});
			continue;
		}
		result[index] = .{.size = size, .relative = relative, .scaleX = scaleX, .scaleY = scaleY};
	}
	return result;
}

// MARK: compute work groups

/// The number inside `ivec3(a, b, c)` or `vec2(x, y)` at position `index`, or null.
fn constructorArgument(value: []const u8, constructor: []const u8, index: usize, argumentCount: usize) ?[]const u8 {
	const trimmed = std.mem.trim(u8, value, " \t");
	if(!std.mem.startsWith(u8, trimmed, constructor)) return null;
	const rest = std.mem.trimStart(u8, trimmed[constructor.len..], " \t");
	if(rest.len < 2 or rest[0] != '(' or rest[rest.len - 1] != ')') return null;
	var arguments = std.mem.splitScalar(u8, rest[1 .. rest.len - 1], ',');
	var seen: usize = 0;
	var wanted: ?[]const u8 = null;
	while(arguments.next()) |argument| : (seen += 1) {
		if(seen == index) wanted = std.mem.trim(u8, argument, " \t");
	}
	if(seen != argumentCount) return null;
	return wanted;
}

/// Reads `const ivec3 workGroups` and `const vec2 workGroupsRender` out of a compute source, line by
/// line and comment-blind like every other `const` directive (`ConstDirectiveParser`). The last
/// declaration of each wins, as Iris's handler overwrites on every match.
pub fn parseWorkGroups(source: []const u8) WorkGroups {
	var result = WorkGroups{};
	var lines = std.mem.splitAny(u8, source, "\r\n");
	while(lines.next()) |rawLine| {
		if(std.mem.indexOf(u8, rawLine, "workGroups") == null) continue;
		var line = std.mem.trim(u8, rawLine, " \t");
		if(!std.mem.startsWith(u8, line, "const")) continue;
		line = std.mem.trimStart(u8, line["const".len..], " \t");
		const semicolon = std.mem.indexOfScalar(u8, line, ';') orelse continue;
		line = line[0..semicolon];
		const equals = std.mem.indexOfScalar(u8, line, '=') orelse continue;
		const value = line[equals + 1 ..];
		var head = std.mem.tokenizeAny(u8, line[0..equals], " \t");
		const typeName = head.next() orelse continue;
		const name = head.next() orelse continue;
		if(head.next() != null) continue;

		if(std.mem.eql(u8, typeName, "ivec3") and std.mem.eql(u8, name, "workGroups")) {
			var groups: [3]u32 = undefined;
			var ok = true;
			for(0..3) |axis| {
				const text = constructorArgument(value, "ivec3", axis, 3) orelse {
					ok = false;
					break;
				};
				groups[axis] = std.fmt.parseInt(u32, text, 10) catch {
					ok = false;
					break;
				};
				if(groups[axis] == 0) ok = false;
			}
			if(ok) result.absolute = groups;
		} else if(std.mem.eql(u8, typeName, "vec2") and std.mem.eql(u8, name, "workGroupsRender")) {
			var scale: [2]f32 = undefined;
			var ok = true;
			for(0..2) |axis| {
				const text = constructorArgument(value, "vec2", axis, 2) orelse {
					ok = false;
					break;
				};
				scale[axis] = std.fmt.parseFloat(f32, text) catch {
					ok = false;
					break;
				};
				if(!(scale[axis] > 0)) ok = false;
			}
			if(ok) result.relative = scale;
		}
	}
	return result;
}

// MARK: program discovery

/// The programs a pack may provide, in the order the pipeline runs them.
///
/// `composite`/`deferred` come in numbered variants; the unnumbered name is slot 0, which is why
/// they are represented as a base name plus an index rather than as separate enum values.
/// Tag names are the on-disk base names, so `gbuffers_terrain` is `gbuffers_terrain.fsh`.
/// Taken from Iris's `ProgramId`/`ProgramArrayId`. Distant Horizons programs are omitted, having
/// no meaning outside that mod.
pub const ProgramKind = enum {
	// Shadow group.
	shadow,
	shadow_solid,
	shadow_cutout,
	shadow_water,
	shadow_entities,
	shadow_lightning,
	shadow_block,
	// Gbuffers group.
	gbuffers_basic,
	gbuffers_line,
	gbuffers_textured,
	gbuffers_textured_lit,
	gbuffers_skybasic,
	gbuffers_skytextured,
	gbuffers_clouds,
	gbuffers_terrain,
	gbuffers_terrain_solid,
	gbuffers_terrain_cutout,
	gbuffers_damagedblock,
	gbuffers_block,
	gbuffers_block_translucent,
	gbuffers_beaconbeam,
	gbuffers_item,
	gbuffers_entities,
	gbuffers_entities_translucent,
	gbuffers_lightning,
	gbuffers_particles,
	gbuffers_particles_translucent,
	gbuffers_entities_glowing,
	gbuffers_armor_glint,
	gbuffers_spidereyes,
	gbuffers_hand,
	gbuffers_weather,
	gbuffers_water,
	gbuffers_hand_water,
	// Numbered groups.
	setup,
	begin,
	shadowcomp,
	prepare,
	deferred,
	composite,
	// Single.
	final,

	pub fn baseName(self: ProgramKind) []const u8 {
		return @tagName(self);
	}

	/// Whether this kind has numbered variants (`composite1`, `deferred3`, ...).
	pub fn isNumbered(self: ProgramKind) bool {
		return switch(self) {
			.setup, .begin, .shadowcomp, .prepare, .deferred, .composite => true,
			else => false,
		};
	}

	/// The program to use when a pack does not supply this one.
	///
	/// Packs rely on this heavily - most provide `gbuffers_terrain` and nothing else in that
	/// family, expecting blocks, water and damaged blocks to inherit it. Without the chain those
	/// surfaces would silently render with no pack program at all.
	pub fn fallback(self: ProgramKind) ?ProgramKind {
		return switch(self) {
			.shadow_solid, .shadow_cutout, .shadow_water, .shadow_entities, .shadow_block => .shadow,
			.shadow_lightning => .shadow_entities,

			.gbuffers_line, .gbuffers_textured, .gbuffers_skybasic => .gbuffers_basic,
			.gbuffers_textured_lit, .gbuffers_skytextured, .gbuffers_clouds, .gbuffers_beaconbeam, .gbuffers_armor_glint, .gbuffers_spidereyes => .gbuffers_textured,
			.gbuffers_terrain, .gbuffers_item, .gbuffers_entities, .gbuffers_particles, .gbuffers_hand, .gbuffers_weather => .gbuffers_textured_lit,
			.gbuffers_terrain_solid, .gbuffers_terrain_cutout, .gbuffers_damagedblock, .gbuffers_block, .gbuffers_water => .gbuffers_terrain,
			.gbuffers_block_translucent => .gbuffers_block,
			.gbuffers_entities_translucent, .gbuffers_lightning, .gbuffers_entities_glowing => .gbuffers_entities,
			.gbuffers_particles_translucent => .gbuffers_particles,
			.gbuffers_hand_water => .gbuffers_hand,

			else => null,
		};
	}
};

/// How many work groups a compute program is dispatched with, from its own `const` directives.
///
/// Iris reads two (`ProgramSet.locateDirectives`, `ComputeDirectiveParser`): `const ivec3
/// workGroups = ivec3(x, y, z);` is an absolute count, and `const vec2 workGroupsRender = vec2(sx,
/// sy);` scales the render size by a fraction and divides by the program's local size. With neither,
/// `ComputeProgram.getWorkGroups` covers the render size at the local size, one group deep. The
/// absolute form wins when both are declared.
pub const WorkGroups = struct {
	absolute: ?[3]u32 = null,
	relative: ?[2]f32 = null,
};

/// One `.csh` of a program's compute chain.
///
/// Iris reads `<name>.csh` and then `<name>_a.csh` through `<name>_z.csh`, stopping at the first
/// letter that is missing (`ProgramSet.readComputeArray`), and dispatches every one in that order
/// before the program's own fullscreen draw. A chain can exist with no `.fsh` at all - Nostalgic Red
/// Voxels' `prepare4` and `deferred1` are compute only - and then the program is a compute-only
/// pass that draws nothing and flips no buffer.
pub const ComputeSource = struct {
	/// The file's base name, `composite1_a` for `composite1_a.csh`, for labels and dumps.
	name: []u8,
	/// `""` for the unsuffixed file, `_a` to `_z` otherwise. The unsuffixed compute shares the
	/// program's own `enabled`; a suffixed one is its own program to Iris's disable list, which
	/// matches by path without extension (`ShaderPack.java:259-263`), so `program.composite3.enabled
	/// = false` leaves `composite3_a.csh` running there and here.
	suffix: []const u8,
	source: []u8,
	workGroups: WorkGroups = .{},
	enabled: bool = true,

	pub fn deinit(self: *ComputeSource, allocator: NeverFailingAllocator) void {
		allocator.free(self.name);
		allocator.free(self.source);
	}
};

pub const Program = struct {
	kind: ProgramKind,
	index: u8 = 0,
	vertexSource: ?[]u8 = null,
	fragmentSource: ?[]u8 = null,
	/// The pack's own `.gsh`, when it ships one. Iris attaches it whenever present, and a pack
	/// that has one routes every varying through it, so it is not optional for that program.
	geometrySource: ?[]u8 = null,
	/// The program's compute chain, in dispatch order; empty for most programs. See `ComputeSource`.
	computes: []ComputeSource = &.{},
	drawBuffers: DrawBuffers = .{},
	/// The colortex buffers this program's fragment stage declares `<buffer>MipmapEnabled = true`
	/// for, as a bitmask; see `parseMipmapEnabled`. Read from the live view of the source like
	/// `drawBuffers`, so a declaration in a branch the pack's options switch off does not count.
	mipmappedBuffers: u16 = 0,
	/// Filled from `program.<name>.enabled` in `shaders.properties`. Covers the vertex and fragment
	/// stages and the unsuffixed compute; a suffixed compute carries its own flag.
	enabled: bool = true,

	/// Whether anything of this program runs: its draw, or any compute in its chain.
	pub fn anyEnabled(self: *const Program) bool {
		if(self.enabled and self.fragmentSource != null) return true;
		for(self.computes) |compute| {
			if(compute.suffix.len == 0) {
				if(self.enabled) return true;
			} else if(compute.enabled) return true;
		}
		return false;
	}

	/// Whether one compute of the chain runs, resolving the unsuffixed one against `enabled`.
	pub fn computeEnabled(self: *const Program, compute: *const ComputeSource) bool {
		return if(compute.suffix.len == 0) self.enabled else compute.enabled;
	}

	pub fn deinit(self: *Program, allocator: NeverFailingAllocator) void {
		if(self.vertexSource) |source| allocator.free(source);
		if(self.fragmentSource) |source| allocator.free(source);
		if(self.geometrySource) |source| allocator.free(source);
		freeComputes(allocator, self.computes);
	}
};

fn freeComputes(allocator: NeverFailingAllocator, computes: []ComputeSource) void {
	for(computes) |*compute| compute.deinit(allocator);
	if(computes.len != 0) allocator.free(computes);
}

/// Builds the `/name.fsh`-style path for a program, e.g. `composite` index 2 -> `/composite2.fsh`.
///
/// `directory` is the dimension folder a modern pack keeps its programs in (`world0` for the
/// overworld). Packs that predate that convention leave it empty and put programs at the shaders
/// root; both layouts are live in the wild, so lookup tries the folder first and falls back.
/// Note this only affects *program* lookup - an `#include "/lib/x.glsl"` inside `world0/` still
/// resolves against the shaders root, which `resolvePath` already does.
pub fn programPath(allocator: NeverFailingAllocator, kind: ProgramKind, index: u8, extension: []const u8, directory: []const u8) []u8 {
	return programPathSuffixed(allocator, kind, index, "", extension, directory);
}

/// `programPath` with a suffix between the number and the extension, for the compute chain's
/// `composite1_a.csh`.
pub fn programPathSuffixed(allocator: NeverFailingAllocator, kind: ProgramKind, index: u8, suffix: []const u8, extension: []const u8, directory: []const u8) []u8 {
	var out = List(u8).init(allocator);
	if(directory.len != 0) {
		out.append('/');
		out.appendSlice(std.mem.trim(u8, directory, "/"));
	}
	out.append('/');
	out.appendSlice(kind.baseName());
	// Slot 0 is spelled without a number, which is why `composite` and `composite0` are the same
	// program and a pack may not provide both.
	if(kind.isNumbered() and index != 0) out.print("{}", .{index});
	out.appendSlice(suffix);
	out.appendSlice(extension);
	return out.toOwnedSlice();
}

/// Highest numbered variant for `composite`/`deferred`/`prepare`/... Iris allows 100 slots, and
/// packs do reach well past 16 - Nostalgia alone ships `composite15`.
pub const maxNumberedPrograms = 100;

/// Loads every program the pack provides, resolving includes as it goes.
///
/// A program is only taken as present when it has a fragment shader; a lone `.vsh` is meaningless
/// and treating it as a program would insert an empty pass into the chain.
/// How many declaring lines the user's option overrides actually rewrote, across every program
/// source loaded since it was last reset.
///
/// Reported rather than inferred: an override naming an option the pack does not declare rewrites
/// nothing and changes nothing, which makes any experiment run through the options file
/// unfalsifiable. The caller resets this before a load and reads it afterwards.
pub var appliedOverrideCount: usize = 0;

pub fn loadPrograms(
	allocator: NeverFailingAllocator,
	provider: SourceProvider,
	settings: *Settings,
	dimensionDirectory: []const u8,
	overrides: *const options.Overrides,
	environment: *const preprocess.Defines,
	diagnostics: ?*List(u8),
) []Program {
	var programs = List(Program).init(allocator);

	inline for(@typeInfo(ProgramKind).@"enum".fields) |field| {
		const kind: ProgramKind = @enumFromInt(field.value);
		const limit: u8 = if(kind.isNumbered()) maxNumberedPrograms else 1;
		var index: u8 = 0;
		while(index < limit) : (index += 1) {
			if(loadProgram(allocator, provider, settings, kind, index, dimensionDirectory, overrides, environment, diagnostics)) |program| {
				programs.append(program);
			}
		}
	}
	return programs.toOwnedSlice();
}

/// A stage's source as the preprocessor leaves it: dead `#if` branches gone, the pack's own
/// `#define`s applied to the conditions after them, everything else - comments included - intact.
///
/// This is the text Iris reads directives from. `ShaderPack.java:286` runs a C preprocessor
/// (`JcppProcessor.glslPreprocessSource`, `KEEPCOMMENTS` on) over every program before the
/// `ProgramSource` exists, so a `DRAWBUFFERS` comment or a `const` declaration inside a branch the
/// pack's options switch off does not exist as far as Iris is concerned. The compiled source stays
/// the pack's own text, which the driver preprocesses for itself.
///
/// `environment` is Iris's: the `MC_*`/`IRIS_*` macros and the `IRIS_FEATURE_*` flags, and no
/// option values - those are the `#define` lines in the source, already rewritten by
/// `options.apply`. Cloned per stage, because `run` mutates its table with the source's own
/// definitions.
fn liveView(allocator: NeverFailingAllocator, source: []const u8, environment: *const preprocess.Defines) []u8 {
	var defines = environment.clone(allocator);
	defer defines.deinit();
	return preprocess.run(allocator, source, &defines);
}

/// Resolves a program file, preferring the dimension folder and falling back to the shaders root.
/// Returns the path that exists, or null. Caller owns the returned path.
fn findProgramFile(
	allocator: NeverFailingAllocator,
	provider: SourceProvider,
	kind: ProgramKind,
	index: u8,
	suffix: []const u8,
	extension: []const u8,
	dimensionDirectory: []const u8,
) ?[]u8 {
	if(dimensionDirectory.len != 0) {
		const scoped = programPathSuffixed(allocator, kind, index, suffix, extension, dimensionDirectory);
		if(provider.read(scoped) != null) return scoped;
		allocator.free(scoped);
	}
	const root = programPathSuffixed(allocator, kind, index, suffix, extension, "");
	if(provider.read(root) != null) return root;
	allocator.free(root);
	return null;
}

/// Which compute files Iris reads beside a program of this kind (`ProgramSet`'s constructor).
///
/// The composite-style stages and `final` take the lettered chain, and so does `shadow`, whose
/// chain runs before the shadow map is drawn. `setup` is read by the unlettered reader alone:
/// `setup.csh`, `setup1.csh` and so on, one file each, dispatched once at load and after a resize.
/// Every gbuffers program has none.
const ComputeChain = enum {none, single, lettered};

fn computeChainOf(kind: ProgramKind) ComputeChain {
	return switch(kind) {
		.setup => .single,
		.begin, .shadowcomp, .prepare, .deferred, .composite, .final, .shadow => .lettered,
		else => .none,
	};
}

/// Loads a program's `.csh` chain: the unsuffixed file, then `_a` to `_z` until one is missing.
///
/// The work-group directives come from the live view, as every other directive does: Nostalgic Red
/// Voxels declares four `workGroups` sizes under `#if VX_VOL_SIZE == N`, and Iris reads the file
/// through the same preprocessing provider as any program (`ShaderPack.java:286`).
fn loadComputeChain(
	allocator: NeverFailingAllocator,
	provider: SourceProvider,
	kind: ProgramKind,
	index: u8,
	dimensionDirectory: []const u8,
	overrides: *const options.Overrides,
	environment: *const preprocess.Defines,
	diagnostics: ?*List(u8),
) []ComputeSource {
	const chain = computeChainOf(kind);
	if(chain == .none) return &.{};

	var list = List(ComputeSource).init(allocator);
	var step: usize = 0;
	while(step <= computeSuffixes.len) : (step += 1) {
		if(step != 0 and chain == .single) break;
		const suffix: []const u8 = if(step == 0) "" else computeSuffixes[step - 1];
		const path = findProgramFile(allocator, provider, kind, index, suffix, ".csh", dimensionDirectory) orelse {
			// Iris stops at the first missing letter; a `_c.csh` with no `_b.csh` is never read.
			if(step != 0) break;
			continue;
		};
		defer allocator.free(path);

		const raw = resolveIncludes(allocator, path, provider, diagnostics) catch |err| {
			if(diagnostics) |d| d.print("{s}: {s}\n", .{path, @errorName(err)});
			if(step != 0) break;
			continue;
		};
		defer allocator.free(raw);
		const source = options.apply(allocator, raw, overrides, &appliedOverrideCount);

		const live = liveView(allocator, source, environment);
		defer allocator.free(live);

		var name = List(u8).init(allocator);
		name.appendSlice(kind.baseName());
		if(kind.isNumbered() and index != 0) name.print("{}", .{index});
		name.appendSlice(suffix);

		list.append(.{
			.name = name.toOwnedSlice(),
			.suffix = suffix,
			.source = source,
			.workGroups = parseWorkGroups(live),
		});
	}
	return list.toOwnedSlice();
}

/// `_a` to `_z`, the order Iris walks a compute chain in.
const computeSuffixes: [26][]const u8 = blk: {
	var result: [26][]const u8 = undefined;
	for(0..26) |i| {
		result[i] = &[2]u8{'_', @intCast('a' + i)};
	}
	break :blk result;
};

/// Sets each program's `enabled` from `program.<name>.enabled` in `shaders.properties`.
///
/// A separate step from `loadPrograms`, and run after it, because the properties file is read
/// through a preprocessor whose macro table holds the pack's option values - and those are only
/// known once the sources have been read. Iris has the same order: the option set first, then
/// `ShaderProperties` with it (`ShaderPack.java:164-175`). Only the literal `true`/`false` forms
/// are decided here; a condition over option names is `bridge.collectOptionDisabledPrograms`'s.
pub fn applyEnabledFlags(allocator: NeverFailingAllocator, programs: []Program, properties: *const Properties) void {
	var key = List(u8).init(allocator);
	defer key.deinit();
	for(programs) |*program| {
		key.clearRetainingCapacity();
		key.appendSlice("program.");
		key.appendSlice(program.kind.baseName());
		if(program.kind.isNumbered() and program.index != 0) key.print("{}", .{program.index});
		key.appendSlice(".enabled");
		program.enabled = properties.getBool(key.items, true);
		// A lettered compute is its own program name to Iris, `program.composite3_a.enabled`.
		for(program.computes) |*compute| {
			if(compute.suffix.len == 0) continue;
			key.clearRetainingCapacity();
			key.appendSlice("program.");
			key.appendSlice(compute.name);
			key.appendSlice(".enabled");
			compute.enabled = properties.getBool(key.items, true);
		}
	}
}

fn loadProgram(
	allocator: NeverFailingAllocator,
	provider: SourceProvider,
	settings: *Settings,
	kind: ProgramKind,
	index: u8,
	dimensionDirectory: []const u8,
	overrides: *const options.Overrides,
	environment: *const preprocess.Defines,
	diagnostics: ?*List(u8),
) ?Program {
	const computes = loadComputeChain(allocator, provider, kind, index, dimensionDirectory, overrides, environment, diagnostics);
	const fragmentPath = findProgramFile(allocator, provider, kind, index, "", ".fsh", dimensionDirectory) orelse {
		// A chain with no `.fsh` is a compute-only program: it dispatches and draws nothing.
		if(computes.len == 0) return null;
		return .{.kind = kind, .index = index, .computes = computes};
	};
	defer allocator.free(fragmentPath);

	const fragmentRaw = resolveIncludes(allocator, fragmentPath, provider, diagnostics) catch |err| {
		if(diagnostics) |d| d.print("{s}: {s}\n", .{fragmentPath, @errorName(err)});
		freeComputes(allocator, computes);
		return null;
	};
	// Applied after includes, so an option declared in a shared header is rewritten wherever it
	// actually lands rather than only in the file that happens to declare it.
	const fragment = options.apply(allocator, fragmentRaw, overrides, &appliedOverrideCount);
	allocator.free(fragmentRaw);

	const vertex: ?[]u8 = if(findProgramFile(allocator, provider, kind, index, "", ".vsh", dimensionDirectory)) |vertexPath| blk: {
		defer allocator.free(vertexPath);
		const raw = resolveIncludes(allocator, vertexPath, provider, diagnostics) catch |err| {
			if(diagnostics) |d| d.print("{s}: {s}\n", .{vertexPath, @errorName(err)});
			break :blk null;
		};
		defer allocator.free(raw);
		break :blk options.apply(allocator, raw, overrides, &appliedOverrideCount);
	} else null;

	const geometry: ?[]u8 = if(findProgramFile(allocator, provider, kind, index, "", ".gsh", dimensionDirectory)) |geometryPath| blk: {
		defer allocator.free(geometryPath);
		const raw = resolveIncludes(allocator, geometryPath, provider, diagnostics) catch |err| {
			if(diagnostics) |d| d.print("{s}: {s}\n", .{geometryPath, @errorName(err)});
			break :blk null;
		};
		defer allocator.free(raw);
		break :blk options.apply(allocator, raw, overrides, &appliedOverrideCount);
	} else null;

	// Every directive comes from the live view, never from the raw text - see `liveView`.
	// Complementary's `composite4` is the case that made the difference visible: `DRAWBUFFERS:3`
	// for its bloom tiles, then `DRAWBUFFERS:30` under `#if MOTION_BLUR_EFFECT == 1`, an option
	// that is off by default. Read from the raw text with last-wins, colortex0 was attached to an
	// output the shader never assigns, and the tiles it was building landed in the scene buffer as
	// well - the blurred frame with a pyramid of shrinking scene copies in one corner, in every
	// Complementary screenshot of 2026-09-04.
	const liveFragment = liveView(allocator, fragment, environment);
	defer allocator.free(liveFragment);
	parseSettings(allocator, liveFragment, settings);
	if(vertex) |source| {
		const live = liveView(allocator, source, environment);
		defer allocator.free(live);
		parseSettings(allocator, live, settings);
	}
	if(geometry) |source| {
		const live = liveView(allocator, source, environment);
		defer allocator.free(live);
		parseSettings(allocator, live, settings);
	}

	// A directive the raw text has and the live view lacks means a condition this preprocessor
	// could not evaluate took every branch away; the raw text's answer is then the previous
	// behaviour and the better guess, and the log says it happened.
	const drawBuffers = parseDrawBuffers(allocator, liveFragment) orelse blk: {
		const raw = parseDrawBuffers(allocator, fragment);
		if(raw != null) {
			if(diagnostics) |d| d.print("{s}: no DRAWBUFFERS directive survives preprocessing; taking the raw text's\n", .{fragmentPath});
		}
		break :blk raw orelse DrawBuffers{.targets = @splat(0), .count = 1};
	};

	return .{
		.kind = kind,
		.index = index,
		.vertexSource = vertex,
		.fragmentSource = fragment,
		.geometrySource = geometry,
		.computes = computes,
		.drawBuffers = drawBuffers,
		.mipmappedBuffers = parseMipmapEnabled(liveFragment),
	};
}

// MARK: directory source

/// Serves a shaderpack from an extracted directory.
///
/// Reads are cached and owned by an arena, because `SourceProvider.read` hands back a borrowed
/// slice and the loader reads the same include many times across programs - Nostalgia pulls
/// `lib/settings.glsl` into nearly every one of its ~60 programs.
pub const DirectoryProvider = struct {
	root: std.Io.Dir,
	io: std.Io,
	arena: std.heap.ArenaAllocator,
	cache: std.StringHashMapUnmanaged(?[]const u8) = .empty,

	pub fn init(allocator: NeverFailingAllocator, io: std.Io, path: []const u8) !DirectoryProvider {
		return .{
			.root = try std.Io.Dir.cwd().openDir(io, path, .{}),
			.io = io,
			.arena = std.heap.ArenaAllocator.init(allocator.allocator),
		};
	}

	pub fn deinit(self: *DirectoryProvider) void {
		self.cache.deinit(self.arena.allocator());
		self.arena.deinit();
		self.root.close(self.io);
	}

	fn readImpl(ptr: *anyopaque, path: []const u8) ?[]const u8 {
		const self: *DirectoryProvider = @ptrCast(@alignCast(ptr));
		// A cached miss is stored as null, so `get` returning a present-but-null entry means
		// "already looked, not there" and must not trigger a second syscall.
		if(self.cache.get(path)) |cached| return cached;

		const arena = self.arena.allocator();
		// Paths arrive shaders-root-absolute; strip the leading slash to make them relative.
		const relative = std.mem.trimStart(u8, path, "/");
		const contents: ?[]const u8 = self.root.readFileAlloc(self.io, relative, arena, .unlimited) catch null;
		const key = arena.dupe(u8, path) catch unreachable;
		self.cache.put(arena, key, contents) catch unreachable;
		return contents;
	}

	pub fn provider(self: *DirectoryProvider) SourceProvider {
		return .{.ptr = self, .readFn = &readImpl};
	}
};

// MARK: per-program directives

/// Iris's shadow colour buffer count, `PackShadowDirectives.MAX_SHADOW_COLOR_BUFFERS_IRIS`. OptiFine
/// had two; `HIGHER_SHADOWCOLOR` is the feature flag for the other six, which Rethinking Voxels
/// reads for its interactive water (`shadowcolor2` and `3` behind `WATER_STYLE >= 2`).
pub const shadowColorCount = 8;

/// Which of the eight shadow colour buffers the pack touches at all: every stage source scanned
/// for `shadowcolorN` and `shadowcolorimgN`, plus what the shadow-side programs' DRAWBUFFERS name.
/// `ShadowRenderTargets.getOrCreate` allocates each on first use, and the bridge does the same,
/// because six more main-and-alt pairs at the map's resolution are 200 MB for a pack that reads
/// two. The first two are always on; every shadow program writes at least `shadowcolor0`.
pub fn shadowColorUsage(programs: []const Program) [shadowColorCount]bool {
	var used: [shadowColorCount]bool = @splat(false);
	used[0] = true;
	used[1] = true;
	for(programs) |*program| {
		if(program.kind == .shadow or program.kind == .shadowcomp) {
			for(program.drawBuffers.slice()) |target| {
				if(target < shadowColorCount) used[target] = true;
			}
		}
		for([_]?[]const u8{program.fragmentSource, program.vertexSource, program.geometrySource}) |maybe| {
			markShadowColorMentions(maybe orelse continue, &used);
		}
		for(program.computes) |*compute| markShadowColorMentions(compute.source, &used);
	}
	return used;
}

fn markShadowColorMentions(source: []const u8, used: *[shadowColorCount]bool) void {
	var rest = source;
	while(std.mem.indexOf(u8, rest, "shadowcolor")) |at| {
		var after = rest[at + "shadowcolor".len ..];
		if(std.mem.startsWith(u8, after, "img")) after = after["img".len..];
		if(after.len != 0 and std.ascii.isDigit(after[0]) and (after.len == 1 or !std.ascii.isDigit(after[1]))) {
			const index = after[0] - '0';
			if(index < shadowColorCount) used[index] = true;
		}
		rest = after;
	}
}

/// An `alphaTest.<program>` override (`ShaderProperties.java:255-290`): the test Iris injects in
/// place of the one the program's `ShaderKey` carries, and the value its `alphaTestRef` uniform
/// reads (`IrisInternalUniforms.java:38`, the current program's reference). BSL adds a test at
/// 0.001 to its water, which carries none by default; Bliss switches its water's off and its
/// terrain's on at 0.1. Every such line was ignored until 2026-09-12.
pub const AlphaTest = struct {
	function: glsl.AlphaTestFunction,
	reference: f32,
};

/// Reads one `alphaTest.<program>` value. `off` and `false` are `AlphaTest.ALWAYS`, no test at
/// reference 0; otherwise a function name and a reference. What Iris logs as an error resolves to
/// null here, and the program keeps its default.
pub fn parseAlphaTest(value: []const u8) ?AlphaTest {
	const trimmed = std.mem.trim(u8, value, " \t\r");
	if(std.ascii.eqlIgnoreCase(trimmed, "off") or std.ascii.eqlIgnoreCase(trimmed, "false")) {
		return .{.function = .always, .reference = 0};
	}
	var parts = std.mem.tokenizeAny(u8, trimmed, " \t");
	const functionName = parts.next() orelse return null;
	const referenceText = parts.next() orelse return null;
	const function = glsl.AlphaTestFunction.parse(functionName) orelse return null;
	const reference = std.fmt.parseFloat(f32, referenceText) catch return null;
	return .{.function = function, .reference = reference};
}

/// The `alphaTest.<name>` override for the program spelled `name`, if the pack declared one.
pub fn alphaTestOverride(properties: *const Properties, name: []const u8) ?AlphaTest {
	var key: [96]u8 = undefined;
	const text = properties.get(std.fmt.bufPrint(&key, "alphaTest.{s}", .{name}) catch return null) orelse return null;
	return parseAlphaTest(text);
}

/// A `scale.<program>` viewport override (`ShaderProperties.java:225-242`, `ViewportData`): the
/// pass draws into `scale` of each axis of its target, starting `x` and `y` of the way across.
/// Iris applies it to the composite-style passes (`CompositeRenderer.java:263-267`); a pack uses
/// it to run a blur or a light-shaft pass at a fraction of the screen.
pub const ViewportScale = struct {
	scale: f32 = 1,
	x: f32 = 0,
	y: f32 = 0,
};

/// Reads one `scale.<program>` value: a scale alone, or a scale and two offsets.
pub fn parseScale(value: []const u8) ?ViewportScale {
	var parts = std.mem.tokenizeAny(u8, std.mem.trim(u8, value, " \t\r"), " \t");
	const scale = std.fmt.parseFloat(f32, parts.next() orelse return null) catch return null;
	const xText = parts.next() orelse return .{.scale = scale};
	const yText = parts.next() orelse return null;
	const x = std.fmt.parseFloat(f32, xText) catch return null;
	const y = std.fmt.parseFloat(f32, yText) catch return null;
	return .{.scale = scale, .x = x, .y = y};
}

/// The `scale.<name>` override for the program spelled `name`, if the pack declared one.
pub fn scaleOverride(properties: *const Properties, name: []const u8) ?ViewportScale {
	var key: [96]u8 = undefined;
	const text = properties.get(std.fmt.bufPrint(&key, "scale.{s}", .{name}) catch return null) orelse return null;
	return parseScale(text);
}

/// The name a pack writes for a program in its per-program directives: the base name, with the
/// index appended for a numbered program past the first - `composite`, `composite1`,
/// `gbuffers_water`. `program.<name>.enabled`, `blend.<name>`, `alphaTest.<name>` and
/// `scale.<name>` all key on it.
pub fn programName(program: *const Program, buffer: []u8) []const u8 {
	const base = program.kind.baseName();
	if(!program.kind.isNumbered() or program.index == 0) return base;
	return std.fmt.bufPrint(buffer, "{s}{}", .{base, program.index}) catch base;
}

/// The program a pack supplies for `kind`, or the first of its fallbacks it does supply:
/// `ProgramFallbackResolver.resolveNullable` over the `ProgramId` chain, so a pack that ships
/// `gbuffers_terrain` and no `gbuffers_water` draws water with terrain's program, as Iris does,
/// and one that ships only `gbuffers_textured_lit` has a terrain program at all. A program the
/// pack switched off through `program.<name>.enabled` counts as absent, which is what Iris's own
/// "the fallback program will be used instead" means by disabling one.
pub fn findProgram(programs: []Program, kind: ProgramKind) ?*Program {
	var wanted: ?ProgramKind = kind;
	while(wanted) |current| : (wanted = current.fallback()) {
		for(programs) |*program| {
			if(program.kind == current and program.enabled and program.fragmentSource != null) return program;
		}
	}
	return null;
}

// MARK: tests

const testing = std.testing;
const testingAllocator = main.heap.testingAllocator;

/// An in-memory pack, so the loader can be exercised without a filesystem.
const FakePack = struct {
	files: std.StringHashMapUnmanaged([]const u8) = .empty,

	fn deinit(self: *FakePack) void {
		self.files.deinit(testingAllocator.allocator);
	}

	fn add(self: *FakePack, path: []const u8, contents: []const u8) void {
		self.files.put(testingAllocator.allocator, path, contents) catch unreachable;
	}

	fn readImpl(ptr: *anyopaque, path: []const u8) ?[]const u8 {
		const self: *FakePack = @ptrCast(@alignCast(ptr));
		return self.files.get(path);
	}

	fn provider(self: *FakePack) SourceProvider {
		return .{.ptr = self, .readFn = &readImpl};
	}
};

test "include paths resolve relative and absolute" {
	const cases = [_]struct {dir: []const u8, target: []const u8, expected: []const u8}{
		.{.dir = "/", .target = "common.glsl", .expected = "/common.glsl"},
		.{.dir = "/lib", .target = "util.glsl", .expected = "/lib/util.glsl"},
		.{.dir = "/lib", .target = "/other.glsl", .expected = "/other.glsl"},
		.{.dir = "/lib/deep", .target = "../up.glsl", .expected = "/lib/up.glsl"},
		.{.dir = "/lib", .target = "./here.glsl", .expected = "/lib/here.glsl"},
		.{.dir = "/lib", .target = "/a/../b.glsl", .expected = "/b.glsl"},
	};
	for(cases) |case| {
		const result = resolvePath(testingAllocator, case.dir, case.target);
		defer testingAllocator.free(result);
		try testing.expectEqualStrings(case.expected, result);
	}
}

test "includes are spliced recursively" {
	var pack = FakePack{};
	defer pack.deinit();
	pack.add("/composite.fsh", "A\n#include \"/lib/one.glsl\"\nB\n");
	pack.add("/lib/one.glsl", "ONE\n#include \"two.glsl\"\n");
	pack.add("/lib/two.glsl", "TWO\n");

	const result = try resolveIncludes(testingAllocator, "/composite.fsh", pack.provider(), null);
	defer testingAllocator.free(result);
	try testing.expectEqualStrings("A\nONE\nTWO\nB\n", result);
}

test "include cycles and missing files are reported, not hung on" {
	var pack = FakePack{};
	defer pack.deinit();
	pack.add("/a.fsh", "#include \"/b.glsl\"\n");
	pack.add("/b.glsl", "#include \"/a.fsh\"\n");
	try testing.expectError(error.Cycle, resolveIncludes(testingAllocator, "/a.fsh", pack.provider(), null));

	var missing = FakePack{};
	defer missing.deinit();
	missing.add("/a.fsh", "#include \"/nope.glsl\"\n");
	try testing.expectError(error.Missing, resolveIncludes(testingAllocator, "/a.fsh", missing.provider(), null));
}

test "shaders.properties parses comments, both separators and continuations" {
	const source =
		\\# a comment
		\\program.composite2.enabled = false
		\\blend.gbuffers_water=SRC_ALPHA ONE_MINUS_SRC_ALPHA ONE ZERO
		\\sliders = SHADOW_QUALITY \
		\\BLOOM_STRENGTH
		\\
		\\  spaced.key  =  spaced value
		\\
	;
	var properties = parseProperties(testingAllocator, source);
	defer properties.deinit();

	try testing.expectEqualStrings("false", properties.get("program.composite2.enabled").?);
	try testing.expect(!properties.getBool("program.composite2.enabled", true));
	try testing.expect(properties.getBool("program.composite1.enabled", true));
	try testing.expectEqualStrings("SRC_ALPHA ONE_MINUS_SRC_ALPHA ONE ZERO", properties.get("blend.gbuffers_water").?);
	try testing.expectEqualStrings("spaced value", properties.get("spaced.key").?);
	try testing.expectEqualStrings("SHADOW_QUALITY BLOOM_STRENGTH", properties.get("sliders").?);
	try testing.expect(properties.get("# a comment") == null);
}

test "size.buffer takes fractions of the screen, and resolves a macro value" {
	// Complementary's shape: the value is a `#define`d option name, and it expands to `0.5`, meaning
	// half the screen per axis. An integer-only parser reads neither and silently leaves the buffer
	// at full size, which puts the pack's own addressing into a quarter of it.
	var properties = parseProperties(testingAllocator,
		\\size.buffer.colortex1 = REFLECTION_RES REFLECTION_RES
		\\size.buffer.colortex4 = 256 384
		\\size.buffer.colortex5 = 0.5 720
		\\size.buffer.colortex6 = NOT_A_THING NOT_A_THING
		\\
	);
	defer properties.deinit();

	var settings = Settings{};
	applyBufferSizes(&properties, &settings, &.{.{.name = "REFLECTION_RES", .value = "0.5"}});

	// Relative on both axes, resolved against the screen only when the targets are allocated.
	try testing.expectEqual(@as(u31, 640), settings.colortexSize[1].?[0].resolve(1280));
	try testing.expectEqual(@as(u31, 360), settings.colortexSize[1].?[1].resolve(720));
	// ...and it follows a resize, which an absolute size must not.
	try testing.expectEqual(@as(u31, 960), settings.colortexSize[1].?[0].resolve(1920));

	// Absolute stays absolute.
	try testing.expectEqual(@as(u31, 256), settings.colortexSize[4].?[0].resolve(1280));
	try testing.expectEqual(@as(u31, 384), settings.colortexSize[4].?[1].resolve(720));

	// Iris decides per axis, so a mixed declaration is legal.
	try testing.expectEqual(@as(u31, 640), settings.colortexSize[5].?[0].resolve(1280));
	try testing.expectEqual(@as(u31, 720), settings.colortexSize[5].?[1].resolve(720));

	// An unresolvable name leaves the buffer at screen size rather than at zero - a zero-sized
	// attachment stops the whole framebuffer rendering.
	try testing.expect(settings.colortexSize[6] == null);
}

test "the last directive in a file wins, as Iris's parser states" {
	// Complementary's `gbuffers_terrain` shape: a narrow set up front, a wider one inside a
	// conditional, and a third output written under it. Taking the first mapped two slots and threw
	// the normals away, which lit every surface with no normal and returned black.
	//
	// Iris: `CommentDirectiveParser.findDirective` uses `lastIndexOf`, commented "since those take
	// precedence". This is the parser alone, over the text it is given; `loadProgram` gives it the
	// preprocessed view, in which a dead branch's directive is not there to win.
	const source =
		\\/* DRAWBUFFERS:06 */
		\\gl_FragData[0] = color;
		\\gl_FragData[1] = material;
		\\#ifdef GENERATED_NORMALS
		\\    /* DRAWBUFFERS:064 */
		\\    gl_FragData[2] = normal;
		\\#endif
		\\
	;
	const result = parseDrawBuffers(testingAllocator, source).?;
	try testing.expectEqualSlices(u8, &.{0, 6, 4}, result.slice());

	// A later directive naming a target this host cannot provide is skipped whole, and the last
	// *usable* one wins. Complementary's `deferred1` is exactly this: the branches using Iris custom
	// images (colortex18/19) come last in the file, and `DRAWBUFFERS:054` is the one that compiles
	// here. Truncating at the bad entry instead would yield `{0, 5}` and silently drop an output.
	const customImages =
		\\/* DRAWBUFFERS:05 */
		\\/* DRAWBUFFERS:054 */
		\\/* RENDERTARGETS: 0,5,4,19 */
		\\/* RENDERTARGETS: 0,5,19,18 */
		\\
	;
	try testing.expectEqualSlices(u8, &.{0, 5, 4}, parseDrawBuffers(testingAllocator, customImages).?.slice());

	// Both spellings, and mixed, take the same rule.
	const mixed = "/* RENDERTARGETS: 0,1 */\n/* RENDERTARGETS: 0,1,2,3 */\n";
	try testing.expectEqualSlices(u8, &.{0, 1, 2, 3}, parseDrawBuffers(testingAllocator, mixed).?.slice());

	// A single directive is unaffected, which is the case every other fixture pack exercises.
	const single = "/* DRAWBUFFERS:0231 */\nvoid main() {}\n";
	try testing.expectEqualSlices(u8, &.{0, 2, 3, 1}, parseDrawBuffers(testingAllocator, single).?.slice());
}

test "DRAWBUFFERS and RENDERTARGETS both parse" {
	{
		const result = parseDrawBuffers(testingAllocator, "/* DRAWBUFFERS:0231 */\nvoid main() {}").?;
		try testing.expectEqualSlices(u8, &.{0, 2, 3, 1}, result.slice());
	}
	{
		// Hex digits address colortex10-15.
		const result = parseDrawBuffers(testingAllocator, "/* DRAWBUFFERS:af */\n").?;
		try testing.expectEqualSlices(u8, &.{10, 15}, result.slice());
	}
	{
		const result = parseDrawBuffers(testingAllocator, "/* RENDERTARGETS: 0,2,13 */\n").?;
		try testing.expectEqualSlices(u8, &.{0, 2, 13}, result.slice());
	}
	{
		// The word appearing in ordinary code must not be mistaken for the directive.
		try testing.expect(parseDrawBuffers(testingAllocator, "int DRAWBUFFERS = 3;\n") == null);
		try testing.expect(parseDrawBuffers(testingAllocator, "void main() {}\n") == null);
	}
}

test "const settings are read out of shader source" {
	const source =
		\\const int colortex0Format = RGBA16F;
		\\const int colortex5Format = R11F_G11F_B10F;
		\\const bool colortex5Clear = false;
		\\const int shadowMapResolution = 2048;
		\\const float shadowDistance = 120.0;
		\\const float sunPathRotation = -40.0;
		\\const int somethingThePackInvented = 7;
		\\
	;
	var settings = Settings{};
	parseSettings(testingAllocator, source, &settings);

	try testing.expectEqual(TextureFormat.rgba16f, settings.colortexFormat[0]);
	try testing.expectEqual(TextureFormat.r11f_g11f_b10f, settings.colortexFormat[5]);
	try testing.expectEqual(false, settings.colortexClear[5]);
	try testing.expectEqual(true, settings.colortexClear[0]);
	try testing.expectEqual(@as(u32, 2048), settings.shadowMapResolution);
	try testing.expectEqual(@as(f32, 120.0), settings.shadowDistance);
	try testing.expectEqual(@as(f32, -40.0), settings.sunPathRotation);
	// Untouched defaults stay put.
	try testing.expectEqual(TextureFormat.rgba8, settings.colortexFormat[1]);
}

test "clear colours are read as Kappa and photon declare them" {
	const source =
		\\const vec4 colortex15ClearColor = vec4(0.0, 1.0, 0.0, 0.0);
		\\const vec4 colortex3ClearColor = vec4(0.5);
		\\const vec4 colortex4ClearColor = vec3(1.0, 1.0, 1.0);
		\\const bool colortex15Clear = false;
		\\
	;
	var settings = Settings{};
	parseSettings(testingAllocator, source, &settings);

	try testing.expectEqual([4]f32{0, 1, 0, 0}, settings.colortexClearColor[15].?);
	try testing.expectEqual([4]f32{0.5, 0.5, 0.5, 0.5}, settings.colortexClearColor[3].?);
	// A malformed value keeps the slot's default rather than half a colour.
	try testing.expect(settings.colortexClearColor[4] == null);
	try testing.expect(settings.colortexClearColor[0] == null);
	// `ClearColor` must not be mistaken for `Clear`, nor the reverse.
	try testing.expectEqual(false, settings.colortexClear[15]);
	try testing.expectEqual(true, settings.colortexClear[3]);
}

test "the shadow camera's constants are read as Kappa, photon and Bliss declare them" {
	// Kappa's `lib/shadowconst.glsl`, photon's `settings.glsl` and `include/buffers.glsl`, and
	// Bliss's Distant Horizons block, which asks Iris for its render-distance planes with -1.
	const source =
		\\const float shadowIntervalSize  = 2.0;
		\\const float shadowNearPlane = -1.0;
		\\const float shadowFarPlane = -1.0;
		\\const vec4 shadowcolor0ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
		\\const bool shadowcolor1Clear = false;
		\\
	;
	var settings = Settings{};
	parseSettings(testingAllocator, source, &settings);

	try testing.expectEqual(@as(f32, 2.0), settings.shadowIntervalSize);
	try testing.expectEqual(@as(f32, -1.0), settings.shadowNearPlane);
	try testing.expectEqual(@as(f32, -1.0), settings.shadowFarPlane);
	try testing.expectEqual([4]f32{0, 0, 0, 0}, settings.shadowcolorClearColor[0].?);
	try testing.expect(settings.shadowcolorClearColor[1] == null);
	// `ClearColor` on shadowcolor0 leaves its `Clear` flag alone, and the reverse.
	try testing.expectEqual(true, settings.shadowcolorClear[0]);
	try testing.expectEqual(false, settings.shadowcolorClear[1]);

	// Untouched, a pack gets Iris's defaults: the 0.05 to 256 ortho and the 2-block snap.
	const untouched = Settings{};
	try testing.expectEqual(@as(f32, 0.05), untouched.shadowNearPlane);
	try testing.expectEqual(@as(f32, 256.0), untouched.shadowFarPlane);
	try testing.expectEqual(@as(f32, 2.0), untouched.shadowIntervalSize);
}

test "colortexNMipmapEnabled is read per program" {
	// Complementary's actual declarations: `composite4` mipmaps colortex0 for its bloom,
	// `composite6` mipmaps colortex3.
	try testing.expectEqual(@as(u16, 1 << 0), parseMipmapEnabled("const bool colortex0MipmapEnabled = true;\n"));
	try testing.expectEqual(@as(u16, 1 << 3), parseMipmapEnabled("const bool colortex3MipmapEnabled = true;\n"));
	// Indented, as it appears inside `composite3`'s `#ifdef` block.
	try testing.expectEqual(@as(u16, 1 << 0), parseMipmapEnabled("    const bool colortex0MipmapEnabled = true;\n"));
	// Several buffers at once.
	try testing.expectEqual(
		@as(u16, (1 << 1) | (1 << 7)),
		parseMipmapEnabled("const bool colortex1MipmapEnabled = true;\nconst bool colortex7MipmapEnabled = true;\n"),
	);
}

test "a mipmap directive set false does not enable the buffer" {
	// The declaration exists either way, so keying off its presence rather than its value would
	// mipmap every buffer a pack merely mentions.
	try testing.expectEqual(@as(u16, 0), parseMipmapEnabled("const bool colortex0MipmapEnabled = false;\n"));
	// And a later `false` turns an earlier `true` back off, as Iris's directive handler does.
	try testing.expectEqual(
		@as(u16, 0),
		parseMipmapEnabled("const bool colortex0MipmapEnabled = true;\nconst bool colortex0MipmapEnabled = false;\n"),
	);
}

test "legacy OptiFine buffer names map to their colortex slots" {
	// `LEGACY_RENDER_TARGETS` in Iris: gcolor, gdepth, gnormal, composite, gaux1-4 are colortex0-7.
	try testing.expectEqual(@as(u16, 1 << 0), parseMipmapEnabled("const bool gcolorMipmapEnabled = true;\n"));
	try testing.expectEqual(@as(u16, 1 << 3), parseMipmapEnabled("const bool compositeMipmapEnabled = true;\n"));
	try testing.expectEqual(@as(u16, 1 << 7), parseMipmapEnabled("const bool gaux4MipmapEnabled = true;\n"));
}

test "unrelated declarations do not enable mipmaps" {
	// The scan must not fire on the pack's own constants, on a different directive family, or on a
	// buffer index that does not exist.
	try testing.expectEqual(@as(u16, 0), parseMipmapEnabled("const bool colortex0Clear = false;\n"));
	try testing.expectEqual(@as(u16, 0), parseMipmapEnabled("const int colortex0Format = RGBA16F;\n"));
	try testing.expectEqual(@as(u16, 0), parseMipmapEnabled("const bool somethingMipmapEnabled = true;\n"));
	try testing.expectEqual(@as(u16, 0), parseMipmapEnabled("const bool colortex99MipmapEnabled = true;\n"));
	try testing.expectEqual(@as(u16, 0), parseMipmapEnabled("void main() {}\n"));
}

test "program paths follow the unnumbered-slot-zero rule" {
	const cases = [_]struct {kind: ProgramKind, index: u8, dir: []const u8, expected: []const u8}{
		.{.kind = .composite, .index = 0, .dir = "", .expected = "/composite.fsh"},
		.{.kind = .composite, .index = 3, .dir = "", .expected = "/composite3.fsh"},
		.{.kind = .deferred, .index = 0, .dir = "", .expected = "/deferred.fsh"},
		.{.kind = .final, .index = 0, .dir = "", .expected = "/final.fsh"},
		.{.kind = .gbuffers_terrain, .index = 0, .dir = "", .expected = "/gbuffers_terrain.fsh"},
		// Modern packs keep programs in a dimension folder.
		.{.kind = .composite, .index = 5, .dir = "world0", .expected = "/world0/composite5.fsh"},
		.{.kind = .shadow, .index = 0, .dir = "/world0/", .expected = "/world0/shadow.fsh"},
	};
	for(cases) |case| {
		const result = programPath(testingAllocator, case.kind, case.index, ".fsh", case.dir);
		defer testingAllocator.free(result);
		try testing.expectEqualStrings(case.expected, result);
	}
}

test "dimension folder programs are preferred, with fallback to the shaders root" {
	var pack = FakePack{};
	defer pack.deinit();
	// `composite` exists in both places; the dimension folder wins.
	pack.add("/composite.fsh", "void main() {int root = 1;}\n");
	pack.add("/world0/composite.fsh", "void main() {int scoped = 1;}\n");
	// `final` only exists at the root, so it must still be found.
	pack.add("/final.fsh", "void main() {}\n");

	var properties = parseProperties(testingAllocator, "");
	defer properties.deinit();
	var settings = Settings{};

	// These tests are not about option overrides; an empty set exercises the pass-through.
	var emptyOverrides = options.Overrides.init(testingAllocator);
	defer emptyOverrides.deinit();
	var environment = preprocess.Defines.init(testingAllocator);
	defer environment.deinit();
	const programs = loadPrograms(testingAllocator, pack.provider(), &settings, "world0", &emptyOverrides, &environment, null);
	defer {
		for(programs) |*program| program.deinit(testingAllocator);
		testingAllocator.free(programs);
	}

	try testing.expectEqual(@as(usize, 2), programs.len);
	try testing.expect(std.mem.indexOf(u8, programs[0].fragmentSource.?, "scoped") != null);
	try testing.expectEqual(ProgramKind.final, programs[1].kind);
}

test "alpha test overrides read Iris's grammar: off, or a function and a reference" {
	try testing.expectEqual(glsl.AlphaTestFunction.always, parseAlphaTest("off").?.function);
	try testing.expectEqual(glsl.AlphaTestFunction.always, parseAlphaTest(" false ").?.function);
	const greater = parseAlphaTest("GREATER 0.005").?;
	try testing.expectEqual(glsl.AlphaTestFunction.greater, greater.function);
	try testing.expectApproxEqAbs(@as(f32, 0.005), greater.reference, 1e-6);
	try testing.expect(parseAlphaTest("GREATER") == null);
	try testing.expect(parseAlphaTest("SOMETIMES 0.1") == null);

	var properties = parseProperties(testingAllocator, "alphaTest.gbuffers_water = false\nalphaTest.gbuffers_terrain = GREATER 0.1\n");
	defer properties.deinit();
	try testing.expectEqual(glsl.AlphaTestFunction.always, alphaTestOverride(&properties, "gbuffers_water").?.function);
	try testing.expectEqual(glsl.AlphaTestFunction.greater, alphaTestOverride(&properties, "gbuffers_terrain").?.function);
	try testing.expect(alphaTestOverride(&properties, "shadow") == null);
}

test "scale overrides take a scale alone or with two offsets, keyed by the indexed program name" {
	const half = parseScale("0.5").?;
	try testing.expectApproxEqAbs(@as(f32, 0.5), half.scale, 1e-6);
	try testing.expectApproxEqAbs(@as(f32, 0.0), half.x, 1e-6);
	const quarter = parseScale("0.25 0.5 0.75").?;
	try testing.expectApproxEqAbs(@as(f32, 0.5), quarter.x, 1e-6);
	try testing.expectApproxEqAbs(@as(f32, 0.75), quarter.y, 1e-6);
	try testing.expect(parseScale("0.5 0.25") == null);
	try testing.expect(parseScale("half") == null);

	var properties = parseProperties(testingAllocator, "scale.composite1 = 0.5\n");
	defer properties.deinit();
	var buffer: [64]u8 = undefined;
	const first = Program{.kind = .composite, .index = 1};
	try testing.expectEqualStrings("composite1", programName(&first, &buffer));
	try testing.expect(scaleOverride(&properties, programName(&first, &buffer)) != null);
	const zeroth = Program{.kind = .composite, .index = 0};
	try testing.expectEqualStrings("composite", programName(&zeroth, &buffer));
	try testing.expect(scaleOverride(&properties, programName(&zeroth, &buffer)) == null);
	const water = Program{.kind = .gbuffers_water, .index = 0};
	try testing.expectEqualStrings("gbuffers_water", programName(&water, &buffer));
}

test "a missing program resolves through Iris's fallback chain, and a disabled one counts as missing" {
	var programs = [_]Program{
		.{.kind = .gbuffers_textured_lit, .fragmentSource = @constCast("void main() {}")},
		.{.kind = .gbuffers_water, .enabled = false, .fragmentSource = @constCast("void main() {}")},
		.{.kind = .composite, .index = 2},
	};
	// No terrain and no textured: terrain lands on textured_lit, and water falls past its own
	// disabled program and the absent terrain to the same place.
	try testing.expectEqual(ProgramKind.gbuffers_textured_lit, findProgram(&programs, .gbuffers_terrain).?.kind);
	try testing.expectEqual(ProgramKind.gbuffers_textured_lit, findProgram(&programs, .gbuffers_water).?.kind);
	// Nothing in the sky chain, and `shadow` has no chain at all.
	try testing.expect(findProgram(&programs, .gbuffers_skybasic) == null);
	try testing.expect(findProgram(&programs, .shadow) == null);
	// A compute-only program is not a draw fallback.
	try testing.expect(findProgram(&programs, .composite) == null);
}

test "shadow colour usage is what the sources name plus the shadow-side draw buffers" {
	var programs = [_]Program{
		.{.kind = .composite, .fragmentSource = @constCast("uniform sampler2D shadowcolor3; uniform sampler2D shadowcolor10;")},
		.{.kind = .shadowcomp, .drawBuffers = .{.targets = [_]u8{5} ++ [_]u8{0} ** 15, .count = 1}},
	};
	const used = shadowColorUsage(&programs);
	try testing.expectEqual([shadowColorCount]bool{true, true, false, true, false, true, false, false}, used);
}

test "loading a small pack finds its programs and honours enabled flags" {
	var pack = FakePack{};
	defer pack.deinit();
	pack.add("/gbuffers_terrain.vsh", "#include \"/lib/shared.glsl\"\nvoid main() {}\n");
	pack.add("/gbuffers_terrain.fsh", "/* DRAWBUFFERS:01 */\nvoid main() {}\n");
	pack.add("/lib/shared.glsl", "const int shadowMapResolution = 4096;\n");
	pack.add("/composite.fsh", "void main() {}\n");
	pack.add("/composite2.fsh", "void main() {}\n");
	pack.add("/final.fsh", "void main() {}\n");
	// A stray vertex shader with no fragment partner is not a program.
	pack.add("/composite7.vsh", "void main() {}\n");

	var properties = parseProperties(testingAllocator, "program.composite2.enabled = false\n");
	defer properties.deinit();
	var settings = Settings{};

	// These tests are not about option overrides; an empty set exercises the pass-through.
	var emptyOverrides = options.Overrides.init(testingAllocator);
	defer emptyOverrides.deinit();
	var environment = preprocess.Defines.init(testingAllocator);
	defer environment.deinit();
	const programs = loadPrograms(testingAllocator, pack.provider(), &settings, "", &emptyOverrides, &environment, null);
	defer {
		for(programs) |*program| program.deinit(testingAllocator);
		testingAllocator.free(programs);
	}
	applyEnabledFlags(testingAllocator, programs, &properties);

	try testing.expectEqual(@as(usize, 4), programs.len);
	try testing.expectEqual(ProgramKind.gbuffers_terrain, programs[0].kind);
	try testing.expectEqualSlices(u8, &.{0, 1}, programs[0].drawBuffers.slice());
	// The include was spliced before settings were scanned, so the nested const took effect.
	try testing.expectEqual(@as(u32, 4096), settings.shadowMapResolution);

	var sawDisabledComposite2 = false;
	for(programs) |program| {
		if(program.kind == .composite and program.index == 2) {
			sawDisabledComposite2 = true;
			try testing.expect(!program.enabled);
		}
		if(program.kind == .composite and program.index == 0) try testing.expect(program.enabled);
	}
	try testing.expect(sawDisabledComposite2);
}

test "directives are read from the live branch, as Iris reads them after preprocessing" {
	// Complementary's composite4, reduced: the bloom pass draws colortex3, and colortex0 as well
	// only when motion blur is on. Read from the raw text, last-wins attached colortex0 to an
	// output the shader never writes. The `const` declarations follow the same rule, and the
	// user's override of the option has to move the answer, since it rewrites the very `#define`
	// the condition reads.
	const composite4 =
		\\#define FRAGMENT_SHADER
		\\#define MOTION_BLUR_EFFECT -1 //[-1 1]
		\\#define BLOOM_QUALITY 2 //[1 2 3]
		\\const bool colortex0MipmapEnabled = true;
		\\#if BLOOM_QUALITY > 2
		\\const bool colortex5MipmapEnabled = true;
		\\const int noiseTextureResolution = 512;
		\\#else
		\\const int noiseTextureResolution = 128;
		\\#endif
		\\#ifdef FRAGMENT_SHADER
		\\void main() {
		\\    /* DRAWBUFFERS:3 */
		\\    gl_FragData[0] = vec4(1.0);
		\\    #if MOTION_BLUR_EFFECT == 1
		\\        /* DRAWBUFFERS:30 */
		\\        gl_FragData[1] = vec4(0.0);
		\\    #endif
		\\}
		\\#endif
		\\
	;
	var environment = preprocess.Defines.init(testingAllocator);
	defer environment.deinit();
	environment.putMacroString("MC_VERSION 12100");

	{
		var pack = FakePack{};
		defer pack.deinit();
		pack.add("/composite4.fsh", composite4);
		var properties = parseProperties(testingAllocator, "");
		defer properties.deinit();
		var settings = Settings{};
		var noOverrides = options.Overrides.init(testingAllocator);
		defer noOverrides.deinit();
		const programs = loadPrograms(testingAllocator, pack.provider(), &settings, "", &noOverrides, &environment, null);
		defer {
			for(programs) |*program| program.deinit(testingAllocator);
			testingAllocator.free(programs);
		}
		try testing.expectEqual(@as(usize, 1), programs.len);
		try testing.expectEqualSlices(u8, &.{3}, programs[0].drawBuffers.slice());
		try testing.expectEqual(@as(u16, 1 << 0), programs[0].mipmappedBuffers);
		try testing.expectEqual(@as(u32, 128), settings.noiseTextureResolution);
		// The compiled source is still the pack's own text, dead branches and all.
		try testing.expect(std.mem.indexOf(u8, programs[0].fragmentSource.?, "DRAWBUFFERS:30") != null);
	}
	{
		var pack = FakePack{};
		defer pack.deinit();
		pack.add("/composite4.fsh", composite4);
		var properties = parseProperties(testingAllocator, "");
		defer properties.deinit();
		var settings = Settings{};
		var overrides = options.Overrides.init(testingAllocator);
		defer overrides.deinit();
		overrides.put("MOTION_BLUR_EFFECT", "1");
		overrides.put("BLOOM_QUALITY", "3");
		const programs = loadPrograms(testingAllocator, pack.provider(), &settings, "", &overrides, &environment, null);
		defer {
			for(programs) |*program| program.deinit(testingAllocator);
			testingAllocator.free(programs);
		}
		try testing.expectEqualSlices(u8, &.{3, 0}, programs[0].drawBuffers.slice());
		try testing.expectEqual(@as(u16, (1 << 0) | (1 << 5)), programs[0].mipmappedBuffers);
		try testing.expectEqual(@as(u32, 512), settings.noiseTextureResolution);
	}
}

test "a directive behind a condition this preprocessor cannot read falls back to the raw text" {
	// A function-like macro in a `#if` is beyond the evaluator, so the branch reads as dead and
	// the live view has no directive at all. The raw text's answer is the previous behaviour and
	// better than declaring a single colortex0 the pack never asked for.
	const source =
		\\#define IS_ON(x) ((x) > 0)
		\\#define FEATURE 1
		\\void main() {
		\\    #if IS_ON(FEATURE)
		\\        /* DRAWBUFFERS:12 */
		\\    #endif
		\\}
		\\
	;
	var environment = preprocess.Defines.init(testingAllocator);
	defer environment.deinit();
	var pack = FakePack{};
	defer pack.deinit();
	pack.add("/composite.fsh", source);
	var properties = parseProperties(testingAllocator, "");
	defer properties.deinit();
	var settings = Settings{};
	var noOverrides = options.Overrides.init(testingAllocator);
	defer noOverrides.deinit();
	var diagnostics = List(u8).init(testingAllocator);
	defer diagnostics.deinit();
	const programs = loadPrograms(testingAllocator, pack.provider(), &settings, "", &noOverrides, &environment, &diagnostics);
	defer {
		for(programs) |*program| program.deinit(testingAllocator);
		testingAllocator.free(programs);
	}
	try testing.expectEqualSlices(u8, &.{1, 2}, programs[0].drawBuffers.slice());
	try testing.expect(std.mem.indexOf(u8, diagnostics.items, "no DRAWBUFFERS directive survives preprocessing") != null);
}

test "image declarations parse in every shape the corpus uses" {
	// Bliss's 1D block table, Nostalgic Red Voxels' 2D puddle map, photon's 3D voxel volume with a
	// `none` sampler beside it, a relative image, Complementary's macro-valued volume and its plain
	// `RGBA` atlas; then the three lines that must not allocate.
	var properties = parseProperties(testingAllocator,
		\\image.imgBlockData = texBlockData RG_INTEGER RG32UI UNSIGNED_INT false false 2048
		\\image.puddle_img = puddle_sampler red_integer r8ui unsigned_int true false 128 128
		\\image.voxel_img = voxel_sampler red_integer r8ui unsigned_byte true false 64 64 64
		\\image.occupancyVolume = none RED_INTEGER R32I INT true false 96 128 96
		\\image.halfScreen = halfScreen_sampler rgba rgba16f half_float false true 0.5 0.25
		\\image.wsr_img = wsr_sampler red_integer r16ui unsigned_int true false COLORED_LIGHTING 64 COLORED_LIGHTING
		\\image.playerAtlas_img = playerAtlas_sampler RGBA RGBA unsigned_byte false false 64 64
		\\image.badFormat = s rgba NOT_A_FORMAT float false false 8 8
		\\image.badSize = s rgba rgba8 float false false 8 zero
		\\image.short = s rgba rgba8 float false
		\\
	);
	defer properties.deinit();
	const declarations = parseImages(testingAllocator, &properties, &.{.{.name = "COLORED_LIGHTING", .value = "256"}});
	defer freeImages(testingAllocator, declarations);

	try testing.expectEqual(@as(usize, 7), declarations.len);
	// Sorted by name, so the order is stable whatever the hash map did.
	try testing.expectEqualStrings("halfScreen", declarations[0].name);
	try testing.expectEqual(ImageShape.relative, declarations[0].shape);
	try testing.expectEqual(@as(f32, 0.5), declarations[0].relativeWidth);
	try testing.expectEqual(@as(f32, 0.25), declarations[0].relativeHeight);

	try testing.expectEqualStrings("imgBlockData", declarations[1].name);
	try testing.expectEqual(ImageShape.oneD, declarations[1].shape);
	try testing.expectEqual(@as(u32, 2048), declarations[1].width);
	try testing.expectEqual(TextureFormat.rg32ui, declarations[1].format);
	try testing.expectEqualStrings("texBlockData", declarations[1].samplerName.?);
	try testing.expect(!declarations[1].clear);

	try testing.expectEqualStrings("occupancyVolume", declarations[2].name);
	try testing.expect(declarations[2].samplerName == null);
	try testing.expectEqual(ImageShape.threeD, declarations[2].shape);
	try testing.expectEqual(@as(u32, 128), declarations[2].height);
	try testing.expect(declarations[2].clear);

	try testing.expectEqualStrings("playerAtlas_img", declarations[3].name);
	try testing.expectEqual(TextureFormat.rgba8, declarations[3].format);
	try testing.expectEqual(ImageShape.twoD, declarations[3].shape);

	try testing.expectEqualStrings("puddle_img", declarations[4].name);
	try testing.expectEqual(ImageShape.twoD, declarations[4].shape);
	try testing.expectEqual(@as(u32, 128), declarations[4].width);

	try testing.expectEqualStrings("voxel_img", declarations[5].name);
	try testing.expectEqual(@as(u32, 64), declarations[5].depth);

	try testing.expectEqualStrings("wsr_img", declarations[6].name);
	try testing.expectEqual(@as(u32, 256), declarations[6].width);
	try testing.expectEqual(@as(u32, 64), declarations[6].height);
	try testing.expectEqual(@as(u32, 256), declarations[6].depth);
}

test "a seventeenth image is refused, as Iris refuses it" {
	var source = List(u8).init(testingAllocator);
	defer source.deinit();
	for(0..17) |index| source.print("image.img{} = none rgba rgba8 float false false 4 4\n", .{index});
	var properties = parseProperties(testingAllocator, source.items);
	defer properties.deinit();
	const declarations = parseImages(testingAllocator, &properties, &.{});
	defer freeImages(testingAllocator, declarations);
	try testing.expectEqual(@as(usize, maxImages), declarations.len);
}

test "buffer objects parse in both of Iris's forms" {
	var properties = parseProperties(testingAllocator,
		\\bufferObject.0 = 5000192
		\\bufferObject.3 = 5376
		\\bufferObject.1 = 16 true 0.5 0.25
		\\bufferObject.2 = 0
		\\bufferObject.9 = 64
		\\bufferObject.4 = lots
		\\
	);
	defer properties.deinit();
	const buffers = parseBufferObjects(&properties);
	try testing.expectEqual(@as(u64, 5000192), buffers[0].?.size);
	try testing.expect(!buffers[0].?.relative);
	try testing.expectEqual(@as(u64, 5376), buffers[3].?.size);
	try testing.expect(buffers[1].?.relative);
	try testing.expectEqual(@as(f32, 0.5), buffers[1].?.scaleX);
	try testing.expectEqual(@as(f32, 0.25), buffers[1].?.scaleY);
	// A size under 1 switches the buffer off, an index past 8 is refused, and a non-number is skipped.
	try testing.expect(buffers[2] == null);
	try testing.expect(buffers[4] == null);
	try testing.expect(buffers[5] == null);
}

test "work groups are read from the compute source, the last declaration winning" {
	// Nostalgic Red Voxels' shape: several sizes under `#if`, of which the live view keeps one; and
	// photon's relative form.
	try testing.expectEqual([3]u32{32, 16, 32}, parseWorkGroups(
		\\const ivec3 workGroups = ivec3(12, 8, 12);
		\\    const ivec3 workGroups = ivec3(32, 16, 32);
		\\layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
		\\
	).absolute.?);
	const relative = parseWorkGroups("const vec2 workGroupsRender = vec2(0.5, 0.5);\n");
	try testing.expect(relative.absolute == null);
	try testing.expectEqual([2]f32{0.5, 0.5}, relative.relative.?);
	// The name must be exact and the constructor complete.
	try testing.expect(parseWorkGroups("const ivec3 workGroupsX = ivec3(1, 1, 1);\n").absolute == null);
	try testing.expect(parseWorkGroups("const ivec3 workGroups = ivec3(1, 1);\n").absolute == null);
	try testing.expect(parseWorkGroups("void main() {}\n").absolute == null);
}

test "a compute chain is discovered beside its program and stops at the first gap" {
	var pack = FakePack{};
	defer pack.deinit();
	pack.add("/composite1.fsh", "void main() {}\n");
	pack.add("/composite1.csh", "const ivec3 workGroups = ivec3(4, 4, 4);\nvoid main() {}\n");
	pack.add("/composite1_a.csh", "void main() {}\n");
	// `_c` without `_b` is never read, as in Iris's `readComputeArray`.
	pack.add("/composite1_c.csh", "void main() {}\n");
	// A compute-only program: no `.fsh` at all.
	pack.add("/prepare4.csh", "void main() {}\n");
	pack.add("/prepare4_a.csh", "void main() {}\n");
	// `final` takes a chain, and the unsuffixed file may be missing while the lettered one exists.
	pack.add("/final.fsh", "void main() {}\n");
	pack.add("/final_a.csh", "void main() {}\n");
	// `setup` is read unlettered only.
	pack.add("/setup.csh", "void main() {}\n");
	pack.add("/setup_a.csh", "void main() {}\n");
	pack.add("/setup1.csh", "void main() {}\n");

	var properties = parseProperties(testingAllocator, "program.composite1_a.enabled = false\n");
	defer properties.deinit();
	var settings = Settings{};
	var emptyOverrides = options.Overrides.init(testingAllocator);
	defer emptyOverrides.deinit();
	var environment = preprocess.Defines.init(testingAllocator);
	defer environment.deinit();
	const programs = loadPrograms(testingAllocator, pack.provider(), &settings, "", &emptyOverrides, &environment, null);
	defer {
		for(programs) |*program| program.deinit(testingAllocator);
		testingAllocator.free(programs);
	}
	applyEnabledFlags(testingAllocator, programs, &properties);

	var sawComposite1 = false;
	var sawPrepare4 = false;
	var sawFinal = false;
	var setupCount: usize = 0;
	for(programs) |program| {
		if(program.kind == .composite and program.index == 1) {
			sawComposite1 = true;
			try testing.expectEqual(@as(usize, 2), program.computes.len);
			try testing.expectEqualStrings("composite1", program.computes[0].name);
			try testing.expectEqualStrings("", program.computes[0].suffix);
			try testing.expectEqual([3]u32{4, 4, 4}, program.computes[0].workGroups.absolute.?);
			try testing.expectEqualStrings("composite1_a", program.computes[1].name);
			try testing.expectEqualStrings("_a", program.computes[1].suffix);
			// The lettered compute carries its own enable; the program's own still runs.
			try testing.expect(program.enabled);
			try testing.expect(!program.computes[1].enabled);
			try testing.expect(program.computeEnabled(&program.computes[0]));
			try testing.expect(!program.computeEnabled(&program.computes[1]));
			try testing.expect(program.anyEnabled());
		}
		if(program.kind == .prepare and program.index == 4) {
			sawPrepare4 = true;
			try testing.expect(program.fragmentSource == null);
			try testing.expectEqual(@as(usize, 2), program.computes.len);
			try testing.expectEqual(@as(u8, 0), program.drawBuffers.count);
		}
		if(program.kind == .final) {
			sawFinal = true;
			try testing.expectEqual(@as(usize, 1), program.computes.len);
			try testing.expectEqualStrings("final_a", program.computes[0].name);
		}
		if(program.kind == .setup) {
			setupCount += 1;
			try testing.expectEqual(@as(usize, 1), program.computes.len);
			try testing.expectEqualStrings("", program.computes[0].suffix);
		}
	}
	try testing.expect(sawComposite1);
	try testing.expect(sawPrepare4);
	try testing.expect(sawFinal);
	try testing.expectEqual(@as(usize, 2), setupCount);
}

test "every buffer format a pack in the corpus declares parses, integer and snorm included" {
	// R32UI is Nostalgic Red Voxels' atomic depth buffer; the SNORM pair and RGBA16I appear in
	// the other packs. Each used to parse to null and silently allocate RGBA8.
	for([_][]const u8{"R32UI", "RGBA8_SNORM", "RGB8_SNORM", "RGBA16I", "RGBA16F", "R11F_G11F_B10F", "rgba8"}) |name| {
		try std.testing.expect(TextureFormat.parse(name) != null);
	}
	try std.testing.expectEqual(TextureFormat.r32ui, TextureFormat.parse("R32UI").?);
	try std.testing.expectEqual(@as(?TextureFormat, null), TextureFormat.parse("NOT_A_FORMAT"));
}
