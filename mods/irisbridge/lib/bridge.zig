//! Module entry point - the only thing the engine imports.
//!
//! Everything the engine needs to call lives here as a small, stable hook surface, so the
//! additions to `src/renderer.zig` stay a handful of one-line calls rather than the pipeline
//! reaching into engine internals from a dozen places.
//!
//! Every hook is safe to call when no shaderpack is loaded; each returns immediately. That is
//! deliberate - it means the engine-side changes need no `if (shadersEnabled)` guards scattered
//! through the frame, and vanilla rendering is unaffected when the feature is off.

const std = @import("std");

const main = @import("main");
const c = main.c;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const List = main.ListManaged;

pub const glsl = @import("glsl.zig");
pub const pack = @import("pack.zig");
pub const targets = @import("targets.zig");
pub const flip = @import("flip.zig");
pub const matrix = @import("matrix.zig");
pub const uniforms = @import("uniforms.zig");
pub const pipeline = @import("pipeline.zig");
pub const prologue = @import("prologue.zig");
pub const install = @import("install.zig");
pub const expression = @import("expression.zig");
pub const customuniforms = @import("customuniforms.zig");
pub const packtextures = @import("packtextures.zig");
pub const images = @import("images.zig");
pub const options = @import("options.zig");
pub const preprocess = @import("preprocess.zig");
pub const blockmap = @import("blockmap.zig");
pub const blockids = @import("blockids.zig");
pub const blend = @import("blend.zig");
pub const coverage = @import("coverage.zig");

/// Logs what the user could have written instead, which is the only thing that makes a
/// misspelled pack name diagnosable without going and looking at the folder.
/// Adds option overrides to the macro table a `.properties` file is read through, the way Iris adds
/// option values to its (`PropertiesPreprocessor.java:29-51`): a boolean that is on is a defined
/// name with no value, a boolean that is off is not defined at all, and any other option carries its
/// value. `Overrides` spells booleans "true"/"false", so an off switch put in verbatim would be a
/// defined name, and a `#ifdef` in `shaders.properties` would read it as on.
fn putOverrideDefines(defines: *preprocess.Defines, overrides: *const options.Overrides) void {
	var iterator = overrides.map.iterator();
	while(iterator.next()) |entry| {
		const value = entry.value_ptr.*;
		if(std.ascii.eqlIgnoreCase(value, "false")) {
			defines.remove(entry.key_ptr.*);
		} else if(std.ascii.eqlIgnoreCase(value, "true")) {
			defines.put(entry.key_ptr.*, "");
		} else {
			defines.put(entry.key_ptr.*, value);
		}
	}
}

fn logAvailablePacks(allocator: NeverFailingAllocator, io: std.Io) void {
	const entries = install.list(allocator, io, shaderpackDirectory);
	defer install.freeList(allocator, entries);
	if(entries.len == 0) {
		std.log.info("irisbridge: no shaderpacks found in {s}/", .{shaderpackDirectory});
		return;
	}
	var names = List(u8).init(allocator);
	defer names.deinit();
	for(entries, 0..) |entry, index| {
		if(index != 0) names.appendSlice(", ");
		names.appendSlice(entry.name);
		if(entry.kind == .zip) names.appendSlice(" (zip)");
	}
	std.log.info("irisbridge: available shaderpacks: {s}", .{names.items});
}

/// Where extracted shaderpacks are looked for, relative to the Cubyz working directory.
pub const shaderpackDirectory = "shaderpacks";

/// The loaded pipeline, or null when running without a pack.
var active: ?Pipeline = null;
var arena: ?std.heap.ArenaAllocator = null;

pub const Pipeline = struct {
	name: []const u8,
	settings: pack.Settings,
	programs: []pack.Program,
	renderTargets: targets.RenderTargets,
	quad: pipeline.Quad,
	/// Compiled post-chain passes, already in execution order with their bindings resolved.
	passes: []pipeline.Pass,
	/// This frame's uniform snapshot, shared by every pass in the frame.
	frameUniforms: uniforms.Values = .{},
	/// The pack's terrain program, bound in place of Cubyz's while chunks are drawn.
	terrainPass: ?pipeline.Pass = null,
	/// The pack's shadow program, which renders chunks from the light's direction.
	shadowPass: ?pipeline.Pass = null,
	/// `shadowTranslucent` from shaders.properties, true unless the pack says otherwise
	/// (`PackShadowDirectives.java:87`): whether the transparent meshes join the shadow pass.
	shadowTranslucent: bool = true,
	/// Set while `renderShadowMap` is on its translucent layer, so `bindShadowUniforms` knows to
	/// blend: the shadow program draws both layers and the engine rebinds it before each LOD.
	shadowTranslucentPhase: bool = false,
	/// The pack's `gbuffers_water`, bound in place of Cubyz's transparent chunk program.
	waterPass: ?pipeline.Pass = null,
	/// Uniforms the pack defines as expressions in shaders.properties.
	custom: customuniforms.Set,
	/// noisetex plus neutral LabPBR stand-ins, which packs sample unconditionally.
	textures: packtextures.Set,
	/// Which buffers end the frame with their newest contents in `alt`, and so must be copied back
	/// to `main` before the next frame reads them.
	finalFlip: flip.FlipState = .{},
	/// The sides the whole gbuffers stage reads and writes - equal to each other, because geometry
	/// continues the image `prepare` left rather than ping-ponging away from it. Resolved in `load`
	/// and handed to every gbuffers pass there, so this is the one definition rather than a copy.
	///
	/// Kept on the pipeline because what stands in for that stage has no pass to read it from:
	/// `importWorld`, which *is* the gbuffers stage when the pack's terrain program did not
	/// compile, used to fall back to `passes[0].bindings` - the sequence as it stands before any
	/// `prepare` has run, which for a pack whose `prepare` chain touches colortex0 is the other
	/// texture entirely.
	gbuffersBindings: flip.PassBindings = .{},
	/// Set by `beginTranslucent` when it has run the deferred passes for this frame, so
	/// `runPostChain` does not run them again; cleared there once the chain is done.
	deferredRanEarly: bool = false,
	/// Which colortex buffers the `prepare` chain writes before geometry runs.
	/// The pack's `gbuffers_skybasic`, drawn over a synthesised fullscreen triangle before terrain.
	/// Null when the pack ships none; a pack whose sky program discards simply draws nothing.
	skyPass: ?pipeline.Pass = null,
	/// The pack's `gbuffers_skytextured`, drawn over the sun and moon quads the bridge builds after
	/// the sky and before terrain; see `drawCelestialBodies`. Null when the pack ships none.
	skyTexturedPass: ?pipeline.Pass = null,
	/// The pack's `sun` and `moon` directives, true unless it wrote `false`
	/// (`ShaderProperties.handleBooleanDirective`): Kappa draws its own sun and keeps the moon.
	drawSun: bool = true,
	drawMoon: bool = true,
	preparedTargets: flip.TargetSet = .{},
	/// The options this pack exposes in its own settings screens, for the in-game screen to offer.
	/// The strings borrow from `programs`, which is freed after them in `deinit`.
	packOptions: []options.Option = &.{},
	/// The presets the pack ships, offered alongside its options.
	profiles: options.Profiles,
	/// Stamps the scene depth back into the default framebuffer, so the selection outline drawn on
	/// the finished frame is occluded by the world rather than floating over it.
	depthRestore: pipeline.DepthRestore = .{},
	/// The pack's `block.properties`, and the GPU table the prologue reads `mc_Entity` from.
	blocks: blockmap.Map,
	blockIdTable: blockids.Table = .{},
	/// The pack's own images and storage buffers, `image.<name>` and `bufferObject.N`.
	images: images.Set = .{},
	/// The `setup` computes, dispatched once after the first clear and again after a resize
	/// (`IrisRenderingPipeline.java:500-519`, `:979-988`). Compute-only passes, in index order.
	setupPasses: []pipeline.Pass = &.{},
	setupPending: bool = true,
	/// The `shadow.csh` chain, dispatched before the shadow map is drawn (`:885-891`).
	shadowComputes: []pipeline.ComputePass = &.{},
	/// The `shadowcomp` chain, run at the end of the shadow pass over the shadow colour buffers,
	/// with its own flip sequence in each pass's `bindings.shadowRead`/`shadowWrite`.
	shadowCompositePasses: []pipeline.Pass = &.{},

	pub fn deinit(self: *Pipeline, allocator: NeverFailingAllocator) void {
		self.custom.deinit();
		self.textures.deinit();
		self.blocks.deinit();
		self.blockIdTable.deinit();
		self.profiles.deinit();
		self.depthRestore.deinit();
		// Before the programs, which own the strings these borrow.
		allocator.free(self.packOptions);
		for(self.programs) |*program| program.deinit(allocator);
		allocator.free(self.programs);
		if(self.terrainPass) |*item| item.deinit(allocator);
		if(self.shadowPass) |*item| item.deinit(allocator);
		if(self.waterPass) |*item| item.deinit(allocator);
		if(self.skyPass) |*item| item.deinit(allocator);
		if(self.skyTexturedPass) |*item| item.deinit(allocator);
		for(self.passes) |*item| item.deinit(allocator);
		allocator.free(self.passes);
		for(self.setupPasses) |*item| item.deinit(allocator);
		if(self.setupPasses.len != 0) allocator.free(self.setupPasses);
		for(self.shadowComputes) |*item| item.deinit(allocator);
		if(self.shadowComputes.len != 0) allocator.free(self.shadowComputes);
		for(self.shadowCompositePasses) |*item| item.deinit(allocator);
		if(self.shadowCompositePasses.len != 0) allocator.free(self.shadowCompositePasses);
		self.images.deinit();
		self.quad.deinit();
		self.renderTargets.deinit();
	}
};

/// Sorts programs of one kind by index.
fn lessThanByIndex(_: void, a: *const pack.Program, b: *const pack.Program) bool {
	return a.index < b.index;
}

/// A pass's bindings with the shadow colour pair's read side set to what the `shadowcomp` chain
/// leaves, which is what every program outside that chain reads.
fn withShadowSides(bindings: flip.PassBindings, sides: [flip.shadowColorCount]flip.Side) flip.PassBindings {
	var result = bindings;
	result.shadowRead = sides;
	result.shadowWrite = sides;
	return result;
}

/// Every stage source of every program, for option discovery and the coverage report: fragment,
/// vertex, geometry and the compute chain. Iris discovers options from every file in the pack.
/// Every stage source of every program, or with `enabledOnly` just those that will run.
///
/// The coverage report wants the second: a disabled program's uniforms are nobody's concern, and
/// BSL's `shadowcomp`, off behind `MULTICOLORED_BLOCKLIGHT`, was listing its voxel images as
/// unsupplied. Option discovery wants the first, since an option is declared wherever it is
/// declared and a program switched off by one option may still declare another.
fn appendSources(list: *List([]const u8), programs: []const pack.Program, enabledOnly: bool) void {
	for(programs) |*program| {
		if(enabledOnly and !program.enabled) continue;
		if(program.fragmentSource) |source| list.append(source);
		if(program.vertexSource) |source| list.append(source);
		if(program.geometrySource) |source| list.append(source);
		for(program.computes) |*compute| {
			if(enabledOnly and !compute.enabled) continue;
			list.append(compute.source);
		}
	}
}

/// Sorts post-chain programs into the order Iris runs them: prepare, deferred, composite, final,
/// each group by ascending index.
fn lessThanByExecutionOrder(_: void, a: *const pack.Program, b: *const pack.Program) bool {
	const orderA = pipeline.passOrder(a.kind);
	const orderB = pipeline.passOrder(b.kind);
	if(orderA != orderB) return orderA < orderB;
	return a.index < b.index;
}

/// True when a pack is loaded and the engine should route rendering through it.
pub fn isActive() bool {
	return active != null;
}

