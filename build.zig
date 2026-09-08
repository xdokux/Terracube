const std = @import("std");

fn libName(b: *std.Build, name: []const u8, target: std.Target) []const u8 {
	return switch (target.os.tag) {
		.windows => b.fmt("{s}.lib", .{name}),
		else => b.fmt("lib{s}.a", .{name}),
	};
}

fn linkLibraries(b: *std.Build, exe: *std.Build.Step.Compile, useLocalDeps: bool) void {
	const target = exe.root_module.resolved_target.?;
	const t = target.result;
	const optimize = exe.root_module.optimize.?;

	const depsLib = b.fmt("cubyz_deps_{s}-{s}-{s}", .{@tagName(t.cpu.arch), @tagName(t.os.tag), switch (t.os.tag) {
		.linux => "musl",
		.macos => "none",
		.windows => "gnu",
		else => "none",
	}});
	const artifactName = libName(b, depsLib, t);

	var depsName: []const u8 = b.fmt("cubyz_deps_{s}_{s}", .{@tagName(t.cpu.arch), @tagName(t.os.tag)});
	if (useLocalDeps) depsName = "local";

	const libsDeps = b.lazyDependency(depsName, .{
		.target = target,
		.optimize = optimize,
	}) orelse {
		// Lazy dependencies with a `url` field will fail here the first time.
		// build.zig will restart and try again.
		std.log.info("Downloading cubyz_deps libraries {s}.", .{depsName});
		return;
	};
	const headersDeps = if (useLocalDeps) libsDeps else b.lazyDependency("cubyz_deps_headers", .{}) orelse {
		std.log.info("Downloading cubyz_deps headers {s}.", .{depsName});
		return;
	};

	exe.root_module.addIncludePath(headersDeps.path("include"));
	exe.root_module.addObjectFile(libsDeps.path("lib").path(b, artifactName));
	const subPath = libsDeps.path("lib").path(b, depsLib);
	exe.root_module.addObjectFile(subPath.path(b, libName(b, "glslang", t)));
	exe.root_module.addObjectFile(subPath.path(b, libName(b, "MachineIndependent", t)));
	exe.root_module.addObjectFile(subPath.path(b, libName(b, "GenericCodeGen", t)));
	exe.root_module.addObjectFile(subPath.path(b, libName(b, "glslang-default-resource-limits", t)));
	exe.root_module.addObjectFile(subPath.path(b, libName(b, "SPIRV", t)));
	exe.root_module.addObjectFile(subPath.path(b, libName(b, "SPIRV-Tools", t)));
	exe.root_module.addObjectFile(subPath.path(b, libName(b, "SPIRV-Tools-opt", t)));

	const translate_c = b.addTranslateC(.{
		.root_source_file = b.path("src/c.h"),
		.target = target,
		.optimize = optimize,
	});
	translate_c.addIncludePath(headersDeps.path("include"));

	exe.root_module.addImport("c", translate_c.createModule());

	if (t.os.tag == .macos) {
		const moltenVkLibInstall = b.addInstallFile(subPath.path(b, "libMoltenVK.dylib"), "bin/Cubyz.app/Contents/Frameworks/libMoltenVK.dylib");
		const moltenVkJsonInstall = b.addInstallFile(subPath.path(b, "MoltenVK_icd.json"), "bin/Cubyz.app/Contents/Resources/vulkan/icd.d/MoltenVK_icd.json");
		exe.step.dependOn(&moltenVkLibInstall.step);
		exe.step.dependOn(&moltenVkJsonInstall.step);

		const validationLayerLibInstall = b.addInstallFile(subPath.path(b, "libVkLayer_khronos_validation.dylib"), "bin/Cubyz.app/Contents/Frameworks/libVkLayer_khronos_validation.dylib");
		const validationLayerJsonInstall = b.addInstallFile(subPath.path(b, "VkLayer_khronos_validation.json"), "bin/Cubyz.app/Contents/Resources/vulkan/explicit_layer.d/VkLayer_khronos_validation.json");
		exe.step.dependOn(&validationLayerLibInstall.step);
		exe.step.dependOn(&validationLayerJsonInstall.step);
	}

	if (t.os.tag == .windows) {
		exe.root_module.linkSystemLibrary("bcrypt", .{});
		exe.root_module.linkSystemLibrary("comdlg32", .{});
		exe.root_module.linkSystemLibrary("crypt32", .{});
		exe.root_module.linkSystemLibrary("gdi32", .{});
		exe.root_module.linkSystemLibrary("ole32", .{});
		exe.root_module.linkSystemLibrary("opengl32", .{});
		exe.root_module.linkSystemLibrary("ws2_32", .{});
	} else if (t.os.tag == .macos) {
		exe.root_module.linkFramework("Cocoa", .{});
		exe.root_module.linkFramework("CoreFoundation", .{});
		exe.root_module.linkFramework("IOKit", .{});
		exe.root_module.linkFramework("QuartzCore", .{});
	} else if (t.os.tag != .linux) {
		std.log.err("Unsupported target: {}\n", .{t.os.tag});
	}
}

