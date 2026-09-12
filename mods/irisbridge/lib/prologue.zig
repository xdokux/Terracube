//! Synthesises Minecraft's vertex inputs from Cubyz's SSBO pull.
//!
//! This is the piece that makes a pack's own `gbuffers_terrain` runnable on Cubyz geometry, and it
//! is the hardest bridge in the mod. Cubyz's terrain has no vertex buffer at all: every
//! attribute is unpacked in the vertex shader from SSBOs indexed by `gl_VertexID` and
//! `gl_BaseInstance` (see `assets/cubyz/shaders/chunks/chunk_vertex.vert`). Pack shaders are
//! written against `gl_Vertex`, `gl_Normal`, `gl_MultiTexCoord0/1`, `mc_Entity`, `mc_midTexCoord`
//! and `at_tangent`, none of which can exist as real attributes here.
//!
//! So the prologue performs the same SSBO pull Cubyz does, then *computes* each of those names as
//! an ordinary global. The pack's `main` is renamed by the transformer, and the `main` generated
//! here runs the setup before calling it - there is no way to inject a statement into the top of
//! someone else's function, and this avoids trying.
//!
//! The SSBO layouts below are duplicated from Cubyz's own shaders. That duplication is a real
//! maintenance hazard: if `chunk_meshing.zig` changes its buffer layout, this silently reads
//! garbage rather than failing to compile. `bindingsMatchEngine` documents the coupling, and the
//! layouts are kept byte-identical to the originals so a diff against them is meaningful.

const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const List = main.ListManaged;

const glsl = @import("glsl.zig");

const lightmap = @import("lightmap.zig");

/// The name the pack's own `main` is renamed to.
pub const packEntryPoint = "cubyz_packMain";

/// Attribute declarations that must be stripped from pack source, because the prologue defines
/// them as computed globals instead.
pub const suppliedAttributes = [_][]const u8{
	"mc_Entity",
	"mc_midTexCoord",
	"at_tangent",
	// The vector from the vertex to its block's centre, in sixty-fourths of a block. Kappa and
	// Nostalgia hinge wind displacement on it; Complementary voxelises with it. Unfed, an attribute
	// reads (0, 0, 0), so every vertex claimed to sit at its block's centre.
	"at_midBlock",
};

/// The widths the pack itself declares for those three attributes.
///
/// They are pack-declared names rather than `gl_` built-ins, so the width is the pack's choice and
/// not this bridge's. The prologue used to declare all three as `vec4` - which is what the four
/// packs it grew up against happen to write - and GLSL has no implicit narrowing, so a pack that
/// declares one narrower loses its whole program:
///
///     photon_v1.3b/shaders/program/gbuffers_all_translucent.vsh:42   attribute vec2 mc_midTexCoord;
///     ...:156   vec2 uv_minus_mid = uv - mc_midTexCoord;
///     ...:157   atlas_tile_offset = min(uv, mc_midTexCoord - uv_minus_mid);
///
///     gbuffers_water (vert) failed to compile:
///     0(3195) : error C7011: implicit cast from "vec4" to "vec2"
///     0(3196) : error C7011: implicit cast from "vec4" to "vec2"
///
/// Across the six extracted packs, `mc_Entity` is declared `vec4` 28 times, `vec3` three times and
/// `vec2` twice; `mc_midTexCoord` `vec4` 23 times and `vec2` five times; `at_tangent` is always
/// `vec4`. Both packs added since this bridge was written are in the minority, which is the
/// conformance argument arriving again: a rule that held for every pack tested so far is not the
/// same thing as a correct one.
///
/// `vec4` stays the default for a source that never declares the name - nothing there reads it, and
/// the widest type is what every other pack expects.
pub const AttributeTypes = struct {
	entity: []const u8 = "vec4",
	midTexCoord: []const u8 = "vec4",
	tangent: []const u8 = "vec4",
	/// `vec3` in four of the five packs; Iris widens it to `vec4` only for the block-emission
	/// feature, which this bridge does not advertise.
	midBlock: []const u8 = "vec3",

	/// Reads the widths back out of the pack's own already-include-resolved vertex source.
	///
	/// The lookup shares its matcher with the stripper that deletes these very declarations
	/// (`glsl.matchDeclaration`), so a replacement cannot be emitted at a different type from the
	/// declaration it replaces.
	///
	/// The result borrows from `source`, which must outlive it.
	pub fn fromSource(allocator: NeverFailingAllocator, source: []const u8) AttributeTypes {
		return .{
			.entity = glsl.declaredType(allocator, source, "mc_Entity") orelse "vec4",
			.midTexCoord = glsl.declaredType(allocator, source, "mc_midTexCoord") orelse "vec4",
			.tangent = glsl.declaredType(allocator, source, "at_tangent") orelse "vec4",
			.midBlock = glsl.declaredType(allocator, source, "at_midBlock") orelse "vec3",
		};
	}

	fn writeDeclarations(self: AttributeTypes, out: *List(u8)) void {
		out.print("{s} mc_Entity;\n{s} mc_midTexCoord;\n{s} at_tangent;\n{s} at_midBlock;\n", .{self.entity, self.midTexCoord, self.tangent, self.midBlock});
	}

	/// Whether this pack asked for anything other than the `vec4` the prologue used to assume.
	///
	/// Only so the load can say so. A fix whose consequence is never logged cannot be told apart
	/// from a no-op - both leave a working pack working - and this one is invisible in the image by
	/// design: it either compiles or it does not.
	pub fn differFromDefault(self: AttributeTypes) bool {
		const default = AttributeTypes{};
		return !std.mem.eql(u8, self.entity, default.entity) or
			!std.mem.eql(u8, self.midTexCoord, default.midTexCoord) or
			!std.mem.eql(u8, self.tangent, default.tangent) or
			!std.mem.eql(u8, self.midBlock, default.midBlock);
	}
};

/// The swizzle that narrows the prologue's computed `vec4` to the width the pack declared.
///
/// A swizzle rather than a per-width constructor because it is one rule for every case and it keeps
/// the value's construction in one place: the prologue computes the same full `vec4` it always did,
/// and only the hand-over to the pack's name narrows.
///
/// An unrecognised type gets no swizzle, so it fails exactly as it does today - loudly, at compile
/// time, in the dumped source - rather than being silently reinterpreted.
fn narrowTo(declared: []const u8) []const u8 {
	if(std.mem.eql(u8, declared, "vec3")) return ".xyz";
	if(std.mem.eql(u8, declared, "vec2")) return ".xy";
	if(std.mem.eql(u8, declared, "float")) return ".x";
	return "";
}

/// SSBO binding points, copied from `src/renderer/chunk_meshing.zig`.
///
/// If those change, the prologue reads the wrong buffers, and nothing in the type system catches
/// it: a binding mismatch reads whichever buffer happened to be bound there and produces
/// plausible-looking nonsense rather than an error. The declarations in `ssboDeclarations` spell
/// the numbers out, so `checkSsboBindings` below asserts at compile time that the two agree.
pub const bindingsMatchEngine = struct {
	pub const faceData = 3;
	pub const quads = 4;
	pub const chunks = 6;
	pub const lightData = 10;
};

/// The Cubyz SSBO layouts the vertex prologue pulls its attributes from, mirrored from
/// `assets/cubyz/shaders/chunks/chunk_vertex.vert`.
///
/// A plain literal rather than a formatted string: the block is mostly braces, and threading four
/// numbers through `print` would mean escaping every one of them for the sake of values that must
/// not vary anyway. `checkSsboBindings` is what keeps it honest instead.
const ssboDeclarations =
	\\// ---- Cubyz SSBO layouts (mirrored from chunks/chunk_vertex.vert) ----
	\\struct CubyzFaceData {
	\\    int encodedPositionAndLightIndex;
	\\    int textureAndQuad;
	\\};
	\\layout(std430, binding = 3) buffer _cubyzFaceData {CubyzFaceData cubyzFaceData[];};
	\\
	\\struct CubyzQuadInfo {
	\\    vec3 normal;
	\\    float corners[4][3];
	\\    vec2 cornerUV[4];
	\\    uint textureSlot;
	\\    int opaqueInLod;
	\\};
	\\layout(std430, binding = 4) buffer _cubyzQuads {CubyzQuadInfo cubyzQuads[];};
	\\
	\\layout(std430, binding = 10) buffer _cubyzLightData {uint cubyzLightData[];};
	\\
	\\struct CubyzChunkData {
	\\    ivec4 position;
	\\    vec4 minPos;
	\\    vec4 maxPos;
	\\    int voxelSize;
	\\    uint lightStart;
	\\    uint vertexStartOpaque;
	\\    uint faceCountsByNormalOpaque[14];
	\\    uint vertexStartTransparent;
	\\    uint vertexCountTransparent;
	\\    uint visibilityState;
	\\    uint oldVisibilityState;
	\\};
	\\layout(std430, binding = 6) buffer _cubyzChunks {CubyzChunkData cubyzChunks[];};
	\\
;

// Fails the build if a declaration in `ssboDeclarations` stops matching `bindingsMatchEngine`.
// The doc comment on those constants used to claim they were what the generated GLSL was built
// from. They were not - the numbers were written out by hand in both places, so updating one would
// silently leave the other behind. This is the check that makes the claim true.
comptime {
	for([_]struct {binding: u32, buffer: []const u8}{
		.{.binding = bindingsMatchEngine.faceData, .buffer = "_cubyzFaceData"},
		.{.binding = bindingsMatchEngine.quads, .buffer = "_cubyzQuads"},
		.{.binding = bindingsMatchEngine.lightData, .buffer = "_cubyzLightData"},
		.{.binding = bindingsMatchEngine.chunks, .buffer = "_cubyzChunks"},
	}) |entry| {
		const expected = std.fmt.comptimePrint("binding = {d}) buffer {s} ", .{entry.binding, entry.buffer});
		if(std.mem.indexOf(u8, ssboDeclarations, expected) == null) {
			@compileError("prologue: SSBO declaration does not match bindingsMatchEngine: expected '" ++ expected ++ "'");
		}
	}
}

