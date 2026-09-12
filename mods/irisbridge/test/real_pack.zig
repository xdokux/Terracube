//! Conformance harness: loads and transforms EVERY shaderpack present, and reports per pack.
//!
//! Unit tests on hand-written snippets cannot tell you whether the loader survives contact with a
//! real pack, and testing against a single pack cannot tell you whether it survives contact with
//! *packs*. Almost every bug found so far came from a convention the one bundled pack happened to
//! use - comment-wrapped `const` directives, dimension folders, core `texture()` on the block
//! sampler. Running the whole corpus keeps the next such assumption visible.
//!
//! Drop any pack into `shaderpacks/` - folder or `.zip` - and it is picked up automatically. With
//! no packs present the test skips rather than failing, so the suite still runs on a bare checkout.
//!
//! It is a test rather than an executable so it gets the testing allocator's leak detection, and
//! so it never produces a standalone binary.

const std = @import("std");

const cubyz = @import("main");
const pack = @import("pack");
const glsl = pack.glsl;
const install = @import("install");

const allocator = cubyz.heap.testingAllocator;

const shaderpackDirectory = "shaderpacks";
const dimension = "world0";

/// The GL-independent part of `pipeline.standardMacros`, which needs a context for the vendor
/// strings and so cannot be called here. Kept in step by hand; a `#if` on one of these picks the
/// wrong branch quietly if the two drift.
const standardEnvironment = [_][]const u8{
	"MC_VERSION 12100",       "MC_GL_VERSION 460",     "MC_GLSL_VERSION 460",  "MC_MIPMAP_LEVEL 4",
	"MC_RENDER_QUALITY 1.0",  "MC_SHADOW_QUALITY 1.0", "MC_HAND_DEPTH 0.125",  "MC_NORMAL_MAP",
	"MC_SPECULAR_MAP",        "MAX_COLOR_BUFFERS 16",  "IS_IRIS",              "IRIS_TAG_SUPPORT 2",
	"IRIS_VERSION 10800",     "MC_OS_WINDOWS",         "MC_GL_VENDOR_NVIDIA",  "MC_GL_RENDERER_GEFORCE",
};

/// What one pack produced, so a regression shows up as a change in the numbers rather than a
/// pass/fail that hides how much actually worked.
const Report = struct {
	name: []const u8,
	programs: usize = 0,
	stages: usize = 0,
	bytes: usize = 0,
	leftovers: usize = 0,
	/// `.fsh` files that look like programs but matched no known program name.
	unrecognised: usize = 0,
	/// `clamp` bounds the transformer wrapped in `float(...)` for the driver
	/// (`glsl.markIntegerClampBounds`). Counted because the rewrite is invisible in the image and a
	/// change in this number is the only cheap sign that it fired, or stopped firing.
	clampBounds: usize = 0,
	/// Geometry-stage programs in which a pack helper taking the block texture as a `sampler2D`
	/// parameter was given an array overload (`glsl.SamplerFunction`). Bliss's terrain is the one
	/// that needs it; a change here says the shape appeared or vanished somewhere.
	overloads: usize = 0,
	/// Fragment stages whose transformed source defines no `main`. The alpha-test wrapper renames
	/// the pack's `main` and supplies its own; if the rename happens and the wrapper does not, the
	/// stage compiles and fails to link (Kappa, Nostalgia and photon, 2026-09-04). A pack's own
	/// `main` is fine and so is the wrapper's; none at all is a broken program.
	missingMain: usize = 0,
	/// Programs whose `DRAWBUFFERS` differs between the raw text and the live view the loader reads
	/// it from (`pack.liveView`): a directive in a branch the pack's options switch off. Each is
	/// printed, since every one is a buffer that used to be attached to an output nothing wrote.
	movedDrawBuffers: usize = 0,
	/// `shaders.properties` keys whose presence or value depends on the pack's option set being in
	/// the preprocessor's table, as Iris has it. Each is printed: a program enable, a buffer size or
	/// a texture binding the bridge read wrong while only the user's overrides were in the table.
	optionDecidedKeys: usize = 0,
	/// `.csh` sources found beside the programs and transformed as compute stages
	/// (`pack.ComputeSource`); they count in `stages` too.
	computes: usize = 0,
	/// Computes with neither `workGroups` nor `workGroupsRender`, dispatched at the render size.
	/// Legal, and worth a number: every compute in the corpus declares one, so a change here is a
	/// directive the loader stopped reading.
	computesWithoutGroups: usize = 0,
	/// Shader storage blocks in the transformed sources whose binding was moved past the engine's
	/// (`glsl.Options.storageBindingBase`), against the number of blocks found at all. The two must
	/// agree, or a pack buffer shares a binding point with Cubyz's chunk data.
	storageBlocks: usize = 0,
	relocatedStorageBlocks: usize = 0,
	/// `image.<name>` and `bufferObject.N` declarations the option-resolved properties carry.
	customImages: usize = 0,
	bufferObjects: usize = 0,
	failed: ?[]const u8 = null,
};