pub fn makeModFeature(io: std.Io, step: *std.Build.Step, name: []const u8) !void {
	var featureList: std.ArrayListUnmanaged(u8) = .empty;
	defer featureList.deinit(step.owner.allocator);

	var modDir = try std.Io.Dir.cwd().openDir(io, "mods", .{.iterate = true});
	defer modDir.close(io);

	var iterator = modDir.iterate();
	while (try iterator.next(io)) |modEntry| {
		if (modEntry.kind != .directory) continue;

		var mod = try modDir.openDir(io, modEntry.name, .{});
		defer mod.close(io);

		var featureDir = mod.openDir(io, name, .{.iterate = true}) catch continue;
		defer featureDir.close(io);

		var featureIterator = featureDir.iterate();
		while (try featureIterator.next(io)) |featureEntry| {
			if (featureEntry.kind != .file) continue;
			if (!std.mem.endsWith(u8, featureEntry.name, ".zig")) continue;

			try featureList.appendSlice(step.owner.allocator, step.owner.fmt(
				\\pub const @"{s}:{s}" = @import("{s}/{s}/{s}");
				\\
			,
				.{
					modEntry.name,
					featureEntry.name[0 .. featureEntry.name.len - 4],
					modEntry.name,
					name,
					featureEntry.name,
				},
			));
		}
	}

	const file_path = step.owner.fmt("mods/{s}.zig", .{name});
	try std.Io.Dir.cwd().writeFile(io, .{.data = featureList.items, .sub_path = file_path});
}

pub fn addModFeatureModule(b: *std.Build, exe: *std.Build.Step.Compile, name: []const u8) !void {
	const module = b.createModule(.{
		.root_source_file = b.path(b.fmt("mods/{s}.zig", .{name})),
		.target = exe.root_module.resolved_target,
		.optimize = exe.root_module.optimize,
	});
	module.addImport("main", exe.root_module);
	exe.root_module.addImport(name, module);
}

fn addModFeatures(b: *std.Build, exe: *std.Build.Step.Compile) !void {
	const step = try b.allocator.create(std.Build.Step);
	step.* = std.Build.Step.init(.{
		.id = .custom,
		.name = "Create Mods",
		.owner = b,
		.makeFn = makeModFeaturesStep,
	});
	exe.step.dependOn(step);

	for (modFeatures) |name| {
		try addModFeatureModule(b, exe, name);
	}
}

/// The kinds of Zig code a mod may contribute. Each one becomes a module built from every
/// `mods/<mod>/<feature>/*.zig` file, which the corresponding registry in `src` merges with
/// its own built-in list.
const modFeatures = [_][]const u8{"rotations", "structuremapgen", "mapgen", "climategen"};

/// The renderer-side mod, if installed.
///
/// This one is not a `modFeature`: those generate a list of independent files that a registry
/// merges, which suits worldgen but not a render pipeline with a single entry point and ordered
/// per-frame hooks. Instead `mods/renderhook.zig` is generated to forward to this module when it
/// is present and to no-op otherwise, so `src/renderer.zig` can call the hooks unconditionally
/// and the engine still builds with the mod absent.
const renderHookMod = "irisbridge";
const renderHookRoot = "mods/" ++ renderHookMod ++ "/lib/bridge.zig";