/// Generates the vertex prologue for a terrain gbuffers program.
///
/// `textureArrayBinding` is where Cubyz's block texture array lives, so the fragment stage can be
/// pointed at the right layer.
pub fn terrainVertex(allocator: NeverFailingAllocator, tinted: bool, attributes: AttributeTypes, throughGeometry: bool) []u8 {
	var out = List(u8).init(allocator);
	out.appendSlice(ssboDeclarations);
	// Not a Cubyz buffer: this one is built by `blockids.zig` from the pack's own
	// `block.properties`. Written from the constant so the two cannot drift apart - a mismatched
	// binding would read whichever buffer happened to be bound there and produce plausible-looking
	// nonsense rather than an error.
	out.print(
		\\// ---- pack block ids, indexed by Cubyz texture index (see blockids.zig) ----
		\\layout(std430, binding = {}) buffer _cubyzBlockIds {{int cubyzBlockIds[];}};
		\\// One entry carries three facts: the pack's block id, the block's light emission on
		\\// Minecraft's 0-15 scale, and whether the block is a Cubyz fluid.
		\\const int cubyz_idMask = {};
		\\const int cubyz_emissionShift = {};
		\\const int cubyz_fluidBit = {};
		\\
	, .{
		@import("blockids.zig").binding,
		@import("blockids.zig").idMask,
		@import("blockids.zig").emissionShift,
		@import("blockids.zig").fluidBit,
	});
	out.appendSlice(
		\\
		\\uniform vec3 cubyz_ambientLight;
		\\uniform ivec3 cubyz_playerPositionInteger;
		\\uniform vec3 cubyz_playerPositionFraction;
		\\
		\\// ---- the Minecraft vertex environment, computed rather than attributed ----
		\\vec4 cubyz_Vertex;
		\\vec3 cubyz_Normal;
		\\vec4 cubyz_Color;
		\\vec4 cubyz_MultiTexCoord0;
		\\vec4 cubyz_MultiTexCoord1;
		\\
	);
	// The three pack-declared attributes, at the width the pack declared them. See `AttributeTypes`.
	attributes.writeDeclarations(&out);
	out.appendSlice(
		\\
		\\/// Layer of Cubyz's block texture array this face samples, handed to the fragment stage
		\\/// because the pack's `texture2D(gtexture, uv)` has no way to know about array layers.
		\\
	);
	// Behind a pack's own geometry stage the name takes a `V` suffix, so the passthrough that
	// stage is given can declare the fragment-facing `cubyz_textureLayer` as its output without
	// colliding with its input. See `geometryPassthrough`.
	out.print("flat out int {s};\n", .{if(throughGeometry) "cubyz_textureLayerV" else "cubyz_textureLayer"});
	out.appendSlice(
		\\/// Per-face correction the fragment prologue applies to the block texture: `.rgb` multiplies
		\\/// the colour and `.a` is a floor under the alpha; see `cubyz_applyVertexTint`. (1, 1, 1, 0)
		\\/// for everything but a fluid.
		\\
	);
	out.print("flat out vec4 {s};\n", .{if(throughGeometry) "cubyz_textureUntintV" else "cubyz_textureUntint"});
	out.appendSlice(
		\\
		\\vec3 cubyz_square(vec3 x) {return x*x;}
		\\
		\\/// Forward declaration, for the same reason `cubyz_packMain` needs one: the definition is
		\\/// emitted after this function, and GLSL demands declaration before use.
		\\void cubyz_applyVertexTint(bool isFluid);
		\\
		\\void cubyz_setupVertex() {
		\\    int faceID = gl_VertexID >> 2;
		\\    int vertexID = gl_VertexID & 3;
		\\    int chunkID = gl_BaseInstance;
		\\    int voxelSize = cubyzChunks[chunkID].voxelSize;
		\\    int encoded = cubyzFaceData[faceID].encodedPositionAndLightIndex;
		\\    int textureAndQuad = cubyzFaceData[faceID].textureAndQuad;
		\\
		\\    uint lightIndex = cubyzChunks[chunkID].lightStart + 4*uint(encoded >> 16);
		\\    uint fullLight = cubyzLightData[lightIndex + uint(vertexID)];
		\\    vec3 sunLight = vec3(fullLight >> 25 & 31u, fullLight >> 20 & 31u, fullLight >> 15 & 31u);
		\\    vec3 blockLight = vec3(fullLight >> 10 & 31u, fullLight >> 5 & 31u, fullLight >> 0 & 31u);
		\\
		\\    // Minecraft's lightmap is two scalars where Cubyz has two RGB triples, so each is
		\\    // collapsed to its strongest channel. Lossy in the direction that matters least: packs
		\\    // use these to pick a colour from the lightmap texture, and Cubyz already applied its
		\\    // own per-channel colour to the light it stores.
		\\    float torchLight = max(max(blockLight.r, blockLight.g), blockLight.b)/31.0;
		\\
		\\    // Sky *access*, not sun intensity. Minecraft's sky lightmap sits at 15/15 anywhere a
		\\    // surface can see the sky, dropping only once it is genuinely enclosed; Cubyz's sun
		\\    // light attenuates with every block it travels past. Packs gate on the Minecraft
		\\    // meaning — `deferred1.fsh` kills direct sunlight outright below 0.2 — so passing
		\\    // Cubyz's raw intensity through makes ordinary outdoor shade lose the sun entirely,
		\\    // and a shadow map that says otherwise never gets asked.
		\\    //
		\\    // A plateau with a LINEAR ramp. An earlier attempt cubed it and crushed exactly the
		\\    // band this has to lift; see `lightmap.zig`, where the threshold and its measurement
		\\    // live and are pinned by tests.
		\\    float rawSkyLight = max(max(sunLight.r, sunLight.g), sunLight.b)/31.0;
		\\
	);
	out.print(
		\\    float skyLight = min(1.0, rawSkyLight/{d:.4});
		\\
	, .{@as(f32, @import("lightmap.zig").skyAccessFull)});
	out.appendSlice(
		\\
		\\    // Minecraft's raw lightmap coordinate, 0..240 per axis (light level times 16), which is
		\\    // what Iris puts in gl_MultiTexCoord1 (`VanillaTransformer.java:45`, `vec4(iris_UV2, 0, 1)`)
		\\    // and what gl_TextureMatrix[1] turns into the 1/32..31/32 texel centre - that matrix is
		\\    // scale 1/256 plus 1/32 (`BuiltinReplacementUniforms.java:12`), and `uniforms.zig`
		\\    // uploads it. Packs split on which half they use: Kappa, Nostalgia, BSL, Complementary and
		\\    // Solas multiply by the matrix and are indifferent to the convention, while Bliss
		\\    // (`all_solid.vsh:215`, `/ 240.0`) and photon (`gbuffers_all_solid.vsh:97`, `* rcp(240.0)`)
		\\    // read the raw value. Handing them the final coordinate instead put their sky light at
		\\    // 0.968/240, which is a world with no sky light anywhere: photon lit only the disc its
		\\    // shadow map covers, since past it the shadow comes from the lightmap, and Bliss's terrain
		\\    // went black under what looked like cloud shadow.
		\\    cubyz_MultiTexCoord1 = vec4(torchLight*240.0, skyLight*240.0, 0.0, 1.0);
		\\
		\\    int textureIndex = textureAndQuad & 65535;
		\\    int quadIndex = textureAndQuad >> 16;
		\\
	);
	out.print("    {s} = textureIndex;\n", .{if(throughGeometry) "cubyz_textureLayerV" else "cubyz_textureLayer"});
	out.appendSlice(
		\\
		\\    // Read here rather than beside `mc_Entity`, because the fluid bit has to be known before
		\\    // the vertex position is built. A miss reads 0, which is what an ordinary block reports
		\\    // in Minecraft too, so an unmatched block behaves as plain solid terrain rather than
		\\    // selecting a random effect. The bounds check matters: with no world loaded the table is
		\\    // empty, and an unguarded read past a zero-length SSBO is undefined rather than zero.
		\\    int cubyz_blockEntry = 0;
		\\    if(textureIndex >= 0 && textureIndex < cubyzBlockIds.length()) {
		\\        cubyz_blockEntry = cubyzBlockIds[textureIndex];
		\\    }
		\\    int cubyz_blockId = cubyz_blockEntry & cubyz_idMask;
		\\    bool cubyz_isFluid = (cubyz_blockEntry & cubyz_fluidBit) != 0;
		\\
		\\    vec3 position = vec3(encoded & 31, encoded >> 5 & 31, encoded >> 10 & 31);
		\\    vec3 cubyz_corner = vec3(
		\\        cubyzQuads[quadIndex].corners[vertexID][0],
		\\        cubyzQuads[quadIndex].corners[vertexID][1],
		\\        cubyzQuads[quadIndex].corners[vertexID][2]);
		\\
		\\    // **Minecraft renders fluids at 14/16 of a block; Cubyz models them as full cubes.**
		\\    // Packs key on that height, and the gate is knife-edge: Complementary's water foam is
		\\    // `clamp((fract(worldPos.y) - 0.7) * 10.0, 0.0, 1.0)`, a stable 0.875 in Minecraft but
		\\    // exactly 0.0 against a full cube — a floating-point boundary, so `fract` rounds to
		\\    // either 0.99998 or 0.00002 per pixel per frame and the foam flickers on and off.
		\\    //
		\\    // Lowering the block's top corners by an eighth puts the surface where every pack already
		\\    // expects it. The whole top rim moves rather than just the top face, so the side quads
		\\    // shorten with it and no gap opens at the waterline. Applied before the `voxelSize`
		\\    // multiply, so an LOD cell lowers proportionally rather than by an absolute eighth.
		\\    //
		\\    // Cubyz's own rendering is untouched: this is the pack prologue, which only runs with a
		\\    // shaderpack loaded.
		\\    // **Two quads describe one water surface, in different block frames.** `chunk_meshing`
		\\    // emits a transparent boundary twice — `appendNeighborFacingQuads(block, neighbor.reverse(),
		\\    // pos, true)` for the back face and `(block, neighbor, neighborPos, false)` for the front —
		\\    // and those calls pass *different positions*. So the same physical plane arrives once with
		\\    // its corners at local z≈1 (expressed in the water block) and once at local z≈0 (expressed
		\\    // in the block on the other side of the boundary).
		\\    //
		\\    // Catching only the first is what produced two water layers an eighth apart: lowered when
		\\    // seen from underwater, unmoved from above.
		\\    //
		\\    // The normal separates the second case from a fluid's genuine *bottom*, which also sits at
		\\    // local z≈0 but faces down. Cubyz is Z-up here — this runs before the Y-up conversion — so
		\\    // a surface facing up has normal.z > 0.
		\\    bool cubyz_atFluidTop = cubyz_corner.z > 0.99 ||
		\\        (cubyz_corner.z < 0.01 && cubyzQuads[quadIndex].normal.z > 0.5);
		\\    if(cubyz_isFluid && cubyz_atFluidTop) cubyz_corner.z -= 0.125;
		\\
		\\    position += cubyz_corner;
		\\    position *= voxelSize;
		\\    position += vec3(cubyzChunks[chunkID].position.xyz - cubyz_playerPositionInteger);
		\\    position -= cubyz_playerPositionFraction;
		\\
		\\    vec3 normal = cubyzQuads[quadIndex].normal;
		\\
		\\    // Hand the pack a Y-up world, matching `matrix.zig`'s basis change. Everything the pack
		\\    // derives from these is then in Minecraft's orientation without it knowing.
		\\    cubyz_Vertex = vec4(position.x, position.z, -position.y, 1.0);
		\\    cubyz_Normal = vec3(normal.x, normal.z, -normal.y);
		\\
		\\    cubyz_MultiTexCoord0 = vec4(cubyzQuads[quadIndex].cornerUV[vertexID]*voxelSize, 0.0, 1.0);
		\\    // Each block texture is its own array layer, so the "tile" is the whole [0,1] square and
		\\    // its midpoint is the centre. This is better behaved than a real atlas for parallax:
		\\    // there are no neighbouring tiles to bleed in from.
		\\
	);
	out.print("    mc_midTexCoord = vec4(0.5, 0.5, 0.0, 0.0){s};\n", .{narrowTo(attributes.midTexCoord)});
	out.appendSlice(
		\\
		\\    // Cubyz applies light per vertex rather than as a vertex colour; packs expect white and
		\\    // get their lighting from the lightmap coordinate above.
		\\    cubyz_Color = vec4(1.0);
		\\    cubyz_applyVertexTint(cubyz_isFluid);
		\\
		\\    // `at_tangent` is the direction of increasing texture **U**, and its `.w` is the handedness
		\\    // of the frame. It is not "some edge of the quad" — that distinction is the entire point of
		\\    // a tangent frame, because packs build their TBN on it to orient normal maps and to march
		\\    // parallax in texture space.
		\\    //
		\\    // This used to be `corners[1] - corners[0]` with `.w` hardcoded to 1.0, which is correct
		\\    // only when that edge happens to run along U and the frame happens to be right-handed.
		\\    // Cubyz's quads carry corner positions *and* corner UVs, so the real thing is derivable and
		\\    // there is no reason to approximate it.
		\\    //
		\\    // Kappa's water is what exposed it: it rebuilds the bitangent as
		\\    // `cross(at_tangent.xyz, gl_Normal.xyz) * at_tangent.w` and then marches `dir / -dir.y`
		\\    // through that frame, so a tangent rotated against UV — or mirrored — puts a sign change in
		\\    // the divisor and folds the surface along the line where it crosses.
		\\    vec3 cubyz_p0 = vec3(cubyzQuads[quadIndex].corners[0][0], cubyzQuads[quadIndex].corners[0][1], cubyzQuads[quadIndex].corners[0][2]);
		\\    vec3 cubyz_p1 = vec3(cubyzQuads[quadIndex].corners[1][0], cubyzQuads[quadIndex].corners[1][1], cubyzQuads[quadIndex].corners[1][2]);
		\\    vec3 cubyz_p2 = vec3(cubyzQuads[quadIndex].corners[2][0], cubyzQuads[quadIndex].corners[2][1], cubyzQuads[quadIndex].corners[2][2]);
		\\    vec3 cubyz_dp1 = cubyz_p1 - cubyz_p0;
		\\    vec3 cubyz_dp2 = cubyz_p2 - cubyz_p0;
		\\    vec2 cubyz_dt1 = cubyzQuads[quadIndex].cornerUV[1] - cubyzQuads[quadIndex].cornerUV[0];
		\\    vec2 cubyz_dt2 = cubyzQuads[quadIndex].cornerUV[2] - cubyzQuads[quadIndex].cornerUV[0];
		\\
		\\    // Degenerate when a quad's first three corners are collinear in texture space. The old edge
		\\    // tangent is the fallback, which keeps such a quad shaded rather than NaN. The voxelSize
		\\    // scaling cancels in this ratio, so LOD quads take the same branch as full-detail ones.
		\\    float cubyz_uvDet = cubyz_dt1.x*cubyz_dt2.y - cubyz_dt2.x*cubyz_dt1.y;
		\\    vec3 cubyz_tangent;
		\\    vec3 cubyz_bitangent;
		\\    if(abs(cubyz_uvDet) < 1e-8) {
		\\        cubyz_tangent = cubyz_dp1;
		\\        cubyz_bitangent = cross(normal, cubyz_dp1);
		\\    } else {
		\\        float cubyz_invDet = 1.0/cubyz_uvDet;
		\\        cubyz_tangent = (cubyz_dp1*cubyz_dt2.y - cubyz_dp2*cubyz_dt1.y)*cubyz_invDet;
		\\        cubyz_bitangent = (cubyz_dp2*cubyz_dt1.x - cubyz_dp1*cubyz_dt2.x)*cubyz_invDet;
		\\    }
		\\
		\\    vec3 tangent = normalize(vec3(cubyz_tangent.x, cubyz_tangent.z, -cubyz_tangent.y) + vec3(1e-9));
		\\    vec3 bitangent = vec3(cubyz_bitangent.x, cubyz_bitangent.z, -cubyz_bitangent.y);
		\\    // Packs rebuild the bitangent as `cross(tangent, normal) * w`, so `.w` is whichever sign
		\\    // makes that agree with the one the quad's own UVs imply.
		\\    float handedness = dot(cross(tangent, cubyz_Normal), bitangent) < 0.0 ? -1.0 : 1.0;
		\\
	);
	out.print("    at_tangent = vec4(tangent, handedness){s};\n", .{narrowTo(attributes.tangent)});
	// Vertex to block centre, in sixty-fourths of a block, from the corner offset the position was
	// just built from. Z-up to Y-up is (x, z, -y), applied to the offset exactly as to the
	// position. Per voxel rather than per block for LOD meshes, which is the unit the pack's own
	// maths treats it as. The `.w` is the block's light emission, 0-15, which is what Iris puts
	// there behind `BLOCK_EMISSION_ATTRIBUTE` (`MixinChunkRenderRebuildTask.java:52`); Rethinking
	// Voxels lifts a voxel's block light to `at_midBlock.w/20` and Bliss numbers its light sources
	// from it, so a zero here left every torch dark in their voxel lighting.
	out.print("    at_midBlock = vec4((0.5 - cubyz_corner.x) * 64.0, (0.5 - cubyz_corner.z) * 64.0, -(0.5 - cubyz_corner.y) * 64.0, float((cubyz_blockEntry >> cubyz_emissionShift) & 15)){s};\n", .{narrowTo(attributes.midBlock)});
	out.appendSlice(
		\\
		\\    // Block identity, from the table `blockids.zig` builds by matching Cubyz's block names
		\\    // against the pack's own `block.properties`. This is what makes a pack's foliage wave,
		\\    // its emitters glow and its water render as water.
		\\    //
		\\    // Keyed by texture index because that is what a face actually carries — see
		\\    // `blockids.zig` for why the block type is not available here.
		\\    //
		\\    // A miss reads 0, which is what an ordinary block reports in Minecraft too, so an
		\\    // unmatched block behaves as plain solid terrain rather than selecting a random effect.
		\\    // The bounds check matters: with no world loaded the table is empty, and an unguarded
		\\    // read past a zero-length SSBO is undefined rather than zero.
		\\
	);
	out.print("    mc_Entity = vec4(float(cubyz_blockId), 0.0, 0.0, 0.0){s};\n", .{narrowTo(attributes.entity)});
	out.appendSlice(
		\\}
		\\
	);

	// `glColor` is where Minecraft keeps the water tint, and Cubyz keeps the same quantity
	// somewhere else. `transparent_fragment.frag` reads a per-texel absorption from the
	// reflectivity array and multiplies the blend by it. A pack reads `glColor` twice - as the
	// water's own colour, and as the tint applied to everything seen *through* the surface - so
	// leaving it white makes water stop colouring the riverbed at all and read as clear glass.
	//
	// The two engines also disagree about where a fluid's colour lives, and the fix for that is the
	// `cubyz_textureUntint` varying. Minecraft's `water_still.png` is a light grey that the biome
	// tint colours, so a pack draws `texture * glColor`; Cubyz's `water.png` is already dark blue,
	// (21, 99, 163) on average, and handing that texture over beside a blue `glColor` coloured the
	// water twice: (0.015, 0.21, 0.53) against Minecraft's (0.19, 0.36, 0.70) for the same formula.
	// So a fluid's texture is divided by the tint on the fragment side (every block-texture
	// sampling helper in `terrainFragment` applies the factor), which makes it the grey Minecraft
	// hands over, and `texture * glColor` comes out at exactly the colour Cubyz authored. A
	// translucent block that is not a fluid - Cubyz's glass, dyed or clear - is Minecraft's
	// stained glass: its colour is in the texture and `glColor` is white, so it gets no tint and no
	// untint at all.
	//
	// Only for the translucent pass. Opaque blocks default to a white absorption texture, so the
	// sample would be a white no-op on the renderer's hottest vertex path.
	const untintName = if(throughGeometry) "cubyz_textureUntintV" else "cubyz_textureUntint";
	if(tinted) {
		// Imported here rather than at file scope, matching `terrainFragment` - it is the only
		// thing in this file that needs a GL-side constant.
		const targets = @import("targets.zig");
		// Cubed, because the two engines mean different things by the value. Cubyz's absorption is
		// a transmission coefficient applied once per block traversed, so one block's worth is
		// nearly clear; Minecraft's `glColor` is the colour the water already is, with depth handled
		// separately by the pack. Three blocks is the rough traversal a pack assumes. That exponent
		// is a unit conversion between two engines that genuinely disagree - a judgement, unlike the
		// rest of this file, and no exponent matches exactly. For `water_absorption.png`'s
		// (144, 208, 240) it gives (0.18, 0.54, 0.83), about the brightness of Minecraft's default
		// water tint (0.25, 0.46, 0.89).
		out.print(
			\\
			\\layout(binding = {}) uniform sampler2DArray cubyz_vertexAbsorption;
			\\
			\\// The alpha floor is Minecraft's water texture: `water_still.png` is about 0.70 opaque
			\\// (178 of 255), and every pack composes its water surface against that - Bliss weights
			\\// the water's own colour by the texel alpha and lets the rest be the refracted bottom.
			\\// Cubyz's `water.png` is 0.42, so more than half of every water pixel was the lake bed,
			\\// dark wherever the water is deep. A fluid's alpha is lifted to Minecraft's; nothing
			\\// else is touched, and Cubyz's own transparency is what its own shader still draws.
			\\const float cubyz_minecraftWaterAlpha = 178.0/255.0;
			\\
			\\void cubyz_applyVertexTint(bool isFluid) {{
			\\    {s} = vec4(1.0, 1.0, 1.0, 0.0);
			\\    if(!isFluid) return;
			\\    vec3 absorption = texelFetch(cubyz_vertexAbsorption, ivec3(0, 0, {s}), 0).rgb;
			\\    vec3 tint = absorption*cubyz_square(absorption);
			\\    cubyz_Color.rgb = tint;
			\\    {s} = vec4(1.0/max(tint, vec3(1.0/255.0)), cubyz_minecraftWaterAlpha);
			\\}}
			\\
		, .{targets.cubyzReflectivityTextureUnit, untintName, if(throughGeometry) "cubyz_textureLayerV" else "cubyz_textureLayer", untintName});
	} else {
		out.print(
			\\
			\\void cubyz_applyVertexTint(bool isFluid) {{
			\\    {s} = vec4(1.0, 1.0, 1.0, 0.0);
			\\}}
			\\
		, .{untintName});
	}

	// GLSL demands declaration before use, and the pack's body is spliced in *after* this, so the
	// generated entry point needs a forward declaration to call into it.
	out.appendSlice("void ");
	out.appendSlice(packEntryPoint);
	out.appendSlice("();\n\nvoid main() {\n    cubyz_setupVertex();\n    ");
	out.appendSlice(packEntryPoint);
	out.appendSlice("();\n}\n");
	return out.toOwnedSlice();
}

