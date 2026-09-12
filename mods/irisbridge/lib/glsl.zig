//! Rewrites OptiFine/Iris shaderpack GLSL into the core-profile GLSL that Cubyz compiles.
//!
//! Shaderpacks are written against the GLSL 120 *compatibility* profile: `gl_Vertex`,
//! `gl_ModelViewMatrix`, `attribute`/`varying`, `texture2D`, `gl_FragData`. Cubyz compiles
//! `#version 460` core, where none of that exists. Iris solves this with a full ANTLR grammar
//! (glsl-transformer); this does it with a GLSL tokenizer and targeted token rewriting, which is
//! enough because every rewrite here is a rename of a known identifier rather than a structural
//! edit.
//!
//! The renames are not cosmetic. GLSL reserves the `gl_` prefix in *all* profiles, so a compat
//! built-in cannot simply be redeclared with its original name even though core does not define
//! it - `vec4 gl_Vertex;` is an error. Every compat built-in therefore becomes a `cubyz_` name
//! that the shim (and, for vertex stages, the injected prologue in `prologue.zig`) declares.
//!
//! Legacy *functions* are handled by overload rather than rename-in-place, because their core
//! replacements differ in arity and in return type: `shadow2D` returns `vec4` in compat but core
//! `texture` on a `sampler2DShadow` returns `float`. Emitting real wrapper functions keeps that
//! difference in one auditable place instead of spreading arity-aware surgery through the
//! rewriter.
//!
//! Invariant the tests pin down: tokenization round-trips exactly. Concatenating every token's
//! text reproduces the input byte for byte. That is what makes it safe to rewrite only the
//! identifier tokens we recognise and pass everything else - comments, preprocessor lines,
//! numbers we may have lexed imprecisely - through untouched.

const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const List = main.ListManaged;

/// `compute` is a pack `.csh`: no vertex inputs, no varyings, no `gl_FragData`, and the same
/// `#version`, `#extension`, `#define` and legacy-function handling as every other stage.
pub const Stage = enum {vertex, fragment, geometry, compute};

/// Iris's `AlphaTestFunction`, by the name a pack writes in `alphaTest.<program> = <function>
/// <reference>`. `always` is `AlphaTest.ALWAYS`, no test injected; `never` discards every
/// fragment; the rest are the comparison `AlphaTest.toExpression` writes.
pub const AlphaTestFunction = enum {
	never,
	less,
	equal,
	lequal,
	greater,
	notequal,
	gequal,
	always,

	/// The GLSL comparison the injected test uses, or null for the two that are not comparisons.
	pub fn expression(self: AlphaTestFunction) ?[]const u8 {
		return switch(self) {
			.less => "<",
			.equal => "==",
			.lequal => "<=",
			.greater => ">",
			.notequal => "!=",
			.gequal => ">=",
			.never, .always => null,
		};
	}

	/// `AlphaTestFunction.fromString`: the enum's own names, plus `GL_ALWAYS`, the one prefixed
	/// spelling shaders.properties documents. Case-insensitive here, a superset of Iris.
	pub fn parse(name: []const u8) ?AlphaTestFunction {
		const bare = if(std.ascii.startsWithIgnoreCase(name, "GL_")) name["GL_".len..] else name;
		inline for(std.meta.fields(AlphaTestFunction)) |field| {
			if(std.ascii.eqlIgnoreCase(bare, field.name)) return @enumFromInt(field.value);
		}
		return null;
	}
};

pub const Token = struct {
	kind: Kind,
	text: []const u8,
	/// Which preprocessor directive this token sits inside, `.none` for ordinary code.
	directive: Directive = .none,

	pub const Kind = enum {identifier, number, punctuation, whitespace, newline, comment, string};
};

/// Only the directives that change how a token should be treated are distinguished.
pub const Directive = enum {
	none,
	/// `#version` - dropped, we emit our own.
	version,
	/// `#extension` - dropped, core 460 already provides what packs ask for.
	extension,
	/// `#include` - resolved earlier, in `pack.zig`. Left alone if it survives to here.
	include,
	/// `#line` - left alone; rewriting it would scramble compiler diagnostics.
	line,
	/// `#define`, `#if`, `#ifdef`, ... - identifiers in the body still need rewriting, because a
	/// macro body can contain `texture2D` or `gl_Vertex` just as ordinary code can.
	other,
};

// MARK: tokenizer