/// Hooks `src/renderer.zig` and the settings screens may call. Kept in one place so adding a hook
/// is a single edit, and so the no-mod stubs cannot drift from the real signatures.
///
/// The two that fill a caller-owned list rather than returning a slice do so deliberately: the
/// absent-mod stub has to synthesise a return value, and there is no valid zero for a non-optional
/// slice. A `void` hook that appends nothing degrades to "no packs offered", which is exactly right.
const renderHooks = [_][]const u8{
	"pub fn updateSize(width: u31, height: u31) void",
	"pub fn beginFrame(deltaTime: f32, playerPos: main.vec.Vec3d) void",
	"pub fn runPostChain(worldFramebuffer: c_uint, screenWidth: u31, screenHeight: u31) void",
	"pub fn runPreparePasses(screenWidth: u31, screenHeight: u31) void",
	"pub fn isActive() bool",
	"pub fn beginTerrain() bool",
	"pub fn endTerrain() void",
	"pub fn beginTranslucent() bool",
	"pub fn endTranslucent() void",
	"pub fn beginCubyzShadedDraws() void",
	"pub fn endCubyzShadedDraws() void",
	"pub fn restoreSceneDepth() void",
	"pub fn renderShadowMap(chunkLists: *const main.renderer.chunk_meshing.ChunkLists, ambient: main.vec.Vec3f, playerPos: main.vec.Vec3d) void",
	"pub fn listShaderPacks(allocator: main.heap.NeverFailingAllocator, out: *main.ListManaged([]const u8)) void",
	"pub fn listPackOptions(allocator: main.heap.NeverFailingAllocator, out: *main.ListManaged(main.renderer.ShaderPackOption)) void",
	"pub fn setPackOption(name: []const u8, value: []const u8) void",
};

/// The return type of a hook signature, for synthesising a stub body when the mod is absent.
fn hookReturnType(signature: []const u8) []const u8 {
	const close = std.mem.lastIndexOfScalar(u8, signature, ')').?;
	return std.mem.trim(u8, signature[close + 1 ..], " ");
}

/// Whether the renderer-side mod is installed in this tree.
///
/// Checked rather than assumed, so the engine builds either way: with the mod absent the generated
/// `mods/renderhook.zig` is all no-op stubs and `src/renderer.zig` calls them unconditionally.
fn renderHookPresent(b: *std.Build) bool {
	return if(b.build_root.handle.statFile(b.graph.io, renderHookRoot, .{})) |_| true else |_| false;
}