/// Loads a shaderpack by directory name under `shaderpackDirectory`.
///
/// Returns false and leaves the previous state untouched on any failure, because a pack that
/// fails to load must fall back to vanilla rendering rather than leave a half-built pipeline
/// attached to the frame.
pub fn load(allocator: NeverFailingAllocator, io: std.Io, name: []const u8) bool {
	unload(allocator);

	// Accepts either an extracted folder or a `.zip`, since that is how packs are distributed.
	const packDirectory = install.resolve(allocator, io, shaderpackDirectory, name) catch |err| {
		std.log.err("irisbridge: could not open shaderpack '{s}': {s}", .{name, @errorName(err)});
		logAvailablePacks(allocator, io);
		return false;
	};
	defer allocator.free(packDirectory);

	// Zipping a pack usually captures its containing folder, so `shaders/` may be one level down.
	const shadersRoot = install.findShadersRoot(allocator, io, packDirectory) orelse {
		std.log.err("irisbridge: '{s}' has no shaders/ directory — is it a shaderpack?", .{name});
		return false;
	};
	defer allocator.free(shadersRoot);

	var provider = pack.DirectoryProvider.init(allocator, io, shadersRoot) catch {
		std.log.err("irisbridge: could not read {s}", .{shadersRoot});
		return false;
	};
	defer provider.deinit();

	// Option overrides live beside the pack as `<name>.options.txt`, so they survive re-extracting
	// a zip and are visible without digging into the pack itself.
	var overridePath = List(u8).init(allocator);
	defer overridePath.deinit();
	overridePath.appendSlice(shaderpackDirectory);
	overridePath.append('/');
	overridePath.appendSlice(name);
	overridePath.appendSlice(".options.txt");

	var optionsFileExists = true;
	var overrides = blk: {
		const text = main.files.cwd().read(allocator, overridePath.items) catch {
			optionsFileExists = false;
			break :blk options.Overrides.init(allocator);
		};
		defer allocator.free(text);
		break :blk options.Overrides.parse(allocator, text);
	};
	defer overrides.deinit();
	// `profile` is not an option a shader declares - it names one of the pack's own presets. Taken
	// out before anything else looks at the table, so it is never treated as a `#define` to rewrite.
	const requestedProfile = overrides.take("profile");
	if(overrides.count() != 0) {
		std.log.info("irisbridge: {} option override(s) from {s}", .{overrides.count(), overridePath.items});
	}
	// Reset per load; reported after the programs are built, once every source has been rewritten.
	pack.appliedOverrideCount = 0;

	// Built once per load: the vendor macros need a GL query, and every program gets the same set.
	// Also the macro table the `.properties` files are preprocessed against, which is why it is
	// resolved here rather than just before program compilation - a pack gates its modern block
	// names on `MC_VERSION`, and reading that file without these would take the legacy branch.
	const macros = pipeline.standardMacros(allocator);
	defer pipeline.freeMacros(allocator, macros);

	// One driver question, asked once per process, answered in the log. Temporary - see the doc
	// comment; it decides whether photon's `read_tex(gtexture)` macro case has a cheap fix or needs
	// the transformer to preprocess.
	pipeline.probeBuiltinOverloadOnce();

	// Iris reads its properties files through a C preprocessor whose table holds the environment
	// macros and every option's value (`PropertiesPreprocessor.java:29-51`), and the option values
	// come from the shader sources, which it therefore reads first (`ShaderPack.java:151-175`).
	// Here the sources cannot come first: the user's `profile=` in the options file names a preset
	// declared in shaders.properties, and its values have to reach the sources before the options
	// are discovered from them. So the file is read twice. This first pass sees the environment
	// and the user's overrides alone, and only the feature flags and the profiles are taken from
	// it - neither is declared under an option anywhere in the corpus. The second pass, once the
	// programs are loaded, sees the whole option set and is the one everything else reads.
	//
	// Conditionals are evaluated before the properties are parsed, or a pack that gates a whole
	// section on its Minecraft version contributes both branches and the later one wins.
	var defines = preprocess.Defines.init(allocator);
	defer defines.deinit();
	for(macros) |macro| defines.putMacroString(macro);
	putOverrideDefines(&defines, &overrides);

	const rawProperties = provider.provider().read("/shaders.properties") orelse "";
	const firstPassSource = preprocess.run(allocator, rawProperties, &defines);
	defer allocator.free(firstPassSource);
	var firstPass = pack.parseProperties(allocator, firstPassSource);
	defer firstPass.deinit();

	// A pack states what it needs in `iris.features.required`, and Iris refuses the whole pack when
	// it cannot provide one of them rather than loading it into a broken state. The same here: both
	// voxel packs require `CUSTOM_IMAGES SSBO COMPUTE_SHADERS`, and loading them anyway left a
	// frame with no `final`, five refused programs and a GUI over a stale window - which is what
	// "the menus were unreachable" was. Declined here, the pack never replaces Cubyz's rendering
	// and the log says why in one line.
	if(firstPass.get("iris.features.required")) |required| {
		var missing = List(u8).init(allocator);
		defer missing.deinit();
		var flags = std.mem.tokenizeAny(u8, required, " \t");
		while(flags.next()) |flag| {
			if(pipeline.isSupportedFeature(flag)) continue;
			if(missing.items.len != 0) missing.appendSlice(", ");
			missing.appendSlice(flag);
		}
		if(missing.items.len != 0) {
			std.log.err("irisbridge: {s} requires Iris features this bridge does not implement, so it is not loaded: {s}", .{name, missing.items});
			return false;
		}
	}
	// And the optional ones it asked about become `IRIS_FEATURE_*` defines, for those that exist.
	const programMacros = pipeline.withFeatureMacros(allocator, macros, firstPass.get("iris.features.optional"));
	defer pipeline.freeMacros(allocator, programMacros);

	var profiles = options.parseProfiles(allocator, firstPassSource);
	// Ownership moves into `active` on success, so - like `blocks` below - this is not an `errdefer`:
	// the function reports failure with `false`, and every bail-out has to release it explicitly.
	var profilesOwned = true;
	defer if(profilesOwned) profiles.deinit();
	var disabledPrograms = List([]const u8).init(allocator);
	defer disabledPrograms.deinit();
	applyRequestedProfile(allocator, &profiles, requestedProfile, &overrides, &disabledPrograms);

	var settings = pack.Settings{};
	var diagnostics = List(u8).init(allocator);
	defer diagnostics.deinit();

	// The directive view of each program is evaluated against Iris's environment - the standard
	// macros and the feature flags, no option values, which the rewritten `#define` lines carry
	// themselves (`ShaderPack.java:254-286`).
	var environment = preprocess.Defines.init(allocator);
	defer environment.deinit();
	for(programMacros) |macro| environment.putMacroString(macro);
	const programs = pack.loadPrograms(allocator, provider.provider(), &settings, overworldDirectory, &overrides, &environment, &diagnostics);
	if(diagnostics.items.len != 0) {
		std.log.warn("irisbridge: {s}", .{diagnostics.items});
	}
	if(programs.len == 0) {
		std.log.err("irisbridge: {s} contains no usable programs", .{name});
		allocator.free(programs);
		return false;
	}

	// The option set, as Iris's `ShaderPackOptions` holds it: every option the sources declare, at
	// the value the rewritten source now carries. `discoverAll` keeps the first declaration of a
	// name where Iris drops one declared with two defaults, which is close enough for a macro table.
	const declaredOptions = declaredOptionsOf(allocator, programs);
	defer allocator.free(declaredOptions);

	// The second reading of shaders.properties, and the only one of block.properties, through the
	// table Iris uses for both: the environment with every feature flag this bridge has - Iris adds
	// every usable one (`ShaderPack.java:167-172`) - and the option set in Iris's shape, a boolean
	// that is on a defined name, one that is off absent, a valued option carrying its value
	// (`PropertiesPreprocessor.java:126-150`). What the first pass could not see, because it only
	// had the user's overrides: Solas binds its Milky Way image under `#ifdef MILKY_WAY`, on by
	// default, so its night sky read the depth texture as a galaxy and came out red; photon sizes its
	// cloud buffers under `#if CLOUDS_TEMPORAL_UPSCALING == 4`, so colortex9 and colortex10 were
	// screen-sized where the pack assumes a quarter; Bliss switches `deferred2` off under
	// `#ifdef CLOUDS_INTERSECT_TERRAIN`, so its clouds were drawn by two passes; Complementary gates
	// program enables on `SHADOW_QUALITY` and `FXAA_DEFINE`, right so far only because their
	// defaults happened to agree with an undefined name reading as 0.
	var propertiesDefines = preprocess.Defines.init(allocator);
	defer propertiesDefines.deinit();
	for(macros) |macro| propertiesDefines.putMacroString(macro);
	for(pipeline.supportedFeatures) |flag| {
		var featureMacro = List(u8).init(allocator);
		defer featureMacro.deinit();
		featureMacro.appendSlice("IRIS_FEATURE_");
		for(flag) |char| featureMacro.append(std.ascii.toUpper(char));
		propertiesDefines.put(featureMacro.items, "");
	}
	options.putDefines(&propertiesDefines, declaredOptions);

	// `run` mutates its table with the file's own `#define`s, so each file gets a copy.
	const propertiesSource = blk: {
		var table = propertiesDefines.clone(allocator);
		defer table.deinit();
		break :blk preprocess.run(allocator, rawProperties, &table);
	};
	defer allocator.free(propertiesSource);
	var properties = pack.parseProperties(allocator, propertiesSource);
	defer properties.deinit();
	pack.applyEnabledFlags(allocator, programs, &properties);

	const blockPropertiesSource = provider.provider().read("/block.properties") orelse "";
	var blocks = blk: {
		var table = propertiesDefines.clone(allocator);
		defer table.deinit();
		break :blk blockmap.parse(allocator, blockPropertiesSource, &table);
	};
	// Not `errdefer`: this function reports failure with `false` rather than an error, so every
	// bail-out below has to release this explicitly. Ownership moves into `active` on success.
	var blocksOwned = true;
	defer if(blocksOwned) blocks.deinit();
	if(blocks.entries.len != 0) {
		std.log.info("irisbridge: block.properties: {} entries{s}", .{
			blocks.entries.len,
			if(blocks.droppedStateEntries != 0) " (state-predicated entries dropped)" else "",
		});
		if(blocks.droppedStateEntries != 0) {
			std.log.info("irisbridge: {} block entry(s) carry state predicates Cubyz cannot express, and are skipped", .{blocks.droppedStateEntries});
		}
	} else {
		std.log.info("irisbridge: no block.properties; mc_Entity stays 0 for every block", .{});
	}

	// Whether the overrides actually reached the shader source, not just whether they were read. An
	// override naming an option the pack does not declare - a typo, or a name it spells differently -
	// rewrites nothing and changes nothing, which makes any experiment run through the options file
	// unfalsifiable. Reported per program-source rewrite, so the count exceeds the number of
	// overrides whenever an option is declared in a header several programs include.
	if(overrides.count() != 0) {
		if(pack.appliedOverrideCount == 0) {
			std.log.err("irisbridge: none of the {} option override(s) matched a declaration — check the names against the generated options file", .{overrides.count()});
		} else {
			std.log.info("irisbridge: option overrides rewrote {} declaring line(s) across the pack's sources", .{pack.appliedOverrideCount});
		}
	}

	// The options this pack puts in its own settings screens, in the order it lists them. Kept on the
	// pipeline so the in-game screen can offer them; the strings borrow from the program sources,
	// which `programs` owns and which outlive it.
	const packOptions = collectPackOptions(allocator, programs, propertiesSource);

	// Written only when the user has none, so it can never overwrite their choices. The in-game
	// screen edits this same file, so the two agree on where a choice lives rather than each
	// keeping its own copy.
	if(!optionsFileExists) {
		writeOptionsTemplate(allocator, overridePath.items, name, programs, propertiesSource, &profiles);
	}

	// A `size.buffer` value, and an image's dimensions, are frequently `#define`d names rather
	// than literals - Complementary's `REFLECTION_RES`, its `COLORED_LIGHTING 64 COLORED_LIGHTING`
	// voxel volume - and have to resolve to the value actually compiled into the pack, after the
	// user's overrides. That is the whole option set as the rewritten sources carry it.
	var optionMacros = List(pack.Macro).init(allocator);
	defer optionMacros.deinit();
	for(declaredOptions) |option| optionMacros.append(.{.name = option.name, .value = option.current});
	pack.applyBufferSizes(&properties, &settings, optionMacros.items);
	// The pack's own images and buffers, from the same option-resolved properties. Parsed here,
	// ahead of the coverage report, so their sampler names count as supplied; allocated once the
	// render targets are, below.
	const imageDeclarations = pack.parseImages(allocator, &properties, optionMacros.items);
	const bufferObjects = pack.parseBufferObjects(&properties);

	// The pack's own `program.<name>.enabled` conditions, which join the same list a profile's
	// `!program.x` entries produce - exactly as Iris merges them into one `disabledPrograms`.
	collectOptionDisabledPrograms(declaredOptions, &properties, &disabledPrograms);

	// A profile's `!program.x` entries take effect here, on the same names `shaders.properties`
	// uses for `program.x.enabled` - so the two ways a pack can switch a program off agree. A
	// lettered compute is its own name in that list: photon writes `program.world0/deferred4_a.
	// enabled = SH_SKYLIGHT`, and the unsuffixed `deferred4` stays on either way.
	for(programs) |*program| {
		for(program.computes) |*compute| {
			if(compute.suffix.len == 0 or !compute.enabled) continue;
			if(!isNameDisabled(compute.name, disabledPrograms.items)) continue;
			compute.enabled = false;
			std.log.info("irisbridge: profile or option disabled compute {s}", .{compute.name});
		}
		if(!program.enabled) continue;
		if(!isProgramDisabled(allocator, program, disabledPrograms.items)) continue;
		program.enabled = false;
		// With the index: BSL's log used to read "disabled program composite" twice for
		// composite2 and composite3, which reads as the chain's first composite being off.
		std.log.info("irisbridge: profile or option disabled program {s}{}", .{program.kind.baseName(), program.index});
	}

	// After both disable passes, so the report describes the programs that will actually run.
	reportCoverage(allocator, name, programs, &properties, imageDeclarations);
	pack.reportUnsupportedDirectives(name, settings);

	var renderTargets = targets.RenderTargets.init(&settings);
	// Before the first `updateSize`, which is where the shadow colour pairs get their storage.
	renderTargets.shadowColorUsed = pack.shadowColorUsage(programs);
	// Which buffers are not screen-sized, resolved. A pack addresses a declared buffer with maths
	// that assumes its size, so a directive that fails to parse is not a missing feature - it puts
	// every read and write of that buffer in the wrong place, silently, and the parse failure is a
	// `continue` nobody sees. Reported at load so the answer is in the log rather than inferred.
	{
		var sizes = List(u8).init(allocator);
		defer sizes.deinit();
		for(&settings.colortexSize, 0..) |declared, index| {
			const axes = declared orelse continue;
			sizes.print(" colortex{}={}x{}", .{index, axes[0].resolve(main.renderer.lastWidth), axes[1].resolve(main.renderer.lastHeight)});
			if(axes[0] == .relative or axes[1] == .relative) sizes.appendSlice(" (relative)");
		}
		if(sizes.items.len != 0) {
			std.log.info("irisbridge: declared buffer sizes:{s} (screen is {}x{})", .{sizes.items, main.renderer.lastWidth, main.renderer.lastHeight});
		} else {
			std.log.info("irisbridge: pack declares no buffer sizes; every colortex is screen-sized", .{});
		}
	}
	// Allocate storage immediately. Loading happens lazily on the first rendered frame, which is
	// after `updateViewport` has already run, so waiting for the next resize would leave every
	// attachment a name without storage and the framebuffer incomplete.
	renderTargets.updateSize(main.renderer.lastWidth, main.renderer.lastHeight);
	// The pack's images and buffers, before any program links: the resource gate in
	// `pipeline.buildPass` accepts exactly what this set holds, and refuses the rest by name.
	var imageSet = images.Set.init(allocator, imageDeclarations, bufferObjects, main.renderer.lastWidth, main.renderer.lastHeight);
	if(imageSet.images.len != 0 or imageSet.buffers.len != 0) {
		const described = imageSet.describe(allocator);
		defer allocator.free(described);
		std.log.info("irisbridge: {} custom image(s) and {} buffer object(s) allocated:{s}", .{imageSet.images.len, imageSet.buffers.len, described});
	}
	const quad = pipeline.Quad.init();

	// Collect the post-chain programs in execution order. gbuffers and shadow programs are kept
	// in `programs` for later but take no part in the composite chain.
	var ordered = List(*pack.Program).init(allocator);
	defer ordered.deinit();
	for(programs) |*program| {
		if(!program.anyEnabled()) continue;
		if(!pipeline.isPostChainKind(program.kind)) continue;
		ordered.append(program);
	}
	std.mem.sort(*pack.Program, ordered.items, {}, lessThanByExecutionOrder);

	// Built first, and the flip sequence resolved afterwards over what actually built. A program
	// that failed to compile still has draw buffers, and resolving over the declared list handed
	// every later pass a phantom flip - the side nothing wrote (`flip.zig`, "a pass that never
	// runs must not be in the sequence"). Nothing here depends on a pass's bindings until they are
	// assigned below.
	var passes = List(pipeline.Pass).init(allocator);
	for(ordered.items) |program| {
		const built = pipeline.buildPass(allocator, program, programMacros, &properties, &imageSet) orelse continue;
		passes.append(built);
	}

	var prepareCount: usize = 0;
	var deferredCount: usize = 0;
	var beginCount: usize = 0;
	for(passes.items) |*pass| {
		if(pipeline.runsBeforeGeometry(pass.kind)) prepareCount += 1;
		if(pass.kind == .begin) beginCount += 1;
		if(pass.kind == .deferred) deferredCount += 1;
	}

	// The gbuffers stage takes no part in the flip sequence. That is not an optimisation, it is
	// the contract: geometry draws *over* whatever `prepare` left in the buffer, so it must write the
	// side that was last written rather than ping-ponging to the other one.
	//
	// Iris states this by inverting the flip set for the geometry framebuffer alone
	// (`RenderTargets.createGbufferFramebuffer`: `stageWritesToMain = invert(stageWritesToAlt, ...)`),
	// and by not advancing its `BufferFlipper` across the stage at all.
	//
	// Getting it wrong is quietly destructive rather than obviously broken. Nostalgia's `prepare1`
	// writes the sky *and the sun* into colortex0; with the composite convention, terrain went into
	// the opposite texture. The two then live in separate images, and any pass reading the sky side
	// sees a full-screen sky with the sun in it and no geometry in front - a sun glowing through
	// solid rock, visible even underground.
	//
	// A compute-only pass names no draw buffer and so flips nothing, which is how Iris's
	// `ComputeOnlyPass` sits in its chain too.
	var passDrawBuffers = List([]const u8).init(allocator);
	defer passDrawBuffers.deinit();
	for(passes.items) |*pass| {
		passDrawBuffers.append(if(pass.writesToScreen) &.{} else pass.drawBuffers.slice());
	}

	const allBindings = flip.resolveBindings(allocator, passDrawBuffers.items);
	defer allocator.free(allBindings);
	const finalFlip = flip.finalState(passDrawBuffers.items);

	// The `shadowcomp` chain, which has its own two-buffer flip over the shadow colour pair. Built
	// here because the side it leaves is what every other program reads `shadowcolor0` from, and
	// that has to be stamped into the bindings below before they are handed out. A shadow program
	// naming a buffer past `shadowcolor1` gets Iris's `{0, 1}` instead
	// (`ShadowRenderTargets.createColorFramebuffer`).
	var shadowComposites = List(pipeline.Pass).init(allocator);
	{
		var orderedShadow = List(*pack.Program).init(allocator);
		defer orderedShadow.deinit();
		for(programs) |*program| {
			if(program.kind != .shadowcomp or !program.anyEnabled()) continue;
			orderedShadow.append(program);
		}
		std.mem.sort(*pack.Program, orderedShadow.items, {}, lessThanByIndex);
		for(orderedShadow.items) |program| {
			var built = pipeline.buildPass(allocator, program, programMacros, &properties, &imageSet) orelse continue;
			if(built.program != 0) {
				var pastPair = false;
				for(built.drawBuffers.slice()) |target| {
					if(target >= flip.shadowColorCount) pastPair = true;
				}
				if(pastPair) {
					std.log.warn("irisbridge: shadowcomp{} names a shadow colour buffer past shadowcolor{}; drawing shadowcolor0 and 1 as Iris does", .{built.index, flip.shadowColorCount - 1});
					built.drawBuffers = .{.targets = [_]u8{0, 1} ++ [_]u8{0} ** 14, .count = 2};
				}
			}
			shadowComposites.append(built);
		}
	}
	var shadowDrawBuffers = List([]const u8).init(allocator);
	defer shadowDrawBuffers.deinit();
	for(shadowComposites.items) |*pass| shadowDrawBuffers.append(pass.drawBuffers.slice());
	const shadowChainBindings = flip.resolveBindings(allocator, shadowDrawBuffers.items);
	defer allocator.free(shadowChainBindings);
	const shadowFinalSides = flipSidesFor(flip.finalState(shadowDrawBuffers.items));
	var shadowSides: [flip.shadowColorCount]flip.Side = @splat(.main);
	for(&shadowSides, 0..) |*side, index| side.* = shadowFinalSides[index];
	for(allBindings) |*binding| binding.* = withShadowSides(binding.*, shadowSides);

	// Geometry writes the side the first post-geometry pass reads, which is exactly the side the
	// last `prepare` wrote. `read` carries that state; copying it over `write` is the inversion.
	var gbuffersBindings: flip.PassBindings = if(prepareCount < allBindings.len)
		allBindings[prepareCount]
	else
		withShadowSides(.{.read = flipSidesFor(finalFlip), .write = flipSidesFor(finalFlip)}, shadowSides);
	gbuffersBindings.write = gbuffersBindings.read;

	// The translucent draw comes *after* the deferred passes - Iris runs them in
	// `beginTranslucents` (`IrisRenderingPipeline.java:1061-1063`), between opaque and translucent
	// geometry, and builds the translucent programs against the flip state they leave
	// (`flippedAfterTranslucent`, `:317`). So water writes the side the first pass after deferred
	// reads, by the same inversion as above. Packs are written to that order: Bliss's water
	// reflects the sky its `deferred1` renders into colortex4, and drawn before that pass it
	// reflected a buffer nothing had written yet this frame, which is a black lake.
	var translucentBindings: flip.PassBindings = if(prepareCount + deferredCount < allBindings.len)
		allBindings[prepareCount + deferredCount]
	else
		withShadowSides(.{.read = flipSidesFor(finalFlip), .write = flipSidesFor(finalFlip)}, shadowSides);
	translucentBindings.write = translucentBindings.read;

	// The state the shadow pass runs in: after `begin`, before `prepare`. Its own program samples
	// the colortex set from there, and so do the `shadowcomp` passes and the `shadow.csh` chain.
	var shadowStageBindings: flip.PassBindings = if(beginCount < allBindings.len)
		allBindings[beginCount]
	else
		withShadowSides(.{.read = flipSidesFor(finalFlip), .write = flipSidesFor(finalFlip)}, shadowSides);
	shadowStageBindings.write = shadowStageBindings.read;
	for(shadowComposites.items, shadowChainBindings) |*pass, chain| {
		pass.bindings = shadowStageBindings;
		for(&pass.bindings.shadowRead, &pass.bindings.shadowWrite, 0..) |*read, *write, index| {
			read.* = chain.read[index];
			write.* = chain.write[index];
		}
	}

	// Which buffers the `begin` and `prepare` chains filled before geometry runs. This decides
	// whether Cubyz's sky is blitted in to stand in for the vanilla sky geometry, or whether the
	// pack drew its own and the blit would destroy it - see `beginTerrain`.
	const preparedTargets = flip.writtenTargets(passDrawBuffers.items[0..@min(prepareCount, passDrawBuffers.items.len)]);

	// What the chain has drawn to before each pass, for the override rule in `bindOverrides`. The
	// set restarts with every stage renderer in Iris - begin, prepare, deferred, and composite
	// together with final (`CompositeRenderer.java:96`, `FinalPassRenderer.java:84`); the gbuffers
	// and shadow programs get an empty one (`IrisRenderingPipeline.java:334`). So a buffer the
	// deferred stage wrote does not lapse a `texture.composite.*` override, which is what lets
	// photon hand `composite0` a worley volume under the name `colortex0` right after `deferred4`
	// drew the scene into that same name.
	var groupStart: usize = 0;
	var previousGroup: ?u8 = null;
	for(passes.items, allBindings, 0..) |*built, binding, index| {
		const group: u8 = switch(built.kind) {
			.begin => 0,
			.prepare => 1,
			.deferred => 2,
			.composite, .final => 3,
			else => 4,
		};
		if(previousGroup == null or previousGroup.? != group) {
			groupStart = index;
			previousGroup = group;
		}
		built.bindings = binding;
		built.writtenBefore = flip.writtenTargets(passDrawBuffers.items[groupStart..index]);
	}

	// The `setup` computes, one pass per `setupN.csh`, dispatched from `beginFrame` once the
	// targets have had their first clear. They see the sequence as it stands before anything has
	// run, which for `colorimgN` is the side geometry will write.
	var setupPasses = List(pipeline.Pass).init(allocator);
	{
		var orderedSetup = List(*pack.Program).init(allocator);
		defer orderedSetup.deinit();
		for(programs) |*program| {
			if(program.kind != .setup or !program.anyEnabled()) continue;
			orderedSetup.append(program);
		}
		std.mem.sort(*pack.Program, orderedSetup.items, {}, lessThanByIndex);
		for(orderedSetup.items) |program| {
			var built = pipeline.buildPass(allocator, program, programMacros, &properties, &imageSet) orelse continue;
			built.bindings = gbuffersBindings;
			setupPasses.append(built);
		}
	}

	// The `shadow.csh` chain, beside the shadow program, dispatched before the map is drawn.
	var shadowComputes: []pipeline.ComputePass = &.{};
	for(programs) |*program| {
		if(program.kind != .shadow) continue;
		shadowComputes = pipeline.buildComputes(allocator, program, programMacros, &imageSet);
		break;
	}

	// The resolved ping-pong table, dumped once at load rather than per frame, because it is static:
	// `resolveBindings` walks the pass list one time and nothing changes it afterwards.
	//
	// It is here because a wrong side does not error - it reads a real, complete texture holding an
	// *older* frame's or an older pass's contents. That shows up as a value which is plausible in
	// isolation and impossible in sequence, which is exactly what a per-pass pixel trace catches and
	// nothing else does. A pass whose output equals the output of the pass two steps back, rather than
	// the one immediately before it, is reading the side that one wrote.
	//
	// Only the albedo target is listed: it is the one every pass in the tail of a chain reads and
	// writes, so an off-by-one anywhere in the sequence shows up here first.
	{
		var table = List(u8).init(allocator);
		defer table.deinit();
		for(passes.items) |*built| {
			if(built.program == 0) {
				table.print("\n    {s}{} dispatches {} compute(s), draws nothing", .{built.kind.baseName(), built.index, built.computes.len});
				continue;
			}
			table.print("\n    {s}{} draws", .{built.kind.baseName(), built.index});
			if(built.drawBuffers.slice().len == 0) {
				table.appendSlice(" screen");
			} else {
				for(built.drawBuffers.slice()) |target| table.print(" {}", .{target});
			}
			table.print("   colortex0 read={s} write={s}", .{
				@tagName(built.bindings.read[0]),
				@tagName(built.bindings.write[0]),
			});
			if(built.computes.len != 0) table.print(" after {} compute(s)", .{built.computes.len});
		}
		for(shadowComposites.items) |*built| {
			table.print("\n    shadowcomp{} ", .{built.index});
			if(built.program == 0) {
				table.print("dispatches {} compute(s), draws nothing", .{built.computes.len});
				continue;
			}
			table.appendSlice("draws shadowcolor");
			for(built.drawBuffers.slice()) |target| table.print(" {}", .{target});
			table.print("   shadowcolor0 read={s} write={s}", .{@tagName(built.bindings.shadowRead[0]), @tagName(built.bindings.shadowWrite[0])});
		}
		if(setupPasses.items.len != 0) table.print("\n    {} setup pass(es), {} shadow compute(s)", .{setupPasses.items.len, shadowComputes.len});
		std.log.info("irisbridge: resolved pass order and colortex0 sides:{s}", .{table.items});
	}

	// The terrain gbuffers program, run on Cubyz's own geometry through the SSBO-pull prologue.
	var terrainPass: ?pipeline.Pass = null;
	// Through Iris's fallback chain (`pack.findProgram`): a pack with no `gbuffers_terrain` draws
	// terrain with `gbuffers_textured_lit`, `gbuffers_textured` or `gbuffers_basic`, whichever it
	// ships first, as `ProgramFallbackResolver` resolves it. The older and smaller packs are built
	// that way, and until 2026-09-12 they got no terrain program here at all.
	if(pack.findProgram(programs, .gbuffers_terrain)) |program| {
		terrainPass = pipeline.buildGbuffersPass(allocator, program, programMacros, &properties, false, true, &imageSet);
		if(terrainPass) |*built| {
			// Taken from the resolved sequence rather than assumed: `prepare` runs first and may
			// already have flipped a buffer geometry writes.
			built.bindings = gbuffersBindings;
		}
		if(terrainPass != null) {
			std.log.info("irisbridge: {s} compiled against the Cubyz vertex prologue as the terrain program", .{program.kind.baseName()});
		} else {
			std.log.warn("irisbridge: {s} did not compile against the prologue as the terrain program", .{program.kind.baseName()});
		}
	}

	// The shadow program uses the same prologue: it is ordinary terrain geometry drawn from a
	// different viewpoint.
	var shadowPass: ?pipeline.Pass = null;
	for(programs) |*program| {
		if(program.kind != .shadow) continue;
		// Tinted, like the water program: the shadow pass draws the transparent meshes too, and a
		// fluid's texture has to arrive there as it does in the camera pass - grey beside a
		// coloured `glColor`, its alpha at Minecraft's - or the pack's `shadow.fsh` writes its
		// shadow colour from Cubyz's dark texel at 0.42. The opaque meshes are untouched by it:
		// the tint returns early for anything that is not a fluid.
		shadowPass = pipeline.buildGbuffersPass(allocator, program, programMacros, &properties, true, true, &imageSet);
		if(shadowPass) |*built| {
			// The shadow pass draws into the shadow depth map and the `shadowcolor` buffers its
			// DRAWBUFFERS name (`renderShadowMap`), never into the colortex set, so these bindings
			// only decide what its samplers read: the state after `begin`, which is what its
			// place in the frame - before `prepare` - leaves for it.
			built.bindings = shadowStageBindings;
			std.log.info("irisbridge: shadow program compiled", .{});
		} else {
			std.log.warn("irisbridge: shadow program did not compile; shadows stay unoccluded", .{});
		}
		break;
	}

	// Cubyz's transparent chunk meshes are the same SSBO geometry as the opaque ones - the mesher
	// sorts them into a second list and the renderer draws them with a blending pipeline. So water
	// needs no new geometry path, only the pack's own translucent program over the same prologue.
	//
	// `pack.zig` resolves the fallback chain, so a pack shipping only `gbuffers_terrain` still
	// lands here with terrain's source, which is what Minecraft does too.
	var waterPass: ?pipeline.Pass = null;
	// `gbuffers_water` falls back to `gbuffers_terrain` in Iris, so a pack that ships only the
	// latter still draws its water through the pack; one that switched its water program off gets
	// the fallback too, which is what Iris's disabling means.
	if(pack.findProgram(programs, .gbuffers_water)) |program| {
		// No alpha test: `TERRAIN_TRANSLUCENT` carries `AlphaTests.OFF` (`ShaderKey.java:28`).
		waterPass = pipeline.buildGbuffersPass(allocator, program, programMacros, &properties, true, false, &imageSet);
		if(waterPass) |*built| {
			// Translucents draw after the opaque pass and into the same buffers, so they share its
			// side of the flip. Taking the post-chain's first binding instead would put water on the
			// side nothing reads.
			//
			// The post-deferred side when the pack's own terrain program is in use, because that is
			// when the deferred passes run early (`beginTranslucent`); without it the scene is only
			// imported at post-chain time, deferred stays late, and water shares the geometry side.
			built.bindings = if(terrainPass != null) translucentBindings else gbuffersBindings;
			std.log.info("irisbridge: {s} compiled as the water program; transparent chunks draw through the pack", .{program.kind.baseName()});
		} else {
			std.log.warn("irisbridge: {s} did not compile as the water program; transparent chunks keep Cubyz's shader", .{program.kind.baseName()});
		}
	}

	// The pack's own sky geometry, if it draws any.
	//
	// Built unconditionally rather than behind a per-pack check, because whether a pack uses this
	// program is something the program itself decides at draw time: Nostalgia's collapses its vertex
	// to `vec4(-1.0)` and Kappa's discards, so both rasterise nothing and the imported Cubyz sky they
	// already relied on survives untouched. Complementary computes its atmosphere here and writes it.
	// No detection, no branch on a pack name.
	var skyPass: ?pipeline.Pass = null;
	if(pack.findProgram(programs, .gbuffers_skybasic)) |program| {
		skyPass = pipeline.buildSkyPass(allocator, program, programMacros, &properties, &imageSet, false);
		if(skyPass) |*built| {
			// Drawn during the gbuffers stage, so it shares that stage's side of the flip - the sky
			// is the thing terrain then draws *over*, in the same image.
			built.bindings = gbuffersBindings;
			std.log.info("irisbridge: {s} compiled as the sky program; the pack's own sky draws before terrain", .{program.kind.baseName()});
		} else {
			std.log.warn("irisbridge: {s} did not compile as the sky program; Cubyz's sky stands in", .{program.kind.baseName()});
		}
	}

	// The sun and the moon, through `gbuffers_skytextured` over quads the bridge builds where
	// Minecraft's `renderSky` puts them (`prologue.skyTexturedVertex`, `drawCelestialBodies`). BSL
	// draws both this way by default, Kappa and Nostalgia the moon, and Complementary's Reimagined
	// style and the voxel packs built on it both; until 2026-09-12 none of them had a sun or a
	// moon here at all, since the program was never given anything to draw.
	var skyTexturedPass: ?pipeline.Pass = null;
	if(pack.findProgram(programs, .gbuffers_skytextured)) |program| {
		skyTexturedPass = pipeline.buildSkyPass(allocator, program, programMacros, &properties, &imageSet, true);
		if(skyTexturedPass) |*built| {
			built.bindings = gbuffersBindings;
			std.log.info("irisbridge: {s} compiled as the textured sky program; the sun and moon draw before terrain", .{program.kind.baseName()});
		} else {
			std.log.warn("irisbridge: {s} did not compile as the textured sky program; no sun or moon quads", .{program.kind.baseName()});
		}
	}

	if(passes.items.len == 0) {
		std.log.err("irisbridge: {s} produced no compilable passes", .{name});
		passes.deinit();
		// The gbuffers programs linked before this point and are not in `passes`, so they need
		// releasing by name or their GL programs outlive the failed load.
		if(terrainPass) |*item| item.deinit(allocator);
		if(shadowPass) |*item| item.deinit(allocator);
		if(waterPass) |*item| item.deinit(allocator);
		if(skyPass) |*item| item.deinit(allocator);
		if(skyTexturedPass) |*item| item.deinit(allocator);
		for(shadowComposites.items) |*item| item.deinit(allocator);
		shadowComposites.deinit();
		for(setupPasses.items) |*item| item.deinit(allocator);
		setupPasses.deinit();
		for(shadowComputes) |*item| item.deinit(allocator);
		if(shadowComputes.len != 0) allocator.free(shadowComputes);
		imageSet.deinit();
		var mutableTargets = renderTargets;
		mutableTargets.deinit();
		var mutableQuad = quad;
		mutableQuad.deinit();
		// Before the programs, whose sources these borrow from.
		allocator.free(packOptions);
		for(programs) |*program| program.deinit(allocator);
		allocator.free(programs);
		return false;
	}

	active = .{
		.name = allocator.dupe(u8, name),
		.settings = settings,
		.programs = programs,
		.renderTargets = renderTargets,
		.quad = quad,
		.passes = passes.toOwnedSlice(),
		.terrainPass = terrainPass,
		.shadowPass = shadowPass,
		.shadowTranslucent = properties.getBool("shadowTranslucent", true),
		.waterPass = waterPass,
		// Built above and, until 2026-09-12, never stored: `drawPackSky` found null every frame,
		// and no pack's `gbuffers_skybasic` ever drew. Complementary computes its atmosphere there.
		.skyPass = skyPass,
		.skyTexturedPass = skyTexturedPass,
		.drawSun = properties.getBool("sun", true),
		.drawMoon = properties.getBool("moon", true),
		.custom = customuniforms.build(allocator, &properties),
		.textures = packtextures.init(allocator, shadersRoot, settings.noiseTextureResolution, properties.get("texture.noise") orelse "", &properties),
		.blocks = blocks,
		.finalFlip = finalFlip,
		.gbuffersBindings = gbuffersBindings,
		.preparedTargets = preparedTargets,
		.packOptions = packOptions,
		.profiles = profiles,
		.images = imageSet,
		.setupPasses = setupPasses.toOwnedSlice(),
		.setupPending = true,
		.shadowComputes = shadowComputes,
		.shadowCompositePasses = shadowComposites.toOwnedSlice(),
		.depthRestore = pipeline.DepthRestore.init(),
	};
	blocksOwned = false;
	profilesOwned = false;
	// Built here if a world is already loaded, and by `rebuildIfStale` on the first frame after one
	// is: the pack can load before the block registry is populated.
	blockids.rebuildIfStale(allocator, &active.?.blockIdTable, &active.?.blocks);
	std.log.info("irisbridge: loaded {s} ({} programs, {} passes in the chain)", .{name, programs.len, active.?.passes.len});
	return true;
}