fn isIdentifierStart(c: u8) bool {
	return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentifierChar(c: u8) bool {
	return std.ascii.isAlphanumeric(c) or c == '_';
}

/// True if a `.` following this token is a swizzle/member access rather than the start of a
/// fractional literal. Getting this wrong is harmless - misjudged numbers still round-trip,
/// they just get lexed as several tokens - but it keeps the stream tidy for callers that
/// inspect it.
fn endsValue(kind: Token.Kind, text: []const u8) bool {
	return switch(kind) {
		.identifier, .number => true,
		.punctuation => text.len == 1 and (text[0] == ')' or text[0] == ']'),
		else => false,
	};
}

pub fn tokenize(allocator: NeverFailingAllocator, source: []const u8) []Token {
	var tokens = List(Token).init(allocator);
	var i: usize = 0;
	// Whether anything other than whitespace has appeared on this logical line yet. A `#` is
	// only a directive when it is the first thing on its line.
	var lineHasContent = false;
	var directive: Directive = .none;
	var expectDirectiveName = false;
	var lastValueKind: Token.Kind = .newline;
	var lastValueText: []const u8 = "";

	while(i < source.len) {
		const start = i;
		const c = source[i];

		if(c == '\n') {
			i += 1;
			tokens.append(.{.kind = .newline, .text = source[start..i], .directive = directive});
			directive = .none;
			expectDirectiveName = false;
			lineHasContent = false;
			lastValueKind = .newline;
			continue;
		}

		// A backslash-newline splices lines: it ends neither the logical line nor the directive.
		if(c == '\\' and i + 1 < source.len and (source[i + 1] == '\n' or source[i + 1] == '\r')) {
			i += 1;
			if(i < source.len and source[i] == '\r') i += 1;
			if(i < source.len and source[i] == '\n') i += 1;
			tokens.append(.{.kind = .whitespace, .text = source[start..i], .directive = directive});
			continue;
		}

		if(c == ' ' or c == '\t' or c == '\r') {
			while(i < source.len and (source[i] == ' ' or source[i] == '\t' or source[i] == '\r')) i += 1;
			tokens.append(.{.kind = .whitespace, .text = source[start..i], .directive = directive});
			continue;
		}

		if(c == '/' and i + 1 < source.len and source[i + 1] == '/') {
			i += 2;
			while(i < source.len and source[i] != '\n') {
				// A line comment ending in a backslash continues onto the next line.
				if(source[i] == '\\' and i + 1 < source.len) {
					i += 1;
					if(i < source.len and source[i] == '\r') i += 1;
					if(i < source.len and source[i] == '\n') i += 1;
					continue;
				}
				i += 1;
			}
			tokens.append(.{.kind = .comment, .text = source[start..i], .directive = directive});
			lineHasContent = true;
			continue;
		}

		if(c == '/' and i + 1 < source.len and source[i + 1] == '*') {
			i += 2;
			while(i + 1 < source.len and !(source[i] == '*' and source[i + 1] == '/')) i += 1;
			i = @min(i + 2, source.len);
			tokens.append(.{.kind = .comment, .text = source[start..i], .directive = directive});
			lineHasContent = true;
			continue;
		}

		if(c == '"') {
			i += 1;
			while(i < source.len and source[i] != '"' and source[i] != '\n') {
				if(source[i] == '\\' and i + 1 < source.len) i += 1;
				i += 1;
			}
			if(i < source.len and source[i] == '"') i += 1;
			tokens.append(.{.kind = .string, .text = source[start..i], .directive = directive});
			lineHasContent = true;
			continue;
		}

		if(c == '#' and !lineHasContent) {
			i += 1;
			tokens.append(.{.kind = .punctuation, .text = source[start..i], .directive = .other});
			directive = .other;
			expectDirectiveName = true;
			lineHasContent = true;
			continue;
		}

		if(isIdentifierStart(c)) {
			while(i < source.len and isIdentifierChar(source[i])) i += 1;
			const text = source[start..i];
			if(expectDirectiveName) {
				expectDirectiveName = false;
				directive = directiveFromName(text);
				// Retroactively retag the `#` so a caller dropping a directive drops all of it.
				tokens.items[tokens.items.len - 1].directive = directive;
			}
			tokens.append(.{.kind = .identifier, .text = text, .directive = directive});
			lineHasContent = true;
			lastValueKind = .identifier;
			lastValueText = text;
			continue;
		}

		const startsNumber = std.ascii.isDigit(c) or
			(c == '.' and i + 1 < source.len and std.ascii.isDigit(source[i + 1]) and !endsValue(lastValueKind, lastValueText));
		if(startsNumber) {
			while(i < source.len and (isIdentifierChar(source[i]) or source[i] == '.')) {
				const isExponent = source[i] == 'e' or source[i] == 'E' or source[i] == 'p' or source[i] == 'P';
				i += 1;
				if(isExponent and i < source.len and (source[i] == '+' or source[i] == '-')) i += 1;
			}
			tokens.append(.{.kind = .number, .text = source[start..i], .directive = directive});
			lineHasContent = true;
			lastValueKind = .number;
			lastValueText = source[start..i];
			continue;
		}

		i += 1;
		const text = source[start..i];
		tokens.append(.{.kind = .punctuation, .text = text, .directive = directive});
		lineHasContent = true;
		lastValueKind = .punctuation;
		lastValueText = text;
	}
	return tokens.toOwnedSlice();
}

fn directiveFromName(name: []const u8) Directive {
	if(std.mem.eql(u8, name, "version")) return .version;
	if(std.mem.eql(u8, name, "extension")) return .extension;
	if(std.mem.eql(u8, name, "include")) return .include;
	if(std.mem.eql(u8, name, "line")) return .line;
	return .other;
}

// MARK: rewrite table

/// Compat built-ins that become uniforms supplied by `uniforms.zig`.
const matrixBuiltins = [_][]const u8{
	"gl_ModelViewMatrix",
	"gl_ModelViewProjectionMatrix",
	"gl_ProjectionMatrix",
	"gl_NormalMatrix",
	"gl_ModelViewMatrixInverse",
	"gl_ProjectionMatrixInverse",
	"gl_ModelViewProjectionMatrixInverse",
	"gl_TextureMatrix",
};

/// Compat vertex inputs. In a gbuffers program these are synthesised by the injected prologue
/// from Cubyz's SSBO pull; elsewhere they come from a real vertex buffer.
const vertexInputBuiltins = [_][]const u8{
	"gl_Vertex",
	"gl_Normal",
	"gl_Color",
	"gl_MultiTexCoord0",
	"gl_MultiTexCoord1",
	"gl_MultiTexCoord2",
	"gl_MultiTexCoord3",
	"gl_MultiTexCoord4",
	"gl_MultiTexCoord5",
	"gl_MultiTexCoord6",
	"gl_MultiTexCoord7",
};

/// Compat varyings, which have to be declared explicitly in core.
const varyingBuiltins = [_][]const u8{
	"gl_FrontColor",
	"gl_BackColor",
	"gl_TexCoord",
	"gl_FogFragCoord",
};

/// Legacy sampling functions. Each gets a `cubyz_`-prefixed wrapper in the shim.
const legacyTextureFunctions = [_][]const u8{
	"texture1D",
	"texture2D",
	"texture2DLod",
	"texture2DProj",
	"texture2DProjLod",
	"texture3D",
	"texture3DLod",
	"textureCube",
	"textureCubeLod",
	"shadow2D",
	"shadow2DLod",
	"shadow2DProj",
	// The rest of the set Iris's `CommonTransformer` renames. BSL and Bliss write the ARB and
	// `2D`-suffixed spellings, and the driver refuses them outright in a core profile.
	"texture2DGrad",
	"texture2DGradARB",
	"texture3DGrad",
	"texelFetch2D",
	"texelFetch3D",
	"textureSize2D",
};

fn isIn(list: []const []const u8, name: []const u8) bool {
	for(list) |entry| {
		if(std.mem.eql(u8, entry, name)) return true;
	}
	return false;
}

/// Built-ins that still exist in core and must be left alone.
fn isCoreBuiltin(name: []const u8) bool {
	const kept = [_][]const u8{
		"gl_Position", "gl_PointSize", "gl_FragDepth", "gl_FragCoord", "gl_FrontFacing",
		"gl_VertexID", "gl_InstanceID", "gl_BaseInstance", "gl_PrimitiveID", "gl_Layer",
		"gl_ClipDistance", "gl_PointCoord", "gl_in", "gl_out", "gl_InvocationID",
		"gl_WorkGroupID", "gl_LocalInvocationID", "gl_GlobalInvocationID",
		// Geometry-stage built-ins, which a pack's `.gsh` reads and core still defines.
		"gl_PrimitiveIDIn", "gl_ViewportIndex",
	};
	return isIn(&kept, name);
}

// `declaresShadowSampler` used to live here: a token scan for `sampler2DShadow <name>`, used to pick
// which GL sampler object to bind to the shadow units. It is gone rather than merely unused, because
// leaving it invites someone to reach for it again.
//
// It cannot answer the question. A pack declares the same name both ways behind a conditional -
// Complementary's `lib/uniforms.glsl` has `uniform sampler2D shadowtex0;` under `#ifdef COMPOSITE1`
// and `uniform sampler2DShadow shadowtex0;` under the `#else` - and this file deliberately does not
// evaluate conditionals, so a scan sees both and has to guess. `pipeline.resolveShadowComparison`
// asks the linked program with `glGetActiveUniform` instead, which is the driver's answer *after*
// preprocessing and therefore not a guess at all.

// MARK: analysis

/// What a single translation unit actually uses, so the shim only declares what is needed.
/// Declaring everything would compile, but it makes the generated source unreadable when a pack
/// misbehaves and someone has to read it.
pub const Usage = struct {
	matrices: std.StringHashMapUnmanaged(void) = .empty,
	vertexInputs: std.StringHashMapUnmanaged(void) = .empty,
	varyings: std.StringHashMapUnmanaged(void) = .empty,
	textureFunctions: std.StringHashMapUnmanaged(void) = .empty,
	usesFragData: bool = false,
	usesFragColor: bool = false,
	/// `ftransform()` is a compat built-in with no core equivalent. It expands to
	/// `gl_ModelViewProjectionMatrix * gl_Vertex`, so using it pulls both of those in even when
	/// the shader never names them.
	usesFtransform: bool = false,
	/// True when the pack reads `gl_Fog`, the compat fog-parameter struct. Core removed it at 140,
	/// so an equivalent has to be declared and fed from Cubyz's own fog.
	usesFog: bool = false,
	/// True when the pack declares its own variable called `texture`, as OptiFine-era packs do
	/// (`uniform sampler2D texture;`). In core that name collides with the built-in sampling
	/// function, so every mention of it has to be renamed - but only when the declaration is
	/// actually present, since packs written for Iris call core `texture()` directly.
	shadowsTextureName: bool = false,

	pub fn deinit(self: *Usage, allocator: NeverFailingAllocator) void {
		self.matrices.deinit(allocator.allocator);
		self.vertexInputs.deinit(allocator.allocator);
		self.varyings.deinit(allocator.allocator);
		self.textureFunctions.deinit(allocator.allocator);
	}
};

/// Type keywords that can introduce a variable named `texture`.
fn isSamplerOrTypeKeyword(name: []const u8) bool {
	if(std.mem.startsWith(u8, name, "sampler")) return true;
	if(std.mem.startsWith(u8, name, "isampler")) return true;
	if(std.mem.startsWith(u8, name, "usampler")) return true;
	const types = [_][]const u8{"vec2", "vec3", "vec4", "float", "int", "uint", "bool", "mat2", "mat3", "mat4"};
	return isIn(&types, name);
}

pub fn analyse(allocator: NeverFailingAllocator, tokens: []const Token) Usage {
	var usage = Usage{};
	var previousIdentifier: ?[]const u8 = null;
	for(tokens) |token| {
		if(token.directive == .version or token.directive == .extension or token.directive == .line) continue;
		if(token.kind != .identifier) {
			if(token.kind != .whitespace and token.kind != .comment and token.kind != .newline) previousIdentifier = null;
			continue;
		}
		const name = token.text;
		if(isIn(&matrixBuiltins, name)) usage.matrices.put(allocator.allocator, name, {}) catch unreachable;
		if(isIn(&vertexInputBuiltins, name)) usage.vertexInputs.put(allocator.allocator, name, {}) catch unreachable;
		if(isIn(&varyingBuiltins, name)) usage.varyings.put(allocator.allocator, name, {}) catch unreachable;
		if(isIn(&legacyTextureFunctions, name)) usage.textureFunctions.put(allocator.allocator, name, {}) catch unreachable;
		if(std.mem.eql(u8, name, "gl_Fog")) usage.usesFog = true;
		if(std.mem.eql(u8, name, "gl_FragData")) usage.usesFragData = true;
		if(std.mem.eql(u8, name, "gl_FragColor")) usage.usesFragColor = true;
		if(std.mem.eql(u8, name, "ftransform")) {
			usage.usesFtransform = true;
			usage.matrices.put(allocator.allocator, "gl_ModelViewProjectionMatrix", {}) catch unreachable;
			usage.vertexInputs.put(allocator.allocator, "gl_Vertex", {}) catch unreachable;
		}
		if(std.mem.eql(u8, name, "texture")) {
			if(previousIdentifier) |previous| {
				if(isSamplerOrTypeKeyword(previous)) usage.shadowsTextureName = true;
			}
		}
		previousIdentifier = name;
	}
	return usage;
}

// MARK: transform

pub const Options = struct {
	stage: Stage,
	/// The `#version` to emit, or null for Iris's rule: the pack's own version raised to at least
	/// 410 core (`TransformPatcher.java:145`). Programs carrying the SSBO-pull prologue pass 460,
	/// which `gl_BaseInstance` and the storage blocks need.
	///
	/// This was expected to fix Bliss's `clamp(float, float, int)`, on the theory that NVIDIA's
	/// `float64_t` overloads only appear at 460. Measured wrong: the run of 2026-09-01 15:07 shows
	/// the same four failures at 410 core. The rule is kept because it is Iris's, and 410 is what
	/// every pack author tested against; the clamp itself is handled by `markIntegerClampBounds`.
	version: ?u16 = null,
	/// How many `gl_FragData` slots to declare, from the program's DRAWBUFFERS/RENDERTARGETS
	/// directive. The mapping from slot to colortex attachment is a CPU-side `glDrawBuffers`
	/// call, not something the shader sees.
	fragDataCount: u8 = 1,
	/// Source spliced in between the shim and the pack body. For gbuffers programs this is the
	/// SSBO-pull prologue that defines `cubyz_Vertex` and friends; empty elsewhere.
	prologue: []const u8 = "",
	/// Emitted as `#define` lines ahead of the body, for `shaders.properties` options.
	defines: []const []const u8 = &.{},
	/// Renames the pack's `main` to this, so generated code can supply the real entry point.
	///
	/// Cubyz's terrain has no vertex buffer: `mc_Entity` and the rest have to be *computed* from
	/// an SSBO pull before the pack's code runs. There is no way to inject a statement at the top
	/// of someone else's `main`, so instead the pack's `main` becomes an ordinary function and the
	/// prologue's generated `main` calls the setup and then it.
	entryPointName: ?[]const u8 = null,
	/// Append Iris's alpha test after the pack's fragment `main`. Needs `entryPointName`.
	///
	/// OptiFine ran the fixed-function alpha test after every gbuffers fragment shader, and packs
	/// written for it never discard a transparent texel themselves - BSL, Nostalgia, Solas and
	/// Complementary have no alpha discard in their terrain program at all. Iris keeps them working
	/// by appending the test to `main` (`CommonTransformer.java:217-222`, the expression from
	/// `AlphaTest.toExpression`) for every non-core program that writes `gl_FragData[0]`, at the
	/// reference its `ShaderKey` carries: 0.1 for terrain cutout and the shadow pass, off for
	/// translucents. Without it here, Cubyz's grass tufts - `cubyz:cross` quads on a binary-alpha
	/// texture - drew their empty texels as opaque green, so every tuft was a solid block in every
	/// pack that did not discard on its own; the screenshots of 2026-09-04 show exactly that, and
	/// Kappa, which does discard on its own, drawing plants.
	alphaTest: bool = false,
	/// The comparison the injected test uses: `GREATER` for every `ShaderKey` default, or
	/// whatever the pack's `alphaTest.<program>` override names. `always` injects nothing
	/// whatever `alphaTest` says, and `never` discards every fragment, as `AlphaTest.toExpression`.
	alphaTestFunction: AlphaTestFunction = .greater,
	/// Attribute names whose declarations must be deleted from the pack source.
	///
	/// Cubyz's terrain has no vertex buffer, so `mc_Entity` and friends cannot be real attributes
	/// - the prologue computes them from the SSBO pull instead. The pack still declares them
	/// (`attribute vec4 mc_Entity;`), and leaving that in place would be a duplicate declaration
	/// of a name the prologue already defines.
	strippedAttributes: []const []const u8 = &.{},
	/// Per-sampler redirects: a sampling call whose first argument names one of these becomes the
	/// helper for its flavour. A list rather than one shared helper, because the targets are not
	/// interchangeable - the block texture is a genuine array lookup while `specular` is
	/// synthesised from Cubyz's emission and reflectivity arrays.
	arraySamplers: []const SamplerRedirect = &.{},
	/// Fallback for a sampling call inside the pack's *own* macro, where neither the callee nor
	/// the sampler can be named. Overloaded on sampler type so the compiler resolves it per
	/// expansion - after preprocessing, which is exactly where a token scan cannot reach.
	macroDispatch: ?MacroDispatch = null,
	/// Where the pack's shader storage blocks are moved to: `layout(std430, binding = N) buffer`
	/// becomes `binding = base + N`. Iris binds `bufferObject.N` at binding point N and packs write
	/// that number into their GLSL, but Cubyz's own chunk buffers already sit at 1, 3, 4, 6, 8, 9,
	/// 10 and 11 and a gbuffers program carries both sets at once - Complementary's
	/// `playerVerticesBuffer` is at 3, the same point as the prologue's face data. So every pack
	/// block is relocated by a constant and the buffers are bound there (`images.storageBindingBase`).
	/// Null leaves the declarations alone.
	storageBindingBase: ?u32 = null,
};

/// Index of the next token that is not whitespace, a comment, or a newline.
fn nextSignificant(tokens: []const Token, from: usize) ?usize {
	var i = from;
	while(i < tokens.len) : (i += 1) {
		switch(tokens[i].kind) {
			.whitespace, .comment, .newline => {},
			else => return i,
		}
	}
	return null;
}

/// How a sampling function interprets its arguments after the sampler and the coordinate.
///
/// `texture(s, c, x)` and `textureLod(s, c, x)` have the same argument *shape* and different
/// meanings - a bias applied to the implicitly computed level of detail, against an explicit
/// level. Redirecting both onto one helper name therefore cannot express the difference: whichever
/// body that overload happens to have wins, and the other reading is silently substituted. The
/// original redirect did exactly that, so every `textureLod` on the block texture sampled with a
/// bias instead - a wrong mip level, never an error.
///
/// `textureGrad` has a distinct shape and would not collide, but it gets its own flavour anyway so
/// that "which built-in was this" is answered in one place rather than inferred from arity.
///
/// `texelFetch` takes integer texel coordinates rather than normalised ones, so it is not merely a
/// fourth spelling of the same lookup: the helper has to add the array layer as an integer and
/// must not scale anything. Complementary and its derivatives fetch a 16x16 block of texels around
/// the tile centre to average lava's brightness, and without this flavour that call was left as
/// `texelFetch(sampler2DArray, ivec2, int)`, which has no overload and took the terrain program
/// down.
pub const Flavour = enum {plain, lod, grad, fetch};

/// Sampling functions whose call site must be redirected when they target a texture array.
const SamplingFunction = struct {name: []const u8, flavour: Flavour};

const samplingFunctions = [_]SamplingFunction{
	.{.name = "texture", .flavour = .plain},
	.{.name = "texture2D", .flavour = .plain},
	.{.name = "textureLod", .flavour = .lod},
	.{.name = "texture2DLod", .flavour = .lod},
	.{.name = "textureGrad", .flavour = .grad},
	.{.name = "texture2DGrad", .flavour = .grad},
	.{.name = "texture2DGradARB", .flavour = .grad},
	.{.name = "texelFetch", .flavour = .fetch},
	.{.name = "texelFetch2D", .flavour = .fetch},
};

fn flavourOf(name: []const u8) ?Flavour {
	for(samplingFunctions) |entry| {
		if(std.mem.eql(u8, entry.name, name)) return entry.flavour;
	}
	return null;
}

/// One sampler name and the helpers a sampling call against it is rewritten to.
///
/// Three helpers rather than one, because the flavours are not interchangeable - see `Flavour`. A
/// redirect whose target ignores its extra arguments anyway (`specular`, which synthesises a value
/// from Cubyz's material arrays) may name the same helper three times, provided that helper carries
/// an overload for each argument shape.
pub const SamplerRedirect = struct {
	/// The name as the pack spells it.
	sampler: []const u8,
	/// `texture`/`texture2D` - an optional bias.
	function: []const u8,
	/// `textureLod`/`texture2DLod` - an explicit level.
	lodFunction: []const u8,
	/// `textureGrad`/`texture2DGrad` - explicit derivatives.
	gradFunction: []const u8,
	/// `texelFetch` - integer texel coordinates and an explicit level.
	fetchFunction: []const u8,
};

fn redirectFor(redirects: []const SamplerRedirect, name: []const u8, flavour: Flavour) ?[]const u8 {
	for(redirects) |entry| {
		if(!std.mem.eql(u8, entry.sampler, name)) continue;
		return switch(flavour) {
			.plain => entry.function,
			.lod => entry.lodFunction,
			.grad => entry.gradFunction,
			.fetch => entry.fetchFunction,
		};
	}
	return null;
}

/// Helpers for a sampling call whose sampler argument is a macro parameter, and so has no
/// identity this file can resolve.
///
/// Packs commonly wrap every texture read in a function-like macro. Three of the six packs in the
/// corpus do it, under two different names and by two different authors:
///
///     Kappa, Nostalgia   #define stex(x) texture(x, uv)
///                        #define stexLod(x, lod) textureLod(x, uv, lod)
///     photon             #define read_tex(x) texture(x, uv, lod_bias)
///                        #define read_tex(x) textureGrad(x, parallax_uv, uv_gradient[0], uv_gradient[1])
///
/// The per-sampler redirect cannot handle these from either end. At the *call site* the callee is
/// `read_tex`, not a sampling function, so nothing fires - correctly, since rewriting it would
/// destroy the macro's argument list. Inside the *body* the sampler is `x`, which names no
/// particular sampler: photon invokes the same macro with `gtexture`, `normals` and `specular`.
/// And the transformer deliberately does not preprocess, so it never sees the expansion where the
/// identity would be known.
///
/// So the body is redirected to a helper that is overloaded on sampler type, and the *compiler*
/// resolves it per expansion - after preprocessing, which is precisely where the token scan cannot
/// reach. `cubyz_sampleAny(sampler2DArray, ...)` performs Cubyz's array lookup; the `sampler2D`
/// overload passes straight through to the built-in.
///
/// Overloading the built-in `texture` itself would have been simpler and does not work: the driver
/// accepts the declaration and then hides every built-in overload of that name, measured by
/// `pipeline.probeBuiltinOverloadOnce`. It would have taken all four working packs down.
///
/// The cost, stated up front: a redirect that depended on knowing *which* sampler it had cannot
/// survive this. `read_tex(specular)` resolves to the plain `sampler2D` passthrough rather than to
/// `cubyz_sampleSpecular`, so a pack reading its material maps through a macro gets the neutral 1x1
/// texture instead of the LabPBR value synthesised from Cubyz's emission and reflectivity.
/// Distinguishing them needs the type of the macro's argument, which is inference across a call
/// graph - the same wall `textureAF` sits behind under "Known limits". A pack that reads its
/// material maps directly is unaffected.
pub const MacroDispatch = struct {
	function: []const u8,
	lodFunction: []const u8,
	gradFunction: []const u8,
	fetchFunction: []const u8,

	fn forFlavour(self: MacroDispatch, flavour: Flavour) []const u8 {
		return switch(flavour) {
			.plain => self.function,
			.lod => self.lodFunction,
			.grad => self.gradFunction,
			.fetch => self.fetchFunction,
		};
	}
};

/// Whether `name` is a parameter of the function-like `#define` whose body contains token `index`.
///
/// Walks back to the start of the logical line rather than pre-collecting every macro, because the
/// question is only ever asked about a call this file has already decided it cannot resolve - a
/// handful of times per source rather than once per token. A backslash continuation lexes as
/// whitespace, not a newline, so a macro spanning several physical lines is walked correctly.
fn isMacroParameter(tokens: []const Token, index: usize, name: []const u8) bool {
	// Every token on a `#define` line carries `.other`; ordinary code carries `.none`. This is the
	// cheap gate that keeps the walk off the hot path.
	if(tokens[index].directive != .other) return false;

	var start = index;
	while(start > 0 and tokens[start - 1].kind != .newline) start -= 1;

	var i = nextSignificant(tokens, start) orelse return false;
	if(tokens[i].kind != .punctuation or !std.mem.eql(u8, tokens[i].text, "#")) return false;
	i = nextSignificant(tokens, i + 1) orelse return false;
	if(!std.mem.eql(u8, tokens[i].text, "define")) return false;
	i = nextSignificant(tokens, i + 1) orelse return false;
	if(tokens[i].kind != .identifier) return false;

	// No whitespace between the name and the `(`. That is exactly what separates a function-like
	// macro from an object-like one whose body happens to start with a parenthesis, and the
	// tokenizer emits whitespace as its own token, so the adjacency test is the whole rule.
	if(i + 1 >= tokens.len) return false;
	if(tokens[i + 1].kind != .punctuation or !std.mem.eql(u8, tokens[i + 1].text, "(")) return false;

	i += 2;
	while(i < tokens.len) : (i += 1) {
		const token = tokens[i];
		// The parameter list ends at the closing paren; a newline means the line was malformed.
		if(token.kind == .newline) return false;
		if(token.kind == .punctuation and std.mem.eql(u8, token.text, ")")) return false;
		if(token.kind == .identifier and std.mem.eql(u8, token.text, name)) return true;
	}
	return false;
}

/// Marks sampling calls whose first argument names a redirected sampler, recording which helper
/// each call site becomes.
///
/// Renaming the *sampler* is not enough on its own. Cubyz stores block textures in a
/// `sampler2DArray`, and a pack writes `texture(gtexture, coord)` with a two-component coord -
/// which has no valid overload for an array sampler, whatever the sampler is called. The call
/// itself has to change, and only when it targets the block texture: the very same program also
/// samples `lightmap` and `depthtex0`, which are ordinary 2D textures and must be left alone.
fn markArraySamplerCalls(tokens: []const Token, arraySamplers: []const SamplerRedirect, macroDispatch: ?MacroDispatch, rename: [](?[]const u8)) void {
	if(arraySamplers.len == 0) return;
	for(tokens, 0..) |token, i| {
		if(token.kind != .identifier) continue;
		const flavour = flavourOf(token.text) orelse continue;

		const openIndex = nextSignificant(tokens, i + 1) orelse continue;
		if(tokens[openIndex].kind != .punctuation or !std.mem.eql(u8, tokens[openIndex].text, "(")) continue;
		const argumentIndex = nextSignificant(tokens, openIndex + 1) orelse continue;
		if(tokens[argumentIndex].kind != .identifier) continue;
		// `texture` is on the redirect list as a sampler *variable*; an identifier followed by a
		// parenthesis in argument position is a call, not a sampler, and is left alone.
		if(nextSignificant(tokens, argumentIndex + 1)) |after| {
			if(isPunctuation(tokens[after], "(")) continue;
		}

		if(redirectFor(arraySamplers, tokens[argumentIndex].text, flavour)) |helper| {
			rename[i] = helper;
			continue;
		}
		// A sampler this file cannot name. If it is a macro's own parameter, the identity is only
		// knowable after preprocessing, so the choice is handed to overload resolution instead.
		// See `MacroDispatch`.
		const dispatch = macroDispatch orelse continue;
		if(!isMacroParameter(tokens, argumentIndex, tokens[argumentIndex].text)) continue;
		rename[i] = dispatch.forFlavour(flavour);
	}
}

/// A pack function that takes the block texture as a `sampler2D` parameter, and so needs a second
/// overload taking Cubyz's array.
///
/// Bliss's terrain reads its albedo through `texture2D_POMSwitch(sampler2D sampler, ...)`, called
/// once with the block texture and once with `normals`. Under Iris both are `sampler2D` and the
/// one function serves; here the block texture is a `sampler2DArray`, and passing it to that
/// parameter is `C1102: incompatible type for parameter #1`, which took Bliss's whole terrain
/// program down the moment its sampler started being redirected at all. Complementary's
/// `textureAF` is the same shape, recorded under "Known limits" as a wall.
///
/// It is not a wall for a function that only ever *samples* its parameter. The body's sampling
/// calls on the parameter go through the type-dispatching helpers `MacroDispatch` already exists
/// for, and the function is emitted twice: as written, and with `sampler2DArray` in place of
/// `sampler2D` for those parameters. The compiler then picks per call site, exactly as it does for
/// a macro's parameter. The overload's prototype goes on the original definition's line, so it is
/// declared before every caller without moving a line; its body goes after the pack's source, so
/// nothing the driver reports drifts.
///
/// A function whose parameter is used any other way - `textureSize`, passed to something that is
/// not a sampling call, compared - is left alone, because the array copy could not compile and a
/// dead overload that fails still fails the program. That is the honest boundary: `textureAF`
/// stays where it is.
const SamplerFunction = struct {
	/// The return-type token, where the overload's prototype is emitted.
	start: usize,
	/// The `(` and `)` of the parameter list.
	open: usize,
	close: usize,
	/// The closing `}` of a definition, or the `;` of a prototype.
	end: usize,
	isDefinition: bool,
	name: []const u8,
	/// Token indices of the `sampler2D` type words to substitute, and the parameters' names.
	typeTokens: [8]usize = undefined,
	names: [8][]const u8 = undefined,
	count: usize = 0,
	/// The preprocessor conditionals the definition sits inside, as directive lines to replay
	/// around the copy. Complementary's `textureAF` lives under `#if ANISOTROPIC_FILTER > 0`, and
	/// a copy emitted outside that block referenced globals the block never declared -
	/// `spriteBounds`, `inverseM` - and took the terrain program down in a configuration where the
	/// original was not even compiled. The copy has to be dead exactly where the original is.
	conditionals: [16]DirectiveLine = undefined,
	conditionalCount: usize = 0,
	/// How many of those open a block, which is how many `#endif`s close the copy.
	opens: usize = 0,
};

/// One `#if`-family directive line, as a token range from its `#` to the end of the line.
const DirectiveLine = struct {
	from: usize,
	to: usize,
	opens: bool,
};

/// Finds every function declaring a `sampler2D` parameter, at global scope.
fn findSamplerFunctions(allocator: NeverFailingAllocator, tokens: []const Token) []SamplerFunction {
	var found = List(SamplerFunction).init(allocator);
	var braceDepth: usize = 0;
	// The `#if`-family lines currently open, so a function can carry its own conditionals.
	var conditionals = List(DirectiveLine).init(allocator);
	defer conditionals.deinit();
	var i: usize = 0;
	while(i < tokens.len) : (i += 1) {
		const token = tokens[i];
		if(token.directive != .none) {
			if(!isPunctuation(token, "#")) continue;
			const nameIndex = nextSignificant(tokens, i + 1) orelse continue;
			if(tokens[nameIndex].kind != .identifier) continue;
			const name = tokens[nameIndex].text;
			var lineEnd = i;
			while(lineEnd < tokens.len and tokens[lineEnd].kind != .newline) lineEnd += 1;
			if(std.mem.eql(u8, name, "if") or std.mem.eql(u8, name, "ifdef") or std.mem.eql(u8, name, "ifndef")) {
				conditionals.append(.{.from = i, .to = lineEnd, .opens = true});
			} else if(std.mem.eql(u8, name, "else") or std.mem.eql(u8, name, "elif")) {
				conditionals.append(.{.from = i, .to = lineEnd, .opens = false});
			} else if(std.mem.eql(u8, name, "endif")) {
				while(conditionals.items.len != 0) {
					const popped = conditionals.pop();
					if(popped.opens) break;
				}
			}
			i = lineEnd;
			continue;
		}
		if(token.kind == .punctuation) {
			if(std.mem.eql(u8, token.text, "{")) braceDepth += 1;
			if(std.mem.eql(u8, token.text, "}") and braceDepth > 0) braceDepth -= 1;
			continue;
		}
		if(braceDepth != 0 or token.kind != .identifier) continue;
		// `<type> <name> (` at global scope is a function header; nothing else has that shape.
		const nameIndex = nextSignificant(tokens, i + 1) orelse break;
		if(tokens[nameIndex].kind != .identifier) continue;
		const open = nextSignificant(tokens, nameIndex + 1) orelse break;
		if(!isPunctuation(tokens[open], "(")) continue;

		var close = open + 1;
		var depth: usize = 0;
		while(close < tokens.len) : (close += 1) {
			if(tokens[close].kind != .punctuation) continue;
			if(isPunctuation(tokens[close], "(")) depth += 1;
			if(isPunctuation(tokens[close], ")")) {
				if(depth == 0) break;
				depth -= 1;
			}
		}
		if(close >= tokens.len) break;
		const after = nextSignificant(tokens, close + 1) orelse break;
		const isDefinition = isPunctuation(tokens[after], "{");
		if(!isDefinition and !isPunctuation(tokens[after], ";")) {
			i = close;
			continue;
		}

		var function = SamplerFunction{.start = i, .open = open, .close = close, .end = after, .isDefinition = isDefinition, .name = tokens[nameIndex].text};
		// Nested deeper than the copy can replay is not a shape in the corpus; such a function is
		// simply not overloaded.
		if(conditionals.items.len > function.conditionals.len) {
			i = close;
			continue;
		}
		for(conditionals.items, 0..) |line, index| {
			function.conditionals[index] = line;
			if(line.opens) function.opens += 1;
		}
		function.conditionalCount = conditionals.items.len;
		// Each parameter is the tokens between top-level commas; a `sampler2D` word marks one to
		// substitute, and the last identifier in it is the name.
		var parameterStart = open + 1;
		var j = open + 1;
		var parenDepth: usize = 0;
		while(j <= close) : (j += 1) {
			const t = tokens[j];
			const boundary = j == close or (parenDepth == 0 and isPunctuation(t, ","));
			if(isPunctuation(t, "(")) parenDepth += 1;
			if(isPunctuation(t, ")") and j != close) parenDepth -= 1;
			if(!boundary) continue;
			var typeToken: ?usize = null;
			var lastIdentifier: ?usize = null;
			for(parameterStart..j) |k| {
				if(tokens[k].kind != .identifier) continue;
				if(std.mem.eql(u8, tokens[k].text, "sampler2D")) typeToken = k;
				lastIdentifier = k;
			}
			if(typeToken != null and lastIdentifier != null and lastIdentifier.? != typeToken.? and function.count < function.typeTokens.len) {
				function.typeTokens[function.count] = typeToken.?;
				function.names[function.count] = tokens[lastIdentifier.?].text;
				function.count += 1;
			}
			parameterStart = j + 1;
		}

		if(isDefinition) {
			var end = after + 1;
			var bodyDepth: usize = 1;
			while(end < tokens.len) : (end += 1) {
				if(isPunctuation(tokens[end], "{")) bodyDepth += 1;
				if(isPunctuation(tokens[end], "}")) {
					bodyDepth -= 1;
					if(bodyDepth == 0) break;
				}
			}
			if(end >= tokens.len) break;
			function.end = end;
		}
		if(function.count != 0) found.append(function);
		i = function.end;
		braceDepth = 0;
	}
	return found.toOwnedSlice();
}

/// Whether every use of a sampler parameter inside the body is the first argument of a sampling
/// call this file knows, which is the condition under which the array overload can compile.
fn onlySampled(tokens: []const Token, function: SamplerFunction) bool {
	var i = function.close + 1;
	while(i <= function.end) : (i += 1) {
		const token = tokens[i];
		if(token.kind != .identifier) continue;
		var isParameter = false;
		for(function.names[0..function.count]) |name| {
			if(std.mem.eql(u8, name, token.text)) isParameter = true;
		}
		if(!isParameter) continue;
		const open = previousSignificant(tokens, i) orelse return false;
		if(!isPunctuation(tokens[open], "(")) return false;
		const callee = previousSignificant(tokens, open) orelse return false;
		if(tokens[callee].kind != .identifier or flavourOf(tokens[callee].text) == null) return false;
	}
	return true;
}

/// Routes the sampling calls on each qualifying function's sampler parameters through the
/// dispatch helpers, and returns the functions to emit overloads for. Prototypes are kept only
/// when a qualifying definition of the same name exists.
fn markSamplerParameterFunctions(allocator: NeverFailingAllocator, tokens: []const Token, dispatch: MacroDispatch, rename: [](?[]const u8)) []SamplerFunction {
	const candidates = findSamplerFunctions(allocator, tokens);
	defer allocator.free(candidates);
	var kept = List(SamplerFunction).init(allocator);
	for(candidates) |function| {
		if(!function.isDefinition or !onlySampled(tokens, function)) continue;
		var i = function.close + 1;
		while(i <= function.end) : (i += 1) {
			if(tokens[i].kind != .identifier) continue;
			var isParameter = false;
			for(function.names[0..function.count]) |name| {
				if(std.mem.eql(u8, name, tokens[i].text)) isParameter = true;
			}
			if(!isParameter) continue;
			const open = previousSignificant(tokens, i).?;
			const callee = previousSignificant(tokens, open).?;
			rename[callee] = dispatch.forFlavour(flavourOf(tokens[callee].text).?);
		}
		kept.append(function);
	}
	// A prototype of a kept definition needs the overload's prototype beside it too, or a caller
	// between the two would see only the `sampler2D` form.
	const definitionCount = kept.items.len;
	for(candidates) |function| {
		if(function.isDefinition) continue;
		for(kept.items[0..definitionCount]) |definition| {
			if(std.mem.eql(u8, definition.name, function.name) and definition.count == function.count) {
				kept.append(function);
				break;
			}
		}
	}
	return kept.toOwnedSlice();
}

/// Marks the bound of a `clamp` call that has to be wrapped in `float(...)` for the driver.
///
/// NVIDIA rejects `clamp(float, float, int)` as ambiguous between its `float` and `float64_t`
/// overloads. Bliss writes `clamp(maxIT_clouds / sqrt(...), 0.0, maxIT)` with `maxIT` an `int`
/// (`lib/volumetricClouds.glsl:444`), and that one line took `deferred`, `deferred2`,
/// `composite` and `composite3` down. The call is legal GLSL and unambiguous by the
/// specification's own rules - an int-to-float conversion beats an int-to-double one - and the
/// pack is known to run under Iris on this vendor. What differs there is not known: the version
/// policy, the `#extension` hoisting and Iris's unused-function removal (`deferred` calls
/// `renderClouds` under nothing but `OVERWORLD_SHADER`) have each been eliminated in turn.
///
/// The obvious shim, a user-defined `float clamp(float, float, int)`, cannot be used. This driver
/// hides every built-in overload of a name once a user function carries it - measured for
/// `texture` by `pipeline.probeBuiltinOverloadOnce` - so it would take every other `clamp` in the
/// file with it.
///
/// So the call is made exact instead, in the one shape where that is provably a no-op. When one
/// bound of a `clamp` is a float literal, the other has to be a scalar for the call to be valid at
/// all - `clamp(genFType, float, float)` is the only family a float literal binds to - so
/// `float(...)` around it is the identity for a float and precisely the conversion the driver was
/// asked to infer for an int. Nothing is done inside `#define` bodies, where a bound may be a
/// macro parameter with a different type per expansion, or when the bound is anything but a
/// single identifier or number token. No type is inferred; this stays a token rewrite.
fn markIntegerClampBounds(tokens: []const Token, wrap: []bool) usize {
	var count: usize = 0;
	for(tokens, 0..) |token, i| {
		if(token.kind != .identifier or token.directive != .none) continue;
		if(!std.mem.eql(u8, token.text, "clamp")) continue;
		const openIndex = nextSignificant(tokens, i + 1) orelse continue;
		if(!isPunctuation(tokens[openIndex], "(")) continue;

		// Each argument as its only significant token, or null when it has several. Only the
		// single-token shape is ever rewritten, so that is all that needs recording.
		var arguments: [3]?usize = .{null, null, null};
		var argumentCount: usize = 0;
		var tokensInArgument: usize = 0;
		var single: ?usize = null;
		var depth: usize = 0;
		var closed = false;
		var j = openIndex + 1;
		while(j < tokens.len) : (j += 1) {
			const inner = tokens[j];
			if(inner.kind == .whitespace or inner.kind == .comment or inner.kind == .newline) continue;
			// A directive inside the argument list means the arguments themselves are conditional.
			if(inner.directive != .none) break;
			if(inner.kind == .punctuation) {
				if(isPunctuation(inner, "(") or isPunctuation(inner, "[")) depth += 1;
				if(isPunctuation(inner, ")") or isPunctuation(inner, "]")) {
					if(depth == 0) {
						closed = true;
						break;
					}
					depth -= 1;
				}
				if(depth == 0 and isPunctuation(inner, ",")) {
					if(argumentCount < 3) arguments[argumentCount] = if(tokensInArgument == 1) single else null;
					argumentCount += 1;
					tokensInArgument = 0;
					single = null;
					continue;
				}
			}
			tokensInArgument += 1;
			single = j;
		}
		if(!closed) continue;
		if(argumentCount < 3) arguments[argumentCount] = if(tokensInArgument == 1) single else null;
		argumentCount += 1;
		if(argumentCount != 3) continue;

		const low = arguments[1] orelse continue;
		const high = arguments[2] orelse continue;
		const lowIsFloat = isFloatLiteral(tokens[low]);
		if(lowIsFloat == isFloatLiteral(tokens[high])) continue; // both literal, or neither: nothing to make exact
		const other = if(lowIsFloat) high else low;
		if(tokens[other].kind != .identifier and tokens[other].kind != .number) continue;
		wrap[other] = true;
		count += 1;
	}
	return count;
}

fn isPunctuation(token: Token, text: []const u8) bool {
	return token.kind == .punctuation and std.mem.eql(u8, token.text, text);
}

/// A number token spelled as a float: a fraction or an exponent, and not a hex literal, whose
/// `E` digit would otherwise pass for one.
fn isFloatLiteral(token: Token) bool {
	if(token.kind != .number) return false;
	if(std.mem.startsWith(u8, token.text, "0x") or std.mem.startsWith(u8, token.text, "0X")) return false;
	for(token.text) |c| {
		if(c == '.' or c == 'e' or c == 'E') return true;
	}
	return false;
}

/// Every `uniform <type> <name>` a source declares.
///
/// This exists to answer the question that per-pack debugging cannot: *what is this pack asking for
/// that we never supply?* An unsupplied uniform is not an error at any level - it links fine, and
/// GL hands the shader a zero - so a pack reading `renderStage` or `temperature` renders confidently
/// wrong with nothing in any log. Enumerating declarations and subtracting what the bridge provides
/// turns that silence into a list.
///
/// Names are slices into `source`, which must outlive the result. Duplicates are not filtered; the
/// caller is aggregating across programs anyway.
pub fn declaredUniforms(allocator: NeverFailingAllocator, source: []const u8, out: *List([]const u8)) void {
	const tokens = tokenize(allocator, source);
	defer allocator.free(tokens);

	var i: usize = 0;
	while(i < tokens.len) : (i += 1) {
		const token = tokens[i];
		if(token.kind != .identifier or token.directive != .none) continue;
		if(!std.mem.eql(u8, token.text, "uniform")) continue;

		// `uniform` may be followed by a precision qualifier before the type.
		var typeIndex = nextSignificant(tokens, i + 1) orelse continue;
		if(tokens[typeIndex].kind != .identifier) continue;
		if(isPrecisionQualifier(tokens[typeIndex].text)) {
			typeIndex = nextSignificant(tokens, typeIndex + 1) orelse continue;
			if(tokens[typeIndex].kind != .identifier) continue;
		}

		const nameIndex = nextSignificant(tokens, typeIndex + 1) orelse continue;
		if(tokens[nameIndex].kind != .identifier) continue;

		// A uniform *block* (`uniform Foo { ... }`) has a brace here rather than a terminator, and
		// its name is the block's, not a uniform's.
		const afterIndex = nextSignificant(tokens, nameIndex + 1) orelse continue;
		if(tokens[afterIndex].kind != .punctuation) continue;
		const after = tokens[afterIndex].text;
		if(!std.mem.eql(u8, after, ";") and !std.mem.eql(u8, after, "[") and !std.mem.eql(u8, after, ",")) continue;

		out.append(tokens[nameIndex].text);
		i = nameIndex;
	}
}

fn isPrecisionQualifier(name: []const u8) bool {
	return std.mem.eql(u8, name, "lowp") or std.mem.eql(u8, name, "mediump") or std.mem.eql(u8, name, "highp");
}

/// The highest `gl_FragData[N]` index the source actually writes, plus one.
///
/// The `DRAWBUFFERS` directive is not a reliable size for the output array, because a pack may
/// carry several of them in one file behind `#if`s:
///
///     /* DRAWBUFFERS:06 */
///     gl_FragData[0] = colour;
///     gl_FragData[1] = material;
///     #if BLOCK_REFLECT_QUALITY >= 2
///         /* DRAWBUFFERS:064 */
///         gl_FragData[2] = normal;
///     #endif
///
/// Which one is live is decided by the *driver*, long after the loader has read the first directive
/// and sized the array from it. Sizing to the highest index written instead makes the declaration
/// large enough whichever branch survives. Slots the CPU-side `glDrawBuffers` never maps simply
/// discard their writes, which is the same thing that happens on Iris when a pack's conditionals
/// disagree with the directive it parsed.
fn highestFragDataIndex(tokens: []const Token) u8 {
	var highest: u8 = 0;
	for(tokens, 0..) |token, i| {
		if(token.kind != .identifier) continue;
		if(!std.mem.eql(u8, token.text, "gl_FragData")) continue;

		const openIndex = nextSignificant(tokens, i + 1) orelse continue;
		if(tokens[openIndex].kind != .punctuation or !std.mem.eql(u8, tokens[openIndex].text, "[")) continue;
		const indexToken = nextSignificant(tokens, openIndex + 1) orelse continue;
		// Only a literal index can be resolved here. A computed one keeps whatever the directive
		// said, which is the best available answer.
		const value = std.fmt.parseInt(u8, tokens[indexToken].text, 10) catch continue;
		highest = @max(highest, value +| 1);
	}
	return highest;
}

/// One `<qualifier> <type> <name>[, <name>...];` declaration, by token index.
///
/// A declarator *list* is real: Solas writes `uniform sampler2D gtexture, noisetex;`, and a
/// matcher that only knew the single form left that declaration standing, so `gtexture` was
/// renamed onto the prologue's `sampler2DArray` and the two collided.
const Declaration = struct {
	typeIndex: usize,
	nameIndices: [maxDeclarators]usize,
	nameCount: usize,
	endIndex: usize,

	fn names(self: *const Declaration) []const usize {
		return self.nameIndices[0..self.nameCount];
	}
};

/// More declarators than any pack writes on one line; a longer list is simply not matched.
const maxDeclarators = 8;

/// The nearest significant token before `from`, skipping whitespace and comments.
fn previousSignificant(tokens: []const Token, from: usize) ?usize {
	var i = from;
	while(i > 0) {
		i -= 1;
		switch(tokens[i].kind) {
			.whitespace, .comment, .newline => {},
			else => return i,
		}
	}
	return null;
}

/// Matches a declaration beginning at `i`, or null when the tokens there are something else.
///
/// Deliberately shared by `markStrippedDeclarations` and `declaredType`. The prologue declares a
/// replacement for precisely the declarations the stripper deletes, so a rule the two disagreed
/// about would either leave a duplicate declaration standing or synthesise a replacement at the
/// wrong type - and neither is visible until a driver rejects the generated source, in a file that
/// exists nowhere on disk.
///
/// Note what it does *not* accept: a precision qualifier between the qualifier and the type
/// (`attribute mediump vec2 x;`). That is a pre-existing limitation rather than a new one, and it
/// fails loudly - the declaration survives stripping and collides with the prologue's - so it is
/// left as it stands rather than widened speculatively. No pack in the corpus writes one.
fn matchDeclaration(tokens: []const Token, i: usize) ?Declaration {
	const token = tokens[i];
	if(token.kind != .identifier or token.directive != .none) return null;
	// `uniform` is included because the same problem applies to samplers the prologue
	// replaces: a pack's `uniform sampler2D gtexture;` would otherwise collide with the
	// texture-array declaration that stands in for it.
	if(!std.mem.eql(u8, token.text, "attribute") and !std.mem.eql(u8, token.text, "in") and !std.mem.eql(u8, token.text, "uniform")) return null;

	const typeIndex = nextSignificant(tokens, i + 1) orelse return null;
	if(tokens[typeIndex].kind != .identifier) return null;

	var declaration = Declaration{.typeIndex = typeIndex, .nameIndices = undefined, .nameCount = 0, .endIndex = 0};
	var cursor = typeIndex;
	while(true) {
		const nameIndex = nextSignificant(tokens, cursor + 1) orelse return null;
		if(tokens[nameIndex].kind != .identifier) return null;
		if(declaration.nameCount == maxDeclarators) return null;
		declaration.nameIndices[declaration.nameCount] = nameIndex;
		declaration.nameCount += 1;

		const after = nextSignificant(tokens, nameIndex + 1) orelse return null;
		if(tokens[after].kind != .punctuation) return null;
		if(std.mem.eql(u8, tokens[after].text, ";")) {
			declaration.endIndex = after;
			return declaration;
		}
		// An array declarator or anything else ends the match, as it always did.
		if(!std.mem.eql(u8, tokens[after].text, ",")) return null;
		cursor = after;
	}
}

/// Marks `attribute <type> <name>;` / `in <type> <name>;` declarations of stripped names for
/// deletion, spanning the qualifier through the semicolon.
fn markStrippedDeclarations(tokens: []const Token, stripped: []const []const u8, skip: []bool) void {
	if(stripped.len == 0) return;
	var i: usize = 0;
	while(i < tokens.len) : (i += 1) {
		const declaration = matchDeclaration(tokens, i) orelse continue;
		var strippedCount: usize = 0;
		for(declaration.names()) |nameIndex| {
			if(isIn(stripped, tokens[nameIndex].text)) strippedCount += 1;
		}
		if(strippedCount == 0) continue;

		if(strippedCount == declaration.nameCount) {
			// Every declarator goes, so the whole statement does.
			for(skip[i .. declaration.endIndex + 1]) |*entry| entry.* = true;
		} else {
			// `uniform sampler2D gtexture, noisetex;` keeps `noisetex`: each stripped name is cut
			// out together with one adjacent comma, so what remains is a shorter, well-formed list.
			// The comma before the name is preferred; the first declarator has none, and a name
			// whose preceding comma already went with its neighbour takes the one after it.
			for(declaration.names()) |nameIndex| {
				if(!isIn(stripped, tokens[nameIndex].text)) continue;
				skip[nameIndex] = true;
				var commaIndex = previousSignificant(tokens, nameIndex) orelse continue;
				if(commaIndex <= declaration.typeIndex or skip[commaIndex]) {
					commaIndex = nextSignificant(tokens, nameIndex + 1) orelse continue;
				}
				if(tokens[commaIndex].kind == .punctuation and std.mem.eql(u8, tokens[commaIndex].text, ",")) skip[commaIndex] = true;
			}
		}
		i = declaration.endIndex;
	}
}

/// The type a source declares `name` at, or null when it does not declare it.
///
/// This exists because the type of a synthesised attribute is the pack's choice, not the
/// bridge's. `mc_Entity`, `mc_midTexCoord` and `at_tangent` are pack-declared names rather than
/// `gl_` built-ins, so a pack picks the width it wants and GLSL has no implicit narrowing to rescue
/// a mismatch. The corpus is genuinely split - of the declarations across six packs, `mc_Entity` is
/// `vec4` 28 times, `vec3` 3 times and `vec2` twice; `mc_midTexCoord` is `vec4` 23 times and `vec2`
/// 5 times - and the four packs this bridge grew up against all happen to say `vec4`.
///
/// The result is a slice into `source`, which must outlive it.
///
/// A pack declaring the same name twice at different types behind `#if`s gets the first, which is
/// the best answer available: this file deliberately does not evaluate conditionals, and the
/// stripper deletes both branches either way.
pub fn declaredType(allocator: NeverFailingAllocator, source: []const u8, name: []const u8) ?[]const u8 {
	const tokens = tokenize(allocator, source);
	defer allocator.free(tokens);

	for(0..tokens.len) |i| {
		const declaration = matchDeclaration(tokens, i) orelse continue;
		for(declaration.names()) |nameIndex| {
			if(std.mem.eql(u8, tokens[nameIndex].text, name)) return tokens[declaration.typeIndex].text;
		}
	}
	return null;
}

/// The number in the pack's own `#version` directive, or null when it has none.
fn declaredVersion(tokens: []const Token) ?u16 {
	for(tokens) |token| {
		if(token.directive != .version or token.kind != .number) continue;
		return std.fmt.parseInt(u16, token.text, 10) catch null;
	}
	return null;
}

/// Rewrites one shader stage. The result is a complete translation unit starting with
/// `#version 460`, which is what `pipelines.zig` expects (it splits at the first newline to
/// insert its own defines).
pub fn transform(allocator: NeverFailingAllocator, source: []const u8, options: Options) []u8 {
	const tokens = tokenize(allocator, source);
	defer allocator.free(tokens);
	var usage = analyse(allocator, tokens);
	defer usage.deinit(allocator);

	var out = List(u8).init(allocator);
	const version = options.version orelse @max(declaredVersion(tokens) orelse 120, 410);
	out.print("#version {} core\n", .{version});
	out.appendSlice("// Generated by irisbridge from a shaderpack source. Do not edit.\n");
	// The pack's own `#extension` lines, hoisted to where the spec wants them. At 460 every one of
	// them is core already; at 410 `GL_ARB_shader_image_load_store` and
	// `GL_ARB_shading_language_packing` are not, and a pack at `#version 130` enables them for
	// exactly that reason. One inside a conditional block is hoisted out of it, so a `: require`
	// on an extension the driver lacks fails where it would have been skipped; none in the corpus.
	for(tokens) |token| {
		if(token.directive == .extension) out.appendSlice(token.text);
	}

	for(options.defines) |define| {
		out.appendSlice("#define ");
		out.appendSlice(define);
		out.append('\n');
	}

	// The DRAWBUFFERS directive gives a starting size; the source itself can need a larger one when
	// it carries several directives behind `#if`s. See `highestFragDataIndex`.
	var sizedOptions = options;
	sizedOptions.fragDataCount = @max(options.fragDataCount, highestFragDataIndex(tokens));

	writeShim(&out, sizedOptions, usage);

	if(options.prologue.len != 0) {
		out.appendSlice("\n// ---- Cubyz vertex prologue ----\n");
		out.appendSlice(options.prologue);
		out.append('\n');
	}

	// Emitted after the prologue, not with the rest of the shim: it calls `cubyz_Vertex`, which
	// the prologue is what declares when there is one.
	//
	// Vertex stage only. `ftransform()` transforms the incoming vertex, so it is meaningless in a
	// fragment shader - but packs put it in headers both stages include, and `analyse` sees it
	// there. Emitting the helper anyway leaves it referencing a `cubyz_Vertex` that only the vertex
	// stage declares, which is what stopped six of Complementary's composite programs compiling.
	if(usage.usesFtransform and options.stage == .vertex) {
		out.appendSlice("vec4 cubyz_ftransform() {return cubyz_ModelViewProjectionMatrix*cubyz_Vertex;}\n");
	}

	const skip = allocator.alloc(bool, tokens.len);
	defer allocator.free(skip);
	@memset(skip, false);
	markStrippedDeclarations(tokens, options.strippedAttributes, skip);

	// Per-token renames, for the rewrites that depend on a token's context rather than its
	// spelling. `rewrite` below maps a name to a name and cannot express either of these:
	//
	//  - a sampling call is redirected by *which sampler it names*, so two `texture2D` calls on one
	//    line can land on different helpers. Renaming the sampler instead cannot work: packs pass a
	//    two-component coordinate and there is no `texture(sampler2DArray, vec2)` overload whatever
	//    the sampler is called. It is also what keeps `lightmap` and `depthtex0` - genuinely 2D, in
	//    the very same program - untouched.
	//  - the pack's `main` becomes an ordinary function, so the generated `main` can run the SSBO
	//    pull before calling it. There is no way to inject a statement into the top of someone
	//    else's function, and this sidesteps needing to.
	const rename = allocator.alloc(?[]const u8, tokens.len);
	defer allocator.free(rename);
	@memset(rename, null);
	markArraySamplerCalls(tokens, options.arraySamplers, options.macroDispatch, rename);
	// Whether Iris's alpha test wrapper is appended below, decided here because the rename of the
	// pack's `main` depends on it. A vertex or geometry stage is renamed for its prologue, which
	// always supplies the `main` that calls it; a fragment stage is renamed only for the wrapper,
	// and the wrapper only exists where Iris puts one - a write to `gl_FragData[0]` or
	// `gl_FragColor` (`CommonTransformer.java:218`). Renaming without the wrapper leaves a
	// fragment stage with no entry point at all, which compiles and then fails to link with
	// NVIDIA's `C3001: no program defined`, repeated until the info log is full. That was the
	// terrain and shadow of Kappa, Nostalgia and photon in the 22:21 run of 2026-09-04: the three
	// packs whose gbuffers fragment stages write their own `out` variables.
	const appendsAlphaTest = options.alphaTest and options.alphaTestFunction != .always and options.stage == .fragment and (writesFragData0(tokens) or usage.usesFragColor);
	const entryPointName: ?[]const u8 = if(options.stage == .fragment and !appendsAlphaTest) null else options.entryPointName;
	if(entryPointName) |entryPoint| {
		for(tokens, rename) |token, *target| {
			if(token.kind == .identifier and std.mem.eql(u8, token.text, "main")) target.* = entryPoint;
		}
	}

	// Pack functions that take the block texture as a `sampler2D` parameter get an array overload;
	// see `SamplerFunction`. Gbuffers fragment stages only, where the dispatch helpers exist.
	const overloads: []SamplerFunction = if(options.macroDispatch) |dispatch| markSamplerParameterFunctions(allocator, tokens, dispatch, rename) else &.{};
	defer if(overloads.len != 0) allocator.free(overloads);
	const prototypeAt = allocator.alloc(?usize, tokens.len);
	defer allocator.free(prototypeAt);
	@memset(prototypeAt, null);
	for(overloads, 0..) |function, index| prototypeAt[function.start] = index;

	// Tokens emitted as `float(<token>)`, for the one call shape NVIDIA cannot resolve. See
	// `markIntegerClampBounds`; the count is logged because the rewrite is invisible in the image
	// and a program either compiles or it does not.
	const wrap = allocator.alloc(bool, tokens.len);
	defer allocator.free(wrap);
	@memset(wrap, false);
	const wrapped = markIntegerClampBounds(tokens, wrap);
	if(wrapped != 0) std.log.debug("irisbridge: {} clamp bound(s) made explicit for the driver", .{wrapped});

	// The pack's storage blocks, moved off Cubyz's binding points. The replacement numbers are
	// formatted here and released once the source has been emitted.
	var relocated = List([]u8).init(allocator);
	defer {
		for(relocated.items) |text| allocator.free(text);
		relocated.deinit();
	}
	if(options.storageBindingBase) |base| {
		const moved = markStorageBindings(allocator, tokens, base, rename, &relocated);
		if(moved != 0) std.log.debug("irisbridge: {} storage block binding(s) relocated past the engine's", .{moved});
	}

	out.appendSlice("\n// ---- shaderpack source ----\n");
	for(tokens, skip, rename, wrap, 0..) |token, stripped, renamed, isWrapped, index| {
		if(stripped) continue;
		// The array overload's prototype, on the definition's own line so no line number moves.
		if(prototypeAt[index]) |overload| {
			emitFunctionTokens(&out, tokens, overloads[overload], overloads[overload].start, overloads[overload].close, true, options.stage, usage, rename, wrap);
			out.appendSlice("; ");
		}
		// Our own `#version` is already emitted, and core 460 subsumes every extension a pack
		// asks for, so both are dropped wholesale - including their trailing newline, so line
		// numbers do not drift.
		if(token.directive == .version or token.directive == .extension) continue;
		if(renamed) |replacement| {
			out.appendSlice(replacement);
			continue;
		}
		if(isWrapped) {
			out.appendSlice("float(");
			out.appendSlice(if(token.kind == .identifier) rewrite(token.text, options.stage, usage) else token.text);
			out.append(')');
			continue;
		}
		if(token.kind != .identifier) {
			out.appendSlice(token.text);
			continue;
		}
		out.appendSlice(rewrite(token.text, options.stage, usage));
	}

	// The array overloads' bodies, after the source so nothing the driver reports drifts; their
	// prototypes above make them callable from anywhere the original was.
	var overloadCount: usize = 0;
	for(overloads) |function| {
		if(!function.isDefinition) continue;
		if(overloadCount == 0) out.appendSlice("\n// ---- Cubyz sampler2DArray overloads of the pack's own sampling helpers ----\n");
		// Inside the same conditionals as the original, so the copy is compiled exactly when the
		// original is. An `#else` or `#elif` entry replays its `#if` first, as it was recorded.
		for(function.conditionals[0..function.conditionalCount]) |line| {
			for(line.from..line.to) |j| out.appendSlice(tokens[j].text);
			out.append('\n');
		}
		emitFunctionTokens(&out, tokens, function, function.start, function.end, false, options.stage, usage, rename, wrap);
		out.append('\n');
		for(0..function.opens) |_| out.appendSlice("#endif\n");
		overloadCount += 1;
	}
	if(overloadCount != 0) std.log.debug("irisbridge: {} pack function(s) given a sampler2DArray overload", .{overloadCount});

	// Iris's alpha test, after the body so the renamed pack `main` is declared before the call.
	// Only where Iris applies it: a fragment stage that writes `gl_FragData[0]` or `gl_FragColor`,
	// both of which are `cubyz_FragData[0]` by now. The reference is the pack-visible
	// `alphaTestRef`, which `uniforms.upload` sets per draw path; declared here only when the pack
	// has not, since a second declaration of the same uniform is an error.
	if(appendsAlphaTest) {
		const entryPoint = entryPointName orelse @panic("alphaTest needs entryPointName");
		out.appendSlice("\n// ---- Cubyz alpha test ----\n");
		if(options.alphaTestFunction.expression()) |comparison| {
			if(!declaresUniform(allocator, source, "alphaTestRef")) out.appendSlice("uniform float alphaTestRef;\n");
			out.print("void main() {{\n\t{s}();\n\tif(!(cubyz_FragData[0].a {s} alphaTestRef)) {{\n\t\tdiscard;\n\t}}\n}}\n", .{entryPoint, comparison});
		} else {
			// `NEVER`: Iris writes a bare `discard;` (`AlphaTest.toExpression`). The pack's body
			// still runs first, as it does there, for whatever else it writes.
			out.print("void main() {{\n\t{s}();\n\tdiscard;\n}}\n", .{entryPoint});
		}
	}
	return out.toOwnedSlice();
}

/// Emits tokens `from..=to` of a `SamplerFunction` with `sampler2D` replaced by `sampler2DArray`
/// on its sampler parameters, applying the same per-token rewrites as the main loop. With
/// `singleLine`, newlines become spaces and comments are dropped, which is what lets a prototype
/// share the definition's line.
fn emitFunctionTokens(out: *List(u8), tokens: []const Token, function: SamplerFunction, from: usize, to: usize, singleLine: bool, stage: Stage, usage: Usage, rename: []const ?[]const u8, wrap: []const bool) void {
	for(from..to + 1) |j| {
		const token = tokens[j];
		var substituted = false;
		for(function.typeTokens[0..function.count]) |typeToken| {
			if(typeToken == j) substituted = true;
		}
		if(substituted) {
			out.appendSlice("sampler2DArray");
			continue;
		}
		if(singleLine and (token.kind == .newline or token.kind == .comment)) {
			out.append(' ');
			continue;
		}
		if(rename[j]) |replacement| {
			out.appendSlice(replacement);
			continue;
		}
		if(wrap[j]) {
			out.appendSlice("float(");
			out.appendSlice(if(token.kind == .identifier) rewrite(token.text, stage, usage) else token.text);
			out.append(')');
			continue;
		}
		out.appendSlice(if(token.kind == .identifier) rewrite(token.text, stage, usage) else token.text);
	}
}

/// Marks the binding number of every shader storage block for relocation by `base`.
///
/// A block is a `layout(...)` list followed, within a few tokens, by the `buffer` keyword - the
/// tokens between may be memory qualifiers or a pack macro standing in for them (Nostalgic Red
/// Voxels writes `layout(std430, binding=0) WRITE_TO_SSBOS buffer stuff`, Complementary
/// `SSBO_QUALIFIER`). `std430` in the list is taken as the same evidence, since only a storage
/// block may carry it. An image's `layout(r32i, binding = 2) uniform` and a uniform block's
/// `layout(std140, binding = 1) uniform` are neither, and image units and uniform-buffer points are
/// separate namespaces that Cubyz does not contest. A binding written as a macro name rather than
/// a number cannot be relocated and is left as it is; none in the corpus.
fn markStorageBindings(allocator: NeverFailingAllocator, tokens: []const Token, base: u32, rename: [](?[]const u8), owned: *List([]u8)) usize {
	const found = findStorageBindings(allocator, tokens);
	defer allocator.free(found);
	for(found) |block| {
		var text = List(u8).init(allocator);
		text.print("{}", .{base + block.value});
		owned.append(text.toOwnedSlice());
		rename[block.token] = owned.items[owned.items.len - 1];
	}
	return found.len;
}

/// A storage block's binding as written: the number token and its value.
pub const StorageBinding = struct {token: usize, value: u32};

/// The binding numbers of every shader storage block in `source`, for the conformance harness to
/// check the relocation against.
pub fn storageBlockBindings(allocator: NeverFailingAllocator, source: []const u8, out: *List(u32)) void {
	const tokens = tokenize(allocator, source);
	defer allocator.free(tokens);
	const found = findStorageBindings(allocator, tokens);
	defer allocator.free(found);
	for(found) |block| out.append(block.value);
}

/// Every storage block with a numeric binding, by the rule `markStorageBindings` documents.
fn findStorageBindings(allocator: NeverFailingAllocator, tokens: []const Token) []StorageBinding {
	var found = List(StorageBinding).init(allocator);
	var i: usize = 0;
	while(i < tokens.len) : (i += 1) {
		if(tokens[i].kind != .identifier or !std.mem.eql(u8, tokens[i].text, "layout")) continue;
		const open = nextSignificant(tokens, i + 1) orelse continue;
		if(!isPunctuation(tokens[open], "(")) continue;

		var std430 = false;
		var bindingToken: ?usize = null;
		var depth: usize = 0;
		var j = open;
		var close: ?usize = null;
		while(j < tokens.len) : (j += 1) {
			const token = tokens[j];
			if(isPunctuation(token, "(")) {
				depth += 1;
			} else if(isPunctuation(token, ")")) {
				depth -= 1;
				if(depth == 0) {
					close = j;
					break;
				}
			} else if(token.kind == .identifier and std.mem.eql(u8, token.text, "std430")) {
				std430 = true;
			} else if(token.kind == .identifier and std.mem.eql(u8, token.text, "binding")) {
				const equals = nextSignificant(tokens, j + 1) orelse continue;
				if(!isPunctuation(tokens[equals], "=")) continue;
				const number = nextSignificant(tokens, equals + 1) orelse continue;
				if(tokens[number].kind == .number) bindingToken = number;
			}
		}
		const closeIndex = close orelse continue;
		i = closeIndex;

		var isBuffer = std430;
		var next = nextSignificant(tokens, closeIndex + 1);
		var steps: usize = 0;
		while(next) |index| : (steps += 1) {
			if(steps == 6) break;
			const token = tokens[index];
			if(token.kind == .identifier and std.mem.eql(u8, token.text, "buffer")) {
				isBuffer = true;
				break;
			}
			// `uniform`, `in`, `out` or a declarator end: not a storage block.
			if(token.kind != .identifier or std.mem.eql(u8, token.text, "uniform") or std.mem.eql(u8, token.text, "in") or std.mem.eql(u8, token.text, "out")) break;
			next = nextSignificant(tokens, index + 1);
		}
		if(!isBuffer) continue;
		const number = bindingToken orelse continue;
		const declared = std.fmt.parseInt(u32, tokens[number].text, 10) catch continue;
		found.append(.{.token = number, .value = declared});
	}
	return found.toOwnedSlice();
}

/// Whether the source names `gl_FragData[0]` at all - the one thing Iris's alpha test keys on
/// (`CommonTransformer.java:218`, `replaceIndexesSet.contains(0L)`). A program writing only
/// slot 1 gets no test, since the test would read an output nothing wrote.
fn writesFragData0(tokens: []const Token) bool {
	for(tokens, 0..) |token, i| {
		if(token.kind != .identifier or !std.mem.eql(u8, token.text, "gl_FragData")) continue;
		const open = nextSignificant(tokens, i + 1) orelse continue;
		if(!isPunctuation(tokens[open], "[")) continue;
		const index = nextSignificant(tokens, open + 1) orelse continue;
		if(tokens[index].kind != .number or !std.mem.eql(u8, tokens[index].text, "0")) continue;
		const close = nextSignificant(tokens, index + 1) orelse continue;
		if(isPunctuation(tokens[close], "]")) return true;
	}
	return false;
}

fn declaresUniform(allocator: NeverFailingAllocator, source: []const u8, name: []const u8) bool {
	var declared = List([]const u8).init(allocator);
	defer declared.deinit();
	declaredUniforms(allocator, source, &declared);
	for(declared.items) |entry| {
		if(std.mem.eql(u8, entry, name)) return true;
	}
	return false;
}

fn rewrite(name: []const u8, stage: Stage, usage: Usage) []const u8 {
	// `attribute` only ever appears in a vertex stage; either way core spells it `in`.
	if(std.mem.eql(u8, name, "attribute")) return "in";
	if(std.mem.eql(u8, name, "varying")) return switch(stage) {
		.vertex => "out",
		.fragment, .geometry, .compute => "in",
	};
	if(std.mem.eql(u8, name, "gl_FragColor")) return "cubyz_FragData[0]";
	if(std.mem.eql(u8, name, "gl_Fog")) return "cubyz_Fog";
	// A pack's own sampler called `texture` becomes `gtexture`, which is what Iris does
	// (`CommonTransformer.java:229-234`): in a gbuffers stage that is the block texture, and its
	// declaration is stripped and its calls redirected under `prologue.suppliedSamplers`. An
	// earlier private name here, `cubyz_textureUnit`, kept core `texture()` callable and nothing
	// else - no unit was ever assigned to it, so it sampled unit 0.
	if(std.mem.eql(u8, name, "texture") and usage.shadowsTextureName) return "gtexture";
	if(isCoreBuiltin(name)) return name;

	if(std.mem.startsWith(u8, name, "gl_")) {
		if(isIn(&matrixBuiltins, name) or isIn(&vertexInputBuiltins, name) or isIn(&varyingBuiltins, name) or std.mem.eql(u8, name, "gl_FragData")) {
			return prefixed(name);
		}
		return name;
	}
	if(isIn(&legacyTextureFunctions, name)) return prefixedLegacy(name);
	if(std.mem.eql(u8, name, "ftransform")) return "cubyz_ftransform";
	return name;
}

/// `gl_Vertex` -> `cubyz_Vertex`. Comptime-built so the returned slice outlives the call without
/// an allocation on the hot path.
fn prefixed(name: []const u8) []const u8 {
	const all = matrixBuiltins ++ vertexInputBuiltins ++ varyingBuiltins ++ [_][]const u8{"gl_FragData"};
	inline for(all) |entry| {
		if(std.mem.eql(u8, entry, name)) return "cubyz_" ++ entry[3..];
	}
	return name;
}

fn prefixedLegacy(name: []const u8) []const u8 {
	inline for(legacyTextureFunctions) |entry| {
		if(std.mem.eql(u8, entry, name)) return "cubyz_" ++ entry;
	}
	return name;
}

// MARK: shim

fn writeShim(out: *List(u8), options: Options, usage: Usage) void {
	out.appendSlice("\n// ---- Cubyz compatibility shim ----\n");

	var matrices = usage.matrices.keyIterator();
	while(matrices.next()) |name| {
		if(std.mem.eql(u8, name.*, "gl_NormalMatrix")) {
			out.appendSlice("uniform mat3 cubyz_NormalMatrix;\n");
		} else if(std.mem.eql(u8, name.*, "gl_TextureMatrix")) {
			out.appendSlice("uniform mat4 cubyz_TextureMatrix[8];\n");
		} else {
			out.appendSlice("uniform mat4 cubyz_");
			out.appendSlice(name.*[3..]);
			out.appendSlice(";\n");
		}
	}

	// Vertex inputs are declared by the prologue when there is one, because there it is a
	// computed value rather than a real attribute.
	if(options.stage == .vertex and options.prologue.len == 0) {
		var inputs = usage.vertexInputs.keyIterator();
		while(inputs.next()) |name| {
			if(std.mem.startsWith(u8, name.*, "gl_MultiTexCoord")) {
				out.appendSlice("in vec4 cubyz_MultiTexCoord");
				out.appendSlice(name.*["gl_MultiTexCoord".len..]);
				out.appendSlice(";\n");
			} else if(std.mem.eql(u8, name.*, "gl_Vertex")) {
				out.appendSlice("in vec4 cubyz_Vertex;\n");
			} else if(std.mem.eql(u8, name.*, "gl_Normal")) {
				out.appendSlice("in vec3 cubyz_Normal;\n");
			} else if(std.mem.eql(u8, name.*, "gl_Color")) {
				out.appendSlice("in vec4 cubyz_Color;\n");
			}
		}
	}

	var varyings = usage.varyings.keyIterator();
	// A compute stage has no varyings to declare; a `gl_TexCoord` it names is in a header shared
	// with the draw stages, and an `in` declaration in a compute shader is a compile error.
	while(if(options.stage == .compute) null else varyings.next()) |name| {
		const direction = if(options.stage == .vertex) "out" else "in";
		// A geometry stage receives one value per input vertex, so its inputs are arrays. Only the
		// input side is declared: a geometry shader that also *writes* a compat varying would need
		// the same name as an output, and packs that ship a `.gsh` write core `in`/`out` for their
		// own varyings, so that case has not come up.
		const perVertex = if(options.stage == .geometry) "[3]" else "";
		out.appendSlice(direction);
		if(std.mem.eql(u8, name.*, "gl_TexCoord")) {
			out.print(" vec4 cubyz_TexCoord{s}[8];\n", .{perVertex});
		} else if(std.mem.eql(u8, name.*, "gl_FogFragCoord")) {
			out.print(" float cubyz_FogFragCoord{s};\n", .{perVertex});
		} else {
			out.appendSlice(" vec4 cubyz_");
			out.appendSlice(name.*[3..]);
			out.print("{s};\n", .{perVertex});
		}
	}

	if(usage.usesFog) {
		// `gl_FogParameters` verbatim, minus the reserved `gl_` prefix. Packs read `.start`, `.end`
		// and `.color` for linear fog; `.scale` is `1/(end - start)`, which fixed-function
		// precomputed and packs still divide by.
		out.appendSlice(
			\\struct cubyz_FogParameters {vec4 color; float density; float start; float end; float scale;};
			\\uniform cubyz_FogParameters cubyz_Fog;
			\\
		);
	}

	if(options.stage == .fragment and (usage.usesFragData or usage.usesFragColor)) {
		// An output array takes consecutive locations, so slot N of the pack's `gl_FragData`
		// lands on draw buffer N, which `glDrawBuffers` has already pointed at the colortex the
		// DRAWBUFFERS directive named.
		out.appendSlice("layout(location = 0) out vec4 cubyz_FragData[");
		out.print("{}", .{@max(options.fragDataCount, 1)});
		out.appendSlice("];\n");
	}

	if(usage.shadowsTextureName) {
		out.appendSlice("// pack declares its own `texture`; renamed to `gtexture`, as Iris does\n");
	}

	var functions = usage.textureFunctions.keyIterator();
	while(functions.next()) |name| writeTextureShim(out, name.*, options.stage);
}

fn writeTextureShim(out: *List(u8), name: []const u8, stage: Stage) void {
	// `shadow2D*` is the one that is not a plain rename: compat returns vec4, core returns float.
	if(std.mem.eql(u8, name, "shadow2D")) {
		out.appendSlice("vec4 cubyz_shadow2D(sampler2DShadow s, vec3 c) {return vec4(texture(s, c));}\n");
		return;
	}
	if(std.mem.eql(u8, name, "shadow2DLod")) {
		out.appendSlice("vec4 cubyz_shadow2DLod(sampler2DShadow s, vec3 c, float l) {return vec4(textureLod(s, c, l));}\n");
		return;
	}
	if(std.mem.eql(u8, name, "shadow2DProj")) {
		out.appendSlice("vec4 cubyz_shadow2DProj(sampler2DShadow s, vec4 c) {return vec4(textureProj(s, c));}\n");
		return;
	}
	if(std.mem.eql(u8, name, "texture2DGrad") or std.mem.eql(u8, name, "texture2DGradARB")) {
		out.print("vec4 cubyz_{s}(sampler2D s, vec2 c, vec2 dx, vec2 dy) {{return textureGrad(s, c, dx, dy);}}\n", .{name});
		return;
	}
	if(std.mem.eql(u8, name, "texture3DGrad")) {
		out.appendSlice("vec4 cubyz_texture3DGrad(sampler3D s, vec3 c, vec3 dx, vec3 dy) {return textureGrad(s, c, dx, dy);}\n");
		return;
	}
	if(std.mem.eql(u8, name, "texelFetch2D")) {
		out.appendSlice("vec4 cubyz_texelFetch2D(sampler2D s, ivec2 c, int l) {return texelFetch(s, c, l);}\n");
		return;
	}
	if(std.mem.eql(u8, name, "texelFetch3D")) {
		out.appendSlice("vec4 cubyz_texelFetch3D(sampler3D s, ivec3 c, int l) {return texelFetch(s, c, l);}\n");
		return;
	}
	if(std.mem.eql(u8, name, "textureSize2D")) {
		out.appendSlice("ivec2 cubyz_textureSize2D(sampler2D s, int l) {return textureSize(s, l);}\n");
		return;
	}
	const spec: struct {sampler: []const u8, coord: []const u8, core: []const u8, projected: bool, lod: bool} =
		if(std.mem.eql(u8, name, "texture1D")) .{.sampler = "sampler1D", .coord = "float", .core = "texture", .projected = false, .lod = false}
		else if(std.mem.eql(u8, name, "texture2D")) .{.sampler = "sampler2D", .coord = "vec2", .core = "texture", .projected = false, .lod = false}
		else if(std.mem.eql(u8, name, "texture2DLod")) .{.sampler = "sampler2D", .coord = "vec2", .core = "textureLod", .projected = false, .lod = true}
		else if(std.mem.eql(u8, name, "texture2DProj")) .{.sampler = "sampler2D", .coord = "vec4", .core = "textureProj", .projected = true, .lod = false}
		else if(std.mem.eql(u8, name, "texture2DProjLod")) .{.sampler = "sampler2D", .coord = "vec4", .core = "textureProjLod", .projected = true, .lod = true}
		else if(std.mem.eql(u8, name, "texture3D")) .{.sampler = "sampler3D", .coord = "vec3", .core = "texture", .projected = false, .lod = false}
		else if(std.mem.eql(u8, name, "texture3DLod")) .{.sampler = "sampler3D", .coord = "vec3", .core = "textureLod", .projected = false, .lod = true}
		else if(std.mem.eql(u8, name, "textureCube")) .{.sampler = "samplerCube", .coord = "vec3", .core = "texture", .projected = false, .lod = false}
		else if(std.mem.eql(u8, name, "textureCubeLod")) .{.sampler = "samplerCube", .coord = "vec3", .core = "textureLod", .projected = false, .lod = true}
		else return;

	out.print("vec4 cubyz_{s}({s} s, {s} c", .{name, spec.sampler, spec.coord});
	if(spec.lod) out.appendSlice(", float l");
	out.print(") {{return {s}(s, c", .{spec.core});
	if(spec.lod) out.appendSlice(", l");
	out.appendSlice(");}\n");

	// The bias overload only exists for the non-LOD forms.
	if(!spec.lod) {
		// A bias is illegal outside a fragment shader, not merely useless: it is relative to an
		// implicitly computed level of detail and only fragment shaders have the derivatives for
		// one. NVIDIA says so outright - `error C5248: Use of 'bias' argument in 'texture' is not
		// valid for this profile`. Packs put these calls in headers that *both* stages include, so
		// the vertex form still has to compile; an explicit level is the only available reading,
		// and is what GLSL 120 required in a vertex shader anyway.
		const biased = if(stage == .fragment) spec.core else if(spec.projected) "textureProjLod" else "textureLod";
		out.print("vec4 cubyz_{s}({s} s, {s} c, float b) {{return {s}(s, c, b);}}\n", .{name, spec.sampler, spec.coord, biased});
	}
}

// MARK: tests

const testing = std.testing;
const testingAllocator = main.heap.testingAllocator;

/// The invariant everything else leans on.
fn expectRoundTrip(source: []const u8) !void {
	const tokens = tokenize(testingAllocator, source);
	defer testingAllocator.free(tokens);
	var rebuilt = List(u8).init(testingAllocator);
	defer rebuilt.deinit();
	for(tokens) |token| rebuilt.appendSlice(token.text);
	try testing.expectEqualStrings(source, rebuilt.items);
}

test "tokenizer round-trips ordinary source" {
	try expectRoundTrip("void main() {\n\tgl_Position = ftransform();\n}\n");
}

test "tokenizer round-trips comments, directives and awkward literals" {
	try expectRoundTrip("#version 120\n// a comment with gl_Vertex in it\n/* block\n   comment */\nfloat x = .5e-3;\nvec3 v; float y = v.x;\n");
	try expectRoundTrip("#define FOO(a) texture2D(gtexture, a)\n#include \"/lib/common.glsl\"\n");
	try expectRoundTrip("int a = 1; \\\n int b = 2;\n");
	try expectRoundTrip("");
}

test "directives are classified" {
	const tokens = tokenize(testingAllocator, "#version 120\n#extension GL_ARB_x : require\n#define A 1\n");
	defer testingAllocator.free(tokens);
	var sawVersion = false;
	var sawExtension = false;
	var sawDefine = false;
	for(tokens) |token| {
		if(token.directive == .version) sawVersion = true;
		if(token.directive == .extension) sawExtension = true;
		if(token.directive == .other and token.kind == .identifier and std.mem.eql(u8, token.text, "A")) sawDefine = true;
	}
	try testing.expect(sawVersion);
	try testing.expect(sawExtension);
	try testing.expect(sawDefine);
}

test "compat built-ins are renamed and core ones are left alone" {
	const source =
		\\#version 120
		\\attribute vec4 mc_Entity;
		\\varying vec2 texcoord;
		\\void main() {
		\\    gl_Position = gl_ModelViewProjectionMatrix*gl_Vertex;
		\\    texcoord = gl_MultiTexCoord0.st;
		\\}
		\\
	;
	const result = transform(testingAllocator, source, .{.stage = .vertex});
	defer testingAllocator.free(result);

	// A `#version 120` pack with no version forced compiles at Iris's floor, 410 core.
	try testing.expect(std.mem.startsWith(u8, result, "#version 410 core\n"));
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_ModelViewProjectionMatrix*cubyz_Vertex") != null);
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_MultiTexCoord0.st") != null);
	// gl_Position survives, and the old version line is gone.
	try testing.expect(std.mem.indexOf(u8, result, "gl_Position") != null);
	try testing.expect(std.mem.indexOf(u8, result, "#version 120") == null);
	// `attribute`/`varying` are reserved words in core and must be gone.
	try testing.expect(std.mem.indexOf(u8, result, "attribute vec4") == null);
	try testing.expect(std.mem.indexOf(u8, result, "varying vec2") == null);
	try testing.expect(std.mem.indexOf(u8, result, "in vec4 mc_Entity;") != null);
	try testing.expect(std.mem.indexOf(u8, result, "out vec2 texcoord;") != null);
	try testing.expect(std.mem.indexOf(u8, result, "uniform mat4 cubyz_ModelViewProjectionMatrix;") != null);
}

test "ftransform expands to a real function with its dependencies declared" {
	const source = "void main() {gl_Position = ftransform();}\n";
	const result = transform(testingAllocator, source, .{.stage = .vertex});
	defer testingAllocator.free(result);

	try testing.expect(std.mem.indexOf(u8, result, "gl_Position = cubyz_ftransform();") != null);
	try testing.expect(std.mem.indexOf(u8, result, "vec4 cubyz_ftransform() {return cubyz_ModelViewProjectionMatrix*cubyz_Vertex;}") != null);
	// Using it must pull in both operands even though the shader never names them.
	try testing.expect(std.mem.indexOf(u8, result, "uniform mat4 cubyz_ModelViewProjectionMatrix;") != null);
	try testing.expect(std.mem.indexOf(u8, result, "in vec4 cubyz_Vertex;") != null);
}

test "ftransform is declared after a prologue that supplies cubyz_Vertex" {
	const source = "void main() {gl_Position = ftransform();}\n";
	const result = transform(testingAllocator, source, .{.stage = .vertex, .prologue = "vec4 cubyz_Vertex;"});
	defer testingAllocator.free(result);

	const prologueAt = std.mem.indexOf(u8, result, "vec4 cubyz_Vertex;").?;
	const helperAt = std.mem.indexOf(u8, result, "vec4 cubyz_ftransform()").?;
	// GLSL requires declaration before use, so the order here is load-bearing.
	try testing.expect(prologueAt < helperAt);
}

test "identifiers inside comments are never rewritten" {
	const source = "// gl_Vertex texture2D\n/* gl_ModelViewMatrix */\nvoid main() {}\n";
	const result = transform(testingAllocator, source, .{.stage = .fragment});
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "// gl_Vertex texture2D") != null);
	try testing.expect(std.mem.indexOf(u8, result, "/* gl_ModelViewMatrix */") != null);
	// Nothing was used, so no shim declarations should have been emitted for them.
	try testing.expect(std.mem.indexOf(u8, result, "uniform mat4 cubyz_ModelViewMatrix;") == null);
}

