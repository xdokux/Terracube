//! Finding shaderpacks and making them readable, whatever form they arrive in.
//!
//! Packs are distributed as `.zip` archives, and users drop them into a `shaderpacks/` folder
//! without extracting. Everything downstream reads through `pack.SourceProvider`, so the only
//! question here is how a given pack becomes one.
//!
//! Zips are extracted once into a cache directory rather than read in place. That is a deliberate
//! trade: a zip-backed provider would avoid the disk copy, but `#include` resolution does hundreds
//! of random lookups across a pack (Nostalgia pulls `lib/settings.glsl` into nearly every one of
//! its ~60 programs), and the directory provider that already serves those is tested. Extracting
//! keeps one code path for reads instead of two that can disagree.

const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const List = main.ListManaged;

// Deliberately no dependency on `pack.zig`: this module only produces a path, and keeping it
// standalone means it can be a module in its own right without the two colliding.

/// Where extracted zips are cached, relative to the shaderpack directory.
pub const cacheDirectoryName = ".cache";

pub const Kind = enum {directory, zip};

pub const Entry = struct {
	/// Name as the user would refer to it in settings - no extension.
	name: []const u8,
	kind: Kind,

	pub fn deinit(self: Entry, allocator: NeverFailingAllocator) void {
		allocator.free(self.name);
	}
};

/// Lists every shaderpack present, whether extracted or still zipped.
///
/// Caller owns the returned slice and each entry's name.
pub fn list(allocator: NeverFailingAllocator, io: std.Io, shaderpackDirectory: []const u8) []Entry {
	var found = List(Entry).init(allocator);

	var directory = std.Io.Dir.cwd().openDir(io, shaderpackDirectory, .{.iterate = true}) catch {
		return found.toOwnedSlice();
	};
	defer directory.close(io);

	var iterator = directory.iterate();
	while(iterator.next(io) catch null) |entry| {
		switch(entry.kind) {
			.directory => {
				// The extraction cache is an implementation detail, not a pack.
				if(std.mem.eql(u8, entry.name, cacheDirectoryName)) continue;
				found.append(.{.name = allocator.dupe(u8, entry.name), .kind = .directory});
			},
			.file => {
				if(!std.ascii.endsWithIgnoreCase(entry.name, ".zip")) continue;
				found.append(.{
					.name = allocator.dupe(u8, entry.name[0 .. entry.name.len - ".zip".len]),
					.kind = .zip,
				});
			},
			else => {},
		}
	}
	return found.toOwnedSlice();
}

pub fn freeList(allocator: NeverFailingAllocator, entries: []Entry) void {
	for(entries) |entry| entry.deinit(allocator);
	allocator.free(entries);
}

pub const ResolveError = error{NotFound, ExtractionFailed};

/// Returns the directory to read a pack from, extracting a zip first if that is what it is.
///
/// Caller owns the returned path.
pub fn resolve(allocator: NeverFailingAllocator, io: std.Io, shaderpackDirectory: []const u8, name: []const u8) ResolveError![]u8 {
	// An already-extracted folder wins, so a user who unzipped by hand gets what they expect and
	// a stale cache never shadows it.
	{
		const direct = join(allocator, &.{shaderpackDirectory, name});
		if(hasDirectory(io, direct)) return direct;
		allocator.free(direct);
	}

	const archive = joinWithSuffix(allocator, &.{shaderpackDirectory, name}, ".zip");
	defer allocator.free(archive);
	if(!hasFile(io, archive)) return error.NotFound;

	const cached = join(allocator, &.{shaderpackDirectory, cacheDirectoryName, name});
	errdefer allocator.free(cached);

	if(hasDirectory(io, cached)) return cached;

	extractZip(io, archive, cached) catch |err| {
		std.log.err("irisbridge: could not extract {s}: {s}", .{archive, @errorName(err)});
		return error.ExtractionFailed;
	};
	std.log.info("irisbridge: extracted {s} to {s}", .{archive, cached});
	return cached;
}

fn extractZip(io: std.Io, archivePath: []const u8, destination: []const u8) !void {
	var file = try std.Io.Dir.cwd().openFile(io, archivePath, .{});
	defer file.close(io);

	var destinationDirectory = try std.Io.Dir.cwd().createDirPathOpen(io, destination, .{});
	defer destinationDirectory.close(io);

	var buffer: [64*1024]u8 = undefined;
	var reader = file.reader(io, &buffer);
	// Zips authored on Windows tooling sometimes carry backslash separators; refusing those would
	// reject perfectly ordinary packs.
	try std.zip.extract(destinationDirectory, &reader, .{.allow_backslashes = true});
}

/// A pack's shader sources may sit at the root or one level down, because zipping a pack folder
/// usually captures the folder itself.
///
/// Returns the path that actually contains `shaders/`, or null.
pub fn findShadersRoot(allocator: NeverFailingAllocator, io: std.Io, packDirectory: []const u8) ?[]u8 {
	{
		const direct = join(allocator, &.{packDirectory, "shaders"});
		if(hasDirectory(io, direct)) return direct;
		allocator.free(direct);
	}

	// One level of nesting, e.g. `Pack.zip` containing `Pack/shaders/`.
	var directory = std.Io.Dir.cwd().openDir(io, packDirectory, .{.iterate = true}) catch return null;
	defer directory.close(io);

	var iterator = directory.iterate();
	while(iterator.next(io) catch null) |entry| {
		if(entry.kind != .directory) continue;
		const nested = join(allocator, &.{packDirectory, entry.name, "shaders"});
		if(hasDirectory(io, nested)) return nested;
		allocator.free(nested);
	}
	return null;
}

// MARK: path helpers

fn join(allocator: NeverFailingAllocator, parts: []const []const u8) []u8 {
	var out = List(u8).init(allocator);
	for(parts, 0..) |part, index| {
		if(index != 0) out.append('/');
		out.appendSlice(part);
	}
	return out.toOwnedSlice();
}

fn joinWithSuffix(allocator: NeverFailingAllocator, parts: []const []const u8, suffix: []const u8) []u8 {
	var out = List(u8).init(allocator);
	for(parts, 0..) |part, index| {
		if(index != 0) out.append('/');
		out.appendSlice(part);
	}
	out.appendSlice(suffix);
	return out.toOwnedSlice();
}

fn hasDirectory(io: std.Io, path: []const u8) bool {
	var directory = std.Io.Dir.cwd().openDir(io, path, .{}) catch return false;
	directory.close(io);
	return true;
}

fn hasFile(io: std.Io, path: []const u8) bool {
	_ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
	return true;
}

comptime {
	// Analysed eagerly so signature drift against `pack.zig` surfaces at build time rather than
	// the first time a user points the setting at a zip.
	_ = &list;
	_ = &resolve;
	_ = &findShadersRoot;
}