/// The options a pack puts in its own settings screens, in the order it lists them.
///
/// Same curation the generated file uses, and for the same reason: a pack declares several hundred
/// `#define`s of which a few dozen are options and the rest are internal constants, and only the
/// pack's own `screen`/`sliders` keys separate the two. A pack that declares no screens falls back
/// to the defines that carry a `//[a b c]` list, since without one an option is indistinguishable
/// from a constant.
///
/// The returned `Option`s borrow from the program sources, so `programs` must outlive them.
fn collectPackOptions(allocator: NeverFailingAllocator, programs: []const pack.Program, propertiesSource: []const u8) []options.Option {
	var sources = List([]const u8).init(allocator);
	defer sources.deinit();
	appendSources(&sources, programs, false);

	const declared = options.discoverAll(allocator, sources.items);
	defer allocator.free(declared);

	var screens = options.parseScreens(allocator, propertiesSource);
	defer screens.deinit();

	var result = List(options.Option).init(allocator);
	for(screens.names) |screenName| {
		for(declared) |option| {
			if(!std.mem.eql(u8, option.name, screenName)) continue;
			result.append(option);
			break;
		}
	}
	if(result.items.len == 0) {
		for(declared) |option| {
			if(option.allowed.len == 0) continue;
			result.append(option);
		}
	}
	return result.toOwnedSlice();
}