/// The bridge's feature flags as `IRIS_FEATURE_*` defines, added to the properties table as
/// `bridge.load` adds them: a pack gates its images and buffers on these.
const featureDefines = [_][]const u8{
	"IRIS_FEATURE_SEPARATE_HARDWARE_SAMPLERS", "IRIS_FEATURE_PER_BUFFER_BLENDING",
	"IRIS_FEATURE_CUSTOM_IMAGES",              "IRIS_FEATURE_SSBO",
	"IRIS_FEATURE_COMPUTE_SHADERS",
};

/// Where the transformer moves a pack's storage blocks; kept in step with `images.storageBindingBase`
/// by hand, since that module needs a GL context to import.
const storageBindingBase: u32 = 16;

/// Whether `source` defines `main`: the identifier as a whole word, followed by `(`, outside
/// comments. Packs write `void main()`, `void main(void)` and `void main ()`, so the match is on
/// the name rather than on one spelling of the signature.
fn definesMain(source: []const u8) bool {
	var offset: usize = 0;
	while(std.mem.indexOfPos(u8, source, offset, "main")) |index| {
		offset = index + 1;
		if(index > 0 and isIdentifierChar(source[index - 1])) continue;
		var after = index + "main".len;
		while(after < source.len and (source[after] == ' ' or source[after] == '\t')) after += 1;
		if(after >= source.len or source[after] != '(') continue;
		if(insideComment(source, index)) continue;
		return true;
	}
	return false;
}

/// How many `float(` the transform added: the shim never emits one, so the difference is the
/// clamp-bound rewrite alone.
fn wrappedBounds(source: []const u8, result: []const u8) usize {
	return std.mem.count(u8, result, "float(") -| std.mem.count(u8, source, "float(");
}

/// Program names this loader intentionally ignores, so they are not reported as gaps.
///
/// `dh_*` are Distant Horizons programs, which Iris only runs when that mod is present and which
/// have no meaning in Cubyz. Anything else unrecognised is a genuine finding worth surfacing.
fn intentionallyIgnored(name: []const u8) bool {
	return std.mem.startsWith(u8, name, "dh_");
}

/// Counts `.fsh` files in the program directory that did not become programs.
fn countUnrecognised(io: std.Io, shadersRoot: []const u8, programs: []const pack.Program) usize {
	var searchPath = std.ArrayList(u8).initCapacity(allocator.allocator, 0) catch return 0;
	defer searchPath.deinit(allocator.allocator);
	searchPath.appendSlice(allocator.allocator, shadersRoot) catch return 0;
	searchPath.appendSlice(allocator.allocator, "/" ++ dimension) catch return 0;

	// Packs put programs either in a dimension folder or at the shaders root.
	var directory = std.Io.Dir.cwd().openDir(io, searchPath.items, .{.iterate = true}) catch
		std.Io.Dir.cwd().openDir(io, shadersRoot, .{.iterate = true}) catch return 0;
	defer directory.close(io);

	var count: usize = 0;
	var iterator = directory.iterate();
	while(iterator.next(io) catch null) |entry| {
		if(entry.kind != .file) continue;
		if(!std.mem.endsWith(u8, entry.name, ".fsh")) continue;
		const base = entry.name[0 .. entry.name.len - ".fsh".len];
		if(intentionallyIgnored(base)) continue;
		if(matchesLoadedProgram(base, programs)) continue;
		count += 1;
		std.debug.print("      unrecognised program file: {s}.fsh\n", .{base});
	}
	return count;
}

