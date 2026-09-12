//! What a pack asks for that the bridge does not supply.
//!
//! An unsupplied uniform is the worst failure mode this port has, because it is not a failure at any
//! level that can report one. The program links, GL hands the shader a zero, and the pack renders
//! confidently wrong. `framemod8` stuck at 0 broke Sildur's temporal sampling with nothing in the
//! log; `renderStage` reading 0 makes a pack treat every draw as the same stage. Both look like
//! "the port is approximate" rather than like a specific missing value.
//!
//! So instead of diagnosing packs one at a time, this enumerates every uniform each program
//! declares and subtracts everything the bridge provides. What remains is the gap list, per pack, in
//! one line each - which is a description of the work rather than a symptom to chase.
//!
//! Sampler names are excluded because they are supplied through a different mechanism
//! (`glUniform1i` to a texture unit) and would otherwise dominate the report.

const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const List = main.ListManaged;

const glsl = @import("glsl.zig");
const uniforms = @import("uniforms.zig");
const targets = @import("targets.zig");

/// Sampler and image uniforms the pipeline binds by texture unit rather than by value.
///
/// `colortexN`, `depthtexN`, `shadowtexN`, `shadowcolorN` and the OptiFine aliases are all handled
/// in `pipeline.bindSamplerUniforms`; the block texture and material maps come from the prologue.
fn isSamplerName(name: []const u8) bool {
	const exact = [_][]const u8{
		"gtexture",   "gcolor",     "tex",         "texture0",   "lightmap",
		"normals",    "specular",   "noisetex",    "shadow",     "watershadow",
		"shadowtex",  "gdepth",     "gnormal",     "composite",  "gaux1",
		"gaux2",      "gaux3",      "gaux4",       "depthtex",   "texture",
		"dhDepthTex", "dhDepthTex0", "dhDepthTex1",
	};
	for(exact) |entry| {
		if(std.mem.eql(u8, entry, name)) return true;
	}
	const prefixes = [_][]const u8{"colortex", "depthtex", "shadowtex", "shadowcolor", "colorimg", "shadowcolorimg"};
	for(prefixes) |prefix| {
		if(std.mem.startsWith(u8, name, prefix)) return true;
	}
	// The generated prologue's own declarations are not the pack's business.
	return std.mem.startsWith(u8, name, "cubyz_");
}

/// True when the bridge supplies this uniform by value.
fn isSupplied(name: []const u8, custom: []const []const u8) bool {
	inline for(@typeInfo(uniforms.Values).@"struct".fields) |field| {
		if(std.mem.eql(u8, field.name, name)) return true;
	}
	for(custom) |entry| {
		if(std.mem.eql(u8, entry, name)) return true;
	}
	// The compat shim rewrites the `gl_*` built-ins to `cubyz_*` names and declares them itself, so
	// a surviving `gl_` name here would be a transformer bug rather than a coverage gap.
	return std.mem.startsWith(u8, name, "gl_");
}

/// Collects the uniforms a pack declares that nothing supplies.
///
/// `sources` are the include-resolved program sources; `custom` are the names the pack's own
/// `shaders.properties` declares as expressions. Result names borrow from `sources`.
pub fn missingUniforms(
	allocator: NeverFailingAllocator,
	sources: []const []const u8,
	custom: []const []const u8,
) [][]const u8 {
	var declared = List([]const u8).init(allocator);
	defer declared.deinit();
	for(sources) |source| glsl.declaredUniforms(allocator, source, &declared);

	var missing = List([]const u8).init(allocator);
	outer: for(declared.items) |name| {
		if(isSamplerName(name)) continue;
		if(isSupplied(name, custom)) continue;
		// The same uniform is declared by every program that uses it.
		for(missing.items) |existing| {
			if(std.mem.eql(u8, existing, name)) continue :outer;
		}
		missing.append(name);
	}
	return missing.toOwnedSlice();
}

/// Logs the gap list, sorted, in one message.
///
/// One line rather than one per uniform: this is a summary of what the pack will render wrong, and
/// a forty-line log spam would get scrolled past rather than read.
pub fn report(allocator: NeverFailingAllocator, packName: []const u8, missing: [][]const u8) void {
	if(missing.len == 0) {
		std.log.info("irisbridge: {s} declares no uniforms the bridge is missing", .{packName});
		return;
	}
	std.mem.sort([]const u8, missing, {}, lessThanAlphabetically);

	var text = List(u8).init(allocator);
	defer text.deinit();
	for(missing, 0..) |name, index| {
		if(index != 0) text.appendSlice(", ");
		text.appendSlice(name);
	}
	std.log.warn("irisbridge: {s} reads {} uniform(s) nothing supplies, so they are zero: {s}", .{packName, missing.len, text.items});
}

/// Logs the `uniforms.unsupported` constants this pack actually reads.
///
/// The report above cannot see these and is not supposed to: they *are* supplied, as documented
/// constants standing in for concepts Cubyz has none of. But `unsupported`'s own doc comment says
/// the list exists so the gap stays visible, and nothing was reading the list - so a pack keying an
/// effect off `rainStrength` or `moonPhase` got a plausible number and no mention anywhere that it
/// will never change. Reported per pack, and only for names the pack declares.
pub fn reportUnsupported(allocator: NeverFailingAllocator, packName: []const u8, sources: []const []const u8) void {
	var declared = List([]const u8).init(allocator);
	defer declared.deinit();
	for(sources) |source| glsl.declaredUniforms(allocator, source, &declared);

	var read = List([]const u8).init(allocator);
	defer read.deinit();
	outer: for(uniforms.unsupported) |name| {
		for(declared.items) |entry| {
			if(!std.mem.eql(u8, entry, name)) continue;
			for(read.items) |existing| {
				if(std.mem.eql(u8, existing, name)) continue :outer;
			}
			read.append(name);
			continue :outer;
		}
	}
	if(read.items.len == 0) return;

	var text = List(u8).init(allocator);
	defer text.deinit();
	for(read.items, 0..) |name, index| {
		if(index != 0) text.appendSlice(", ");
		text.appendSlice(name);
	}
	std.log.info("irisbridge: {s} reads {} documented constant(s) Cubyz has no equivalent for, so they never change: {s}", .{packName, read.items.len, text.items});
}

fn lessThanAlphabetically(_: void, a: []const u8, b: []const u8) bool {
	return std.mem.order(u8, a, b) == .lt;
}