/// Writes the options file a settings screen would otherwise stand in for.
///
/// Only ever called when the file does not exist, so it cannot overwrite anything: the check is in
/// the caller, next to the read that establishes it.
///
/// The option list comes from the pack's *already include-resolved* program sources, which is the
/// only place options can be found - a pack declares them in shared headers and the files that
/// include them, not in `shaders.properties`.
fn writeOptionsTemplate(
	allocator: NeverFailingAllocator,
	path: []const u8,
	packName: []const u8,
	programs: []const pack.Program,
	propertiesSource: []const u8,
	profiles: *const options.Profiles,
) void {
	var sources = List([]const u8).init(allocator);
	defer sources.deinit();
	appendSources(&sources, programs, false);

	const declared = options.discoverAll(allocator, sources.items);
	defer allocator.free(declared);

	var screens = options.parseScreens(allocator, propertiesSource);
	defer screens.deinit();

	const text = options.renderTemplate(allocator, packName, declared, &screens, profiles);
	defer allocator.free(text);

	main.files.cwd().write(path, text) catch |err| {
		std.log.warn("irisbridge: could not write {s}: {s}", .{path, @errorName(err)});
		return;
	};
	std.log.info("irisbridge: wrote {s} listing this pack's options; edit it to change them", .{path});
}

/// Reports which uniforms this pack reads that nothing supplies.
///
/// Run on every load rather than behind a debug flag, because the gap it describes is invisible by
/// construction: an unsupplied uniform links cleanly and reads zero. This is the difference between
/// "the pack looks wrong" and knowing which value it is missing.
fn reportCoverage(
	allocator: NeverFailingAllocator,
	name: []const u8,
	programs: []const pack.Program,
	properties: *const pack.Properties,
	imageDeclarations: []const pack.ImageDeclaration,
) void {
	var sources = List([]const u8).init(allocator);
	defer sources.deinit();
	appendSources(&sources, programs, true);

	// A uniform the pack declares as an expression is supplied by `customuniforms`, not missing;
	// nor is an image the pack declared, or the sampler it reads that image through.
	var customNames = List([]const u8).init(allocator);
	defer customNames.deinit();
	const declarations = customuniforms.parseDeclarations(allocator, properties);
	defer {
		for(declarations) |*declaration| declaration.deinit(allocator);
		allocator.free(declarations);
	}
	for(declarations) |declaration| customNames.append(declaration.name);
	for(imageDeclarations) |declaration| {
		customNames.append(declaration.name);
		if(declaration.samplerName) |samplerName| customNames.append(samplerName);
	}
	// And the pack's own `customTexture.<name>` samplers, which `packtextures` binds by name.
	packtextures.appendNamedTextureNames(properties, &customNames);

	const missing = coverage.missingUniforms(allocator, sources.items, customNames.items);
	defer allocator.free(missing);
	coverage.report(allocator, name, missing);
	coverage.reportUnsupported(allocator, name, sources.items);
}

/// The per-target read side implied by a flip state, for the degenerate case where a pack has
/// nothing but `prepare` passes and there is no later pass to take the state from.
fn flipSidesFor(state: flip.FlipState) [flip.colortexCount]flip.Side {
	var sides: [flip.colortexCount]flip.Side = @splat(.main);
	for(0..flip.colortexCount) |index| {
		sides[index] = if(state.isFlipped(@intCast(index))) .alt else .main;
	}
	return sides;
}

/// Programs the pack switches off through its own options, as `program.<name>.enabled = <condition>`.
///
/// Five of the six packs in the corpus use this and none of them with a literal, so until now every
/// one of them was running programs it had asked to have disabled. See `options.evaluateCondition` for
/// the grammar and for what each pack writes.
///
/// The option set is `declaredOptionsOf`, not the screen-curated list `collectPackOptions` builds:
/// a pack is free to gate a program on an option it never puts in a settings screen, and photon's
/// `TAAU` is exactly that.
///
/// Program names borrow from `properties`, which outlives the disable pass in `load`.
fn collectOptionDisabledPrograms(
	declared: []const options.Option,
	properties: *const pack.Properties,
	out: *List([]const u8),
) void {
	var iterator = properties.entries.iterator();
	while(iterator.next()) |entry| {
		const key = entry.key_ptr.*;
		if(!std.mem.startsWith(u8, key, "program.")) continue;
		if(!std.mem.endsWith(u8, key, ".enabled")) continue;
		var name = key["program.".len .. key.len - ".enabled".len];

		// Iris keys these by the program's *path*, so packs write the dimension folder -
		// `program.world0/composite2.enabled`. Cubyz has one dimension and only loads `world0`, so a
		// directive for another one is ignored rather than collapsed onto this one: a pack may
		// legitimately enable a program in the nether and not in the overworld, and photon writes a
		// full set for all three.
		if(std.mem.indexOfScalar(u8, name, '/')) |slash| {
			if(!std.mem.eql(u8, name[0..slash], overworldDirectory)) continue;
			name = name[slash + 1 ..];
		}

		const condition = std.mem.trim(u8, entry.value_ptr.*, " \t");
		var unknown: []const u8 = "";
		if(options.evaluateCondition(condition, declared, &unknown)) continue;

		out.append(name);
		if(unknown.len != 0) {
			// The one way this can be wrong: a name we failed to discover reads as off, and the
			// program is dropped when the pack wanted it. Reported at warning level precisely because
			// the consequence - a silently shorter chain - is the kind this project keeps paying for.
			std.log.warn("irisbridge: {s} switched off by `{s}`, but '{s}' matches no option this pack declares", .{name, condition, unknown});
		} else {
			std.log.info("irisbridge: {s} switched off by the pack's own `{s}`", .{name, condition});
		}
	}
}

/// Every option the pack's sources declare, at the value the rewritten source carries - the
/// bridge's counterpart of Iris's `ShaderPackOptions`. Vertex and fragment stages both, since a pack
/// is free to declare an option in either. Caller frees the result; the strings borrow from
/// `programs`.
fn declaredOptionsOf(allocator: NeverFailingAllocator, programs: []const pack.Program) []options.Option {
	var sources = List([]const u8).init(allocator);
	defer sources.deinit();
	appendSources(&sources, programs, false);
	return options.discoverAll(allocator, sources.items);
}

/// Whether a profile's `!program.<name>` list names this program.
///
/// The name is rebuilt the way the loader spells it for `program.<name>.enabled` - base name plus
/// index, with index 0 left off - so `!program.composite` and `!program.composite5` select what a
/// pack author would expect.
fn isProgramDisabled(allocator: NeverFailingAllocator, program: *const pack.Program, disabled: []const []const u8) bool {
	if(disabled.len == 0) return false;
	var key = List(u8).init(allocator);
	defer key.deinit();
	key.appendSlice(program.kind.baseName());
	if(program.kind.isNumbered() and program.index != 0) key.print("{}", .{program.index});
	return isNameDisabled(key.items, disabled);
}

fn isNameDisabled(name: []const u8, disabled: []const []const u8) bool {
	for(disabled) |entry| {
		if(std.mem.eql(u8, entry, name)) return true;
	}
	return false;
}

/// Selects one of the pack's own presets, if the user asked for one.
///
/// Reported rather than silently skipped in both directions: naming a profile that does not exist
/// looks identical in-game to naming one that does nothing, and a pack shipping profiles that
/// nobody selected is worth mentioning because the source defaults a pack is left at are frequently
/// not one of its own presets.
fn applyRequestedProfile(
	allocator: NeverFailingAllocator,
	profiles: *const options.Profiles,
	requested: ?[]const u8,
	overrides: *options.Overrides,
	disabledPrograms: *List([]const u8),
) void {
	if(profiles.count() == 0) return;

	const wanted = requested orelse {
		var names = List(u8).init(allocator);
		defer names.deinit();
		for(profiles.names, 0..) |profileName, index| {
			if(index != 0) names.appendSlice(", ");
			names.appendSlice(profileName);
		}
		std.log.info("irisbridge: pack offers profiles: {s} (select one with `profile = <name>` in the options file)", .{names.items});
		return;
	};

	const before = overrides.count();
	if(!profiles.apply(allocator, wanted, overrides, disabledPrograms)) {
		std.log.err("irisbridge: no profile named '{s}' in this pack", .{wanted});
		return;
	}
	std.log.info("irisbridge: profile '{s}' set {} option(s){s}", .{
		wanted,
		overrides.count() - before,
		if(disabledPrograms.items.len != 0) " and disabled programs" else "",
	});
}