fn matchesLoadedProgram(base: []const u8, programs: []const pack.Program) bool {
	for(programs) |program| {
		const name = program.kind.baseName();
		if(!std.mem.startsWith(u8, base, name)) continue;
		// Numbered programs append their index; anything else must match exactly.
		const rest = base[name.len..];
		if(rest.len == 0) return true;
		var allDigits = true;
		for(rest) |ch| {
			if(!std.ascii.isDigit(ch)) allDigits = false;
		}
		if(allDigits) return true;
	}
	return false;
}

test "every shaderpack present loads and transforms" {
	var threaded = std.Io.Threaded.init(allocator.allocator, .{});
	defer threaded.deinit();
	const io = threaded.io();

	const entries = install.list(allocator, io, shaderpackDirectory);
	defer install.freeList(allocator, entries);

	if(entries.len == 0) {
		std.debug.print("SKIP: no shaderpacks in {s}/\n", .{shaderpackDirectory});
		return;
	}

	std.debug.print("\n=== {} shaderpack(s) found ===\n", .{entries.len});

	var anyLoaded = false;
	for(entries) |entry| {
		const report = check(io, entry) catch |err| {
			std.debug.print("  {s:<24} ERROR {s}\n", .{entry.name, @errorName(err)});
			continue;
		};
		if(report.failed) |reason| {
			std.debug.print("  {s:<24} FAILED: {s}\n", .{report.name, reason});
			continue;
		}
		anyLoaded = true;
		std.debug.print("  {s:<40} {:>3} programs  {:>3} stages  {:>6} KiB  {} leftovers  {} unrecognised  {} clamp bound(s)  {} overloaded  {} without main  {} moved by #if  {} keys by options  {} compute(s), {} without groups  {}/{} storage block(s) relocated  {} image(s)  {} buffer object(s)\n", .{
			report.name, report.programs, report.stages, report.bytes/1024, report.leftovers, report.unrecognised, report.clampBounds, report.overloads, report.missingMain, report.movedDrawBuffers, report.optionDecidedKeys,
			report.computes, report.computesWithoutGroups, report.relocatedStorageBlocks, report.storageBlocks, report.customImages, report.bufferObjects,
		});
		// Compat syntax surviving the rewrite means the driver would reject the shader.
		try std.testing.expectEqual(@as(usize, 0), report.leftovers);
		// A fragment stage without `main` compiles and then fails to link.
		try std.testing.expectEqual(@as(usize, 0), report.missingMain);
		// A pack storage block left on its own binding point shares it with Cubyz's chunk data.
		try std.testing.expectEqual(report.storageBlocks, report.relocatedStorageBlocks);
		try std.testing.expect(report.programs > 0);
	}

	try std.testing.expect(anyLoaded);
}