test "macro bodies are rewritten" {
	const source = "#define SAMPLE(x) texture2D(gtexture, x)\nvoid main() {}\n";
	const result = transform(testingAllocator, source, .{.stage = .fragment});
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "#define SAMPLE(x) cubyz_texture2D(gtexture, x)") != null);
	try testing.expect(std.mem.indexOf(u8, result, "vec4 cubyz_texture2D(sampler2D s, vec2 c)") != null);
}

test "a texture bias argument becomes an explicit LOD outside a fragment shader" {
	// The bias argument needs implicit derivatives, so it is a compile *error* in a vertex shader,
	// not merely a no-op. Complementary's composite vertex stages call `texture2D` with one, and
	// NVIDIA rejected the whole program: "Use of 'bias' argument in 'texture' is not valid for this
	// profile".
	const source = "void main() {vec4 c = texture2D(tex, uv, 0.5);}\n";

	const fragment = transform(testingAllocator, source, .{.stage = .fragment});
	defer testingAllocator.free(fragment);
	try testing.expect(std.mem.indexOf(u8, fragment, "vec4 cubyz_texture2D(sampler2D s, vec2 c, float b) {return texture(s, c, b);}") != null);

	const vertex = transform(testingAllocator, source, .{.stage = .vertex});
	defer testingAllocator.free(vertex);
	try testing.expect(std.mem.indexOf(u8, vertex, "vec4 cubyz_texture2D(sampler2D s, vec2 c, float b) {return textureLod(s, c, b);}") != null);
	try testing.expect(std.mem.indexOf(u8, vertex, "float b) {return texture(s, c, b);}") == null);
}