/// Cubyz has a single dimension, so packs are read from their overworld folder.
const overworldDirectory = "world0";

/// Which pack name the current `active` pipeline was built from, so a settings change reloads and
/// an unchanged setting does not retry a pack that already failed.
var loadedFor: ?[]const u8 = null;

/// Set when the settings screen changes a pack option, to force a reload the name comparison alone
/// would not trigger. Written from the GUI thread and consumed on the render thread.
var reloadRequested = std.atomic.Value(bool).init(false);

/// Loads or unloads to match `settings.shaderPack`.
///
/// Done lazily on the first frame rather than at startup because building the pipeline needs a
/// live GL context, and because the pack directory is only meaningful once the working directory
/// is the Cubyz root.
fn ensureLoaded() void {
	const wanted = main.settings.shaderPack;
	// Set by the settings screen when it changes an option: the pack name is unchanged, but the file
	// the loader reads its options from is not, so the comparison below would otherwise skip the
	// reload. Cleared here, on the render thread, which is also the only place `loadedFor` is freed.
	const forced = reloadRequested.swap(false, .monotonic);
	if(loadedFor) |previous| {
		if(!forced and std.mem.eql(u8, previous, wanted)) return;
		main.globalAllocator.free(previous);
		loadedFor = null;
	}
	// Remember the attempt before making it, so a pack that fails to load is not retried every
	// single frame - that would spam the log and stall the frame rate to a crawl.
	loadedFor = main.globalAllocator.dupe(u8, wanted);

	unload(main.globalAllocator);
	if(wanted.len == 0) return;
	_ = load(main.globalAllocator, main.io, wanted);
}

pub fn unload(allocator: NeverFailingAllocator) void {
	if(active) |*state| {
		allocator.free(state.name);
		state.deinit(allocator);
	}
	active = null;
}

/// Fills `out` with the name of every shaderpack present, for a settings screen to list.
///
/// Writes into a caller-owned list rather than returning a slice on purpose: the generated hook has
/// to synthesise a return value when the mod is absent, and there is no valid zero value for a
/// non-optional slice. A `void` hook that fills a list degrades to "adds nothing", which is exactly
/// right - with no mod installed there are no packs to offer.
///
/// Names are duped into `allocator`; the caller owns them.
pub fn listShaderPacks(allocator: NeverFailingAllocator, out: *List([]const u8)) void {
	const entries = install.list(allocator, main.io, shaderpackDirectory);
	defer install.freeList(allocator, entries);
	for(entries) |entry| out.append(allocator.dupe(u8, entry.name));
}

// MARK: pack options

/// The path of the loaded pack's options file. Caller frees.
fn optionsPathFor(allocator: NeverFailingAllocator, packName: []const u8) []u8 {
	var path = List(u8).init(allocator);
	path.appendSlice(shaderpackDirectory);
	path.append('/');
	path.appendSlice(packName);
	path.appendSlice(".options.txt");
	return path.toOwnedSlice();
}

/// Fills `out` with the loaded pack's own options, for the in-game settings screen.
///
/// Adds nothing when no pack is loaded, which is the same graceful degradation `listShaderPacks`
/// relies on: the generated hook is a no-op without the mod, and "no options offered" is the right
/// answer in both cases.
///
/// The current value is resolved the way the loader resolves it - the user's override where there is
/// one, otherwise what the pack's source declares - so the screen shows what is actually in effect
/// rather than what the pack shipped. The file is re-read here rather than cached because it is the
/// single source of truth and a user may have edited it by hand since the pack loaded.
pub fn listPackOptions(allocator: NeverFailingAllocator, out: *List(main.renderer.ShaderPackOption)) void {
	const state = &(active orelse return);

	const path = optionsPathFor(allocator, state.name);
	defer allocator.free(path);
	var overrides = blk: {
		const text = main.files.cwd().read(allocator, path) catch break :blk options.Overrides.init(allocator);
		defer allocator.free(text);
		break :blk options.Overrides.parse(allocator, text);
	};
	defer overrides.deinit();

	// The pack's presets come first: one click there sets many options at once, which is what a
	// shader settings screen leads with too.
	if(state.profiles.count() != 0) {
		var values = List([]const u8).init(allocator);
		for(state.profiles.names) |profileName| values.append(allocator.dupe(u8, profileName));
		const selected = overrides.map.get("profile");
		out.append(.{
			.name = allocator.dupe(u8, "profile"),
			.value = allocator.dupe(u8, selected orelse "(pack default)"),
			.values = values.toOwnedSlice(),
			.overridden = selected != null,
		});
	}

	for(state.packOptions) |option| {
		var values = List([]const u8).init(allocator);
		if(option.kind == .boolean and option.allowed.len == 0) {
			values.append(allocator.dupe(u8, "true"));
			values.append(allocator.dupe(u8, "false"));
		} else {
			var items = std.mem.tokenizeAny(u8, option.allowed, " \t");
			while(items.next()) |item| values.append(allocator.dupe(u8, item));
		}
		// An option with nothing to choose between cannot be operated by a screen that cycles values,
		// and showing a dead row is worse than leaving it to the file.
		if(values.items.len == 0) {
			values.deinit();
			continue;
		}

		const override = overrides.map.get(option.name);
		// Booleans read as the words the file accepts rather than the pack's internal 1/0, matching
		// what the generated template writes.
		const packValue: []const u8 = if(option.kind == .boolean)
			(if(std.mem.eql(u8, option.current, "0")) "false" else "true")
		else
			option.current;

		out.append(.{
			.name = allocator.dupe(u8, option.name),
			.value = allocator.dupe(u8, override orelse packValue),
			.values = values.toOwnedSlice(),
			.overridden = override != null,
		});
	}
}

/// Sets one option in the loaded pack's options file, and reloads the pipeline to apply it.
///
/// The file is edited rather than regenerated, so the legal-value hints and any notes the user wrote
/// survive - and so that a choice made in game and a choice typed into the file are the same thing
/// in the same place, rather than two settings that can disagree.
///
/// The reload is requested by clearing `loadedFor`, not performed here. This runs from a GUI
/// callback, on the main thread, with no GL context current; `ensureLoaded` picks it up on the next
/// frame on the render thread, which is where every other load already happens.
pub fn setPackOption(name: []const u8, value: []const u8) void {
	const state = &(active orelse return);
	const allocator = main.globalAllocator;

	const path = optionsPathFor(allocator, state.name);
	defer allocator.free(path);

	const existing = main.files.cwd().read(allocator, path) catch allocator.dupe(u8, "");
	defer allocator.free(existing);

	const updated = options.updateFile(allocator, existing, name, value);
	defer allocator.free(updated);

	main.files.cwd().write(path, updated) catch |err| {
		std.log.err("irisbridge: could not write {s}: {s}", .{path, @errorName(err)});
		return;
	};

	// Only a flag. Freeing `loadedFor` from here would hand the render thread a dangling pointer to
	// compare against mid-frame; `ensureLoaded` owns that string and releases it itself.
	reloadRequested.store(true, .monotonic);
}

/// Called when the window resizes, before any rendering that frame.
pub fn updateSize(width: u31, height: u31) void {
	const state = &(active orelse return);
	const before = [2]u31{state.renderTargets.width, state.renderTargets.height};
	state.renderTargets.updateSize(width, height);
	state.images.updateSize(width, height);
	// Iris runs the `setup` computes again after a resize (`IrisRenderingPipeline.java:979-988`),
	// once the targets have been cleared afresh - which `beginFrame` does before it dispatches.
	if(before[0] != state.renderTargets.width or before[1] != state.renderTargets.height) state.setupPending = true;
}

/// Called at the start of world rendering, before Cubyz draws anything.
///
/// Uniforms are captured here rather than at use time so every pass in the frame sees one
/// consistent snapshot. Sampling per pass would let the camera matrices drift between the
/// gbuffers stage and the composite chain that reprojects against them.
pub fn beginFrame(deltaTime: f32, playerPos: main.vec.Vec3d) void {
	ensureLoaded();
	const state = &(active orelse return);
	// The block registry is repopulated on every world load, and the pack usually loads before the
	// first world does, so the `mc_Entity` table is checked here rather than only at load time.
	blockids.rebuildIfStale(main.globalAllocator, &state.blockIdTable, &state.blocks);
	state.frameUniforms = uniforms.capture(deltaTime, playerPos, &state.settings);
	// Custom uniforms are expressions over the built-in ones, so they must be evaluated after the
	// snapshot and before any pass uploads.
	state.custom.evaluate(&state.frameUniforms, deltaTime);
	state.renderTargets.clear();

	// The pack's images marked `clear`, zeroed before anything writes them this frame, and its
	// buffers on their binding points (`IrisRenderingPipeline.java:864-866`).
	state.images.clearPerFrame();
	state.images.bindBuffers();

	// Iris's order at the top of the frame, after the clears: the `setup` computes once at load and
	// after a resize (`:500-519`, `:979-988`), then the `begin` passes (`:994`), both before the
	// shadow map and everything else. The screen is the render size Iris hands `begin`; `setup` is
	// dispatched at 1 by 1.
	const screenWidth: u31 = @intCast(main.Window.width);
	const screenHeight: u31 = @intCast(main.Window.height);
	if(state.setupPending) {
		state.setupPending = false;
		for(state.setupPasses) |*pass| {
			pipeline.runPass(&state.quad, &state.renderTargets, &state.textures, &state.images, &state.custom, pass, &state.frameUniforms, 1, 1);
		}
	}
	for(state.passes) |*pass| {
		if(pass.kind != .begin) continue;
		pipeline.runPass(&state.quad, &state.renderTargets, &state.textures, &state.images, &state.custom, pass, &state.frameUniforms, screenWidth, screenHeight);
	}
	c.glUseProgram(0);
	c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
	c.glEnable(c.GL_DEPTH_TEST);
	c.glDepthMask(c.GL_TRUE);
}

/// Runs the deferred/composite/final chain over what Cubyz just rendered.
///
/// Called after Cubyz's own deferred pass and before the HUD, so the pack's `final` output lands
/// on the screen and the interface still draws on top of it.
pub fn runPostChain(worldFramebuffer: c_uint, screenWidth: u31, screenHeight: u31) void {
	const state = &(active orelse return);
	if(state.passes.len == 0) return;

	// Anything the geometry stage stored through a `colorimgN` image has to be visible to the
	// chain. One barrier for the whole stage, rather than one per draw the engine issued.
	c.glMemoryBarrier(pipeline.imageBarrierBits);

	// Depth always comes from Cubyz's pass; colour only when no gbuffers program produced it.
	//
	// `gbuffersBindings`, not `passes[0].bindings`. When this blit runs at all it is *standing in for
	// the whole gbuffers stage*, so it has to land on the side that stage writes - the side the last
	// `prepare` wrote. `passes[0]` is the first `prepare` pass, whose read side is the sequence before
	// anything has run, and the two differ for any pack whose `prepare` chain writes colortex0 an odd
	// number of times. Nostalgia's does, in `skyboxApply.fsh`.
	state.renderTargets.importWorld(worldFramebuffer, state.gbuffersBindings, state.terrainPass == null);



	for(state.passes) |*pass| {
		if(pipeline.runsBeforeGeometry(pass.kind)) continue;
		// Already run between the opaque and translucent geometry, where Iris runs them.
		if(pass.kind == .deferred and state.deferredRanEarly) continue;
		runPostPass(state, pass, screenWidth, screenHeight);
	}
	state.deferredRanEarly = false;

	finishPostChain(state, screenWidth, screenHeight);
}

/// One post-chain pass.
fn runPostPass(state: *Pipeline, pass: *pipeline.Pass, screenWidth: u31, screenHeight: u31) void {
	{
		pipeline.runPass(&state.quad, &state.renderTargets, &state.textures, &state.images, &state.custom, pass, &state.frameUniforms, screenWidth, screenHeight);

	}
}

/// Everything after the last pass: the no-`final` blit, the history copies and the GL state the
/// rest of the frame expects.
fn finishPostChain(state: *Pipeline, screenWidth: u31, screenHeight: u31) void {
	// A chain with no `final` leaves the frame in colortex0, and Iris draws that to the screen
	// itself. So does this - otherwise a pack whose `final` was refused, or which never shipped
	// one, shows the GUI over whatever the window held before, which reads as a hang.
	var hasFinal = false;
	for(state.passes) |*pass| {
		if(pass.writesToScreen) hasFinal = true;
	}
	if(!hasFinal) {
		const sides = flipSidesFor(state.finalFlip);
		state.renderTargets.blitToScreen(0, .{.read = sides, .write = sides}, screenWidth, screenHeight);
	}


	// Filters back to plain before the copies, where Iris resets them too.
	state.renderTargets.resetMipmapping();

	// Carry every accumulation buffer over to the side the next frame reads from. Must happen after
	// the whole chain, since it is the *end* of frame state that decides which side is current.
	state.renderTargets.swapFlippedBuffers(state.finalFlip);

	// Leave GL as the rest of the frame expects to find it, rather than with the last pass's
	// state still applied - the HUD draws immediately after this.
	// Sampler objects are global state; leaving them bound would change how Cubyz's own shaders
	// sample those units for the rest of the frame.
	state.renderTargets.unbindShadowSamplers();
	c.glUseProgram(0);
	c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
	c.glEnable(c.GL_DEPTH_TEST);
	c.glDepthMask(c.GL_TRUE);
	c.glActiveTexture(c.GL_TEXTURE0);
}


/// Stamps the scene's depth into the currently bound framebuffer.
///
/// Called on the default framebuffer after the post chain, so the block selection outline - which
/// draws there rather than into the pack's G-buffer - is occluded by the world. Without it every
/// edge of the selection cube passes the depth test, including the six inside the block, and the
/// result reads as an X-ray wireframe.
///
/// A no-op without a pack, where the outline still draws with the world and needs nothing.
pub fn restoreSceneDepth() void {
	const state = &(active orelse return);
	if(state.terrainPass == null) return;
	state.depthRestore.draw(&state.quad, state.renderTargets.depth[0]);
}

/// Drops the reprojection history, for teleports and world changes.
pub fn resetHistory() void {
	uniforms.resetHistory();
}

