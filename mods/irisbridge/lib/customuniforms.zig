//! Declaration handling for custom uniforms: parsing them out of `shaders.properties`, ordering
//! them by dependency, evaluating once per frame, and uploading them to each program.
//!
//! The expression language itself is `expression.zig`; this is the part that knows about packs.
//!
//! Failure handling is warn and drop, matching Iris, and the reason it matters is that the
//! alternative is worse than it sounds. A dropped uniform is simply never written, so the shader
//! sees GL's default of zero - but a uniform that silently evaluated to zero *would look the same*
//! while hiding the cause. So every drop is logged with its reason, and broken-ness propagates:
//! anything referencing a dropped uniform is dropped too, because a half-evaluated chain produces
//! numbers that are wrong rather than absent.
//!
//! One deliberate divergence: Iris treats a dependency cycle as fatal and falls back to vanilla
//! rendering for the whole pack. Here the cyclic group and its dependents are dropped and the rest
//! of the pack keeps working, which seems the better trade when the alternative is losing every
//! effect over one bad line.

const std = @import("std");

const main = @import("main");
const c = main.c;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const List = main.ListManaged;

const expression = @import("expression.zig");
const biomemap = @import("biomemap.zig");
const pack = @import("pack.zig");
const uniforms = @import("uniforms.zig");

pub const Declaration = struct {
	name: []const u8,
	declaredType: expression.Type,
	source: []const u8,
	tree: ?expression.Tree = null,
	/// Set when this declaration, or something it depends on, could not be used.
	broken: bool = false,

	pub fn deinit(self: *Declaration, allocator: NeverFailingAllocator) void {
		allocator.free(self.name);
		allocator.free(self.source);
		if(self.tree) |tree| tree.deinit(allocator);
	}
};

/// Evaluated custom uniforms for the current frame, plus the machinery to refresh them.
pub const Set = struct {
	declarations: []Declaration,
	/// Evaluation order, as indices into `declarations`. Excludes everything broken.
	order: []u32,
	values: std.StringHashMapUnmanaged(expression.Value) = .empty,
	evaluator: expression.Evaluator,
	allocator: NeverFailingAllocator,
	/// The frame's built-in uniform values, swapped in before each evaluation.
	frame: *const uniforms.Values = undefined,

	pub fn deinit(self: *Set) void {
		for(self.declarations) |*declaration| declaration.deinit(self.allocator);
		self.allocator.free(self.declarations);
		self.allocator.free(self.order);
		self.values.deinit(self.allocator.allocator);
		self.evaluator.deinit();
	}

	pub fn count(self: *const Set) usize {
		return self.order.len;
	}


	fn lookupImpl(ptr: *anyopaque, name: []const u8) ?expression.Value {
		const self: *Set = @ptrCast(@alignCast(ptr));
		// Built-ins win over pack declarations, matching Iris's resolution order - a pack cannot
		// shadow `viewWidth`.
		if(builtinValue(self.frame, name)) |value| return value;
		// Iris defines a `BIOME_<NAME>` constant per registered biome and a `CAT_<CATEGORY>` per
		// biome category for this language, and packs write `in(biome, BIOME_SWAMP, ...)` and
		// `biome_category == CAT_DESERT` against them; without these every such uniform failed with
		// an unknown variable and was never uploaded at all. `PPT_*` rides along, see `biomemap`.
		if(biomemap.constant(name)) |id| return .{.int = id};
		return self.values.get(name);
	}

	/// Recomputes every custom uniform, in dependency order.
	pub fn evaluate(self: *Set, frame: *const uniforms.Values, deltaTime: f32) void {
		self.frame = frame;
		self.evaluator.deltaTime = deltaTime;
		self.evaluator.environment = .{.ptr = self, .lookupFn = &lookupImpl};

		for(self.order) |index| {
			const declaration = &self.declarations[index];
			const tree = declaration.tree orelse continue;
			const value = self.evaluator.evaluate(tree) catch |err| {
				// Only report once: a uniform that fails now fails every frame, and per-frame
				// logging would bury everything else.
				if(!declaration.broken) {
					std.log.warn("irisbridge: custom uniform '{s}' failed at runtime: {s}", .{declaration.name, @errorName(err)});
					declaration.broken = true;
				}
				continue;
			};
			self.values.put(self.allocator.allocator, declaration.name, expression.coerceTo(value, declaration.declaredType)) catch unreachable;
		}
	}

	/// Uploads every custom uniform the program actually declares.
	///
	/// A name the program does not declare is skipped silently - that is normal, since a pack
	/// declares one shared set and each program uses a handful.
	pub fn upload(self: *const Set, program: c_uint) void {
		var nameBuffer: [128]u8 = undefined;
		for(self.order) |index| {
			const declaration = &self.declarations[index];
			if(declaration.broken) continue;
			const value = self.values.get(declaration.name) orelse continue;
			if(declaration.name.len + 1 > nameBuffer.len) continue;
			@memcpy(nameBuffer[0..declaration.name.len], declaration.name);
			nameBuffer[declaration.name.len] = 0;
			const location = c.glGetUniformLocation(program, &nameBuffer);
			if(location < 0) continue;
			uploadValue(location, value);
		}
	}
};