test "a projected bias overload uses the projected LOD form in a vertex shader" {
	const source = "void main() {vec4 c = texture2DProj(tex, uv, 0.5);}\n";
	const vertex = transform(testingAllocator, source, .{.stage = .vertex});
	defer testingAllocator.free(vertex);
	// `textureLod` would not typecheck against a vec4 projected coordinate.
	try testing.expect(std.mem.indexOf(u8, vertex, "float b) {return textureProjLod(s, c, b);}") != null);
}

test "fragment outputs are declared for the requested draw buffer count" {
	const source = "void main() {\n\tgl_FragData[0] = vec4(1.0);\n\tgl_FragData[1] = vec4(0.0);\n}\n";
	const result = transform(testingAllocator, source, .{.stage = .fragment, .fragDataCount = 2});
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "layout(location = 0) out vec4 cubyz_FragData[2];") != null);
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_FragData[0] = vec4(1.0);") != null);
}

test "gl_FragColor becomes draw buffer zero" {
	const source = "void main() {gl_FragColor = vec4(1.0);}\n";
	const result = transform(testingAllocator, source, .{.stage = .fragment});
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_FragData[0] = vec4(1.0);") != null);
	try testing.expect(std.mem.indexOf(u8, result, "layout(location = 0) out vec4 cubyz_FragData[1];") != null);
}