fn check(io: std.Io, entry: install.Entry) !Report {
	var report = Report{.name = entry.name};

	const packDirectory = install.resolve(allocator, io, shaderpackDirectory, entry.name) catch {
		report.failed = "could not resolve";
		return report;
	};
	defer allocator.free(packDirectory);

	const shadersRoot = install.findShadersRoot(allocator, io, packDirectory) orelse {
		report.failed = "no shaders/ directory";
		return report;
	};
	defer allocator.free(shadersRoot);

	var provider = pack.DirectoryProvider.init(allocator, io, shadersRoot) catch {
		report.failed = "could not read shaders/";
		return report;
	};
	defer provider.deinit();

	const rawProperties = provider.provider().read("/shaders.properties") orelse "";

	var settings = pack.Settings{};
	// No option overrides: the harness measures the pack as shipped.
	var overrides = pack.options.Overrides.init(allocator);
	defer overrides.deinit();
	// Iris's environment without a GL context: the fixed half of `pipeline.standardMacros`, so
	// a `#if MC_VERSION >= 11300` in a pack selects the same branch here as in the game.
	var environment = pack.preprocess.Defines.init(allocator);
	defer environment.deinit();
	for(standardEnvironment) |macro| environment.putMacroString(macro);
	const programs = pack.loadPrograms(allocator, provider.provider(), &settings, dimension, &overrides, &environment, null);
	defer {
		for(programs) |*program| program.deinit(allocator);
		allocator.free(programs);
	}
	report.programs = programs.len;
	if(programs.len == 0) {
		report.failed = "no programs discovered";
		return report;
	}

	// shaders.properties the way `bridge.load` reads it: through the preprocessor with the pack's
	// option set in the table. Read a second time with the environment alone, so the report can
	// say which keys the options decide - each is a line Iris honours and the bridge did not
	// before the option set reached this file.
	var sources = std.ArrayList([]const u8).initCapacity(allocator.allocator, 0) catch return report;
	defer sources.deinit(allocator.allocator);
	for(programs) |*program| {
		if(program.fragmentSource) |source| sources.append(allocator.allocator, source) catch return report;
		if(program.vertexSource) |source| sources.append(allocator.allocator, source) catch return report;
		if(program.geometrySource) |source| sources.append(allocator.allocator, source) catch return report;
		for(program.computes) |*compute| sources.append(allocator.allocator, compute.source) catch return report;
	}
	const declared = pack.options.discoverAll(allocator, sources.items);
	defer allocator.free(declared);
	var withOptions = environment.clone(allocator);
	defer withOptions.deinit();
	for(featureDefines) |flag| withOptions.put(flag, "");
	pack.options.putDefines(&withOptions, declared);
	const propertiesSource = pack.preprocess.run(allocator, rawProperties, &withOptions);
	defer allocator.free(propertiesSource);
	var properties = pack.parseProperties(allocator, propertiesSource);
	defer properties.deinit();
	pack.applyEnabledFlags(allocator, programs, &properties);

	// The pack's images and buffers, sized by its options as the bridge sizes them.
	{
		var macros = std.ArrayList(pack.Macro).initCapacity(allocator.allocator, 0) catch return report;
		defer macros.deinit(allocator.allocator);
		for(declared) |option| macros.append(allocator.allocator, .{.name = option.name, .value = option.current}) catch return report;
		const imageDeclarations = pack.parseImages(allocator, &properties, macros.items);
		defer pack.freeImages(allocator, imageDeclarations);
		report.customImages = imageDeclarations.len;
		for(imageDeclarations) |declaration| {
			std.debug.print("      {s} / image.{s}: {s} {s} {}x{}x{}{s}{s}\n", .{
				entry.name, declaration.name, @tagName(declaration.shape), @tagName(declaration.format),
				declaration.width, declaration.height, declaration.depth,
				if(declaration.samplerName != null) " sampled" else "", if(declaration.clear) " cleared" else "",
			});
		}
		for(pack.parseBufferObjects(&properties), 0..) |buffer, index| {
			const declaration = buffer orelse continue;
			report.bufferObjects += 1;
			std.debug.print("      {s} / bufferObject.{}: {} bytes{s}\n", .{entry.name, index, declaration.size, if(declaration.relative) " per screen texel" else ""});
		}
	}
	{
		var bare = environment.clone(allocator);
		defer bare.deinit();
		const bareSource = pack.preprocess.run(allocator, rawProperties, &bare);
		defer allocator.free(bareSource);
		var bareProperties = pack.parseProperties(allocator, bareSource);
		defer bareProperties.deinit();
		var iterator = properties.entries.iterator();
		while(iterator.next()) |pair| {
			const before = bareProperties.get(pair.key_ptr.*);
			if(before != null and std.mem.eql(u8, before.?, pair.value_ptr.*)) continue;
			report.optionDecidedKeys += 1;
			std.debug.print("      {s} / shaders.properties: `{s} = {s}` only with the option set\n", .{entry.name, pair.key_ptr.*, pair.value_ptr.*});
		}
		var bareIterator = bareProperties.entries.iterator();
		while(bareIterator.next()) |pair| {
			if(properties.get(pair.key_ptr.*) != null) continue;
			report.optionDecidedKeys += 1;
			std.debug.print("      {s} / shaders.properties: `{s} = {s}` only without the option set\n", .{entry.name, pair.key_ptr.*, pair.value_ptr.*});
		}
	}

	// Account for every program-shaped file, so a pack whose programs this loader does not
	// recognise shows up as a number rather than as silence. Under-discovery is the quiet failure
	// mode for multi-pack support: the pack loads, renders wrong, and nothing says why.
	report.unrecognised = countUnrecognised(io, shadersRoot, programs);

	for(programs) |program| {
		const drawBufferCount = @max(program.drawBuffers.count, 1);
		if(program.fragmentSource) |source| {
			if(pack.parseDrawBuffers(allocator, source)) |raw| {
				if(!std.mem.eql(u8, raw.slice(), program.drawBuffers.slice())) {
					report.movedDrawBuffers += 1;
					std.debug.print("      {s} / {s}{}: DRAWBUFFERS {any} in the raw text, {any} live\n", .{
						entry.name, program.kind.baseName(), program.index, raw.slice(), program.drawBuffers.slice(),
					});
				}
			}
			// The programs that run on Cubyz's geometry get the gbuffers builder's own options
			// (`pipeline.buildGbuffersPass`): the block-sampler redirects, the dispatch helpers,
			// the stripped sampler declarations, the renamed `main` and the alpha test. The
			// prologue text itself is left out, since it is not part of what this checks.
			const onGeometry = program.kind == .gbuffers_terrain or program.kind == .gbuffers_water or program.kind == .shadow;
			const result = glsl.transform(allocator, source, if(onGeometry) .{
				.stage = .fragment,
				.fragDataCount = drawBufferCount,
				.strippedAttributes = &pack.prologue.suppliedSamplers,
				.arraySamplers = &pack.prologue.arraySamplers,
				.macroDispatch = pack.prologue.macroDispatch,
				.alphaTest = program.kind != .gbuffers_water,
				.entryPointName = if(program.kind != .gbuffers_water) pack.prologue.packEntryPoint else null,
				.storageBindingBase = storageBindingBase,
			} else .{.stage = .fragment, .fragDataCount = drawBufferCount, .storageBindingBase = storageBindingBase});
			defer allocator.free(result);
			report.stages += 1;
			report.bytes += result.len;
			report.leftovers += countLeftovers(result, &.{"attribute ", "varying ", "gl_FragData", "gl_FragColor", "texture2D"}, entry.name, program.kind.baseName(), "fsh");
			report.clampBounds += wrappedBounds(source, result);
			report.overloads += std.mem.count(u8, result, "sampler2DArray overloads of the pack's own");
			countStorageBlocks(source, result, &report);
			if(!definesMain(result)) {
				report.missingMain += 1;
				std.debug.print("      {s} / {s}.fsh: no `main` after the transform\n", .{entry.name, program.kind.baseName()});
			}
		}
		if(program.vertexSource) |source| {
			const result = glsl.transform(allocator, source, .{.stage = .vertex, .storageBindingBase = storageBindingBase});
			defer allocator.free(result);
			report.stages += 1;
			report.bytes += result.len;
			report.leftovers += countLeftovers(result, &.{"attribute ", "varying ", "gl_Vertex", "gl_ModelViewMatrix", "gl_MultiTexCoord0"}, entry.name, program.kind.baseName(), "vsh");
			report.clampBounds += wrappedBounds(source, result);
			countStorageBlocks(source, result, &report);
		}
		if(program.geometrySource) |source| {
			const result = glsl.transform(allocator, source, .{.stage = .geometry, .storageBindingBase = storageBindingBase});
			defer allocator.free(result);
			report.stages += 1;
			report.bytes += result.len;
			report.leftovers += countLeftovers(result, &.{"varying ", "gl_ModelViewMatrix"}, entry.name, program.kind.baseName(), "gsh");
			report.clampBounds += wrappedBounds(source, result);
			countStorageBlocks(source, result, &report);
		}
		for(program.computes) |*compute| {
			const result = glsl.transform(allocator, compute.source, .{.stage = .compute, .storageBindingBase = storageBindingBase});
			defer allocator.free(result);
			report.stages += 1;
			report.computes += 1;
			report.bytes += result.len;
			report.leftovers += countLeftovers(result, &.{"varying ", "attribute ", "gl_FragData", "gl_FragColor", "texture2D"}, entry.name, compute.name, "csh");
			report.clampBounds += wrappedBounds(compute.source, result);
			countStorageBlocks(compute.source, result, &report);
			if(compute.workGroups.absolute == null and compute.workGroups.relative == null) {
				report.computesWithoutGroups += 1;
				std.debug.print("      {s} / {s}.csh: no workGroups directive; dispatched at the render size\n", .{entry.name, compute.name});
			}
			if(!definesMain(result)) {
				report.missingMain += 1;
				std.debug.print("      {s} / {s}.csh: no `main` after the transform\n", .{entry.name, compute.name});
			}
		}
	}
	return report;
}