fn makeRenderHookStep(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
	var io = std.Io.Threaded.init(options.gpa, .{});
	defer io.deinit();

	const b = step.owner;
	const present = if(std.Io.Dir.cwd().statFile(io.io(), renderHookRoot, .{})) |_| true else |_| false;

	// Built by appending formatted slices rather than through a writer, which is the same idiom
	// `makeModFeature` above uses — `std.ArrayList` has no `writer` method in this std.
	var source: std.ArrayList(u8) = .empty;
	defer source.deinit(b.allocator);

	try source.appendSlice(b.allocator, "//! Generated by build.zig. Do not edit.\n");
	// The hook signatures name engine types (`main.vec.Vec3d`, `main.ListManaged`), so this module
	// needs `main` whether or not the mod is installed — the stub branch declares the same
	// signatures it would forward.
	try source.appendSlice(b.allocator, "const main = @import(\"main\");\n");
	if(present) {
		try source.appendSlice(b.allocator, b.fmt("const impl = @import(\"{s}\");\n", .{renderHookMod}));
		try source.appendSlice(b.allocator, "pub const enabled = true;\n");
	} else {
		try source.appendSlice(b.allocator, "pub const enabled = false;\n");
	}
	for(renderHooks) |signature| {
		try source.appendSlice(b.allocator, b.fmt("{s} {{", .{signature}));
		if(present) {
			const name = signature["pub fn ".len..std.mem.indexOfScalar(u8, signature, '(').?];
			const args = signature[std.mem.indexOfScalar(u8, signature, '(').? .. std.mem.lastIndexOfScalar(u8, signature, ')').? + 1];
			try source.appendSlice(b.allocator, b.fmt("return impl.{s}({s});", .{name, stripTypes(b, args)}));
		} else {
			// Discard the arguments so an unused-parameter error does not appear when disabled.
			var parameters = std.mem.tokenizeScalar(u8, signature[std.mem.indexOfScalar(u8, signature, '(').? + 1 .. std.mem.lastIndexOfScalar(u8, signature, ')').?], ',');
			while(parameters.next()) |parameter| {
				const name = std.mem.trim(u8, parameter[0..std.mem.indexOfScalar(u8, parameter, ':').?], " ");
				try source.appendSlice(b.allocator, b.fmt("_ = {s};", .{name}));
			}
			// A hook that answers a question has to answer it. `false` is the honest stub for all of
			// them: with no mod installed nothing is active, no stage is overridden, and the engine
			// takes its own path.
			const returns = hookReturnType(signature);
			if(!std.mem.eql(u8, returns, "void")) {
				try source.appendSlice(b.allocator, b.fmt("return {s};", .{
					if(std.mem.eql(u8, returns, "bool")) "false" else "undefined",
				}));
			}
		}
		try source.appendSlice(b.allocator, "}\n");
	}
	try std.Io.Dir.cwd().writeFile(io.io(), .{.data = source.items, .sub_path = "mods/renderhook.zig"});
}

/// `(width: u31, height: u31)` -> `width, height`, for forwarding a call.
fn stripTypes(b: *std.Build, parenthesised: []const u8) []const u8 {
	var names: std.ArrayList(u8) = .empty;
	var parameters = std.mem.tokenizeScalar(u8, parenthesised[1 .. parenthesised.len - 1], ',');
	while(parameters.next()) |parameter| {
		const colon = std.mem.indexOfScalar(u8, parameter, ':') orelse continue;
		if(names.items.len != 0) names.appendSlice(b.allocator, ", ") catch @panic("OOM");
		names.appendSlice(b.allocator, std.mem.trim(u8, parameter[0..colon], " ")) catch @panic("OOM");
	}
	return names.items;
}

/// Returns the step that writes `mods/renderhook.zig`, so that every artifact compiling `main`
/// can depend on it - the engine's test artifact shares the exe's root module, and without the
/// dependency a clean checkout fails `zig build test` with `'mods\renderhook.zig' file_hash
/// FileNotFound` while `zig build` alone generates the file and hides the gap thereafter.
fn addRenderHook(b: *std.Build, exe: *std.Build.Step.Compile) !*std.Build.Step {
	const step = try b.allocator.create(std.Build.Step);
	step.* = std.Build.Step.init(.{
		.id = .custom,
		.name = "Create Render Hook",
		.owner = b,
		.makeFn = makeRenderHookStep,
	});
	exe.step.dependOn(step);

	if(b.build_root.handle.statFile(b.graph.io, renderHookRoot, .{})) |_| {
		const module = b.createModule(.{
			.root_source_file = b.path(renderHookRoot),
			.target = exe.root_module.resolved_target,
			.optimize = exe.root_module.optimize,
		});
		module.addImport("main", exe.root_module);
		exe.root_module.addImport(renderHookMod, module);
	} else |_| {}

	const hookModule = b.createModule(.{
		.root_source_file = b.path("mods/renderhook.zig"),
		.target = exe.root_module.resolved_target,
		.optimize = exe.root_module.optimize,
	});
	hookModule.addImport("main", exe.root_module);
	if(b.build_root.handle.statFile(b.graph.io, renderHookRoot, .{})) |_| {
		const implModule = b.createModule(.{
			.root_source_file = b.path(renderHookRoot),
			.target = exe.root_module.resolved_target,
			.optimize = exe.root_module.optimize,
		});
		implModule.addImport("main", exe.root_module);
		hookModule.addImport(renderHookMod, implModule);
	} else |_| {}
	exe.root_module.addImport("renderhook", hookModule);
	return step;
}