test "shadow2D keeps its vec4 return type" {
	const source = "void main() {float s = shadow2D(shadowtex0, vec3(0.0)).x;}\n";
	const result = transform(testingAllocator, source, .{.stage = .fragment});
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "vec4 cubyz_shadow2D(sampler2DShadow s, vec3 c) {return vec4(texture(s, c));}") != null);
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_shadow2D(shadowtex0, vec3(0.0)).x") != null);
}

test "a pack that declares its own `texture` sampler gets it renamed to gtexture, as Iris does" {
	const source = "uniform sampler2D texture;\nvoid main() {gl_FragColor = texture2D(texture, vec2(0.0));}\n";
	const result = transform(testingAllocator, source, .{.stage = .fragment});
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "uniform sampler2D gtexture;") != null);
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_texture2D(gtexture, vec2(0.0))") != null);
}

test "in a gbuffers stage the `texture` sampler is the block texture: stripped and redirected" {
	// Bliss and BSL. The declaration goes, the call lands on the array helper, and the argument
	// is the renamed name, which the prologue defines onto Cubyz's array. Before this, the
	// renamed sampler kept its `sampler2D` declaration with no unit assigned and read unit 0 - the
	// screen - onto every block face.
	const source = "uniform sampler2D texture;\nvoid main() {gl_FragData[0] = texture2D(texture, uv);}\n";
	const result = transform(testingAllocator, source, .{
		.stage = .fragment,
		.strippedAttributes = &.{"texture"},
		.arraySamplers = &.{
			.{.sampler = "texture", .function = "cubyz_sampleArray", .lodFunction = "cubyz_sampleArrayLod", .gradFunction = "cubyz_sampleArrayGrad", .fetchFunction = "cubyz_fetchArray"},
		},
	});
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "uniform sampler2D gtexture;") == null);
	try testing.expect(std.mem.indexOf(u8, result, "uniform sampler2D texture;") == null);
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_sampleArray(gtexture, uv)") != null);
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_textureUnit") == null);
}