/// Uniforms the sky prologue declares. Named distinctly from the compatibility shim's matrices so a
/// pack that happens to use `gl_ProjectionMatrixInverse` itself cannot collide with them.
pub const skyProjectionInverse = "cubyz_skyProjectionInverse";
pub const skyModelViewInverse = "cubyz_skyModelViewInverse";

/// Generates the vertex prologue for a sky gbuffers program.
///
/// Minecraft draws its sky as geometry during the gbuffers stage, and packs are split on whether they
/// use that. Nostalgia and Kappa discard in `gbuffers_skybasic` and build their sky in the
/// post-chain instead; Complementary computes `GetSky(...)` in that program and writes it to
/// colortex0. A bridge with no sky geometry path works for the first kind and silently gives the
/// second kind Cubyz's flat imported colour to shade instead of its own atmosphere.
///
/// Cubyz has no sky geometry to route, so this synthesises the only thing such a program actually
/// needs: coverage. These shaders reconstruct the view direction per pixel -
///
///     vec4 screenPos = vec4(gl_FragCoord.xy / vec2(viewWidth, viewHeight), gl_FragCoord.z, 1.0);
///     vec4 viewPos   = gbufferProjectionInverse * (screenPos * 2.0 - 1.0);
///     vec3 nViewPos  = normalize(viewPos.xyz);
///
/// - so they do not need a dome, only fragments at the far plane covering the frustum. A fullscreen
/// triangle unprojected into world space gives exactly that, and the pack's own
/// `gl_Position = ftransform()` transforms it straight back, because `ftransform` is
/// `ModelViewProjection * cubyz_Vertex` and this is its exact inverse. The round trip is why the pack
/// is handed a *position* rather than having its `gl_Position` overwritten: a pack that does
/// something else in its vertex stage keeps doing it.
///
/// That is also what makes this general rather than built around one pack. Nothing here detects
/// a pack or branches on one. A program that discards every fragment draws nothing; a program that
/// collapses its vertex to `vec4(-1.0)`, as Nostalgia's does, rasterises nothing. Both leave the
/// imported sky untouched, which is the behaviour those packs already had.
///
/// The vertex comes from `gl_VertexID` rather than an attribute because the pack's `cubyz_Vertex` is
/// a computed global here, not an input, so there is nothing for a vertex buffer to feed.
pub fn skyVertex(allocator: NeverFailingAllocator, attributes: AttributeTypes) []u8 {
	var out = List(u8).init(allocator);
	out.print(
		\\uniform mat4 {s};
		\\uniform mat4 {s};
		\\
		\\// ---- the Minecraft vertex environment, computed rather than attributed ----
		\\vec4 cubyz_Vertex;
		\\vec3 cubyz_Normal;
		\\vec4 cubyz_Color;
		\\vec4 cubyz_MultiTexCoord0;
		\\vec4 cubyz_MultiTexCoord1;
		\\
	, .{skyProjectionInverse, skyModelViewInverse});
	// A sky program is as free as a terrain one to declare these narrower - photon's
	// `gbuffers_skytextured.vsh` writes `attribute vec2 mc_midTexCoord;` - so it gets the same
	// treatment rather than a second hardcoded guess.
	attributes.writeDeclarations(&out);
	out.print(
		\\
		\\void cubyz_setupVertex() {{
		\\    // The standard three-vertex fullscreen triangle: (-1,-1), (3,-1), (-1,3).
		\\    vec2 ndc = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2))*2.0 - 1.0;
		\\
		\\    // Unproject the far plane. Dividing by w before the second transform keeps the point
		\\    // finite; the pack's `ftransform` re-applies the same pair, so the clip position it
		\\    // computes differs from `ndc` only by a positive scale, which the perspective divide
		\\    // removes.
		\\    vec4 view = {s}*vec4(ndc, 1.0, 1.0);
		\\    view /= view.w;
		\\    vec4 world = {s}*view;
		\\
		\\    cubyz_Vertex = vec4(world.xyz, 1.0);
		\\
		\\    // Vanilla sky geometry carries a white vertex colour. Packs lean on that: Complementary
		\\    // detects vanilla *stars* with `glColor.r == glColor.g && glColor.r < 0.51` and discards
		\\    // when it matches, so handing over anything grey and dim would erase the sky it is
		\\    // being asked to draw.
		\\    cubyz_Color = vec4(1.0);
		\\    cubyz_Normal = vec3(0.0, 1.0, 0.0);
		\\    cubyz_MultiTexCoord0 = vec4((ndc*0.5 + 0.5), 0.0, 1.0);
		\\    // Full sky light, no block light - the sky is not lit by the world. Raw 0..240 like the
		\\    // terrain prologue's; the lightmap matrix in gl_TextureMatrix[1] brings it to 31/32.
		\\    cubyz_MultiTexCoord1 = vec4(0.0, 240.0, 0.0, 1.0);
		\\
	, .{skyProjectionInverse, skyModelViewInverse});
	out.print("    mc_midTexCoord = vec4(0.5, 0.5, 0.0, 0.0){s};\n", .{narrowTo(attributes.midTexCoord)});
	out.print("    at_tangent = vec4(1.0, 0.0, 0.0, 1.0){s};\n", .{narrowTo(attributes.tangent)});
	out.print("    mc_Entity = vec4(0.0){s};\n", .{narrowTo(attributes.entity)});
	out.print("    at_midBlock = vec4(0.0){s};\n", .{narrowTo(attributes.midBlock)});
	out.appendSlice(
		\\}
		\\
	);

	out.appendSlice("void ");
	out.appendSlice(packEntryPoint);
	out.appendSlice("();\n\nvoid main() {\n    cubyz_setupVertex();\n    ");
	out.appendSlice(packEntryPoint);
	out.appendSlice("();\n}\n");
	return out.toOwnedSlice();
}