pub fn makeModFeaturesStep(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
	var io = std.Io.Threaded.init(options.gpa, .{});
	defer io.deinit();

	for (modFeatures) |name| {
		try makeModFeature(io.io(), step, name);
	}
}

fn createLaunchConfig(b: *std.Build) !void {
	var io = std.Io.Threaded.init(b.allocator, .{});
	defer io.deinit();
	std.Io.Dir.cwd().access(io.io(), "launchConfig.zon", .{}) catch {
		const launchConfig =
			\\.{
			\\    .cubyzDir = "",
			\\    .autoEnterWorld = "",
			\\    .headlessServer = false,
			\\    // .preferredAuthenticationAlgorithm = .ed25519, // Uncomment and change this if you own a server in an outdated game version where the default algorithm got compromised.
			\\}
		;
		try std.Io.Dir.cwd().writeFile(io.io(), .{
			.data = launchConfig,
			.sub_path = "launchConfig.zon",
		});
	};
}

pub fn build(b: *std.Build) !void {
	try createLaunchConfig(b);

	// Standard target options allows the person running `zig build` to choose
	// what target to build for. Here we do not override the defaults, which
	// means any target is allowed, and the default is native. Other options
	// for restricting supported target set are available.
	const target = b.standardTargetOptions(.{});

	// Standard release options allow the person running `zig build` to select
	// between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
	const optimize = b.standardOptimizeOption(.{});

	const options = b.addOptions();
	const isRelease = b.option(bool, "release", "Removes the -dev flag from the version") orelse false;
	const version = b.fmt("0.3.0{s}", .{if (isRelease) "" else "-dev"});
	if (b.option([]const u8, "version", "used by the CI to check if the git tag and game version match")) |tagVersion| {
		const tagVersionUpperbound: usize = std.mem.indexOfScalar(u8, tagVersion, '-') orelse tagVersion.len;
		const versionUpperbound: usize = std.mem.indexOfScalar(u8, version, '-') orelse version.len;
		const tagParsed = try std.SemanticVersion.parse(tagVersion[0..tagVersionUpperbound]);
		const versionParsed = try std.SemanticVersion.parse(version[0..versionUpperbound]);
		if (std.SemanticVersion.order(tagParsed, versionParsed) != .eq) {
			std.log.err("Provided version {s} does not match version in build.zig: {s}", .{tagVersion, version});
			return error.VersionMismatch;
		}
	}
	options.addOption([]const u8, "version", version);
	options.addOption(bool, "isTaggedRelease", isRelease);

	const useLocalDeps = b.option(bool, "local", "Use local cubyz_deps") orelse false;

	const largeAssets = b.dependency("cubyz_large_assets", .{});
	b.installDirectory(.{
		.source_dir = largeAssets.path("music"),
		.install_subdir = "assets/cubyz/music/",
		.install_dir = .{.custom = ".."},
	});
	b.installDirectory(.{
		.source_dir = largeAssets.path("fonts"),
		.install_subdir = "assets/cubyz/fonts/",
		.install_dir = .{.custom = ".."},
	});

	const mainModule = b.addModule("main", .{
		.root_source_file = b.path("src/main.zig"),
		.target = target,
		.optimize = optimize,
		.link_libc = true,
		.link_libcpp = true,
	});

	const exe = b.addExecutable(.{
		.name = "Cubyz",
		.root_module = mainModule,
		//.sanitize_thread = true,
	});
	exe.root_module.addOptions("build_options", options);
	exe.root_module.addImport("main", mainModule);
	try addModFeatures(b, exe);
	const renderHookStep = try addRenderHook(b, exe);

	if (isRelease and target.result.os.tag == .windows) {
		exe.subsystem = .windows;
	}

	linkLibraries(b, exe, useLocalDeps);

	var exeInstallOptions: std.Build.Step.InstallArtifact.Options = .{};
	if (target.result.os.tag == .macos) {
		exeInstallOptions = .{
			.dest_dir = .{.override = .{.custom = "bin/Cubyz.app/Contents/MacOS"}},
		};

		const plistContents =
			\\<?xml version="1.0" encoding="UTF-8"?>
			\\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
			\\<plist version="1.0">
			\\<dict>
			\\    <key>CFBundleIconFile</key>
			\\    <string>logo</string>
			\\</dict>
			\\</plist>
		;

		const writeFiles = b.addWriteFiles();
		const plistPath = writeFiles.add("Info.plist", plistContents);
		const plistInstall = b.addInstallFile(plistPath, "bin/Cubyz.app/Contents/Info.plist");
		b.getInstallStep().dependOn(&plistInstall.step);
		const iconsInstall = b.addInstallFile(b.path("assets/cubyz/logo.icns"), "bin/Cubyz.app/Contents/Resources/logo.icns");
		b.getInstallStep().dependOn(&iconsInstall.step);

		// NOTE(blackedout): This is to make the Vulkan loader search in (bundle)/Contents/Frameworks to find the libs referenced in the manifest files
		exe.root_module.addRPathSpecial("@loader_path/../Frameworks");
	}

	const installExe = b.addInstallArtifact(exe, exeInstallOptions);
	b.getInstallStep().dependOn(&installExe.step);

	const run_cmd = b.addRunArtifact(exe);
	run_cmd.step.dependOn(b.getInstallStep());
	if (b.args) |args| {
		run_cmd.addArgs(args);
	}

	const run_step = b.step("run", "Run the app");
	run_step.dependOn(&run_cmd.step);

	const dependencyWithTestRunner = b.lazyDependency("cubyz_test_runner", .{
		.target = target,
		.optimize = optimize,
	}) orelse {
		std.log.info("Downloading cubyz_test_runner dependency.", .{});
		return;
	};
	const exe_tests = b.addTest(.{
		.root_module = mainModule,
		.test_runner = .{.path = dependencyWithTestRunner.path("lib/compiler/test_runner.zig"), .mode = .simple},
	});
	linkLibraries(b, exe_tests, useLocalDeps);
	exe_tests.root_module.addOptions("build_options", options);
	exe_tests.root_module.addImport("main", mainModule);
	try addModFeatures(b, exe_tests);
	// The test artifact compiles `mainModule`, which imports the generated `mods/renderhook.zig`;
	// only the exe's step depended on the generator, so `zig build test` on a clean checkout failed
	// before `zig build` had ever run.
	exe_tests.step.dependOn(renderHookStep);
	const run_exe_tests = b.addRunArtifact(exe_tests);

	const test_step = b.step("test", "Run unit tests");
	test_step.dependOn(&run_exe_tests.step);

	// The renderer-side mod is a separate module, and Zig collects tests per module, so the engine
	// artifact above cannot see its tests. A second artifact picks them up, and only when the mod is
	// actually installed in this tree.
	//
	// It deliberately does *not* import the engine's `main`. Doing so would pull `renderhook` and
	// with it the `irisbridge` module, putting the same `lib/*.zig` files in two modules at once —
	// which Zig rejects outright. The stub in `test/` stands in for the slice of `main` these files
	// touch, so the suite also links in seconds instead of dragging in the C dependencies.
	if (renderHookPresent(b)) {
		const stubModule = b.createModule(.{
			.root_source_file = b.path("mods/irisbridge/test/main_stub.zig"),
			.target = target,
			.optimize = optimize,
		});
		// The real vector maths, not a stand-in: `src/vec.zig` imports nothing but `std`, so the
		// matrix tests exercise exactly the code the engine runs.
		stubModule.addImport("vec", b.createModule(.{.root_source_file = b.path("src/vec.zig")}));

		const modTestModule = b.createModule(.{
			.root_source_file = b.path("mods/irisbridge/tests.zig"),
			.target = target,
			.optimize = optimize,
		});
		modTestModule.addImport("main", stubModule);

		const modTests = b.addTest(.{
			.root_module = modTestModule,
			.test_runner = .{.path = dependencyWithTestRunner.path("lib/compiler/test_runner.zig"), .mode = .simple},
		});
		test_step.dependOn(&b.addRunArtifact(modTests).step);
	}
}