test "a pack helper that only samples its sampler2D parameter gets a sampler2DArray overload" {
	// Bliss's `texture2D_POMSwitch`, called with the block texture and with `normals`. The header
	// spans lines, as the real one does, and the prototype must not add any.
	const source =
		\\vec4 texture2D_POMSwitch(
		\\    sampler2D sampler,
		\\    vec2 coord,
		\\    bool ifPOM,
		\\    float LOD
		\\){
		\\    if(ifPOM) return texture2DGradARB(sampler, coord, vec2(0.0), vec2(0.0));
		\\    return texture2D(sampler, coord, LOD);
		\\}
		\\void main() {gl_FragData[0] = texture2D_POMSwitch(gtexture, uv, false, 0.0) + texture2D_POMSwitch(normals, uv, false, 0.0);}
		\\
	;
	const result = transform(testingAllocator, source, .{
		.stage = .fragment,
		.arraySamplers = &.{
			.{.sampler = "gtexture", .function = "cubyz_sampleArray", .lodFunction = "cubyz_sampleArrayLod", .gradFunction = "cubyz_sampleArrayGrad", .fetchFunction = "cubyz_fetchArray"},
		},
		.macroDispatch = .{.function = "cubyz_sampleAny", .lodFunction = "cubyz_sampleAnyLod", .gradFunction = "cubyz_sampleAnyGrad", .fetchFunction = "cubyz_fetchAny"},
	});
	defer testingAllocator.free(result);
	// Once in the prototype, once in the appended body.
	try testing.expectEqual(@as(usize, 2), std.mem.count(u8, result, "sampler2DArray sampler"));
	// Both copies sample through the dispatch helpers, so each resolves for its own parameter type.
	try testing.expectEqual(@as(usize, 2), std.mem.count(u8, result, "cubyz_sampleAnyGrad(sampler, coord, vec2(0.0), vec2(0.0))"));
	try testing.expectEqual(@as(usize, 2), std.mem.count(u8, result, "cubyz_sampleAny(sampler, coord, LOD)"));
	// The prototype precedes the definition on its line, and the body copy comes after the source.
	const prototype = std.mem.indexOf(u8, result, "sampler2DArray sampler").?;
	const definition = std.mem.indexOf(u8, result, "sampler2D sampler").?;
	try testing.expect(prototype < definition);
	try testing.expect(std.mem.indexOf(u8, result, "sampler2DArray overloads").? > std.mem.indexOf(u8, result, "void main() {cubyz_FragData").?);
	// The pack's lines still number the same.
	const bodyStart = std.mem.indexOf(u8, result, "shaderpack source ----\n").? + "shaderpack source ----\n".len;
	const bodyEnd = std.mem.indexOf(u8, result, "\n// ---- Cubyz sampler2DArray overloads").?;
	try testing.expectEqual(std.mem.count(u8, source, "\n"), std.mem.count(u8, result[bodyStart..bodyEnd], "\n"));
	// The call sites are untouched: overload resolution does the rest.
	try testing.expect(std.mem.indexOf(u8, result, "texture2D_POMSwitch(gtexture, uv, false, 0.0)") != null);
	try testing.expect(std.mem.indexOf(u8, result, "texture2D_POMSwitch(normals, uv, false, 0.0)") != null);
}

test "an overloaded helper's copy sits inside the same preprocessor conditionals as the original" {
	// Complementary's `textureAF` under `#if ANISOTROPIC_FILTER > 0`: with the option off the
	// original is never compiled, and neither may the copy be, or its references to globals the
	// block declares are undefined. An `#else` branch replays its `#if` line first.
	const source =
		\\#if ANISOTROPIC_FILTER > 0
		\\vec4 textureAF(sampler2D s, vec2 uv) {return texture2D(s, uv * spriteScale);}
		\\#else
		\\vec4 plain(sampler2D s, vec2 uv) {return texture2D(s, uv);}
		\\#endif
		\\void main() {gl_FragData[0] = vec4(1.0);}
		\\
	;
	const dispatch = MacroDispatch{.function = "cubyz_sampleAny", .lodFunction = "cubyz_sampleAnyLod", .gradFunction = "cubyz_sampleAnyGrad", .fetchFunction = "cubyz_fetchAny"};
	const result = transform(testingAllocator, source, .{.stage = .fragment, .macroDispatch = dispatch});
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "#if ANISOTROPIC_FILTER > 0\nvec4 textureAF(sampler2DArray s, vec2 uv) {return cubyz_sampleAny(s, uv * spriteScale);}\n#endif\n") != null);
	try testing.expect(std.mem.indexOf(u8, result, "#if ANISOTROPIC_FILTER > 0\n#else\nvec4 plain(sampler2DArray s, vec2 uv) {return cubyz_sampleAny(s, uv);}\n#endif\n") != null);
}

test "a helper that uses its sampler any other way, or lives outside a gbuffers stage, is left alone" {
	const size = "float size(sampler2D tex) {return float(textureSize(tex, 0).x);}\nvoid main() {gl_FragData[0] = vec4(size(gtexture));}\n";
	const dispatch = MacroDispatch{.function = "cubyz_sampleAny", .lodFunction = "cubyz_sampleAnyLod", .gradFunction = "cubyz_sampleAnyGrad", .fetchFunction = "cubyz_fetchAny"};
	const result = transform(testingAllocator, size, .{.stage = .fragment, .macroDispatch = dispatch});
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "sampler2DArray") == null);
	try testing.expect(std.mem.indexOf(u8, result, "textureSize(tex, 0)") != null);

	const sampled = "vec4 read(sampler2D tex, vec2 uv) {return texture2D(tex, uv);}\nvoid main() {gl_FragData[0] = read(gtexture, uv);}\n";
	const composite = transform(testingAllocator, sampled, .{.stage = .fragment});
	defer testingAllocator.free(composite);
	try testing.expect(std.mem.indexOf(u8, composite, "sampler2DArray") == null);
}