fn uploadValue(location: c_int, value: expression.Value) void {
	switch(value) {
		.boolean => |v| c.glUniform1i(location, if(v) 1 else 0),
		.int => |v| c.glUniform1i(location, v),
		.float => |v| c.glUniform1f(location, v),
		.vec2 => |v| c.glUniform2f(location, v[0], v[1]),
		.vec3 => |v| c.glUniform3f(location, v[0], v[1], v[2]),
		.vec4 => |v| c.glUniform4f(location, v[0], v[1], v[2], v[3]),
		.ivec2 => |v| c.glUniform2i(location, v[0], v[1]),
		.mat4 => |v| c.glUniformMatrix4fv(location, 1, c.GL_TRUE, @ptrCast(&v)),
	}
}

/// Looks a built-in uniform up in the frame's values by name.
///
/// `uniforms.Values` field names *are* the uniform names, so this is a comptime walk over that
/// struct rather than a second table that could drift away from it.
pub fn builtinValue(frame: *const uniforms.Values, name: []const u8) ?expression.Value {
	const vec = main.vec;
	inline for(@typeInfo(uniforms.Values).@"struct".fields) |field| {
		if(std.mem.eql(u8, field.name, name)) {
			const value = @field(frame, field.name);
			return switch(field.type) {
				f32 => expression.Value{.float = value},
				// Iris declares twelve of its uniforms as `bool` (`uniform1b` in `CommonUniforms`
				// and `IrisExclusiveUniforms`), and this language types them so: Bliss writes
				// `if(is_hurt, 0.0, Currenthealth)`, where an int condition is a `TypeMismatch`
				// that took its whole health chain down (`ts_1788587576723089700.log`). They stay
				// `i32` in `Values` because `glUniform1i` is how a GLSL `bool` is set.
				i32 => if(isBooleanUniform(field.name)) expression.Value{.boolean = value != 0} else expression.Value{.int = value},
				vec.Vec2f => expression.Value{.vec2 = value},
				vec.Vec3f => expression.Value{.vec3 = value},
				vec.Vec4f => expression.Value{.vec4 = value},
				vec.Vec2i => expression.Value{.ivec2 = value},
				vec.Mat4f => expression.Value{.mat4 = value},
				else => null,
			};
		}
	}
	return null;
}

/// The uniforms Iris uploads with `uniform1b`, and so the ones this language reads as booleans:
/// `CommonUniforms.java` and `IrisExclusiveUniforms.java`, every `uniform1b(` call in the 1.7.3
/// tree. `Values` keeps them as `i32` for the GL upload.
pub const booleanUniforms = [_][]const u8{
	"hideGUI",     "isRightHanded", "is_sneaking",       "is_sprinting", "is_hurt",    "is_invisible",
	"is_burning",  "is_on_ground",  "firstPersonCamera", "isSpectator",  "hasCeiling", "hasSkylight",
};

fn isBooleanUniform(name: []const u8) bool {
	for(booleanUniforms) |candidate| {
		if(std.mem.eql(u8, candidate, name)) return true;
	}
	return false;
}