// MARK: terrain gbuffers

/// Uniforms the generated prologue declares, which no pack knows about.
///
/// Separate from the pack's own uniform set because these describe Cubyz's SSBO encoding rather
/// than anything in the shaderpack format.
fn bindTerrainUniforms(projMatrix: main.vec.Mat4f, ambient: main.vec.Vec3f, playerPos: main.vec.Vec3d) void {
	const state = &(active orelse return);
	const pass = &(state.terrainPass orelse return);

	// Packs branch on the stage to tell terrain from entities from the sky; a constant 0 ("NONE")
	// makes every branch take the wrong arm.
	var terrainFrame = state.frameUniforms;
	terrainFrame.renderStage = pipeline.stages.terrainSolid;
	// Cubyz draws solid and cutout blocks in one pass, and this is the cutout half of what Minecraft
	// splits in two - its own shader discards on alpha here too. See `uniforms.Values.alphaTestRef`.
	terrainFrame.alphaTestRef = pass.alphaTestRef orelse uniforms.alphaTest.oneTenthAlpha;
	uniforms.upload(&terrainFrame, &pass.locations);
	uniforms.uploadCompatMatrices(pass.program, &terrainFrame);

	// Every unit the program's samplers name must actually hold a texture of the matching type.
	// Nostalgia's terrain program samples shadowtex and depthtex as well as the block texture, and
	// pointing a sampler at an empty unit is invalid program texture usage, not a silent black read.
	state.renderTargets.bindSamplers(pass.bindings);
	state.renderTargets.bindShadowSamplers(pass.usesShadowComparison);
	state.custom.upload(pass.program);
	pipeline.bindSamplerUniforms(pass.program);
	state.textures.bind();
	state.textures.bindSamplerUniforms(pass.program);
	// After `bindSamplers`, which put the render targets on the units these replace. Complementary
	// declares `texture.gbuffers.gaux4=lib/textures/cloud-water.png` and samples it four times per
	// water fragment to build its wave normals; unbound, `gaux4` reads colortex7 instead.
	state.textures.bindOverrides(.gbuffers, .{});
	state.images.bindSamplers();
	state.images.bindSamplerUniforms(pass.program);
	_ = state.renderTargets.bindImages(pass.images, pass.bindings, &state.images);

	// Cubyz's arrays, on their own units so they do not collide with colortex.
	bindCubyzMaterialArrays();
	// The prologue declares this buffer unconditionally, so it has to be bound whenever a gbuffers
	// program runs, not only when the pack shipped a block.properties.
	state.blockIdTable.bind();

	bindPrologueUniforms(pass.program, ambient, playerPos);

	// The pack's own matrices still apply; `projMatrix` is already in `frameUniforms`.
	_ = projMatrix;
}

/// Routes the terrain draw through the pack's `gbuffers_terrain`, into the colortex buffers its
/// DRAWBUFFERS directive names.
///
/// Returns false when there is no terrain program, in which case the caller renders normally.
pub fn beginTerrain() bool {
	const state = &(active orelse return false);
	const pass = &(state.terrainPass orelse return false);

	// Before the framebuffer is bound for drawing: Cubyz has already rendered its skybox into
	// `worldFrameBuffer` at this point in the frame, and geometry is about to draw over it, which is
	// the order Minecraft's own gbuffers stage produces.
	//
	// Only when the pack did not already draw a sky of its own. Cubyz's "sky" is a flat clear colour
	// plus stars, and it stands in for the vanilla sky *geometry* a pack would otherwise have shaded
	// with `gbuffers_skybasic`. A pack that builds its sky in `prepare` instead - Nostalgia writes
	// its gradient and sun disc into colortex0 from `skyboxApply.fsh` - has already put the real
	// thing there, and blitting a flat colour over it destroys exactly what it computed.
	//
	// This became destructive only when the gbuffers stage stopped taking part in the flip sequence:
	// before that, geometry wrote the *opposite* side from prepare, so the blit landed in a buffer
	// nothing had filled. Now that it correctly writes the side prepare last wrote, the two collide.
	const albedoTarget = if(pass.drawBuffers.slice().len != 0) pass.drawBuffers.slice()[0] else 0;
	const importsSky = albedoTarget >= flip.colortexCount or !state.preparedTargets.contains(albedoTarget);
	if(importsSky) {
		state.renderTargets.importSky(main.renderer.worldFrameBuffer.frameBuffer, pass.drawBuffers.slice(), pass.bindings);
	}

	drawPackSky(state);
	drawCelestialBodies(state);

	state.renderTargets.bindForPass(pass.drawBuffers.slice(), pass.bindings, true);
	// The extent of what this stage draws into, not the window's. Screen-sized targets - the
	// usual case for the gbuffers stage - resolve to exactly the same numbers.
	const extent = state.renderTargets.viewportFor(pass.drawBuffers.slice());
	c.glViewport(0, 0, extent[0], extent[1]);
	main.renderer.chunk_meshing.terrainOverride = .{
		.program = pass.program,
		.bindUniforms = &bindTerrainUniforms,
	};
	return true;
}

/// Draws the pack's own sky, over whatever the Cubyz import left, before terrain.
///
/// The order is Minecraft's: sky geometry lays down the background and terrain draws over it. Keeping
/// the import in front of this rather than replacing it is what makes the feature safe for every
/// pack - a program that discards or collapses leaves the import exactly as it was, which is the
/// behaviour those packs already had, and no code has to guess which kind of pack it is holding.
///
/// Depth is neither tested nor written. The sky is behind everything by definition, and writing depth
/// would make it an occluder for the composite chain, which reads `depthtex0` to tell sky from world
/// - the far plane is precisely how it knows.
fn drawPackSky(state: *Pipeline) void {
	const pass = &(state.skyPass orelse return);

	state.renderTargets.bindForPass(pass.drawBuffers.slice(), pass.bindings, false);
	// The extent of what this stage draws into, not the window's. Screen-sized targets - the
	// usual case for the gbuffers stage - resolve to exactly the same numbers.
	const extent = state.renderTargets.viewportFor(pass.drawBuffers.slice());
	c.glViewport(0, 0, extent[0], extent[1]);

	c.glUseProgram(pass.program);

	var skyFrame = state.frameUniforms;
	skyFrame.renderStage = pipeline.stages.sky;
	uniforms.upload(&skyFrame, &pass.locations);
	uniforms.uploadCompatMatrices(pass.program, &skyFrame);
	state.renderTargets.bindSamplers(pass.bindings);
	state.renderTargets.bindShadowSamplers(pass.usesShadowComparison);
	state.custom.upload(pass.program);
	pipeline.bindSamplerUniforms(pass.program);
	state.textures.bind();
	state.textures.bindSamplerUniforms(pass.program);
	state.textures.bindOverrides(.gbuffers, .{});
	state.images.bindSamplers();
	state.images.bindSamplerUniforms(pass.program);
	_ = state.renderTargets.bindImages(pass.images, pass.bindings, &state.images);

	// The two matrices the sky prologue unprojects with. Named apart from the compatibility shim's
	// so a pack using `gl_ProjectionMatrixInverse` itself cannot collide with them.
	setSkyMatrix(pass.program, prologue.skyProjectionInverse, skyFrame.gbufferProjectionInverse);
	setSkyMatrix(pass.program, prologue.skyModelViewInverse, skyFrame.gbufferModelViewInverse);

	c.glDisable(c.GL_DEPTH_TEST);
	c.glDepthMask(c.GL_FALSE);
	c.glDisable(c.GL_BLEND);

	// Three vertices, no attributes: the prologue builds the triangle from `gl_VertexID`. A vertex
	// array still has to be bound for a draw to be legal, so the quad's serves.
	c.glBindVertexArray(state.quad.vao);
	c.glDrawArrays(c.GL_TRIANGLES, 0, 3);
	c.glBindVertexArray(0);

	// Terrain depth-tests against what it draws into, so both go back on before the chunk pass.
	c.glEnable(c.GL_DEPTH_TEST);
	c.glDepthMask(c.GL_TRUE);
	c.glUseProgram(0);
}

fn setSkyMatrix(program: c_uint, name: []const u8, value: main.vec.Mat4f) void {
	var buffer: [64]u8 = undefined;
	const terminated = std.fmt.bufPrintZ(&buffer, "{s}", .{name}) catch return;
	const location = c.glGetUniformLocation(program, terminated.ptr);
	if(location >= 0) c.glUniformMatrix4fv(location, 1, c.GL_TRUE, @ptrCast(&value));
}

fn setVec3(program: c_uint, name: []const u8, value: main.vec.Vec3f) void {
	var buffer: [64]u8 = undefined;
	const terminated = std.fmt.bufPrintZ(&buffer, "{s}", .{name}) catch return;
	const location = c.glGetUniformLocation(program, terminated.ptr);
	if(location >= 0) c.glUniform3f(location, value[0], value[1], value[2]);
}

fn setVec4(program: c_uint, name: []const u8, value: [4]f32) void {
	var buffer: [64]u8 = undefined;
	const terminated = std.fmt.bufPrintZ(&buffer, "{s}", .{name}) catch return;
	const location = c.glGetUniformLocation(program, terminated.ptr);
	if(location >= 0) c.glUniform4f(location, value[0], value[1], value[2], value[3]);
}

/// Draws the sun and then the moon through the pack's `gbuffers_skytextured`, after the sky and
/// before terrain, where Minecraft's `renderSky` draws them and Iris's phases put them
/// (`SUN`, then `MOON`).
///
/// Each is one quad in the celestial frame: the sun spans thirty units either way at a hundred
/// out along the frame's Y, the moon twenty at a hundred the other way, both edged by the frame's
/// X and Z (`matrix.celestialAxis`), which `uniforms.capture` computes beside `sunPosition` from
/// the same clock. The sun carries the whole sheet and a colour whose alpha is the rain fade,
/// `(1, 1, 1, 1 - rainStrength)`; the moon carries the cell of its phase, in the mirrored UV
/// order Minecraft's vertices give it, and white. Blending is the pass's: Minecraft's additive
/// pair unless the pack declared `blend.gbuffers_skytextured`. Depth is neither tested nor
/// written, for the same reason as the sky's, and culling is off since the quad's winding
/// depends on where the body is.
fn drawCelestialBodies(state: *Pipeline) void {
	const pass = &(state.skyTexturedPass orelse return);
	const values = &state.frameUniforms;
	if(state.drawSun) {
		drawCelestialBody(state, pass, .sun, values.sunPosition, 30.0, .{0, 0, 1, 1}, .{1, 1, 1, 1.0 - values.rainStrength});
	}
	if(state.drawMoon) {
		// `moon_phases.png` is four cells by two; phase `p` is column `p % 4` of row `p / 4`, and
		// Minecraft's moon vertices pair the low-U edge with the high-X corner.
		const phase: u32 = @intCast(@mod(values.moonPhase, 8));
		const column: f32 = @floatFromInt(phase % 4);
		const row: f32 = @floatFromInt(phase / 4);
		const uLow = column/4.0;
		const uHigh = (column + 1.0)/4.0;
		const vLow = row/2.0;
		const vHigh = (row + 1.0)/2.0;
		drawCelestialBody(state, pass, .moon, values.moonPosition, 20.0, .{uHigh, vLow, uLow, vHigh}, .{1, 1, 1, 1});
	}
}

fn drawCelestialBody(state: *Pipeline, pass: *pipeline.Pass, body: packtextures.Body, center: main.vec.Vec3f, halfSize: f32, uv: [4]f32, color: [4]f32) void {
	state.renderTargets.bindForPass(pass.drawBuffers.slice(), pass.bindings, false);
	const extent = state.renderTargets.viewportFor(pass.drawBuffers.slice());
	c.glViewport(0, 0, extent[0], extent[1]);

	c.glUseProgram(pass.program);
	var frame = state.frameUniforms;
	frame.renderStage = if(body == .sun) pipeline.stages.sun else pipeline.stages.moon;
	uniforms.upload(&frame, &pass.locations);
	uniforms.uploadCompatMatrices(pass.program, &frame);
	state.renderTargets.bindSamplers(pass.bindings);
	state.renderTargets.bindShadowSamplers(pass.usesShadowComparison);
	state.custom.upload(pass.program);
	pipeline.bindSamplerUniforms(pass.program);
	state.textures.bind();
	state.textures.bindSamplerUniforms(pass.program);
	state.textures.bindOverrides(.gbuffers, .{});
	state.images.bindSamplers();
	state.images.bindSamplerUniforms(pass.program);
	_ = state.renderTargets.bindImages(pass.images, pass.bindings, &state.images);
	// After the overrides: the sheet goes under the block-texture sampler names, which nothing
	// else binds in a sky program.
	state.textures.bindCelestial(pass.program, body);

	setSkyMatrix(pass.program, prologue.skyModelViewInverse, frame.gbufferModelViewInverse);
	setVec3(pass.program, prologue.celestialCenter, center);
	setVec3(pass.program, prologue.celestialU, frame.cubyz_celestialX*@as(main.vec.Vec3f, @splat(halfSize)));
	setVec3(pass.program, prologue.celestialV, frame.cubyz_celestialZ*@as(main.vec.Vec3f, @splat(halfSize)));
	setVec4(pass.program, prologue.celestialUv, uv);
	setVec4(pass.program, prologue.celestialColor, color);

	c.glDisable(c.GL_DEPTH_TEST);
	c.glDepthMask(c.GL_FALSE);
	c.glDisable(c.GL_CULL_FACE);
	pipeline.applyBlendState(&pass.blendState);

	c.glBindVertexArray(state.quad.vao);
	c.glDrawArrays(c.GL_TRIANGLES, 0, 6);
	c.glBindVertexArray(0);

	pipeline.resetBlendState();
	c.glEnable(c.GL_CULL_FACE);
	c.glEnable(c.GL_DEPTH_TEST);
	c.glDepthMask(c.GL_TRUE);
	c.glUseProgram(0);
}