test "an identifier followed by a parenthesis in sampler position is a call, not a sampler" {
	// With `texture` on the redirect list, `foo(texture(s, uv))` must not be read as a sampling
	// call whose sampler is named `texture`.
	const source = "void main() {vec4 c = texture2DLod(texture(s, uv), 0.0);}\n";
	const result = transform(testingAllocator, source, .{
		.stage = .fragment,
		.arraySamplers = &.{
			.{.sampler = "texture", .function = "cubyz_sampleArray", .lodFunction = "cubyz_sampleArrayLod", .gradFunction = "cubyz_sampleArrayGrad", .fetchFunction = "cubyz_fetchArray"},
		},
	});
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_sampleArrayLod") == null);
}

test "attribute declarations the prologue supplies are stripped" {
	const source =
		\\attribute vec4 mc_Entity;
		\\attribute vec4 mc_midTexCoord;
		\\attribute vec4 someOtherThing;
		\\void main() {gl_Position = vec4(mc_Entity.x);}
		\\
	;
	const result = transform(testingAllocator, source, .{
		.stage = .vertex,
		.prologue = "vec4 mc_Entity;\nvec4 mc_midTexCoord;\n",
		.strippedAttributes = &.{"mc_Entity", "mc_midTexCoord", "at_tangent"},
	});
	defer testingAllocator.free(result);

	// The prologue's definitions survive; the pack's duplicate declarations do not.
	try testing.expect(std.mem.indexOf(u8, result, "in vec4 mc_Entity;") == null);
	try testing.expect(std.mem.indexOf(u8, result, "in vec4 mc_midTexCoord;") == null);
	try testing.expect(std.mem.indexOf(u8, result, "vec4 mc_Entity;\nvec4 mc_midTexCoord;") != null);
	// Unrelated attributes are left alone, and uses of the stripped names still resolve.
	try testing.expect(std.mem.indexOf(u8, result, "in vec4 someOtherThing;") != null);
	try testing.expect(std.mem.indexOf(u8, result, "vec4(mc_Entity.x)") != null);
}

test "an attribute's declared type is read back at whatever width the pack chose" {
	// photon and Sundial Lite declare these narrower than the four packs this bridge grew up
	// against, and GLSL has no implicit narrowing, so the prologue has to follow the pack.
	const source =
		\\attribute vec2 mc_midTexCoord;
		\\attribute vec3 mc_Entity;
		\\attribute vec4 at_tangent;
		\\void main() {gl_Position = vec4(mc_Entity.x);}
		\\
	;
	try testing.expectEqualStrings("vec2", declaredType(testingAllocator, source, "mc_midTexCoord").?);
	try testing.expectEqualStrings("vec3", declaredType(testingAllocator, source, "mc_Entity").?);
	try testing.expectEqualStrings("vec4", declaredType(testingAllocator, source, "at_tangent").?);
	// A name the source never declares has no answer, so the caller can fall back rather than
	// being handed a confident wrong width.
	try testing.expect(declaredType(testingAllocator, source, "mc_notDeclared") == null);
}

test "the type lookup accepts exactly what the stripper deletes" {
	// The two must agree: the prologue declares a replacement for precisely the declarations the
	// stripper removes, so a form one accepts and the other does not leaves either a duplicate
	// declaration or a replacement at the wrong type.
	const forms = [_][]const u8{
		"attribute vec2 mc_midTexCoord;\n",
		"in vec2 mc_midTexCoord;\n",
		"  attribute   vec2   mc_midTexCoord  ;\n",
		"attribute vec2 mc_midTexCoord; // trailing comment\n",
	};
	for(forms) |source| {
		try testing.expectEqualStrings("vec2", declaredType(testingAllocator, source, "mc_midTexCoord").?);

		const result = transform(testingAllocator, source, .{
			.stage = .vertex,
			.strippedAttributes = &.{"mc_midTexCoord"},
		});
		defer testingAllocator.free(result);
		try testing.expect(std.mem.indexOf(u8, result, "mc_midTexCoord;") == null);
	}
}

test "a declaration behind a conditional is still found" {
	// `#if` is deliberately not evaluated here, and the stripper removes both branches, so the
	// first declaration is the best answer available rather than an arbitrary one.
	const source =
		\\#ifdef MODERN
		\\attribute vec2 mc_midTexCoord;
		\\#else
		\\attribute vec4 mc_midTexCoord;
		\\#endif
		\\
	;
	try testing.expectEqualStrings("vec2", declaredType(testingAllocator, source, "mc_midTexCoord").?);
}

test "the entry point can be renamed so generated code can wrap it" {
	const source = "void main() {gl_Position = vec4(0.0);}\n";
	const result = transform(testingAllocator, source, .{.stage = .vertex, .entryPointName = "cubyz_packMain"});
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "void cubyz_packMain() {") != null);
	try testing.expect(std.mem.indexOf(u8, result, "void main()") == null);
}

test "uniform declarations the prologue replaces are stripped" {
	const source =
		\\uniform sampler2D gtexture;
		\\uniform sampler2D lightmap;
		\\void main() {}
		\\
	;
	const result = transform(testingAllocator, source, .{.stage = .fragment, .strippedAttributes = &.{"gtexture"}});
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "gtexture;") == null);
	// A sampler the prologue does not supply must survive, or the pack references an undeclared name.
	try testing.expect(std.mem.indexOf(u8, result, "uniform sampler2D lightmap;") != null);
}

test "sampling calls are redirected only when they target an array sampler" {
	// The property that matters: the same program samples the block texture (an array) and the
	// lightmap and depth buffer (ordinary 2D). Redirecting all of them, or none, is wrong.
	const source =
		\\void main() {
		\\    vec4 a = texture(gtexture, uv);
		\\    vec4 b = texture(gtexture, uv, 0);
		\\    vec4 c = texture2D(gtexture, uv);
		\\    vec4 d = texture(lightmap, lmcoord);
		\\    float e = texture(depthtex0, uv).r;
		\\}
		\\
	;
	const result = transform(testingAllocator, source, .{
		.stage = .fragment,
		.arraySamplers = &.{.{.sampler = "gtexture", .function = "cubyz_sampleArray", .lodFunction = "cubyz_sampleArrayLod", .gradFunction = "cubyz_sampleArrayGrad", .fetchFunction = "cubyz_fetchArray"}},
	});
	defer testingAllocator.free(result);

	try testing.expect(std.mem.indexOf(u8, result, "cubyz_sampleArray(gtexture, uv)") != null);
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_sampleArray(gtexture, uv, 0)") != null);
	// `texture2D` targeting the array is redirected too, rather than going through the 2D shim.
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_sampleArray(gtexture, uv);") != null);
	// Genuine 2D samplers are untouched.
	try testing.expect(std.mem.indexOf(u8, result, "texture(lightmap, lmcoord)") != null);
	try testing.expect(std.mem.indexOf(u8, result, "texture(depthtex0, uv).r") != null);
}

test "a bias, a level and a gradient reach three different helpers" {
	// `texture(s, c, x)` and `textureLod(s, c, x)` are the same shape and mean different things, so
	// one helper name cannot carry both. Collapsing them made every `textureLod` on the block
	// texture sample with a bias - a wrong mip level, and never an error.
	const source =
		\\void main() {
		\\    vec4 a = texture(gtexture, uv, 1.0);
		\\    vec4 b = textureLod(gtexture, uv, 1.0);
		\\    vec4 c = textureGrad(gtexture, uv, dx, dy);
		\\    vec4 d = texture2DLod(gtexture, uv, 1.0);
		\\}
		\\
	;
	const result = transform(testingAllocator, source, .{
		.stage = .fragment,
		.arraySamplers = &.{.{.sampler = "gtexture", .function = "cubyz_sampleArray", .lodFunction = "cubyz_sampleArrayLod", .gradFunction = "cubyz_sampleArrayGrad", .fetchFunction = "cubyz_fetchArray"}},
	});
	defer testingAllocator.free(result);

	try testing.expect(std.mem.indexOf(u8, result, "cubyz_sampleArray(gtexture, uv, 1.0)") != null);
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_sampleArrayLod(gtexture, uv, 1.0)") != null);
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_sampleArrayGrad(gtexture, uv, dx, dy)") != null);
	// The legacy spelling carries the same meaning as the modern one.
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_sampleArrayLod(gtexture, uv, 1.0);") != null);
}

test "the prologue declares every helper the redirect can emit" {
	// The redirect names a helper; the prologue has to have written it. photon's `gbuffers_water`
	// failed on exactly this gap - the rewrite fired correctly and landed on
	// `cubyz_sampleArray(sampler2DArray, vec2, vec2, vec2)`, which nobody had declared.
	const fragment = @import("prologue.zig").terrainFragment(testingAllocator, true);
	defer testingAllocator.free(fragment);

	for(@import("prologue.zig").arraySamplers) |redirect| {
		for([_][]const u8{redirect.function, redirect.lodFunction, redirect.gradFunction, redirect.fetchFunction}) |helper| {
			var needle: [64]u8 = undefined;
			const declaration = try std.fmt.bufPrint(&needle, "vec4 {s}(", .{helper});
			try testing.expect(std.mem.indexOf(u8, fragment, declaration) != null);
		}
	}
}

test "a stripped name is cut out of a declarator list and the rest survives" {
	// Solas: `uniform sampler2D gtexture, noisetex;`. The block sampler goes, the noise stays,
	// and the result has to be a well-formed declaration whichever position the stripped name held.
	// Compared with whitespace removed: cutting tokens leaves the spaces around them, which is
	// legal GLSL and not the property under test. What matters is the token sequence.
	const cases = [_]struct {source: []const u8, expected: []const u8}{
		.{.source = "uniform sampler2D gtexture, noisetex;\n", .expected = "uniformsampler2Dnoisetex;"},
		.{.source = "uniform sampler2D noisetex, gtexture;\n", .expected = "uniformsampler2Dnoisetex;"},
		.{.source = "uniform sampler2D a, gtexture, b;\n", .expected = "uniformsampler2Da,b;"},
		.{.source = "uniform sampler2D gtexture, tex, b;\n", .expected = "uniformsampler2Db;"},
	};
	for(cases) |case| {
		const result = transform(testingAllocator, case.source, .{.stage = .fragment, .strippedAttributes = &.{"gtexture", "tex"}});
		defer testingAllocator.free(result);
		var squeezed = List(u8).init(testingAllocator);
		defer squeezed.deinit();
		for(result) |char| if(!std.ascii.isWhitespace(char)) squeezed.append(char);
		try testing.expect(std.mem.indexOf(u8, squeezed.items, case.expected) != null);
		try testing.expect(std.mem.indexOf(u8, result, "gtexture") == null);
	}
	// And a list whose every name is stripped goes entirely.
	const all = transform(testingAllocator, "uniform sampler2D gtexture, tex;\nvoid main() {}\n", .{.stage = .fragment, .strippedAttributes = &.{"gtexture", "tex"}});
	defer testingAllocator.free(all);
	try testing.expect(std.mem.indexOf(u8, all, "uniform sampler2D") == null);
}

test "the ARB and 2D-suffixed legacy sampling names get shims, as Iris renames them" {
	const source =
		\\void main() {
		\\    vec4 a = texture2DGradARB(noisetex, uv, dx, dy);
		\\    vec4 b = texelFetch2D(noisetex, ivec2(1, 2), 0);
		\\    ivec2 s = textureSize2D(noisetex, 0);
		\\}
		\\
	;
	const result = transform(testingAllocator, source, .{.stage = .fragment});
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_texture2DGradARB(noisetex, uv, dx, dy)") != null);
	try testing.expect(std.mem.indexOf(u8, result, "vec4 cubyz_texture2DGradARB(sampler2D s, vec2 c, vec2 dx, vec2 dy)") != null);
	try testing.expect(std.mem.indexOf(u8, result, "vec4 cubyz_texelFetch2D(sampler2D s, ivec2 c, int l)") != null);
	try testing.expect(std.mem.indexOf(u8, result, "ivec2 cubyz_textureSize2D(sampler2D s, int l)") != null);
}

test "texelFetch on the block texture is redirected to the integer-coordinate helper" {
	// Complementary's lava brightness average, in shape: a texel fetch against `tex` with integer
	// coordinates and a level. Sending it through the `texture` helper would treat integer texels
	// as normalised coordinates, so it needs a flavour of its own.
	const source =
		\\void main() {
		\\    vec3 a = texelFetch(tex, ivec2(3, 4) + ivec2(x, y), 0).rgb;
		\\    vec4 b = texelFetch(lightmap, ivec2(1, 1), 0);
		\\}
		\\
	;
	const result = transform(testingAllocator, source, .{
		.stage = .fragment,
		.arraySamplers = &.{.{.sampler = "tex", .function = "cubyz_sampleArray", .lodFunction = "cubyz_sampleArrayLod", .gradFunction = "cubyz_sampleArrayGrad", .fetchFunction = "cubyz_fetchArray"}},
	});
	defer testingAllocator.free(result);

	try testing.expect(std.mem.indexOf(u8, result, "cubyz_fetchArray(tex, ivec2(3, 4) + ivec2(x, y), 0)") != null);
	// A fetch against a genuinely 2D sampler in the same program is left alone.
	try testing.expect(std.mem.indexOf(u8, result, "texelFetch(lightmap, ivec2(1, 1), 0)") != null);
}

test "a geometry stage declares its compat varyings per input vertex" {
	const source =
		\\void main() {gl_Position = gl_in[0].gl_Position; float f = gl_FogFragCoord;}
		\\
	;
	const result = transform(testingAllocator, source, .{.stage = .geometry});
	defer testingAllocator.free(result);

	try testing.expect(std.mem.indexOf(u8, result, "in float cubyz_FogFragCoord[3];") != null);
	// `gl_in` is a core built-in and must survive the compat rewrite untouched.
	try testing.expect(std.mem.indexOf(u8, result, "gl_in[0].gl_Position") != null);
}

test "a sampling call inside a pack's own macro is dispatched by type" {
	// photon's idiom, and Kappa's and Nostalgia's under a different name. The callee at the call
	// site is the macro, so nothing can fire there; inside the body the sampler is `x`, which names
	// no particular sampler because the same macro is invoked with three different ones.
	const source =
		\\#define read_tex(x) texture(x, uv, lod_bias)
		\\#define read_tex_grad(x) textureGrad(x, uv, dx, dy)
		\\#define stexLod(x, lod) textureLod(x, uv, lod)
		\\void main() {
		\\    vec4 a = read_tex(gtexture);
		\\    vec4 b = read_tex(normals);
		\\    vec4 c = read_tex_grad(gtexture);
		\\    vec4 d = stexLod(gtexture, 2.0);
		\\}
		\\
	;
	const result = transform(testingAllocator, source, .{
		.stage = .fragment,
		.arraySamplers = &.{.{.sampler = "gtexture", .function = "cubyz_sampleArray", .lodFunction = "cubyz_sampleArrayLod", .gradFunction = "cubyz_sampleArrayGrad", .fetchFunction = "cubyz_fetchArray"}},
		.macroDispatch = .{.function = "cubyz_sampleAny", .lodFunction = "cubyz_sampleAnyLod", .gradFunction = "cubyz_sampleAnyGrad", .fetchFunction = "cubyz_fetchAny"},
	});
	defer testingAllocator.free(result);

	// The macro *bodies* are redirected, each to the helper for its own flavour.
	try testing.expect(std.mem.indexOf(u8, result, "#define read_tex(x) cubyz_sampleAny(x, uv, lod_bias)") != null);
	try testing.expect(std.mem.indexOf(u8, result, "#define read_tex_grad(x) cubyz_sampleAnyGrad(x, uv, dx, dy)") != null);
	try testing.expect(std.mem.indexOf(u8, result, "#define stexLod(x, lod) cubyz_sampleAnyLod(x, uv, lod)") != null);
	// The call sites are untouched - rewriting the callee there would destroy the argument list.
	try testing.expect(std.mem.indexOf(u8, result, "read_tex(gtexture)") != null);
	try testing.expect(std.mem.indexOf(u8, result, "read_tex(normals)") != null);
}