/// The corner each of the six vertex ids of a celestial quad lands on: two triangles, `0 1 2` and
/// `0 2 3`, sharing the diagonal. Corners are numbered counter-clockwise from `(-1, -1)`.
///
/// A table rather than arithmetic, because the arithmetic was wrong once: an off-by-one sent ids
/// 4 and 5 to the same corner, the second triangle collapsed, and the sun rose as a half-disc cut
/// along the diagonal (the user's screenshot of 2026-09-12). `quadCornerSign` is the same rule the
/// GLSL applies, so the tests can check both halves are real triangles covering all four corners.
pub const quadCorners = [6]u8{0, 1, 2, 0, 2, 3};

/// Where a corner sits on the quad, in the units of its edge vectors.
pub fn quadCornerSign(corner: u8) [2]f32 {
	return .{
		if(corner == 1 or corner == 2) 1.0 else -1.0,
		if(corner >= 2) 1.0 else -1.0,
	};
}

/// The uniforms `skyTexturedVertex` builds its quad from, set per draw by `bridge.drawCelestialBodies`.
pub const celestialCenter = "cubyz_celestialCenter";
pub const celestialU = "cubyz_celestialU";
pub const celestialV = "cubyz_celestialV";
pub const celestialUv = "cubyz_celestialUv";
pub const celestialColor = "cubyz_celestialColor";