/// Parses `uniform.<type>.<name>` and `variable.<type>.<name>` entries.
///
/// `variable.` and `uniform.` are treated identically, because Iris's distinction between them is
/// dead code - what decides whether a value reaches the GPU is whether a linked program declares
/// a matching uniform, not which keyword introduced it.
pub fn parseDeclarations(allocator: NeverFailingAllocator, properties: *const pack.Properties) []Declaration {
	var found = List(Declaration).init(allocator);

	var iterator = properties.entries.iterator();
	while(iterator.next()) |entry| {
		const key = entry.key_ptr.*;
		const rest = if(std.mem.startsWith(u8, key, "uniform."))
			key["uniform.".len..]
		else if(std.mem.startsWith(u8, key, "variable."))
			key["variable.".len..]
		else
			continue;

		const dot = std.mem.indexOfScalar(u8, rest, '.') orelse {
			std.log.warn("irisbridge: malformed custom uniform key '{s}'", .{key});
			continue;
		};
		const typeText = rest[0..dot];
		const name = rest[dot + 1 ..];
		// A name may not itself contain a dot; Iris requires exactly two parts after the prefix.
		if(std.mem.indexOfScalar(u8, name, '.') != null) {
			std.log.warn("irisbridge: custom uniform name '{s}' contains a dot", .{name});
			continue;
		}
		const declaredType = expression.parseDeclaredType(typeText) orelse {
			std.log.warn("irisbridge: ignoring invalid uniform type '{s}' of '{s}'", .{typeText, name});
			continue;
		};

		found.append(.{
			.name = allocator.dupe(u8, name),
			.declaredType = declaredType,
			// BSL writes `uniform.float.sandStorm = 0.0;` - a C habit the language has no use for.
			// Iris takes it, so the trailing semicolon is not the pack's problem to fix.
			.source = allocator.dupe(u8, std.mem.trimEnd(u8, entry.value_ptr.*, "; \t")),
		});
	}
	return found.toOwnedSlice();
}

/// Parses every declaration, resolves the dependency order, and drops what cannot work.
pub fn build(allocator: NeverFailingAllocator, properties: *const pack.Properties) Set {
	const declarations = parseDeclarations(allocator, properties);

	var parsed: usize = 0;
	for(declarations) |*declaration| {
		declaration.tree = expression.parse(allocator, declaration.source) catch |err| {
			std.log.warn("irisbridge: failed to parse custom uniform '{s}' ({s}): {s}", .{
				declaration.name, @errorName(err), declaration.source,
			});
			declaration.broken = true;
			continue;
		};
		parsed += 1;
	}

	const order = resolveOrder(allocator, declarations);

	std.log.info("irisbridge: {} custom uniforms declared, {} parsed, {} evaluable", .{
		declarations.len, parsed, order.len,
	});

	return .{
		.declarations = declarations,
		.order = order,
		.evaluator = .{
			.environment = undefined,
			.allocator = allocator,
		},
		.allocator = allocator,
	};
}

/// Kahn topological sort over the references between declarations.
///
/// Anything left over is either in a cycle or depends on something broken; both are dropped with a
/// diagnostic rather than being evaluated in an arbitrary order, since a stale or partially
/// evaluated chain produces wrong numbers instead of missing ones.
fn resolveOrder(allocator: NeverFailingAllocator, declarations: []Declaration) []u32 {
	var order = List(u32).init(allocator);
	var emitted = allocator.alloc(bool, declarations.len);
	defer allocator.free(emitted);
	@memset(emitted, false);

	var names = List([]const u8).init(allocator);
	defer names.deinit();

	var progress = true;
	while(progress) {
		progress = false;
		for(declarations, 0..) |*declaration, index| {
			if(emitted[index] or declaration.broken) continue;
			const tree = declaration.tree orelse continue;

			names.clearRetainingCapacity();
			expression.collectVariables(tree, &names);

			var ready = true;
			for(names.items) |referenced| {
				// A reference to another declaration must already be emitted; anything else is
				// assumed to be a built-in and checked at evaluation time.
				for(declarations, 0..) |*other, otherIndex| {
					if(otherIndex == index) continue;
					if(!std.mem.eql(u8, other.name, referenced)) continue;
					if(other.broken) {
						declaration.broken = true;
						std.log.warn("irisbridge: custom uniform '{s}' dropped: depends on broken '{s}'", .{declaration.name, other.name});
					}
					if(!emitted[otherIndex]) ready = false;
					break;
				}
				// A self-reference can never become ready, and would otherwise spin forever.
				if(std.mem.eql(u8, declaration.name, referenced)) {
					declaration.broken = true;
					std.log.warn("irisbridge: custom uniform '{s}' dropped: references itself", .{declaration.name});
				}
			}
			if(declaration.broken) {
				progress = true;
				continue;
			}
			if(!ready) continue;

			emitted[index] = true;
			order.append(@intCast(index));
			progress = true;
		}
	}

	for(declarations, 0..) |*declaration, index| {
		if(emitted[index] or declaration.broken) continue;
		declaration.broken = true;
		std.log.warn("irisbridge: custom uniform '{s}' dropped: circular or unresolvable dependency", .{declaration.name});
	}

	return order.toOwnedSlice();
}

comptime {
	// Analysed eagerly so drift against `uniforms.Values` or the GL bindings surfaces at build
	// time rather than on the first frame with a pack loaded.
	_ = &build;
	_ = &Set.evaluate;
	_ = &Set.upload;
	_ = &builtinValue;
}