/// Narrows the pack's gbuffers framebuffer to its albedo attachment, for the draws Cubyz still
/// makes with its own shaders inside the geometry stage.
///
/// A single-output shader drawing into a multi-attachment framebuffer writes undefined values to
/// every attachment it does not name. That is GL's rule, not a Cubyz quirk. Kappa's
/// `gbuffers_terrain` declares `/* RENDERTARGETS: 0,1,2,4 */`, so while four buffers are attached,
/// Cubyz's block-selection outline - `block_selection_fragment.frag`, one `layout(location = 0) out
/// vec4` writing black - leaves colortex1, colortex2 and colortex4 undefined wherever it draws.
/// Those hold the pack's packed material data and geometry normals, so the deferred chain decodes
/// garbage for those texels, lights it, and the bloom passes spread the result into a glowing blob
/// several times the size of the cube. The outline's own lines stay visible inside it, which is what
/// makes the symptom recognisable.
///
/// Restricting the draw buffer list to the albedo target alone is the whole fix: outputs the list
/// does not map are discarded rather than written, so the material buffers keep what
/// `gbuffers_terrain` put there and the outline lands in albedo as the black line it is. Entities,
/// item drops, block entities and particles draw in the same region with the same one-output shape
/// and are covered by the same pair.
///
/// This is deliberately *not* the eventual fix. Minecraft draws the outline through
/// `gbuffers_basic`/`gbuffers_line` at render stage OUTLINE, and Kappa ships
/// `program/gbuffer/line.glsl` expecting exactly that. Routing these draws through the pack's own
/// programs is the "remaining gbuffers programs" work; until then this stops them corrupting a
/// buffer they have no business writing.
///
/// The attachments are left physically attached and only unlisted, so nothing has to be
/// re-created - `endCubyzShadedDraws` puts the full list back.
pub fn beginCubyzShadedDraws() void {
	const state = &(active orelse return);
	const pass = &(state.terrainPass orelse return);
	const drawBuffers = pass.drawBuffers.slice();
	// A pack writing one buffer has nothing to corrupt, and rebinding would cost two GL calls a
	// frame to change nothing.
	if(drawBuffers.len <= 1) return;
	state.renderTargets.bindForPass(drawBuffers[0..1], pass.bindings, true);
}

/// Restores the terrain pass's full attachment set after Cubyz's own draws.
pub fn endCubyzShadedDraws() void {
	const state = &(active orelse return);
	const pass = &(state.terrainPass orelse return);
	const drawBuffers = pass.drawBuffers.slice();
	if(drawBuffers.len <= 1) return;
	state.renderTargets.bindForPass(drawBuffers, pass.bindings, true);
}

/// Uniforms for the pack's `gbuffers_water`, which sees the same camera as the terrain pass.
fn bindWaterUniforms(projMatrix: main.vec.Mat4f, ambient: main.vec.Vec3f, playerPos: main.vec.Vec3d) void {
	const state = &(active orelse return);
	const pass = &(state.waterPass orelse return);
	_ = projMatrix;

	// Depth writes on, unlike Cubyz's own transparent pipeline.
	//
	// Cubyz builds `transparentPipeline` with `.depthWrite = false`, which is right for its own
	// shader: it blends layers of transparency against each other and depth writes would let a near
	// surface hide a farther one. Minecraft's translucent pass writes depth, and packs depend on it
	// having done so - the water surface's depth in `depthtex0` against the sea bed's in `depthtex1`
	// is *how the thickness of the water is measured*:
	//
	//     vec2 sceneDepth  = vec2(texture(depthtex0, uv).x, texture(depthtex1, uv).x);
	//     bool translucent = sceneDepth.x < sceneDepth.y;
	//
	// With no depth written the two are identical, `translucent` is never true, and every effect
	// keyed on it switches off - absorption, refraction and the water fog alike. Water then renders
	// as a flat tint over an undimmed sea bed however deep it is.
	//
	// This runs after `transparentPipeline.bind`, which is why it can override it - the same
	// ordering the blend-state replacement below relies on. Undone in `endTranslucent`.
	c.glDepthMask(c.GL_TRUE);

	var waterFrame = state.frameUniforms;
	waterFrame.renderStage = pipeline.stages.terrainTranslucent;
	// The one alpha threshold on this path that is load-bearing. Cubyz's water is a flat 0.42
	// alpha and its resin 0.55, so the opaque cutout value would discard both surfaces outright.
	// Iris uses `NON_ZERO_ALPHA` here for the same reason. See `uniforms.Values.alphaTestRef`.
	waterFrame.alphaTestRef = pass.alphaTestRef orelse uniforms.alphaTest.nonZeroAlpha;
	uniforms.upload(&waterFrame, &pass.locations);
	uniforms.uploadCompatMatrices(pass.program, &waterFrame);
	state.renderTargets.bindSamplers(pass.bindings);
	state.renderTargets.bindShadowSamplers(pass.usesShadowComparison);
	state.custom.upload(pass.program);
	pipeline.bindSamplerUniforms(pass.program);
	state.textures.bind();
	state.textures.bindSamplerUniforms(pass.program);
	// The load-bearing one for Complementary: its water normals are four samples of `gaux4`.
	state.textures.bindOverrides(.gbuffers, .{});
	state.images.bindSamplers();
	state.images.bindSamplerUniforms(pass.program);
	_ = state.renderTargets.bindImages(pass.images, pass.bindings, &state.images);
	bindCubyzMaterialArrays();
	state.blockIdTable.bind();
	bindPrologueUniforms(pass.program, ambient, playerPos);

	// Applied here rather than in `beginTranslucent`, because Cubyz re-binds its transparent
	// pipeline before every translucent draw call - and `Pipeline.bind` rewrites the blend state
	// each time, so anything set once up front would be gone by the actual draw.
	pipeline.applyBlendState(&pass.blendState);
}

/// Routes Cubyz's transparent chunk meshes through the pack's `gbuffers_water`.
///
/// Returns false when the pack has no usable translucent program, in which case Cubyz's own
/// transparent shader draws as before.
pub fn beginTranslucent() bool {
	const state = &(active orelse return false);

	// Taken whether or not the pack has a translucent program, because it is the composite chain
	// that reads these - this is simply the point in Cubyz's frame where Minecraft's own
	// "before translucents" split falls.
	state.renderTargets.captureDepthSnapshots();

	// The depth buffer is complete for opaque geometry at exactly this point, which is what
	// `centerDepthSmooth` is meant to describe - the thing you are looking at, not the water in
	// front of it. The read framebuffer is still the pack's, left bound by the snapshot above.
	c.glBindFramebuffer(c.GL_READ_FRAMEBUFFER, state.renderTargets.framebuffer);
	uniforms.centerDepth.sample(state.renderTargets.width, state.renderTargets.height, state.frameUniforms.frameTime);
	c.glBindFramebuffer(c.GL_READ_FRAMEBUFFER, 0);

	// The deferred passes, here and not at the head of the post chain. Iris's `beginTranslucents`
	// copies the pre-translucent depth, runs every deferred pass, and only then lets translucent
	// geometry draw (`IrisRenderingPipeline.java:1061-1063`); `composite` and `final` follow the
	// whole world. Packs are written to that order: Bliss's `deferred1` renders the sky into
	// colortex4 and its water reflects it, Complementary's `deferred1` is the lighting pass its
	// water refracts, and every pack's water depth-tests against, and reads, a *lit* scene. Drawn
	// first, water reflected buffers nothing had written yet this frame - a black lake in Bliss.
	//
	// Only when the pack's own terrain program is drawing: then the G-buffer and depth are complete
	// here. Without one the scene is imported at post-chain time and deferred has to wait for it.
	if(state.terrainPass != null and !state.deferredRanEarly) {
		var hasDeferred = false;
		for(state.passes) |*pass| {
			if(pass.kind == .deferred) hasDeferred = true;
		}
		if(hasDeferred) {
			// Anything the geometry stage stored through a `colorimgN` image has to be visible to
			// these passes, as it has to be to the rest of the chain.
			c.glMemoryBarrier(pipeline.imageBarrierBits);
			for(state.passes) |*pass| {
				if(pass.kind != .deferred) continue;
				runPostPass(state, pass, @intCast(main.Window.width), @intCast(main.Window.height));
			}
			state.deferredRanEarly = true;
		}
	}

	const pass = &(state.waterPass orelse {
		// No translucent program, so Cubyz's own shader draws the water - with dual-source
		// blending, which GL permits against exactly one draw buffer. The pack's G-buffer is still
		// bound with every attachment `gbuffers_terrain` named, so it is narrowed to the albedo for
		// the duration, as `beginCubyzShadedDraws` does for the engine's other draws. Without this
		// every translucent draw raised `GL_INVALID_OPERATION ... blend` - by the thousand per run
		// once a pack's water program failed, which is what made the frame crawl and the menus
		// unreachable. Returning true routes the caller through `endTranslucent`, which restores
		// the full attachment list.
		beginCubyzShadedDraws();
		return true;
	});

	// Depth is attached: translucents depth-test against the terrain the gbuffers pass wrote, and
	// Cubyz's own depth buffer no longer holds it.
	state.renderTargets.bindForPass(pass.drawBuffers.slice(), pass.bindings, true);
	// The extent of what this stage draws into, not the window's. Screen-sized targets - the
	// usual case for the gbuffers stage - resolve to exactly the same numbers.
	const extent = state.renderTargets.viewportFor(pass.drawBuffers.slice());
	c.glViewport(0, 0, extent[0], extent[1]);
	main.renderer.chunk_meshing.transparentOverride = .{
		.program = pass.program,
		.bindUniforms = &bindWaterUniforms,
	};
	return true;
}

/// Restores Cubyz's own transparent program, and the framebuffer the rest of the frame expects.
///
/// `gbuffers_water` usually names different draw buffers than `gbuffers_terrain`, so leaving its
/// attachments bound would send everything Cubyz draws afterwards - held items, the selection
/// outline - into the water pass's targets rather than the terrain ones.
pub fn endTranslucent() void {
	const state = &(active orelse return);
	state.renderTargets.unbindShadowSamplers();
	main.renderer.chunk_meshing.transparentOverride = null;
	// Restore Cubyz's transparent depth-write state. `Pipeline.bind` sets the mask from its own
	// config, so the next bind would fix this anyway - but the next thing drawn is the item-drop
	// renderer, and leaving a global GL toggle flipped for something else to trip over is how the
	// exposure probe broke rendering earlier in this project.
	c.glDepthMask(c.GL_FALSE);
	// Per-attachment blend state is not undone by Cubyz's next `Pipeline.bind`, which only touches
	// the global enable - so a `blend.gbuffers_water.colortex1=off` would stay off for everything
	// drawn afterwards.
	pipeline.resetBlendState();
	if(state.terrainPass) |*terrain| {
		state.renderTargets.bindForPass(terrain.drawBuffers.slice(), terrain.bindings, true);
	}
}

/// Runs the `prepare` passes, which come before the gbuffers stage.
///
/// Nostalgia's `prepare1` writes the skybox into colortex0; terrain then draws over it. Running
/// these after geometry instead paints the sky across the albedo and every surface loses its
/// texture, with nothing in the logs to say so.
pub fn runPreparePasses(screenWidth: u31, screenHeight: u31) void {
	const state = &(active orelse return);
	for(state.passes) |*pass| {
		// `begin` ran at the top of the frame, before the shadow map; only `prepare` sits here.
		if(pass.kind != .prepare) continue;
		pipeline.runPass(&state.quad, &state.renderTargets, &state.textures, &state.images, &state.custom, pass, &state.frameUniforms, screenWidth, screenHeight);
	}
	c.glUseProgram(0);
	c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
}

/// Uploads the shadow camera's matrices in place of the main camera's.
///
/// The pack's `shadow.vsh` writes `gl_Position` from the same `gl_ModelViewMatrix` and
/// `gl_ProjectionMatrix` that `gbuffers_terrain` uses, so rendering from the light is a matter of
/// substituting those two matrices rather than of a separate code path.
fn bindShadowUniforms(projMatrix: main.vec.Mat4f, ambient: main.vec.Vec3f, playerPos: main.vec.Vec3d) void {
	const state = &(active orelse return);
	const pass = &(state.shadowPass orelse return);
	_ = projMatrix;

	// The `gbuffer*` set stays on the camera here, as it does in every other program. Iris states
	// that in one place: `MatrixUniforms.addMatrix` registers `gbufferModelView`, its `Inverse` and
	// its `Previous` against `CapturedRenderingState::getGbufferModelView` at `PER_FRAME`, and
	// nothing swaps that supplier while the shadow map renders.
	//
	// Packs read it in their shadow programs and mean the camera. Kappa's `shadow/vertex.vsh` takes
	// `length(transMAD(gbufferModelView, scenePos))` to fade parallax out with distance *from the
	// player*, and photon's `voxelization.glsl` centres its light-propagation volume on
	// `gbufferModelViewInverse[2].xyz`, the camera's look direction. Substituting the light's basis
	// would aim both at the sun.
	//
	// This used to overwrite `gbufferModelView`/`gbufferProjection` with the shadow pair. Nothing in
	// the corpus showed it, because both matrices are pure rotations and both uses above happen to be
	// rotation-invariant - which is exactly the kind of accident that stops being one on the next
	// pack.
	var shadowFrame = state.frameUniforms;
	// Iris cuts every shadow caster at a tenth, `SHADOW_TERRAIN_CUTOUT`. At the unsupplied zero a
	// leaf casts the shadow of a solid cube. See `uniforms.Values.alphaTestRef`.
	shadowFrame.alphaTestRef = pass.alphaTestRef orelse uniforms.alphaTest.oneTenthAlpha;
	uniforms.upload(&shadowFrame, &pass.locations);

	// The compat matrices are the current render's, and here that is the light's. Packs undo them
	// explicitly, so this half is load-bearing rather than cosmetic: Complementary's `shadow.glsl`
	// recovers scene space with `shadowModelViewInverse * shadowProjectionInverse * ftransform()`,
	// and photon's and Kappa's with `shadowModelViewInverse` applied to `gl_ModelViewMatrix * vertex`.
	// Each only lands back where it started if `gl_ProjectionMatrix * gl_ModelViewMatrix` is the
	// shadow pair.
	//
	// All four move together, or the pair stops inverting. The forward two were substituted and the
	// inverses were left on the camera, so a pack reading `gl_ModelViewMatrixInverse` beside
	// `gl_ModelViewMatrix` in its shadow program got two matrices that do not compose to identity -
	// no error, no GL warning, and no pack in the current corpus reads them here, which is why it had
	// no symptom. Iris substitutes both: `ExtendedShader` sets `iris_ProjMatInverse` from
	// `areShadowsCurrentlyBeingRendered() ? ShadowRenderer.PROJECTION : getGbufferProjection()`, and
	// derives `iris_ModelViewMatInverse` and `iris_NormalMat` from whatever model-view is current.
	var compat = state.frameUniforms;
	compat.gbufferModelView = state.frameUniforms.shadowModelView;
	compat.gbufferModelViewInverse = state.frameUniforms.shadowModelViewInverse;
	compat.gbufferProjection = state.frameUniforms.shadowProjection;
	compat.gbufferProjectionInverse = state.frameUniforms.shadowProjectionInverse;
	uniforms.uploadCompatMatrices(pass.program, &compat);
	state.custom.upload(pass.program);
	pipeline.bindSamplerUniforms(pass.program);
	state.textures.bind();
	state.textures.bindSamplerUniforms(pass.program);
	// `texture.gbuffers.*` covers the shadow programs: Iris's stage is `GBUFFERS_AND_SHADOW`.
	state.textures.bindOverrides(.gbuffers, .{});
	state.images.bindSamplers();
	state.images.bindSamplerUniforms(pass.program);
	_ = state.renderTargets.bindImages(pass.images, pass.bindings, &state.images);

	bindPrologueUniforms(pass.program, ambient, playerPos);

	// All three arrays, not just the block texture. The fragment prologue declares the emission and
	// reflectivity samplers in every gbuffers program, shadow included, and its LabPBR helper reads
	// them - a declared sampler over an empty unit is undefined usage rather than a black read.
	bindCubyzMaterialArrays();
	// The shadow program runs the same vertex prologue, so it reads the same table. Packs use
	// `mc_Entity` here too, to keep foliage waving in step between the shadow map and the camera
	// view - without it, a waving leaf would cast the shadow of a still one.
	state.blockIdTable.bind();

	// The translucent layer blends, as Minecraft's `RenderType.translucent()` does in the shadow
	// pass too, over the white the shadow colour buffers were cleared to: a caster's
	// `shadowcolor0` comes out as `mix(white, colour, alpha)`, the tint packs multiply a shadow
	// by. The pack's `blend.shadow*` declarations refine it through the resolution every pass
	// gets. The opaque layer keeps the engine's blend-free state, as Iris's solid layer does.
	// Applied per bind rather than once before the layer because the engine rebinds the pipeline,
	// and with it the blend state, before each LOD's draw.
	if(state.shadowTranslucentPhase) pipeline.applyBlendState(&pass.blendState);
}