test "the macro dispatch leaves ordinary calls to the per-sampler redirect" {
	// The dispatch is a fallback for what cannot be named, not a replacement. A call naming the
	// block texture outright must still reach the specific helper, or the LabPBR synthesis for
	// `specular` would be lost everywhere rather than only inside a macro.
	const source =
		\\void main() {
		\\    vec4 a = texture(gtexture, uv);
		\\    vec4 b = texture(specular, uv);
		\\    vec4 c = texture(colortex0, uv);
		\\}
		\\
	;
	const result = transform(testingAllocator, source, .{
		.stage = .fragment,
		.arraySamplers = &.{
			.{.sampler = "gtexture", .function = "cubyz_sampleArray", .lodFunction = "cubyz_sampleArrayLod", .gradFunction = "cubyz_sampleArrayGrad", .fetchFunction = "cubyz_fetchArray"},
			.{.sampler = "specular", .function = "cubyz_sampleSpecular", .lodFunction = "cubyz_sampleSpecular", .gradFunction = "cubyz_sampleSpecular", .fetchFunction = "cubyz_sampleSpecular"},
		},
		.macroDispatch = .{.function = "cubyz_sampleAny", .lodFunction = "cubyz_sampleAnyLod", .gradFunction = "cubyz_sampleAnyGrad", .fetchFunction = "cubyz_fetchAny"},
	});
	defer testingAllocator.free(result);

	try testing.expect(std.mem.indexOf(u8, result, "cubyz_sampleArray(gtexture, uv)") != null);
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_sampleSpecular(specular, uv)") != null);
	// An ordinary 2D sampler outside a macro is not a macro parameter, so nothing fires.
	try testing.expect(std.mem.indexOf(u8, result, "texture(colortex0, uv)") != null);
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_sampleAny(colortex0") == null);
}

test "an object-like macro is not mistaken for a function-like one" {
	// `#define NAME (body)` with a space is object-like; its `(` opens the body, not a parameter
	// list. Treating it as function-like would make `x` look like a parameter of whatever came
	// before it.
	const source =
		\\#define WRAPPED (texture(x, uv))
		\\
	;
	const result = transform(testingAllocator, source, .{
		.stage = .fragment,
		.arraySamplers = &.{.{.sampler = "gtexture", .function = "cubyz_sampleArray", .lodFunction = "cubyz_sampleArrayLod", .gradFunction = "cubyz_sampleArrayGrad", .fetchFunction = "cubyz_fetchArray"}},
		.macroDispatch = .{.function = "cubyz_sampleAny", .lodFunction = "cubyz_sampleAnyLod", .gradFunction = "cubyz_sampleAnyGrad", .fetchFunction = "cubyz_fetchAny"},
	});
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_sampleAny") == null);
}

test "a post-chain pass keeps its macro sampling untouched" {
	// Kappa and Nostalgia define `stex(x) texture(x, uv)` and use it throughout their deferred and
	// composite programs with ordinary colortex samplers. Those passes have no prologue, so the
	// helpers do not exist there - rewriting would break four working packs to fix one. Absent
	// `macroDispatch`, and absent `arraySamplers`, nothing fires.
	const source =
		\\#define stex(x) texture(x, uv)
		\\void main() {vec4 a = stex(colortex0);}
		\\
	;
	const result = transform(testingAllocator, source, .{.stage = .fragment});
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "#define stex(x) texture(x, uv)") != null);
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_sample") == null);
}

test "a sampler name appearing outside a call is not mistaken for one" {
	const source = "void main() {vec2 gtexture_size = vec2(1.0); float x = gtexture_size.x;}\n";
	const result = transform(testingAllocator, source, .{
		.stage = .fragment,
		.arraySamplers = &.{.{.sampler = "gtexture", .function = "cubyz_sampleArray", .lodFunction = "cubyz_sampleArrayLod", .gradFunction = "cubyz_sampleArrayGrad", .fetchFunction = "cubyz_fetchArray"}},
	});
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_sampleArray") == null);
	try testing.expect(std.mem.indexOf(u8, result, "gtexture_size") != null);
}

test "each redirected sampler gets its own helper" {
	// The block texture and the material maps are all redirected, but to different helpers: one is
	// a real array lookup, the others synthesise a LabPBR encoding from Cubyz's material arrays.
	const source =
		\\void main() {
		\\    vec4 albedo = texture2D(gtexture, uv);
		\\    vec4 spec = texture2D(specular, uv);
		\\    vec4 norm = texture2D(normals, uv);
		\\}
		\\
	;
	const result = transform(testingAllocator, source, .{
		.stage = .fragment,
		.arraySamplers = &.{
			.{.sampler = "gtexture", .function = "cubyz_sampleArray", .lodFunction = "cubyz_sampleArrayLod", .gradFunction = "cubyz_sampleArrayGrad", .fetchFunction = "cubyz_fetchArray"},
			.{.sampler = "specular", .function = "cubyz_sampleSpecular", .lodFunction = "cubyz_sampleSpecularLod", .gradFunction = "cubyz_sampleSpecularGrad", .fetchFunction = "cubyz_sampleSpecularFetch"},
			.{.sampler = "normals", .function = "cubyz_sampleNormals", .lodFunction = "cubyz_sampleNormalsLod", .gradFunction = "cubyz_sampleNormalsGrad", .fetchFunction = "cubyz_sampleNormalsFetch"},
		},
	});
	defer testingAllocator.free(result);

	try testing.expect(std.mem.indexOf(u8, result, "cubyz_sampleArray(gtexture, uv)") != null);
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_sampleSpecular(specular, uv)") != null);
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_sampleNormals(normals, uv)") != null);
}

test "a pack that calls core texture() keeps it" {
	const source = "uniform sampler2D gtexture;\nvoid main() {gl_FragColor = texture(gtexture, vec2(0.0));}\n";
	const result = transform(testingAllocator, source, .{.stage = .fragment});
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "texture(gtexture, vec2(0.0))") != null);
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_textureUnit") == null);
}

test "an integer clamp bound beside a float literal is made explicit for the driver" {
	// Bliss, `lib/volumetricClouds.glsl:444`. NVIDIA reports `clamp(float, float, int)` as
	// ambiguous against its float64 overloads; the int is the only argument that can be, so it is.
	const source = "int maxIT = 8;\nvoid main() {maxIT = int(clamp(maxIT / sqrt(x), 0.0, maxIT));}\n";
	const result = transform(testingAllocator, source, .{.stage = .fragment});
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "clamp(maxIT / sqrt(x), 0.0, float(maxIT))") != null);
	// The declaration and the arithmetic use are not bounds and stay as written.
	try testing.expect(std.mem.indexOf(u8, result, "int maxIT = 8;") != null);
	try testing.expect(std.mem.indexOf(u8, result, "float(maxIT) /") == null);
	// No line was added or lost: the driver's line numbers still index the dump.
	try testing.expectEqual(std.mem.count(u8, source, "\n"), std.mem.count(u8, result[std.mem.indexOf(u8, result, "shaderpack source ----\n").? + "shaderpack source ----\n".len ..], "\n"));
}

test "either clamp bound can be the literal, and an integer literal is wrapped too" {
	const source = "void main() {float a = clamp(x, lo, 1.0); float b = clamp(x, 0.0, 30); float c = clamp(x,1e-3,hi);}\n";
	const result = transform(testingAllocator, source, .{.stage = .fragment});
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "clamp(x, float(lo), 1.0)") != null);
	try testing.expect(std.mem.indexOf(u8, result, "clamp(x, 0.0, float(30))") != null);
	try testing.expect(std.mem.indexOf(u8, result, "clamp(x,1e-3,float(hi))") != null);
}

test "the alpha test is appended after the pack's main, declaring the reference only when the pack has not" {
	const source = "void main() {gl_FragData[0] = vec4(1.0, 0.0, 0.0, 0.0);}\n";
	const result = transform(testingAllocator, source, .{.stage = .fragment, .alphaTest = true, .entryPointName = "cubyz_packMain"});
	defer testingAllocator.free(result);
	const packMain = std.mem.indexOf(u8, result, "void cubyz_packMain() {").?;
	const wrapper = std.mem.indexOf(u8, result, "void main() {\n\tcubyz_packMain();\n\tif(!(cubyz_FragData[0].a > alphaTestRef)) {\n\t\tdiscard;").?;
	try testing.expect(packMain < wrapper);
	try testing.expect(std.mem.indexOf(u8, result, "uniform float alphaTestRef;") != null);

	// A pack that declares the uniform itself keeps its declaration and gets no second one.
	const declared = "uniform float alphaTestRef;\nvoid main() {gl_FragColor = vec4(1.0);}\n";
	const result2 = transform(testingAllocator, declared, .{.stage = .fragment, .alphaTest = true, .entryPointName = "cubyz_packMain"});
	defer testingAllocator.free(result2);
	try testing.expectEqual(@as(usize, 1), std.mem.count(u8, result2, "uniform float alphaTestRef;"));
	try testing.expect(std.mem.indexOf(u8, result2, "cubyz_FragData[0].a > alphaTestRef") != null);
}

test "an alpha test override picks the comparison, never discards outright, and always injects nothing" {
	// `alphaTest.<program> = LEQUAL 0.5` and friends (`ShaderProperties.java:255-290`), which Iris
	// injects with the named comparison; `NEVER` is a bare `discard;` and `ALWAYS` is no test at
	// all, whatever the program's default would have been.
	const source = "void main() {gl_FragData[0] = vec4(1.0, 0.0, 0.0, 0.0);}\n";
	const lequal = transform(testingAllocator, source, .{.stage = .fragment, .alphaTest = true, .alphaTestFunction = .lequal, .entryPointName = "cubyz_packMain"});
	defer testingAllocator.free(lequal);
	try testing.expect(std.mem.indexOf(u8, lequal, "if(!(cubyz_FragData[0].a <= alphaTestRef)) {") != null);

	const never = transform(testingAllocator, source, .{.stage = .fragment, .alphaTest = true, .alphaTestFunction = .never, .entryPointName = "cubyz_packMain"});
	defer testingAllocator.free(never);
	try testing.expect(std.mem.indexOf(u8, never, "void main() {\n\tcubyz_packMain();\n\tdiscard;\n}") != null);
	try testing.expect(std.mem.indexOf(u8, never, "alphaTestRef") == null);

	const always = transform(testingAllocator, source, .{.stage = .fragment, .alphaTest = true, .alphaTestFunction = .always, .entryPointName = "cubyz_packMain"});
	defer testingAllocator.free(always);
	try testing.expect(std.mem.indexOf(u8, always, "discard") == null);
	try testing.expect(std.mem.indexOf(u8, always, "cubyz_packMain") == null);

	try testing.expectEqual(AlphaTestFunction.greater, AlphaTestFunction.parse("GREATER").?);
	try testing.expectEqual(AlphaTestFunction.always, AlphaTestFunction.parse("GL_ALWAYS").?);
	try testing.expectEqual(AlphaTestFunction.gequal, AlphaTestFunction.parse("gequal").?);
	try testing.expect(AlphaTestFunction.parse("SOMETIMES") == null);
}

test "no alpha test where Iris applies none: translucents, vertex stages, core-style outputs" {
	const source = "void main() {gl_FragData[0] = vec4(1.0);}\n";
	const off = transform(testingAllocator, source, .{.stage = .fragment});
	defer testingAllocator.free(off);
	try testing.expect(std.mem.indexOf(u8, off, "discard") == null);
	try testing.expect(std.mem.indexOf(u8, off, "void main() {gl_FragData") == null or std.mem.indexOf(u8, off, "cubyz_FragData[0] = vec4(1.0);") != null);

	const vertex = transform(testingAllocator, "void main() {gl_Position = vec4(1.0);}\n", .{.stage = .vertex, .alphaTest = true, .entryPointName = "cubyz_packMain"});
	defer testingAllocator.free(vertex);
	try testing.expect(std.mem.indexOf(u8, vertex, "discard") == null);

	// A program writing its own `out` variable never wrote `gl_FragData[0]`, which is the one
	// thing Iris's injection keys on. Its `main` must then stay `main`: renamed with no wrapper,
	// the stage has no entry point, compiles, and fails to link (Kappa, Nostalgia and photon on
	// 2026-09-04).
	const core = transform(testingAllocator, "out vec4 outColor;\nvoid main() {outColor = vec4(1.0);}\n", .{.stage = .fragment, .alphaTest = true, .entryPointName = "cubyz_packMain"});
	defer testingAllocator.free(core);
	try testing.expect(std.mem.indexOf(u8, core, "discard") == null);
	try testing.expect(std.mem.indexOf(u8, core, "void main() {outColor = vec4(1.0);}") != null);
	try testing.expect(std.mem.indexOf(u8, core, "cubyz_packMain") == null);

	// Slot 1 alone is not slot 0: the test would read an output nothing wrote.
	const slotOne = transform(testingAllocator, "void main() {gl_FragData[1] = vec4(1.0);}\n", .{.stage = .fragment, .alphaTest = true, .entryPointName = "cubyz_packMain"});
	defer testingAllocator.free(slotOne);
	try testing.expect(std.mem.indexOf(u8, slotOne, "discard") == null);
	try testing.expectEqual(@as(usize, 1), std.mem.count(u8, slotOne, "void main()"));
	try testing.expect(std.mem.indexOf(u8, slotOne, "cubyz_packMain") == null);
}

test "clamp bounds that give the driver nothing to infer are left alone" {
	// Both literal; neither literal; a compound bound; a member; an array element; an int literal
	// beside an identifier, which may be the integer family; a hex literal, whose `E` is a digit;
	// a call with conditional arguments; and a macro body, whose parameter has no one type.
	const source =
		\\#define SAT(v, m) clamp(v, 0.0, m)
		\\void main() {
		\\    float a = clamp(x, 0.0, 1.0);
		\\    float b = clamp(x, lo, hi);
		\\    float c = clamp(x, 0.0, hi + 1);
		\\    float d = clamp(x, 0.0, v.x);
		\\    float e = clamp(x, 0.0, arr[2]);
		\\    float f = clamp(x, 0, maxIT);
		\\    float g = clamp(x, 0x1E, maxIT);
		\\    float h = clamp(x,
		\\#ifdef A
		\\        0.0,
		\\#else
		\\        1.0,
		\\#endif
		\\        maxIT);
		\\}
		\\
	;
	const result = transform(testingAllocator, source, .{.stage = .fragment});
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "float(") == null);
}

test "a compute stage keeps the pack's version, made core, with no draw-stage shim" {
	// Nostalgic Red Voxels' shape: a local size, an image, a `workGroups` directive and a legacy
	// sampling call in a header the draw stages share.
	const source =
		\\#version 430
		\\layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
		\\layout(rgba16f) uniform image3D distanceFieldI;
		\\uniform sampler2D noisetex;
		\\const ivec3 workGroups = ivec3(4, 4, 4);
		\\void main() {
		\\    vec4 n = texture2D(noisetex, vec2(0.5));
		\\    imageStore(distanceFieldI, ivec3(gl_GlobalInvocationID), n);
		\\}
		\\
	;
	const result = transform(testingAllocator, source, .{.stage = .compute});
	defer testingAllocator.free(result);
	try testing.expect(std.mem.startsWith(u8, result, "#version 430 core\n"));
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_FragData") == null);
	try testing.expect(std.mem.indexOf(u8, result, "in vec4 cubyz_") == null);
	try testing.expect(std.mem.indexOf(u8, result, "layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;") != null);
	try testing.expect(std.mem.indexOf(u8, result, "const ivec3 workGroups = ivec3(4, 4, 4);") != null);
	// The legacy sampling function is shimmed as in every other stage, and its bias overload takes
	// the explicit-level form, since only a fragment stage may pass a bias.
	try testing.expect(std.mem.indexOf(u8, result, "cubyz_texture2D(noisetex, vec2(0.5))") != null);
	try testing.expect(std.mem.indexOf(u8, result, "vec4 cubyz_texture2D(sampler2D s, vec2 c, float b) {return textureLod(s, c, b);}") != null);
}

test "storage block bindings are relocated past the engine's, images and uniform blocks untouched" {
	// The three spellings in the corpus - Nostalgic Red Voxels' macro qualifier, Complementary's,
	// and a bare one - then the two neighbours that must not move, and a macro binding that cannot.
	const source =
		\\#version 430
		\\layout(std430, binding=0) WRITE_TO_SSBOS buffer stuff {mat4 m; uint data[];};
		\\layout(std430, binding = 3) SSBO_QUALIFIER buffer playerVerticesBuffer {vec3 v[216];} playerVerticesSSBO;
		\\layout(binding = 2) buffer plain {uint x[];};
		\\layout(r32i, binding = 2) uniform iimage3D occupancyVolume;
		\\layout(std140, binding = 1) uniform Block {vec4 q;};
		\\layout(std430, binding = SOME_MACRO) buffer named {uint y[];};
		\\void main() {}
		\\
	;
	const result = transform(testingAllocator, source, .{.stage = .compute, .storageBindingBase = 16});
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "layout(std430, binding=16) WRITE_TO_SSBOS buffer stuff") != null);
	try testing.expect(std.mem.indexOf(u8, result, "layout(std430, binding = 19) SSBO_QUALIFIER buffer playerVerticesBuffer") != null);
	try testing.expect(std.mem.indexOf(u8, result, "layout(binding = 18) buffer plain") != null);
	try testing.expect(std.mem.indexOf(u8, result, "layout(r32i, binding = 2) uniform iimage3D") != null);
	try testing.expect(std.mem.indexOf(u8, result, "layout(std140, binding = 1) uniform Block") != null);
	try testing.expect(std.mem.indexOf(u8, result, "binding = SOME_MACRO) buffer named") != null);

	// Without a base nothing moves, which is what a draw stage of a pack with no buffers gets.
	const untouched = transform(testingAllocator, source, .{.stage = .compute});
	defer testingAllocator.free(untouched);
	try testing.expect(std.mem.indexOf(u8, untouched, "binding=0) WRITE_TO_SSBOS") != null);
	try testing.expect(std.mem.indexOf(u8, untouched, "binding = 3) SSBO_QUALIFIER") != null);
}