/// Counts the storage blocks of one stage and how many the transform moved to `storageBindingBase`
/// or above. The draw stages of the geometry path carry the pack's blocks too - Nostalgic Red
/// Voxels' `shadow.gsh` voxelises into one - so every stage is counted.
fn countStorageBlocks(source: []const u8, result: []const u8, report: *Report) void {
	var before = cubyz.ListManaged(u32).init(allocator);
	defer before.deinit();
	glsl.storageBlockBindings(allocator, source, &before);
	var after = cubyz.ListManaged(u32).init(allocator);
	defer after.deinit();
	glsl.storageBlockBindings(allocator, result, &after);
	report.storageBlocks += before.items.len;
	for(after.items) |binding| {
		if(binding >= storageBindingBase) report.relocatedStorageBlocks += 1;
	}
}

fn isIdentifierChar(c: u8) bool {
	return std.ascii.isAlphanumeric(c) or c == '_';
}

/// Counts compat constructs that survived the rewrite, matching whole identifiers.
///
/// Substring matching gives false positives both ways: `gl_FragData` is a prefix of the
/// `cubyz_FragData` we generate, and `gl_Vertex` is a prefix of `gl_VertexID`, a core built-in
/// that must survive untouched.
fn countLeftovers(source: []const u8, needles: []const []const u8, packName: []const u8, program: []const u8, stage: []const u8) usize {
	var count: usize = 0;
	for(needles) |needle| {
		var offset: usize = 0;
		while(std.mem.indexOfPos(u8, source, offset, needle)) |index| {
			offset = index + 1;
			const after = index + needle.len;
			if(after < source.len and isIdentifierChar(source[after]) and isIdentifierChar(needle[needle.len - 1])) continue;
			if(index > 0 and isIdentifierChar(source[index - 1])) continue;
			if(insideComment(source, index)) continue;
			count += 1;
			const lineStart = if(std.mem.lastIndexOfScalar(u8, source[0..index], '\n')) |n| n + 1 else 0;
			const lineEnd = std.mem.indexOfScalarPos(u8, source, index, '\n') orelse source.len;
			std.debug.print("      {s} / {s}.{s}: leftover `{s}`\n        {s}\n", .{
				packName, program, stage, needle, std.mem.trim(u8, source[lineStart..lineEnd], " \t"),
			});
		}
	}
	return count;
}

/// Whether `index` falls inside a comment.
///
/// Scans from the start rather than looking at the current line, because a `/* ... */` block can
/// span lines - which is exactly how a pack can mention `varying` in prose without it being a
/// declaration the transform missed.
fn insideComment(source: []const u8, index: usize) bool {
	var i: usize = 0;
	while(i < index) : (i += 1) {
		if(source[i] == '/' and i + 1 < source.len) {
			if(source[i + 1] == '/') {
				const lineEnd = std.mem.indexOfScalarPos(u8, source, i, '\n') orelse source.len;
				if(index < lineEnd) return true;
				i = lineEnd;
				continue;
			}
			if(source[i + 1] == '*') {
				const close = std.mem.indexOfPos(u8, source, i + 2, "*/") orelse source.len;
				if(index < close) return true;
				i = close + 1;
				continue;
			}
		}
	}
	return false;
}