/// Generates the vertex prologue for `gbuffers_skytextured`, which draws the sun and the moon.
///
/// Minecraft draws each as one quad in the celestial frame (`LevelRenderer.renderSky`): the sun
/// spans `[-30, 30]` on the frame's X and Z at `Y = 100`, the moon `[-20, 20]` at `Y = -100`, and
/// Iris hands `gbuffers_skytextured` those vertices with the sun texture or the moon-phase sheet on
/// `gtexture`, a white `gl_Color` and the quad's UVs. Cubyz has no such geometry, so the quad is
/// built here from `gl_VertexID`: six vertices, two triangles, corners at the centre plus or minus
/// the two edge vectors, all in view space and handed over in the pack's world space through
/// `gbufferModelViewInverse` - so the pack's own `ftransform()` puts them back exactly where the
/// bridge meant them, the same round trip `skyVertex` relies on. Which body, and its texture, UVs,
/// colour and `renderStage`, are the draw's to set; the prologue does not know or care.
pub fn skyTexturedVertex(allocator: NeverFailingAllocator, attributes: AttributeTypes) []u8 {
	var out = List(u8).init(allocator);
	out.print(
		\\uniform mat4 {s};
		\\uniform vec3 {s};
		\\uniform vec3 {s};
		\\uniform vec3 {s};
		\\/// `(u0, v0, u1, v1)`: the texture rectangle the quad carries, `u0` at the corner the U edge
		\\/// points away from. The moon's phase sheet is eight cells, and its quad is mirrored in U
		\\/// against the sun's, so the draw hands the rectangle over already in the order it needs.
		\\uniform vec4 {s};
		\\uniform vec4 {s};
		\\
		\\// ---- the Minecraft vertex environment, computed rather than attributed ----
		\\vec4 cubyz_Vertex;
		\\vec3 cubyz_Normal;
		\\vec4 cubyz_Color;
		\\vec4 cubyz_MultiTexCoord0;
		\\vec4 cubyz_MultiTexCoord1;
		\\
	, .{skyModelViewInverse, celestialCenter, celestialU, celestialV, celestialUv, celestialColor});
	attributes.writeDeclarations(&out);
	out.print(
		\\
		\\void cubyz_setupVertex() {{
		\\    // Corners 0, 1, 2 then 0, 2, 3, counter-clockwise seen from the centre of the sky; see
		\\    // `quadCorners` and `quadCornerSign` for why this is a table.
		\\    const int cubyz_quadCorners[6] = int[6]({}, {}, {}, {}, {}, {});
		\\    int corner = cubyz_quadCorners[clamp(gl_VertexID, 0, 5)];
		\\    vec2 sign = vec2(corner == 1 || corner == 2 ? 1.0 : -1.0, corner >= 2 ? 1.0 : -1.0);
		\\    vec3 view = {s} + {s}*sign.x + {s}*sign.y;
		\\    vec4 world = {s}*vec4(view, 1.0);
		\\    cubyz_Vertex = vec4(world.xyz, 1.0);
		\\
		\\    cubyz_MultiTexCoord0 = vec4(mix({s}.xy, {s}.zw, sign*0.5 + 0.5), 0.0, 1.0);
		\\    cubyz_Color = {s};
		\\    cubyz_Normal = vec3(0.0, 1.0, 0.0);
		\\    // Sky geometry carries no lightmap; full sky light, raw 0..240 as the terrain prologue's.
		\\    cubyz_MultiTexCoord1 = vec4(0.0, 240.0, 0.0, 1.0);
		\\
	, .{
		quadCorners[0], quadCorners[1], quadCorners[2], quadCorners[3], quadCorners[4], quadCorners[5],
		celestialCenter, celestialU, celestialV, skyModelViewInverse, celestialUv, celestialUv, celestialColor,
	});
	out.print("    mc_midTexCoord = vec4(0.5, 0.5, 0.0, 0.0){s};\n", .{narrowTo(attributes.midTexCoord)});
	out.print("    at_tangent = vec4(1.0, 0.0, 0.0, 1.0){s};\n", .{narrowTo(attributes.tangent)});
	out.print("    mc_Entity = vec4(0.0){s};\n", .{narrowTo(attributes.entity)});
	out.print("    at_midBlock = vec4(0.0){s};\n", .{narrowTo(attributes.midBlock)});
	out.appendSlice(
		\\}
		\\
	);

	out.appendSlice("void ");
	out.appendSlice(packEntryPoint);
	out.appendSlice("();\n\nvoid main() {\n    cubyz_setupVertex();\n    ");
	out.appendSlice(packEntryPoint);
	out.appendSlice("();\n}\n");
	return out.toOwnedSlice();
}

/// Generates the fragment prologue for a terrain gbuffers program.
///
/// Packs call `texture2D(gtexture, coord)` against a single stitched atlas. Cubyz has a
/// `sampler2DArray` with one layer per block texture, so the sampler the pack declares is
/// suppressed and the shim's `cubyz_texture2D` overloads route to the array using the layer the
/// vertex stage computed.
///
/// `translucent` is whether the program draws the transparent meshes - `gbuffers_water`, and the
/// shadow program since the shadow pass draws them too - which is where Cubyz's glass has to be
/// given the albedo it does not have; see `cubyz_untint` below.
pub fn terrainFragment(allocator: NeverFailingAllocator, translucent: bool) []u8 {
	const targets = @import("targets.zig");
	var out = List(u8).init(allocator);
	// Written from the unit constants rather than spelled as literals. They have to agree with what
	// `bridge.bindTerrainUniforms` binds, and a silent disagreement would read whatever texture
	// happened to be on that unit rather than fail - the material maps would just be wrong.
	out.print(
		\\layout(binding = {}) uniform sampler2DArray cubyz_blockTextures;
		\\layout(binding = {}) uniform sampler2DArray cubyz_emissionTextures;
		\\layout(binding = {}) uniform sampler2DArray cubyz_reflectivityTextures;
		\\
	, .{targets.cubyzBlockTextureUnit, targets.cubyzEmissionTextureUnit, targets.cubyzReflectivityTextureUnit});
	out.appendSlice(
		\\flat in int cubyz_textureLayer;
		\\/// Divides a fluid's texture by the tint the vertex stage put in glColor, so the pack sees
		\\/// Minecraft's pair - a grey texture and a coloured glColor - whose product is the colour
		\\/// Cubyz authored - and lifts its alpha to Minecraft's water alpha. (1, 1, 1, 0) for every
		\\/// other block. See `cubyz_applyVertexTint`.
		\\flat in vec4 cubyz_textureUntint;
		\\
		\\/// Cubyz animates textures by swapping array layers, so the live layer is looked up per
		\\/// fragment exactly as `chunks/chunk_fragment.frag` does.
		\\layout(std430, binding = 1) buffer _cubyzAnimatedTexture {float cubyzAnimatedTexture[];};
		\\
		\\vec3 cubyz_layerCoord(vec2 uv) {
		\\    return vec3(uv, cubyzAnimatedTexture[cubyz_textureLayer]);
		\\}
		\\
		\\
	);
	out.print(
		\\/// Whether an alpha-0 texel with a coloured absorption is glass to be given an albedo. Only
		\\/// in a program that draws the transparent meshes: the opaque pass's alpha-0 texels are
		\\/// cutout holes.
		\\const bool cubyz_synthesisesGlass = {s};
		\\
		\\/// Cubyz's glass has no albedo. Every `glass/<colour>.png` is one uniform texel at alpha 0,
		\\/// and the block's look is made in `transparent_fragment.frag` from the material maps alone:
		\\/// the scene behind it multiplied by the absorption colour, plus a fresnel reflection scaled
		\\/// by the reflectivity. A pack handed that texel draws nothing, or a colourless reflective
		\\/// sheet where it reflects on every translucent surface regardless - which is what every pack
		\\/// showed, the same textureless glass in every colour.
		\\///
		\\/// Minecraft's stained glass is the other model, a coloured texel blended by its alpha, and
		\\/// this converts one into the other per texel. The colour is the absorption, the colour the
		\\/// glass lets through and so the colour it reads as; the alpha is set so the pack's blend
		\\/// transmits the luminance Cubyz's multiply does, `dst*(1 - a)` against `dst*absorption`, so
		\\/// `a = 1 - lum(absorption)`. White glass (absorption 240 of 255) comes out at 0.06, all but
		\\/// clear, as the interior of Minecraft's plain `glass` is; blue (35, 109, 195) at 0.61 and
		\\/// black (49) at 0.81. Only where that alpha registers at all: a cutout hole in any other
		\\/// texture has the engine's default white absorption and stays a hole. Reflectivity is not
		\\/// folded in; the pack reads it through `specular` and makes its own reflection.
		\\vec4 cubyz_untint(vec4 texel, vec3 coord) {{
		\\    texel = vec4(texel.rgb*cubyz_textureUntint.rgb, max(texel.a, cubyz_textureUntint.a));
		\\    if(cubyz_synthesisesGlass && texel.a == 0.0) {{
		\\        vec3 absorption = texture(cubyz_reflectivityTextures, coord).rgb;
		\\        float alpha = 1.0 - dot(absorption, vec3(0.2126, 0.7152, 0.0722));
		\\        if(alpha > 1.0/255.0) texel = vec4(absorption, alpha);
		\\    }}
		\\    return texel;
		\\}}
		\\
		\\
	, .{if(translucent) "true" else "false"});
	out.appendSlice(
		\\// Every sampling call whose first argument names the block texture is rewritten to this,
		\\// keeping the sampler as the first argument so the overloads pick the right arity.
		\\//
		\\// A plain `#define` of the sampler name cannot do the job on its own: packs pass a
		\\// two-component coordinate, and there is no valid overload of `texture` taking
		\\// `(sampler2DArray, vec2)` no matter what the sampler is called. The call site has to
		\\// change too, and only where it targets the block texture — the same program samples
		\\// `lightmap` and `depthtex0`, which really are 2D.
		\\//
		\\// Three helper names, not one, because `texture(s, c, x)` and `textureLod(s, c, x)` are the
		\\// same shape with different meanings — a bias against the implicit level, versus an explicit
		\\// level. One name could only carry one of those bodies, so the other reading was silently
		\\// substituted wherever a pack used it.
		\\//
		\\// Every array flavour goes through `cubyz_untint`, with the coordinate it sampled at: the
		\\// only sampler2DArray a pack's call can name is the block texture, a fluid's texture has to
		\\// arrive untinted, and glass has to arrive with the albedo its absorption map implies.
		\\vec4 cubyz_sampleArray(sampler2DArray s, vec2 c) {vec3 lc = cubyz_layerCoord(c); return cubyz_untint(texture(s, lc), lc);}
		\\vec4 cubyz_sampleArray(sampler2DArray s, vec2 c, float b) {vec3 lc = cubyz_layerCoord(c); return cubyz_untint(texture(s, lc, b), lc);}
		\\vec4 cubyz_sampleArray(sampler2DArray s, vec2 c, int b) {vec3 lc = cubyz_layerCoord(c); return cubyz_untint(texture(s, lc, float(b)), lc);}
		\\vec4 cubyz_sampleArray(sampler2DArray s, vec3 c) {vec3 lc = cubyz_layerCoord(c.xy); return cubyz_untint(texture(s, lc), lc);}
		\\vec4 cubyz_sampleArrayLod(sampler2DArray s, vec2 c, float l) {vec3 lc = cubyz_layerCoord(c); return cubyz_untint(textureLod(s, lc, l), lc);}
		\\vec4 cubyz_sampleArrayLod(sampler2DArray s, vec2 c, int l) {vec3 lc = cubyz_layerCoord(c); return cubyz_untint(textureLod(s, lc, float(l)), lc);}
		\\vec4 cubyz_sampleArrayLod(sampler2DArray s, vec3 c, float l) {vec3 lc = cubyz_layerCoord(c.xy); return cubyz_untint(textureLod(s, lc, l), lc);}
		\\// The parallax march form. photon reads every texture through
		\\// `#define read_tex(x) textureGrad(x, parallax_uv, uv_gradient[0], uv_gradient[1])`, so
		\\// without these its `gbuffers_water` redirected correctly and then landed on a signature
		\\// nobody had written.
		\\vec4 cubyz_sampleArrayGrad(sampler2DArray s, vec2 c, vec2 dx, vec2 dy) {vec3 lc = cubyz_layerCoord(c); return cubyz_untint(textureGrad(s, lc, dx, dy), lc);}
		\\vec4 cubyz_sampleArrayGrad(sampler2DArray s, vec3 c, vec2 dx, vec2 dy) {vec3 lc = cubyz_layerCoord(c.xy); return cubyz_untint(textureGrad(s, lc, dx, dy), lc);}
		\\// Integer texel coordinates: the layer joins as an integer and nothing is scaled. The texel
		\\// is turned back into a coordinate for the material read, as `cubyz_sampleSpecular` does.
		\\vec4 cubyz_fetchArray(sampler2DArray s, ivec2 c, int l) {
		\\    int layer = int(cubyzAnimatedTexture[cubyz_textureLayer]);
		\\    vec3 lc = vec3((vec2(c) + 0.5)/vec2(textureSize(s, l).xy), float(layer));
		\\    return cubyz_untint(texelFetch(s, ivec3(c, layer), l), lc);
		\\}
		\\// A parameter or local of the pack's own function that merely happens to be spelled like the
		\\// block texture - Nostalgia's noise fetch takes `sampler2D tex` - is an ordinary 2D sampler.
		\\// The redirect keys on spelling and cannot tell; overload resolution can, and this is the one
		\\// place the type is actually known. Each is a plain passthrough.
		\\vec4 cubyz_sampleArray(sampler2D s, vec2 c) {return texture(s, c);}
		\\vec4 cubyz_sampleArray(sampler2D s, vec2 c, float b) {return texture(s, c, b);}
		\\vec4 cubyz_sampleArray(sampler2D s, vec2 c, int b) {return texture(s, c, float(b));}
		\\vec4 cubyz_sampleArray(sampler2D s, vec3 c) {return texture(s, c.xy);}
		\\vec4 cubyz_sampleArrayLod(sampler2D s, vec2 c, float l) {return textureLod(s, c, l);}
		\\vec4 cubyz_sampleArrayLod(sampler2D s, vec2 c, int l) {return textureLod(s, c, float(l));}
		\\vec4 cubyz_sampleArrayLod(sampler2D s, vec3 c, float l) {return textureLod(s, c.xy, l);}
		\\vec4 cubyz_sampleArrayGrad(sampler2D s, vec2 c, vec2 dx, vec2 dy) {return textureGrad(s, c, dx, dy);}
		\\vec4 cubyz_sampleArrayGrad(sampler2D s, vec3 c, vec2 dx, vec2 dy) {return textureGrad(s, c.xy, dx, dy);}
		\\vec4 cubyz_fetchArray(sampler2D s, ivec2 c, int l) {return texelFetch(s, c, l);}
		\\
		\\// ---- the same, dispatched by sampler *type* rather than by name ----
		\\//
		\\// For a sampling call inside a pack's own macro, where the sampler is the macro's parameter
		\\// and its identity is only knowable after preprocessing. Three of the six packs in the
		\\// corpus wrap every texture read this way. Overload resolution answers per expansion what
		\\// the token scan cannot answer at all; see `glsl.MacroDispatch`.
		\\//
		\\// The `sampler2D` overloads are exact passthroughs, so a macro invoked with an ordinary 2D
		\\// sampler behaves precisely as it did before.
		\\vec4 cubyz_sampleAny(sampler2D s, vec2 c) {return texture(s, c);}
		\\vec4 cubyz_sampleAny(sampler2D s, vec2 c, float b) {return texture(s, c, b);}
		\\vec4 cubyz_sampleAny(sampler2D s, vec2 c, int b) {return texture(s, c, float(b));}
		\\vec4 cubyz_sampleAny(sampler2D s, vec3 c) {return texture(s, c.xy);}
		\\vec4 cubyz_sampleAnyLod(sampler2D s, vec2 c, float l) {return textureLod(s, c, l);}
		\\vec4 cubyz_sampleAnyLod(sampler2D s, vec2 c, int l) {return textureLod(s, c, float(l));}
		\\vec4 cubyz_sampleAnyGrad(sampler2D s, vec2 c, vec2 dx, vec2 dy) {return textureGrad(s, c, dx, dy);}
		\\vec4 cubyz_fetchAny(sampler2D s, ivec2 c, int l) {return texelFetch(s, c, l);}
		\\vec4 cubyz_sampleAny(sampler2DArray s, vec2 c) {return cubyz_sampleArray(s, c);}
		\\vec4 cubyz_sampleAny(sampler2DArray s, vec2 c, float b) {return cubyz_sampleArray(s, c, b);}
		\\vec4 cubyz_sampleAny(sampler2DArray s, vec2 c, int b) {return cubyz_sampleArray(s, c, b);}
		\\vec4 cubyz_fetchAny(sampler2DArray s, ivec2 c, int l) {return cubyz_fetchArray(s, c, l);}
		\\vec4 cubyz_sampleAny(sampler2DArray s, vec3 c) {return cubyz_sampleArray(s, c);}
		\\vec4 cubyz_sampleAnyLod(sampler2DArray s, vec2 c, float l) {return cubyz_sampleArrayLod(s, c, l);}
		\\vec4 cubyz_sampleAnyLod(sampler2DArray s, vec2 c, int l) {return cubyz_sampleArrayLod(s, c, l);}
		\\vec4 cubyz_sampleAnyGrad(sampler2DArray s, vec2 c, vec2 dx, vec2 dy) {return cubyz_sampleArrayGrad(s, c, dx, dy);}
		\\
		\\// ---- LabPBR material data, synthesised from Cubyz's own material arrays ----
		\\//
		\\// Cubyz has no LabPBR textures, but it does carry two of the three things one encodes:
		\\// per-texel reflectivity and per-texel emission. Handing packs a neutral constant throws
		\\// that away and makes every surface identically matte; this translates what exists and is
		\\// explicit about what does not.
		\\//
		\\// The sampler argument is accepted and ignored. It has to stay in the call so the pack's
		\\// own `uniform sampler2D specular;` declaration is still referenced — dropping it would
		\\// leave a declared-but-unused sampler and change nothing else.
		\\vec4 cubyz_labPbrSpecular(vec2 uv) {
		\\    vec3 coord = cubyz_layerCoord(uv);
		\\    float reflectivity = texture(cubyz_reflectivityTextures, coord).a;
		\\    float emission = texture(cubyz_emissionTextures, coord).r;
		\\
		\\    // Cubyz has no roughness. `chunk_fragment.frag` samples a perfect mirror,
		\\    // `fixedCubeMapLookup(reflect(direction, normal))`, and scales it by reflectivity, so a
		\\    // reflective texel is a perfectly smooth surface whose reflectance is the reflectivity:
		\\    // smoothness 1.0 and F0 from the value. A texel with no reflectivity is Iris's own default
		\\    // for a block without a specular map, all zeros (`PBRType.SPECULAR`, 0x00000000), which is
		\\    // the value every pack's hardcoded materials were written against.
		\\    //
		\\    // This read `smoothness = reflectivity` before, on the argument that the engine treats a
		\\    // reflective block as a smooth one - but 27/255 is not smooth, it is rough, and packs took
		\\    // it at its word. Bliss overrides its hardcoded water material whenever `specular.r > 0`
		\\    // (`all_translucent.fsh:727`), turned a smoothness of 0.106 into a roughness of 0.8, and
		\\    // its `visibilityFactor`, exp2(-4 * roughness^3 / f0), came out at 1.5e-6: every
		\\    // reflection off, sun glint included, and the lake a flat dark teal (2026-09-05).
		\\    float smoothness = reflectivity > 0.0 ? 1.0 : 0.0;
		\\    // Held below the 230/255 metal threshold. Cubyz has no metalness concept, and crossing
		\\    // into the metal range makes a pack tint its reflections by the albedo and drop diffuse
		\\    // entirely — a large, wrong change rather than a subtle one.
		\\    float f0 = min(reflectivity, 229.0/255.0);
		\\
		\\    // Cubyz compares `emission.r*4` against the light value, so 0.25 already means fully lit;
		\\    // the same factor is applied here so a block glows in the pack at the strength it glows
		\\    // in the engine. 255/255 is LabPBR's "no emission" sentinel, so genuine emission is
		\\    // capped just below it.
		\\    float emissiveness = min(emission*4.0, 254.0/255.0);
		\\
		\\    // Blue is porosity/SSS. Cubyz's absorption is a translucency tint rather than either of
		\\    // those, so it stays unmapped instead of being forced into a channel that means
		\\    // something else.
		\\    return vec4(smoothness, f0, 0.0, emissiveness);
		\\}
		\\
		\\// One name for all three flavours here, unlike the block texture: the value is synthesised
		\\// rather than sampled, so a level or a derivative has nothing to select and every overload
		\\// returns the same thing. The arities still have to exist, or a redirected call lands on a
		\\// signature that was never declared.
		\\vec4 cubyz_sampleSpecular(sampler2D s, vec2 c) {return cubyz_labPbrSpecular(c);}
		\\vec4 cubyz_sampleSpecular(sampler2D s, vec2 c, float b) {return cubyz_labPbrSpecular(c);}
		\\vec4 cubyz_sampleSpecular(sampler2D s, vec2 c, int l) {return cubyz_labPbrSpecular(c);}
		\\vec4 cubyz_sampleSpecular(sampler2D s, vec3 c) {return cubyz_labPbrSpecular(c.xy);}
		\\vec4 cubyz_sampleSpecular(sampler2D s, vec3 c, float l) {return cubyz_labPbrSpecular(c.xy);}
		\\vec4 cubyz_sampleSpecular(sampler2D s, vec2 c, vec2 dx, vec2 dy) {return cubyz_labPbrSpecular(c);}
		\\vec4 cubyz_sampleSpecular(sampler2D s, vec3 c, vec2 dx, vec2 dy) {return cubyz_labPbrSpecular(c.xy);}
		\\// A texel fetch against the material map: the texel is turned back into a coordinate on
		\\// Cubyz's own arrays, whose layers are all one size.
		\\vec4 cubyz_sampleSpecular(sampler2D s, ivec2 c, int l) {return cubyz_labPbrSpecular((vec2(c) + 0.5) / vec2(textureSize(cubyz_emissionTextures, 0).xy));}
		\\
		\\// Packs spell the block texture several ways depending on their vintage.
		\\#define gtexture cubyz_blockTextures
		\\#define gcolor cubyz_blockTextures
		\\#define tex cubyz_blockTextures
		\\#define texture0 cubyz_blockTextures
		\\
	);
	return out.toOwnedSlice();
}

/// Sampler names a terrain fragment program declares that the prologue replaces.
///
/// Their declarations are stripped for the same reason the vertex attributes are: the prologue
/// supplies an equivalent, and leaving the pack's `uniform sampler2D gtexture;` in place would
/// both duplicate the name and leave it bound to nothing.
/// Deliberately only the names the prologue actually redefines. Stripping a sampler the prologue
/// does *not* provide - `lightmap`, `normals`, `specular` - would leave the pack referencing an
/// undeclared name and fail to compile, which is worse than sampling something wrong.
pub const suppliedSamplers = [_][]const u8{
	"gtexture",
	"gcolor",
	"tex",
	"texture0",
	// The OptiFine-era spelling: `uniform sampler2D texture;`, which Bliss and BSL use. Iris
	// renames that variable to `gtexture` wherever it is not a function call
	// (`CommonTransformer.java:229-234`), and `glsl.rewrite` does the same, so the `#define` for
	// `gtexture` above covers every surviving mention. Listed here so the declaration is stripped
	// and the sampling calls redirected under the pack's own spelling. It was missing, and the
	// consequence was the one this file's founding bug always has: the renamed sampler stayed a
	// `sampler2D` nothing assigned a unit to, read unit 0, and every block face in Bliss and BSL
	// wore a copy of the screen - the "tiny screens within each block" of 2026-09-04. No `#define`
	// for this name: it would swallow the built-in `texture()` in the prologue and shim.
	"texture",
};

/// Where each redirected sampler's calls go.
///
/// The block-texture names resolve to Cubyz's `sampler2DArray` and need a genuine array lookup.
/// `specular` is different in kind: it stays a `sampler2D` the pack declared, and the helper
/// ignores it entirely, synthesising a LabPBR value from Cubyz's material arrays instead. That is
/// why the redirect is per sampler rather than one shared function.
///
/// `normals` is deliberately absent. Cubyz has no normal, height or AO data at any resolution, so
/// the neutral 1x1 texture `packtextures.zig` binds is already the correct answer - a helper here
/// could only return the same constant less directly.
/// Where a sampling call inside a pack's own macro is sent, when the sampler is that macro's
/// parameter and so cannot be named here. The helpers are declared by `terrainFragment`, which is
/// why this is only ever handed to a gbuffers fragment stage.
/// The prologue for a pack's own geometry stage, which from the bridge's side is only a passthrough.
///
/// Iris attaches a `.gsh` beside a program whenever the pack ships one, and a pack that does so
/// routes *every* varying through it: Nostalgic Red Voxels' shadow vertex writes `texCoordV`,
/// `lmCoordV`, `absMidCoordPosV` and the rest, and its geometry stage is what renames them to the
/// names the fragment reads. Without that stage the other two cannot link, and no option changes it.
///
/// The vertex prologue has one varying of its own in that pipeline, the block texture layer, and
/// the pack's geometry code has never heard of it. So the layer is emitted as
/// `cubyz_textureLayerV` when a geometry stage exists and carried across here. It is `flat` and
/// per face, so every input vertex of a primitive agrees on it and `[0]` is the whole story;
/// setting the output once before the pack's `main` runs makes it part of every vertex the pack
/// emits, since a geometry output keeps its value until rewritten.
pub fn geometryPassthrough(allocator: NeverFailingAllocator) []u8 {
	var out = List(u8).init(allocator);
	out.appendSlice(
		\\// ---- irisbridge: carries the vertex prologue's texture layer and fluid untint across the pack's geometry stage ----
		\\flat in int cubyz_textureLayerV[3];
		\\flat out int cubyz_textureLayer;
		\\flat in vec4 cubyz_textureUntintV[3];
		\\flat out vec4 cubyz_textureUntint;
		\\
		\\
	);
	out.print("void {s}();\n\nvoid main() {{\n    cubyz_textureLayer = cubyz_textureLayerV[0];\n    cubyz_textureUntint = cubyz_textureUntintV[0];\n    {s}();\n}}\n", .{packEntryPoint, packEntryPoint});
	return out.toOwnedSlice();
}

pub const macroDispatch = @import("glsl.zig").MacroDispatch{
	.function = "cubyz_sampleAny",
	.lodFunction = "cubyz_sampleAnyLod",
	.gradFunction = "cubyz_sampleAnyGrad",
	.fetchFunction = "cubyz_fetchAny",
};

pub const arraySamplers = blk: {
	const array = glsl.SamplerRedirect{
		.sampler = undefined,
		.function = "cubyz_sampleArray",
		.lodFunction = "cubyz_sampleArrayLod",
		.gradFunction = "cubyz_sampleArrayGrad",
		.fetchFunction = "cubyz_fetchArray",
	};
	var list: [suppliedSamplers.len + 2]glsl.SamplerRedirect = undefined;
	for(suppliedSamplers, 0..) |name, index| {
		list[index] = array;
		list[index].sampler = name;
	}
	// The post-`#define` name too: the rewrite runs on the pack's own spelling, but generated code
	// uses the real one.
	list[suppliedSamplers.len] = array;
	list[suppliedSamplers.len].sampler = "cubyz_blockTextures";
	// Every flavour resolves to the same helper: the value is synthesised, so there is no level or
	// derivative for it to honour. The overloads for each arity are declared in `terrainFragment`.
	list[suppliedSamplers.len + 1] = .{
		.sampler = "specular",
		.function = "cubyz_sampleSpecular",
		.lodFunction = "cubyz_sampleSpecular",
		.gradFunction = "cubyz_sampleSpecular",
		.fetchFunction = "cubyz_sampleSpecular",
	};
	break :blk list;
};

// MARK: tests

const testing = std.testing;
const testingAllocator = main.heap.testingAllocator;

/// The property the whole `AttributeTypes` mechanism exists to hold: whatever width a name is
/// declared at, the value assigned to it is narrowed to the same width.
///
/// Asserted as an invariant over every width rather than as three separate expected strings,
/// because the failure this guards against is precisely the two halves drifting apart - a
/// declaration changed without its assignment compiles to a driver error in a file that exists
/// nowhere on disk.
fn expectDeclarationMatchesAssignment(source: []const u8, name: []const u8, declared: []const u8) !void {
	var declaration: [64]u8 = undefined;
	const declarationText = try std.fmt.bufPrint(&declaration, "{s} {s};", .{declared, name});
	try testing.expect(std.mem.indexOf(u8, source, declarationText) != null);

	// The assignment is the line that starts with the name; its value must carry the swizzle that
	// narrows the prologue's `vec4` to the declared width.
	var assignment: [64]u8 = undefined;
	const assignmentPrefix = try std.fmt.bufPrint(&assignment, "    {s} = ", .{name});
	const start = std.mem.indexOf(u8, source, assignmentPrefix) orelse return error.NoAssignment;
	const end = std.mem.indexOfScalarPos(u8, source, start, ';') orelse return error.UnterminatedAssignment;
	const value = source[start..end];

	const expectedSuffix = narrowTo(declared);
	try testing.expect(std.mem.endsWith(u8, value, expectedSuffix));
	// A narrower declaration must actually narrow: without this the test would pass on the old
	// behaviour, since every value already ends with the empty string.
	if(!std.mem.eql(u8, declared, "vec4")) try testing.expect(expectedSuffix.len != 0);
}

test "the terrain prologue declares the attributes at the pack's own widths" {
	// photon writes exactly this pair, and it is what took its `gbuffers_water` down.
	const packSource =
		\\attribute vec3 mc_Entity;
		\\attribute vec2 mc_midTexCoord;
		\\void main() {gl_Position = vec4(mc_Entity.x);}
		\\
	;
	const attributes = AttributeTypes.fromSource(testingAllocator, packSource);
	const generated = terrainVertex(testingAllocator, false, attributes, false);
	defer testingAllocator.free(generated);

	try expectDeclarationMatchesAssignment(generated, "mc_Entity", "vec3");
	try expectDeclarationMatchesAssignment(generated, "mc_midTexCoord", "vec2");
	// Undeclared falls back to the widest type, which is what every other pack expects.
	try expectDeclarationMatchesAssignment(generated, "at_tangent", "vec4");
}

test "a pack that declares nothing keeps the vec4 the four original fixtures rely on" {
	const attributes = AttributeTypes{};
	const generated = terrainVertex(testingAllocator, false, attributes, false);
	defer testingAllocator.free(generated);

	try expectDeclarationMatchesAssignment(generated, "mc_Entity", "vec4");
	try expectDeclarationMatchesAssignment(generated, "mc_midTexCoord", "vec4");
	try expectDeclarationMatchesAssignment(generated, "at_tangent", "vec4");
	// No swizzle at all in the vec4 case, so the generated source for the packs that already
	// worked is byte-for-byte what it was.
	try testing.expect(std.mem.indexOf(u8, generated, "mc_Entity = vec4(float(cubyz_blockId), 0.0, 0.0, 0.0);") != null);
}

test "the sky prologue follows the pack's widths too" {
	// photon's `gbuffers_skytextured.vsh` declares `attribute vec2 mc_midTexCoord;`, so a second
	// hardcoded vec4 here would just move the same bug to a different program.
	const attributes = AttributeTypes{.midTexCoord = "vec2", .entity = "vec3"};
	const generated = skyVertex(testingAllocator, attributes);
	defer testingAllocator.free(generated);

	try expectDeclarationMatchesAssignment(generated, "mc_Entity", "vec3");
	try expectDeclarationMatchesAssignment(generated, "mc_midTexCoord", "vec2");
	try expectDeclarationMatchesAssignment(generated, "at_tangent", "vec4");
}

test "at_midBlock is the vector from the vertex to its block centre, in Y-up sixty-fourths" {
	// Kappa and Nostalgia hinge their wind displacement on it; Complementary and its derivatives
	// voxelise with it. Every one of them read (0, 0, 0) - an unfed attribute's default - so foliage
	// waved as though every vertex sat at its block's centre.
	const generated = terrainVertex(testingAllocator, false, .{}, false);
	defer testingAllocator.free(generated);
	try expectDeclarationMatchesAssignment(generated, "at_midBlock", "vec3");
	// Z-up to Y-up is (x, z, -y), applied to the offset exactly as it is to the position. The
	// fourth component is the block's light level from the id table, Iris's
	// `BLOCK_EMISSION_ATTRIBUTE`; a pack declaring the attribute as `vec3` never sees it.
	try testing.expect(std.mem.indexOf(u8, generated, "at_midBlock = vec4((0.5 - cubyz_corner.x) * 64.0, (0.5 - cubyz_corner.z) * 64.0, -(0.5 - cubyz_corner.y) * 64.0, float((cubyz_blockEntry >> cubyz_emissionShift) & 15)).xyz;") != null);
	try testing.expect(std.mem.indexOf(u8, generated, "const int cubyz_emissionShift = 26;") != null);
	const wide = terrainVertex(testingAllocator, false, .{.midBlock = "vec4"}, false);
	defer testingAllocator.free(wide);
	try testing.expect(std.mem.indexOf(u8, wide, "float((cubyz_blockEntry >> cubyz_emissionShift) & 15));") != null);
}

test "the lightmap coordinate is Minecraft's raw 0..240, in both prologues" {
	// Bliss divides gl_MultiTexCoord1 by 240 and photon multiplies by rcp(240); the other packs go
	// through gl_TextureMatrix[1]. Only the raw range serves both, and the matrix
	// (`lightmap.lightmapTextureMatrix`, tested there) is what brings the second group to 31/32.
	const terrain = terrainVertex(testingAllocator, false, .{}, false);
	defer testingAllocator.free(terrain);
	try testing.expect(std.mem.indexOf(u8, terrain, "cubyz_MultiTexCoord1 = vec4(torchLight*240.0, skyLight*240.0, 0.0, 1.0);") != null);
	try testing.expect(std.mem.indexOf(u8, terrain, "0.9375 + 0.03125") == null);

	const sky = skyVertex(testingAllocator, .{});
	defer testingAllocator.free(sky);
	try testing.expect(std.mem.indexOf(u8, sky, "cubyz_MultiTexCoord1 = vec4(0.0, 240.0, 0.0, 1.0);") != null);
}

test "a geometry stage gets the texture layer carried across under a distinct input name" {
	// The vertex side renames its output so the passthrough can declare the fragment-facing name
	// as *its* output; the halves have to agree or the program will not link, and a link failure
	// names a varying rather than this file.
	const vertex = terrainVertex(testingAllocator, false, .{}, true);
	defer testingAllocator.free(vertex);
	const geometry = geometryPassthrough(testingAllocator);
	defer testingAllocator.free(geometry);
	const fragment = terrainFragment(testingAllocator, false);
	defer testingAllocator.free(fragment);

	try testing.expect(std.mem.indexOf(u8, vertex, "flat out int cubyz_textureLayerV;") != null);
	try testing.expect(std.mem.indexOf(u8, vertex, "cubyz_textureLayerV = textureIndex;") != null);
	try testing.expect(std.mem.indexOf(u8, geometry, "flat in int cubyz_textureLayerV[3];") != null);
	try testing.expect(std.mem.indexOf(u8, geometry, "flat out int cubyz_textureLayer;") != null);
	try testing.expect(std.mem.indexOf(u8, fragment, "flat in int cubyz_textureLayer;") != null);
	// The fluid untint rides the same way, and the untinted variant still has to write it, or the
	// fragment stage reads an unwritten varying.
	try testing.expect(std.mem.indexOf(u8, vertex, "flat out vec4 cubyz_textureUntintV;") != null);
	try testing.expect(std.mem.indexOf(u8, vertex, "cubyz_textureUntintV = vec4(1.0, 1.0, 1.0, 0.0);") != null);
	try testing.expect(std.mem.indexOf(u8, geometry, "flat in vec4 cubyz_textureUntintV[3];") != null);
	try testing.expect(std.mem.indexOf(u8, geometry, "cubyz_textureUntint = cubyz_textureUntintV[0];") != null);
	try testing.expect(std.mem.indexOf(u8, fragment, "flat in vec4 cubyz_textureUntint;") != null);

	// Without a geometry stage the vertex keeps the fragment-facing name, and never the other.
	const direct = terrainVertex(testingAllocator, false, .{}, false);
	defer testingAllocator.free(direct);
	try testing.expect(std.mem.indexOf(u8, direct, "flat out int cubyz_textureLayer;") != null);
	try testing.expect(std.mem.indexOf(u8, direct, "cubyz_textureLayerV") == null);
	try testing.expect(std.mem.indexOf(u8, direct, "flat out vec4 cubyz_textureUntint;") != null);
	try testing.expect(std.mem.indexOf(u8, direct, "cubyz_textureUntintV") == null);
}

test "a fluid gets Minecraft's water pair, a tint in glColor and the texture divided by it" {
	// Cubyz's water texture is already blue; Minecraft's is grey and glColor colours it. The
	// product `texture * glColor` has to come out at Cubyz's colour, so the vertex stage writes
	// the tint and its reciprocal, and every block-texture helper in the fragment prologue applies
	// the reciprocal. A translucent block that is not a fluid is stained glass: white glColor, no
	// untint.
	const tinted = terrainVertex(testingAllocator, true, .{}, false);
	defer testingAllocator.free(tinted);
	try testing.expect(std.mem.indexOf(u8, tinted, "cubyz_applyVertexTint(cubyz_isFluid);") != null);
	try testing.expect(std.mem.indexOf(u8, tinted, "if(!isFluid) return;") != null);
	try testing.expect(std.mem.indexOf(u8, tinted, "cubyz_Color.rgb = tint;") != null);
	try testing.expect(std.mem.indexOf(u8, tinted, "cubyz_textureUntint = vec4(1.0/max(tint, vec3(1.0/255.0)), cubyz_minecraftWaterAlpha);") != null);
	try testing.expect(std.mem.indexOf(u8, tinted, "const float cubyz_minecraftWaterAlpha = 178.0/255.0;") != null);
	// The layer the absorption is read at is the vertex-side name, which differs behind a
	// geometry stage.
	try testing.expect(std.mem.indexOf(u8, tinted, "ivec3(0, 0, cubyz_textureLayer)") != null);
	const throughGeometry = terrainVertex(testingAllocator, true, .{}, true);
	defer testingAllocator.free(throughGeometry);
	try testing.expect(std.mem.indexOf(u8, throughGeometry, "ivec3(0, 0, cubyz_textureLayerV)") != null);
	try testing.expect(std.mem.indexOf(u8, throughGeometry, "cubyz_textureUntintV = vec4(1.0/max(tint, vec3(1.0/255.0)), cubyz_minecraftWaterAlpha);") != null);

	const fragment = terrainFragment(testingAllocator, false);
	defer testingAllocator.free(fragment);
	try testing.expect(std.mem.indexOf(u8, fragment, "vec4 cubyz_untint(vec4 texel, vec3 coord)") != null);
	try testing.expect(std.mem.indexOf(u8, fragment, "max(texel.a, cubyz_textureUntint.a)") != null);
	try testing.expect(std.mem.indexOf(u8, fragment, "vec4 cubyz_sampleArray(sampler2DArray s, vec2 c) {vec3 lc = cubyz_layerCoord(c); return cubyz_untint(texture(s, lc), lc);}") != null);
	// The 2D passthroughs and the material synthesis are not block-texture reads and stay as they are.
	try testing.expect(std.mem.indexOf(u8, fragment, "vec4 cubyz_sampleArray(sampler2D s, vec2 c) {return texture(s, c);}") != null);
	try testing.expect(std.mem.indexOf(u8, fragment, "cubyz_untint(texture(cubyz_reflectivityTextures") == null);
}

test "the textured sky prologue builds a quad from its centre and edges, UVs mixed per corner" {
	// Minecraft's sun and moon are one quad each in the celestial frame; the draw sets the centre,
	// the two edge vectors, the texture rectangle and the colour, and six vertex ids become the two
	// triangles. Handed over in world space through the inverse model-view, like `skyVertex`, so
	// the pack's `ftransform()` lands them where the bridge put them.
	const generated = skyTexturedVertex(testingAllocator, .{});
	defer testingAllocator.free(generated);
	try testing.expect(std.mem.indexOf(u8, generated, "uniform vec3 cubyz_celestialCenter;") != null);
	try testing.expect(std.mem.indexOf(u8, generated, "const int cubyz_quadCorners[6] = int[6](0, 1, 2, 0, 2, 3);") != null);
	try testing.expect(std.mem.indexOf(u8, generated, "int corner = cubyz_quadCorners[clamp(gl_VertexID, 0, 5)];") != null);
	// Both triangles are real - three distinct corners each - and between them they cover all four
	// corners, sharing the diagonal. The half-sun of 2026-09-12 was the second triangle collapsing
	// onto one corner.
	for(0..2) |triangle| {
		const corners = quadCorners[triangle*3 ..][0..3];
		try testing.expect(corners[0] != corners[1] and corners[1] != corners[2] and corners[0] != corners[2]);
		const a = quadCornerSign(corners[0]);
		const b = quadCornerSign(corners[1]);
		const d = quadCornerSign(corners[2]);
		const area = (b[0] - a[0])*(d[1] - a[1]) - (b[1] - a[1])*(d[0] - a[0]);
		try testing.expect(area > 0.0);
	}
	var covered = [4]bool{false, false, false, false};
	for(quadCorners) |corner| covered[corner] = true;
	try testing.expectEqual([4]bool{true, true, true, true}, covered);
	try testing.expect(std.mem.indexOf(u8, generated, "vec3 view = cubyz_celestialCenter + cubyz_celestialU*sign.x + cubyz_celestialV*sign.y;") != null);
	try testing.expect(std.mem.indexOf(u8, generated, "vec4 world = cubyz_skyModelViewInverse*vec4(view, 1.0);") != null);
	try testing.expect(std.mem.indexOf(u8, generated, "cubyz_MultiTexCoord0 = vec4(mix(cubyz_celestialUv.xy, cubyz_celestialUv.zw, sign*0.5 + 0.5), 0.0, 1.0);") != null);
	try testing.expect(std.mem.indexOf(u8, generated, "cubyz_Color = cubyz_celestialColor;") != null);
	// The pack's attributes are supplied at the widths it declared, as everywhere else.
	try expectDeclarationMatchesAssignment(generated, "mc_Entity", "vec4");
	const narrow = skyTexturedVertex(testingAllocator, .{.midTexCoord = "vec2"});
	defer testingAllocator.free(narrow);
	try expectDeclarationMatchesAssignment(narrow, "mc_midTexCoord", "vec2");
}

test "a translucent program synthesises stained glass from an alpha-0 texel's absorption; an opaque one does not" {
	// Cubyz's glass albedo is one texel at alpha 0 in every colour, its look made from the
	// absorption and reflectivity maps. A pack needs Minecraft's stained-glass pair instead, a
	// coloured texel and an alpha, and the conversion keeps the transmitted luminance equal:
	// `dst*(1 - a)` against `dst*absorption`. Only where a program draws the transparent meshes;
	// the opaque pass's alpha-0 texels are cutout holes and stay so.
	const translucent = terrainFragment(testingAllocator, true);
	defer testingAllocator.free(translucent);
	try testing.expect(std.mem.indexOf(u8, translucent, "const bool cubyz_synthesisesGlass = true;") != null);
	try testing.expect(std.mem.indexOf(u8, translucent, "vec3 absorption = texture(cubyz_reflectivityTextures, coord).rgb;") != null);
	try testing.expect(std.mem.indexOf(u8, translucent, "float alpha = 1.0 - dot(absorption, vec3(0.2126, 0.7152, 0.0722));") != null);
	try testing.expect(std.mem.indexOf(u8, translucent, "if(alpha > 1.0/255.0) texel = vec4(absorption, alpha);") != null);
	// Every block-texture helper hands its coordinate along, or the material read has nowhere to
	// look; the fetch form rebuilds one from the texel.
	try testing.expect(std.mem.indexOf(u8, translucent, "vec4 cubyz_sampleArrayGrad(sampler2DArray s, vec2 c, vec2 dx, vec2 dy) {vec3 lc = cubyz_layerCoord(c); return cubyz_untint(textureGrad(s, lc, dx, dy), lc);}") != null);
	try testing.expect(std.mem.indexOf(u8, translucent, "return cubyz_untint(texelFetch(s, ivec3(c, layer), l), lc);") != null);
	try testing.expect(std.mem.indexOf(u8, translucent, "cubyz_untint(texture(s, cubyz_layerCoord(c)))") == null);

	const opaqueProgram = terrainFragment(testingAllocator, false);
	defer testingAllocator.free(opaqueProgram);
	try testing.expect(std.mem.indexOf(u8, opaqueProgram, "const bool cubyz_synthesisesGlass = false;") != null);
}

test "the material synthesis is a mirror scaled by reflectivity, and zeros where there is none" {
	// Cubyz's shader samples a perfect mirror and scales it by reflectivity, so smoothness is 1.0
	// wherever there is any and the reflectivity is the reflectance; Iris's default specular texel
	// is 0x00000000, which is what a texel with no reflectivity has to read as.
	const fragment = terrainFragment(testingAllocator, false);
	defer testingAllocator.free(fragment);
	try testing.expect(std.mem.indexOf(u8, fragment, "float smoothness = reflectivity > 0.0 ? 1.0 : 0.0;") != null);
	try testing.expect(std.mem.indexOf(u8, fragment, "float f0 = min(reflectivity, 229.0/255.0);") != null);
	try testing.expect(std.mem.indexOf(u8, fragment, "float smoothness = reflectivity;") == null);
}

test "the fragment prologue declares the integer-coordinate fetch helpers" {
	const fragment = terrainFragment(testingAllocator, false);
	defer testingAllocator.free(fragment);
	try testing.expect(std.mem.indexOf(u8, fragment, "vec4 cubyz_fetchArray(sampler2DArray s, ivec2 c, int l)") != null);
	try testing.expect(std.mem.indexOf(u8, fragment, "vec4 cubyz_fetchAny(sampler2D s, ivec2 c, int l)") != null);
	try testing.expect(std.mem.indexOf(u8, fragment, "vec4 cubyz_fetchAny(sampler2DArray s, ivec2 c, int l)") != null);
	try testing.expect(std.mem.indexOf(u8, fragment, "vec4 cubyz_sampleSpecular(sampler2D s, ivec2 c, int l)") != null);
}

test "every supported width narrows, and float reaches a scalar" {
	for([_][]const u8{"vec4", "vec3", "vec2", "float"}) |declared| {
		const generated = terrainVertex(testingAllocator, false, .{.entity = declared}, false);
		defer testingAllocator.free(generated);
		try expectDeclarationMatchesAssignment(generated, "mc_Entity", declared);
	}
}

test "the tinted variant is unaffected by the widths" {
	// `tintFromAbsorption` splices in a second function; the attribute handling has to survive it,
	// since the translucent pass is where photon's failure actually landed.
	const generated = terrainVertex(testingAllocator, true, .{.midTexCoord = "vec2"}, false);
	defer testingAllocator.free(generated);

	try expectDeclarationMatchesAssignment(generated, "mc_midTexCoord", "vec2");
	try testing.expect(std.mem.indexOf(u8, generated, "cubyz_applyVertexTint") != null);
}