/// Between the two layers of the shadow pass: the opaque casters' depth becomes `shadowtex1`, and
/// the binder switches to the translucent layer's blending for the draws that follow.
fn beginShadowTranslucents() void {
	const state = &(active orelse return);
	state.renderTargets.captureShadowDepth();
	state.shadowTranslucentPhase = true;
}

/// Points Cubyz's three texture arrays at the units the fragment prologue declares them on.
///
/// They cannot share units with `colortex0`-`colortex2`: a program declaring both a `sampler2D
/// colortex0` and a `sampler2DArray` on one unit is invalid usage, and the driver rejects the draw
/// rather than picking one.
/// Uploads the uniforms the generated prologue declares, which no pack knows about.
///
/// The prologue reproduces Cubyz's own position encoding, so it needs the same split
/// integer/fraction player position the engine's chunk shader uses - a single double-precision
/// value would lose the fraction at world-edge distances.
fn bindPrologueUniforms(program: c_uint, ambient: main.vec.Vec3f, playerPos: main.vec.Vec3d) void {
	const ambientLocation = c.glGetUniformLocation(program, "cubyz_ambientLight");
	if(ambientLocation >= 0) c.glUniform3f(ambientLocation, ambient[0], ambient[1], ambient[2]);
	const integerLocation = c.glGetUniformLocation(program, "cubyz_playerPositionInteger");
	if(integerLocation >= 0) c.glUniform3i(integerLocation, @intFromFloat(@floor(playerPos[0])), @intFromFloat(@floor(playerPos[1])), @intFromFloat(@floor(playerPos[2])));
	const fractionLocation = c.glGetUniformLocation(program, "cubyz_playerPositionFraction");
	if(fractionLocation >= 0) c.glUniform3f(fractionLocation, @floatCast(@mod(playerPos[0], 1)), @floatCast(@mod(playerPos[1], 1)), @floatCast(@mod(playerPos[2], 1)));
}

fn bindCubyzMaterialArrays() void {
	c.glActiveTexture(c.GL_TEXTURE0 + targets.cubyzBlockTextureUnit);
	c.glBindTexture(c.GL_TEXTURE_2D_ARRAY, main.blocks.meshes.blockTextureArray.textureID);
	c.glActiveTexture(c.GL_TEXTURE0 + targets.cubyzEmissionTextureUnit);
	c.glBindTexture(c.GL_TEXTURE_2D_ARRAY, main.blocks.meshes.emissionTextureArray.textureID);
	c.glActiveTexture(c.GL_TEXTURE0 + targets.cubyzReflectivityTextureUnit);
	c.glBindTexture(c.GL_TEXTURE_2D_ARRAY, main.blocks.meshes.reflectivityAndAbsorptionTextureArray.textureID);
	c.glActiveTexture(c.GL_TEXTURE0);
}

/// Renders chunk geometry into the shadow map from the light's direction.
///
/// Until this ran, `shadowtex0` was cleared to "nothing occludes", so every surface read as fully
/// sunlit - which is why supplying material textures moved the image from too dark straight to
/// blown out rather than to correct. The shadow term was pinned at 1.0 with nothing to bring it
/// down.
pub fn renderShadowMap(chunkLists: *const main.renderer.chunk_meshing.ChunkLists, ambient: main.vec.Vec3f, playerPos: main.vec.Vec3d) void {
	const state = &(active orelse return);
	const pass = &(state.shadowPass orelse return);

	// The `shadow.csh` chain, before the map is drawn, at the map's size
	// (`IrisRenderingPipeline.java:885-891`). Its stage for texture overrides is the shadow
	// program's own, `gbuffers`.
	pipeline.dispatchComputes(
		&state.renderTargets, &state.textures, &state.images, &state.custom, state.shadowComputes, .gbuffers, pass.bindings, .{},
		&state.frameUniforms, @floatFromInt(state.renderTargets.shadowResolution), @floatFromInt(state.renderTargets.shadowResolution),
	);

	// Iris clears every shadow colour buffer before the pass, to opaque white unless the pack
	// says otherwise, and the pack's `shadow.fsh` then writes into whichever ones its DRAWBUFFERS
	// name. Neither happened here until 2026-09-07: the framebuffer carried depth alone, so a pack
	// sampling `shadowcolor0` - BSL at every softened shadow edge, Complementary throughout its
	// coloured shadows - read memory nothing had ever written. Cleared first, then attached, since
	// the clear rebinds the attachments.
	state.renderTargets.clearShadowColor(false);
	state.renderTargets.bindShadowFramebuffer(pass.drawBuffers.slice());
	c.glViewport(0, 0, state.renderTargets.shadowResolution, state.renderTargets.shadowResolution);

	// Cubyz renders the world with `glDepthRange(0.001, 1)` so held items can occupy the first
	// thousandth, and leaves it set. A shaderpack's shadow maths assumes GL's default `[0, 1]`: it
	// compares a depth it computed itself against what the shadow pass stored, and any offset
	// between the two is a shadow bias nobody asked for.
	//
	// It matters far more here than it would elsewhere because of how tight the range is. The ortho
	// spans Iris's 256 blocks and every pack then compresses that by `pos.z *= 0.2`, so the whole
	// span lands inside 20% of the depth buffer - about 0.0008 per block. A 0.001 offset is
	// therefore worth more than a block of bias, and an occluder that thin stops casting. Surfaces
	// mostly survive that; a volumetric ray marching *through* rock does not, and reads lit.
	c.glDepthRange(0, 1);
	defer c.glDepthRange(main.renderer.worldDepthRangeNear, 1);

	c.glClearDepth(1.0);
	c.glDepthMask(c.GL_TRUE);
	c.glClear(c.GL_DEPTH_BUFFER_BIT);

	main.renderer.chunk_meshing.terrainOverride = .{
		.program = pass.program,
		.bindUniforms = &bindShadowUniforms,
	};
	defer main.renderer.chunk_meshing.terrainOverride = null;

	// The shadow map covers a volume around the player, not the camera's view. `chunkLists` is the
	// camera's frustum-culled selection and is deliberately unused; see `collectShadowChunks`.
	_ = chunkLists;
	var shadowLists: main.renderer.chunk_meshing.ChunkLists = @splat(main.ListManaged(u32).init(main.stackAllocator));
	defer for (&shadowLists) |*list| list.deinit();
	// The render distance, not `shadowDistance`. Packs warp shadow coordinates by
	// `coord / (length(coord)*0.85 + 0.15)`, which asymptotes just above 1 - so geometry at *any*
	// distance still lands inside the shadow map. `shadowDistance` sets where resolution falls off,
	// not what the map covers, and filling only that radius leaves an empty annulus around the
	// geometry that every distant sample reads as "nothing occludes".
	collectShadowChunks(playerPos, @floatFromInt(main.settings.renderDistance*main.chunk.chunkSize), &shadowLists);

	// Opaque meshes first, then the transparent ones through the same program, which is Iris's
	// shadow pass: the solid and cutout layers, the pre-translucent depth copy, then
	// `RenderType.translucent()` unless the pack set `shadowTranslucent = false`
	// (`ShadowRenderer.java:459-537`). Water and stained glass cast that way: `shadowtex0` holds
	// their depth, `shadowtex1` the copy taken before them, and `shadowcolor0` the colour the
	// pack's `shadow.fsh` wrote for them, blended over the white clear. Every water look in the
	// corpus stands on it - Complementary's and BSL's tinted shadow under the surface, Kappa's and
	// Nostalgia's caustics computed from it in `shadowcomp` - and until 2026-09-11 the pass drew
	// opaque terrain alone, so the bed of a lake was lit as if the water were not there and the
	// water over it read as a clear sheet.
	//
	// A pack that declines translucent casters still gets the copy, as it does in Iris; the two
	// maps are then equal, which is what such a pack expects `shadowtex1` to be.
	main.renderer.chunk_meshing.drawChunksForShadow(
		&shadowLists,
		state.frameUniforms.shadowProjection,
		ambient,
		playerPos,
		if(state.shadowTranslucent) &beginShadowTranslucents else null,
	);
	if(!state.shadowTranslucent) state.renderTargets.captureShadowDepth();
	state.shadowTranslucentPhase = false;
	// The per-attachment blend state the translucent layer set, cleared as `endTranslucent` does.
	pipeline.resetBlendState();
	// A shadow program writing `shadowcolorimgN`, or voxelising into a pack image, has to be
	// visible to the passes that read it - the `shadowcomp` chain first of all.
	c.glMemoryBarrier(pipeline.imageBarrierBits);

	// The `shadowcomp` chain, over the shadow colour buffers the pass just wrote, where Iris runs
	// it (`ShadowRenderer.renderShadows`, `compositeRenderer.renderAll()` at the end). Computes are
	// dispatched against the screen size, as `ShadowCompositeRenderer` does; the draws cover the
	// map's square. Depth test and writes are put back afterwards for the chunk draws that follow.
	if(state.shadowCompositePasses.len != 0) {
		for(state.shadowCompositePasses) |*composite| {
			pipeline.runPass(&state.quad, &state.renderTargets, &state.textures, &state.images, &state.custom, composite, &state.frameUniforms, @intCast(main.Window.width), @intCast(main.Window.height));
		}
		c.glMemoryBarrier(pipeline.imageBarrierBits);
		c.glUseProgram(0);
		c.glEnable(c.GL_DEPTH_TEST);
		c.glDepthMask(c.GL_TRUE);
	}
	// Nothing else shares the shadow textures' size, and the sky import that follows blits into
	// the same framebuffer sized by everything attached; see `targets.importSky`.
	state.renderTargets.releaseShadowFramebuffer();


	c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
}

/// Every loaded chunk within the pack's shadow distance, whether or not the camera can see it.
///
/// This is the whole point of the shadow pass being separate. Cubyz selects chunks with a
/// hierarchical search that only expands into camera-frustum-visible neighbours, so the list the
/// camera pass builds omits everything behind and beside the viewer. Handing that list to the shadow
/// pass produces a shadow map with holes exactly where the camera is not looking.
///
/// For lit surfaces that is a mild artifact - shadows pop in at the screen edge. For volumetric
/// light it is ruinous: the pack marches a ray through the air and tests each step against the
/// shadow map, so every point whose occluder is missing reads as fully sunlit. The visible result is
/// a beam of sunlight lying across solid rock, anchored in the world, tracking the sun as the camera
/// turns. That symptom outlived six wrong diagnoses before this was found.
///
/// Enumerated directly rather than by reusing Cubyz's search because that search *is* the frustum
/// cull - there is no unculled list to borrow.
///
/// The cost is not small, and an earlier version of this comment claimed it was - "a few hundred
/// validated pointer lookups per frame, because the shadow distance is small". The caller
/// deliberately passes the *render* distance rather than `shadowDistance`, for the reason written
/// there, so at the defaults this is a 769-block cube walked in 32-block steps: 25³ = 15,625
/// `getMesh` lookups every frame. That is affordable and is not the thing to optimise first, but it
/// should be stated accurately, because "a few hundred" is what someone would budget against when
/// deciding whether to widen the radius.
///
/// Only `voxelSize = 1` meshes are collected, so nothing outside the LOD-0 radius casts a shadow at
/// all. That is consistent with the radius being the LOD-0 render distance, and worth writing down
/// next to it: the `far` handed to packs is the LOD-extended 12288, so the world a pack believes it
/// is looking at reaches 32x further than the volume anything can cast a shadow from.
fn collectShadowChunks(playerPos: main.vec.Vec3d, radius: f32, out: *main.renderer.chunk_meshing.ChunkLists) void {
	const chunkSize: i32 = main.chunk.chunkSize;
	// Corners of the shadow volume sit further out than its faces, so the cube is extended by a
	// chunk diagonal. Missing an occluder at the edge reintroduces the very hole this exists to fill.
	const reach: i32 = @intFromFloat(@ceil(radius));
	const centre = main.vec.Vec3i{
		@intFromFloat(@floor(playerPos[0])),
		@intFromFloat(@floor(playerPos[1])),
		@intFromFloat(@floor(playerPos[2])),
	};

	// `prepareRendering` counts what it appends into the renderer's own statistic. The shadow pass
	// is not part of the camera's quad count, and letting it contribute would silently inflate the
	// figure the performance overlay reports.
	const quadsBefore = main.renderer.chunk_meshing.quadsDrawn;
	defer main.renderer.chunk_meshing.quadsDrawn = quadsBefore;

	const mask: i32 = ~(chunkSize - 1);
	var x: i32 = (centre[0] - reach) & mask;
	while(x <= centre[0] + reach) : (x += chunkSize) {
		var y: i32 = (centre[1] - reach) & mask;
		while(y <= centre[1] + reach) : (y += chunkSize) {
			var z: i32 = (centre[2] - reach) & mask;
			while(z <= centre[2] + reach) : (z += chunkSize) {
				// `getMesh` validates that the node it finds is actually the chunk asked for, which
				// a raw node lookup does not - the storage is a hash table and a miss returns some
				// other chunk's node rather than nothing.
				const mesh = main.renderer.mesh_storage.getMesh(.{.wx = x, .wy = y, .wz = z, .voxelSize = 1}) orelse continue;
				mesh.prepareRendering(out);
			}
		}
	}
}

/// Restores Cubyz's own terrain program and framebuffer.
pub fn endTerrain() void {
	if(active) |*state| state.renderTargets.unbindShadowSamplers();
	main.renderer.chunk_meshing.terrainOverride = null;
}

