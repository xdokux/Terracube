//! The `shaders.properties` custom uniform expression language.
//!
//! Packs declare uniforms as expressions that the loader evaluates every frame:
//!
//!     uniform.vec2.viewSize  = vec2(viewWidth, viewHeight)
//!     uniform.float.frameR1  = frac(0.5 + frameCounter / 1.618033988749894)
//!     variable.bool.isCloudSunlit = (worldTime>23000 || worldTime<12900)
//!
//! Without this, those uniforms read zero - and packs divide by them. Nostalgia divides by
//! `viewSize`, so the whole screen becomes NaN and saturates to white. That is what this fixes.
//!
//! Ported from the behaviour of Iris's vendored StarEval engine (`kroppeb/stareval/`) plus Iris's
//! operator and function tables, cross-checked against the Nostalgia corpus. `CUSTOM_UNIFORM_SPEC.md`
//! in the mod root records the derivation, the citations, and the parts that were *not* verifiable
//! from source alone.
//!
//! Three things here are counterintuitive and are not mistakes:
//!
//! 1. The tokenizer is position-sensitive. `.` after something accessible is a member access;
//!    otherwise it may begin a number. `gbufferModelViewInverse.0.0` is two accessors, while
//!    `shadowModelViewInverse.2.0 * 1.0` is two accessors *and then* a float literal. A
//!    conventional greedy-float lexer cannot read this language.
//! 2. `&&` and `||` share one precedence level, as do all six comparisons. `a || b && c`
//!    parses as `(a || b) && c`. Iris has a checked-in fixture asserting this.
//! 3. Matrix access yields a column. Cubyz's `Mat4f` is row-major and uploaded with
//!    `GL_TRUE`, so a column is `{rows[0][i], rows[1][i], rows[2][i], rows[3][i]}`. Reading
//!    `rows[i]` instead would silently transpose every direction a pack derives from
//!    `gbufferModelViewInverse` - wrong sun and shadow directions, no error message.
//!
//! Deliberate divergences from Iris, each because bug-compatibility would be a trap rather than a
//! feature: `min`/`max` with 3+ arguments compute correctly here (Iris ignores everything after
//! the second); a dependency cycle drops the cyclic group rather than disabling the whole pack;
//! there is no `ivecN`/`bvecN` family, which is unreachable in Iris anyway.

const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const List = main.ListManaged;
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec2f = vec.Vec2f;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;

// MARK: values

pub const Type = enum {boolean, int, float, vec2, vec3, vec4, ivec2, mat4};

pub const Value = union(Type) {
	boolean: bool,
	int: i32,
	float: f32,
	vec2: Vec2f,
	vec3: Vec3f,
	vec4: Vec4f,
	ivec2: vec.Vec2i,
	mat4: Mat4f,

	/// The language's only implicit conversion. Everything else is a type error.
	pub fn asFloat(self: Value) ?f32 {
		return switch(self) {
			.float => |value| value,
			.int => |value| @floatFromInt(value),
			else => null,
		};
	}
};

/// Column `index` of a matrix, in the sense GLSL means it.
///
/// Cubyz stores rows and uploads transposed, so the column is a gather across rows. This is the
/// single most consequential line in the file: getting it backwards produces plausible-looking
/// output with every direction vector silently transposed.
pub fn matrixColumn(matrix: Mat4f, index: usize) Vec4f {
	return .{
		lane(matrix.rows[0], index),
		lane(matrix.rows[1], index),
		lane(matrix.rows[2], index),
		lane(matrix.rows[3], index),
	};
}

/// Reads one lane of a SIMD vector by a runtime index.
///
/// Zig only permits comptime-known vector indices, and every index here comes from parsed source,
/// so the dispatch is unavoidable rather than clumsy.
fn lane(v: anytype, index: usize) f32 {
	const length = @typeInfo(@TypeOf(v)).vector.len;
	inline for(0..length) |i| {
		if(i == index) return v[i];
	}
	return 0;
}

// MARK: tokenizer

pub const Token = struct {
	kind: Kind,
	text: []const u8,

	pub const Kind = enum {identifier, number, accessor, operator, openParen, closeParen, comma};
};

pub const ParseError = error{UnexpectedCharacter, UnexpectedToken, UnbalancedParens, EmptyExpression};

/// True when a `.` following this token means member access rather than the start of a number.
///
/// Iris restricts access to identifiers and to other accesses - deliberately, so `vec3(1,2,3).x`
/// and `(a+b).x` are parse errors. Reproducing the restriction is what makes the `.0.0` rule
/// unambiguous.
fn isAccessible(previous: ?Token) bool {
	const token = previous orelse return false;
	return token.kind == .identifier or token.kind == .accessor;
}

fn isIdentifierStart(c: u8) bool {
	return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentifierPart(c: u8) bool {
	return std.ascii.isAlphanumeric(c) or c == '_';
}

/// Number characters per Iris: digits, `.`, and letters - but not signs, which is why `1e-3`
/// cannot be written in this language at all.
fn isNumberPart(c: u8) bool {
	return std.ascii.isAlphanumeric(c) or c == '.';
}

pub fn tokenize(allocator: NeverFailingAllocator, source: []const u8) ParseError![]Token {
	var tokens = List(Token).init(allocator);
	errdefer tokens.deinit();

	var i: usize = 0;
	while(i < source.len) {
		while(i < source.len and std.ascii.isWhitespace(source[i])) i += 1;
		if(i >= source.len) break;

		const previous: ?Token = if(tokens.items.len == 0) null else tokens.items[tokens.items.len - 1];
		const c = source[i];

		if(isIdentifierStart(c)) {
			const start = i;
			while(i < source.len and isIdentifierPart(source[i])) i += 1;
			tokens.append(.{.kind = .identifier, .text = source[start..i]});
			continue;
		}

		// Member access is tested *before* numbers, which is the whole trick.
		if(c == '.' and isAccessible(previous)) {
			i += 1;
			while(i < source.len and std.ascii.isWhitespace(source[i])) i += 1;
			const start = i;
			// Accessor characters exclude `.`, so `.2.0` is two accessors rather than one.
			while(i < source.len and isIdentifierPart(source[i])) i += 1;
			if(i == start) return error.UnexpectedCharacter;
			tokens.append(.{.kind = .accessor, .text = source[start..i]});
			continue;
		}

		if(std.ascii.isDigit(c) or c == '.') {
			const start = i;
			while(i < source.len and isNumberPart(source[i])) i += 1;
			tokens.append(.{.kind = .number, .text = source[start..i]});
			continue;
		}

		if(c == '(') {
			i += 1;
			tokens.append(.{.kind = .openParen, .text = source[i - 1 .. i]});
			continue;
		}
		if(c == ')') {
			i += 1;
			tokens.append(.{.kind = .closeParen, .text = source[i - 1 .. i]});
			continue;
		}
		if(c == ',') {
			i += 1;
			tokens.append(.{.kind = .comma, .text = source[i - 1 .. i]});
			continue;
		}

		const two: []const u8 = if(i + 1 < source.len) source[i .. i + 2] else source[i .. i + 1];
		const pairs = [_][]const u8{"==", "!=", "<=", ">=", "&&", "||"};
		var matched = false;
		for(pairs) |pair| {
			if(std.mem.eql(u8, two, pair)) {
				tokens.append(.{.kind = .operator, .text = source[i .. i + 2]});
				i += 2;
				matched = true;
				break;
			}
		}
		if(matched) continue;

		switch(c) {
			// A lone `&` or `|` is a hard error in Iris, not a bitwise operator.
			'&', '|' => return error.UnexpectedCharacter,
			'+', '-', '*', '/', '%', '<', '>', '!' => {
				tokens.append(.{.kind = .operator, .text = source[i .. i + 1]});
				i += 1;
			},
			else => return error.UnexpectedCharacter,
		}
	}
	return tokens.toOwnedSlice();
}

/// Decodes a number token the way Iris does: integer first (with C-style `0`/`0x`/`0b` prefixes),
/// falling back to float.
///
/// The fallback is load-bearing rather than defensive: `0.5` fails the octal parse and only
/// becomes a float because of it.
pub fn decodeNumber(text: []const u8) ?Value {
	if(text.len >= 2 and text[0] == '0') {
		const parsed: ?i32 = switch(text[1]) {
			'b', 'B' => std.fmt.parseInt(i32, text[2..], 2) catch null,
			'x', 'X' => std.fmt.parseInt(i32, text[2..], 16) catch null,
			else => std.fmt.parseInt(i32, text[1..], 8) catch null,
		};
		if(parsed) |value| return .{.int = value};
	} else if(std.fmt.parseInt(i32, text, 10) catch null) |value| {
		return .{.int = value};
	}
	if(std.fmt.parseFloat(f32, text) catch null) |value| return .{.float = value};
	return null;
}

// MARK: syntax tree

pub const Node = union(enum) {
	constant: Value,
	variable: []const u8,
	access: struct {base: u32, name: []const u8},
	call: struct {name: []const u8, first: u32, count: u32},
};

/// Nodes and call arguments in flat arrays, so an expression is copyable and needs no per-node
/// allocation.
pub const Tree = struct {
	nodes: []Node,
	arguments: []u32,
	root: u32,
	/// Distinguishes this tree from every other one parsed in the process.
	///
	/// `parse` builds a fresh node list per declaration, so node indices restart at 0 for every
	/// one of them. A single `Evaluator` is shared across a pack's whole declaration set, so
	/// keying `smooth()` state by node index alone makes two calls that happen to land at the same
	/// index in their own trees share one accumulator. Iris hands each *resolution* a fresh
	/// `SmoothFloat` (`IrisFunctions.java`); this is how that identity is reproduced here.
	id: u32 = 0,

	pub fn deinit(self: Tree, allocator: NeverFailingAllocator) void {
		allocator.free(self.nodes);
		allocator.free(self.arguments);
	}
};

/// Lower binds tighter, matching Iris's `priority`. Every binary operator is left-associative.
fn precedence(op: []const u8) ?u8 {
	if(op.len == 1) {
		return switch(op[0]) {
			'*', '/', '%' => 0,
			'+', '-' => 1,
			'<', '>' => 2,
			else => null,
		};
	}
	if(std.mem.eql(u8, op, "==") or std.mem.eql(u8, op, "!=") or
		std.mem.eql(u8, op, "<=") or std.mem.eql(u8, op, ">=")) return 2;
	// Both logical operators share one level; `a || b && c` is `(a || b) && c`.
	if(std.mem.eql(u8, op, "&&") or std.mem.eql(u8, op, "||")) return 3;
	return null;
}

fn binaryFunction(op: []const u8) []const u8 {
	if(op.len == 1) {
		return switch(op[0]) {
			'*' => "multiply",
			'/' => "divide",
			'%' => "remainder",
			'+' => "add",
			'-' => "subtract",
			'<' => "lessThan",
			'>' => "moreThan",
			else => unreachable,
		};
	}
	if(std.mem.eql(u8, op, "==")) return "equals";
	if(std.mem.eql(u8, op, "!=")) return "notEquals";
	if(std.mem.eql(u8, op, "<=")) return "lessThanOrEquals";
	if(std.mem.eql(u8, op, ">=")) return "moreThanOrEquals";
	if(std.mem.eql(u8, op, "&&")) return "and";
	if(std.mem.eql(u8, op, "||")) return "or";
	unreachable;
}

const Parser = struct {
	tokens: []const Token,
	index: usize = 0,
	nodes: List(Node),
	arguments: List(u32),

	fn peek(self: *Parser) ?Token {
		if(self.index >= self.tokens.len) return null;
		return self.tokens[self.index];
	}

	fn add(self: *Parser, node: Node) u32 {
		self.nodes.append(node);
		return @intCast(self.nodes.items.len - 1);
	}

	fn parseExpression(self: *Parser, minPrecedence: u8) ParseError!u32 {
		var left = try self.parseUnary();
		while(self.peek()) |token| {
			if(token.kind != .operator) break;
			const level = precedence(token.text) orelse break;
			if(level > minPrecedence) break;
			self.index += 1;
			// Left-associative: the right operand may only bind strictly tighter.
			const right = try self.parseExpression(level -| 1);
			const first: u32 = @intCast(self.arguments.items.len);
			self.arguments.append(left);
			self.arguments.append(right);
			left = self.add(.{.call = .{.name = binaryFunction(token.text), .first = first, .count = 2}});
		}
		return left;
	}

	fn parseUnary(self: *Parser) ParseError!u32 {
		const token = self.peek() orelse return error.EmptyExpression;
		if(token.kind == .operator and (token.text[0] == '-' or token.text[0] == '!') and token.text.len == 1) {
			self.index += 1;
			const operand = try self.parseUnary();
			const first: u32 = @intCast(self.arguments.items.len);
			self.arguments.append(operand);
			return self.add(.{.call = .{
				.name = if(token.text[0] == '-') "negate" else "not",
				.first = first,
				.count = 1,
			}});
		}
		return self.parsePostfix();
	}

	fn parsePostfix(self: *Parser) ParseError!u32 {
		var node = try self.parsePrimary();
		// Access binds only to identifiers and other accesses, so it is applied here rather than
		// as a general postfix over any primary.
		while(self.peek()) |token| {
			if(token.kind != .accessor) break;
			self.index += 1;
			node = self.add(.{.access = .{.base = node, .name = token.text}});
		}
		return node;
	}

	fn parsePrimary(self: *Parser) ParseError!u32 {
		const token = self.peek() orelse return error.EmptyExpression;
		switch(token.kind) {
			.number => {
				self.index += 1;
				const value = decodeNumber(token.text) orelse return error.UnexpectedToken;
				return self.add(.{.constant = value});
			},
			.openParen => {
				self.index += 1;
				const inner = try self.parseExpression(3);
				const closing = self.peek() orelse return error.UnbalancedParens;
				if(closing.kind != .closeParen) return error.UnbalancedParens;
				self.index += 1;
				return inner;
			},
			.identifier => {
				self.index += 1;
				const next = self.peek();
				if(next != null and next.?.kind == .openParen) {
					self.index += 1;
					var collected = List(u32).init(self.nodes.allocator);
					defer collected.deinit();
					while(true) {
						const inner = self.peek() orelse return error.UnbalancedParens;
						if(inner.kind == .closeParen) {
							self.index += 1;
							break;
						}
						collected.append(try self.parseExpression(3));
						const after = self.peek() orelse return error.UnbalancedParens;
						if(after.kind == .comma) {
							self.index += 1;
							continue;
						}
						if(after.kind == .closeParen) {
							self.index += 1;
							break;
						}
						return error.UnexpectedToken;
					}
					const first: u32 = @intCast(self.arguments.items.len);
					self.arguments.appendSlice(collected.items);
					return self.add(.{.call = .{
						.name = token.text,
						.first = first,
						.count = @intCast(collected.items.len),
					}});
				}
				return self.add(.{.variable = token.text});
			},
			else => return error.UnexpectedToken,
		}
	}
};

/// Handed out by `parse`, never reused. Starts at 1 so a default-constructed `Tree` is
/// distinguishable from a parsed one.
var nextTreeId: u32 = 0;

pub fn parse(allocator: NeverFailingAllocator, source: []const u8) ParseError!Tree {
	const tokens = try tokenize(allocator, source);
	defer allocator.free(tokens);
	if(tokens.len == 0) return error.EmptyExpression;

	var parser = Parser{
		.tokens = tokens,
		.nodes = List(Node).init(allocator),
		.arguments = List(u32).init(allocator),
	};
	errdefer {
		parser.nodes.deinit();
		parser.arguments.deinit();
	}

	const root = try parser.parseExpression(3);
	if(parser.index != tokens.len) return error.UnexpectedToken;

	nextTreeId += 1;
	return .{
		.nodes = parser.nodes.toOwnedSlice(),
		.arguments = parser.arguments.toOwnedSlice(),
		.root = root,
		.id = nextTreeId,
	};
}

/// Names every variable an expression reads, for building the dependency graph.
pub fn collectVariables(tree: Tree, out: *List([]const u8)) void {
	for(tree.nodes) |node| {
		if(node == .variable) out.append(node.variable);
	}
}

// MARK: evaluation

pub const EvalError = error{UnknownVariable, UnknownFunction, TypeMismatch, BadArity};

/// The most arguments one call can take. Iris's ceiling: `in` is registered as a fake vararg with
/// one overload per length from 2 to 32 (`IrisFunctions.java:714`), and nothing else takes more
/// than four. The corpus reaches 19 - BSL's `isCold` names eleven biomes, Bliss's `noPuddleAreas`
/// eighteen - and an earlier limit of 8 failed both with `BadArity` before the function name was
/// even looked at.
pub const maxArguments = 32;

/// Where variable values come from during evaluation.
pub const Environment = struct {
	ptr: *anyopaque,
	lookupFn: *const fn (ptr: *anyopaque, name: []const u8) ?Value,

	pub fn lookup(self: Environment, name: []const u8) ?Value {
		return self.lookupFn(self.ptr, name);
	}
};

/// Per-call-site state for `smooth`, which is the only stateful function.
///
/// Identity is the call site, not the `id` argument - Iris hands each *resolution* a fresh
/// accumulator, so two `smooth()` calls sharing an id do not share state, and the id is never
/// read at evaluation time.
pub const SmoothState = struct {
	accumulator: f32 = 0,
	initialised: bool = false,

	/// Transcribed from Iris's `SmoothFloat.updateAndGet`.
	///
	/// The half-life is a tenth of the fade argument, so the default fade of 1 is 0.1 s rather
	/// than the 1 s the Iris documentation claims.
	pub fn update(self: *SmoothState, target: f32, fadeUp: f32, fadeDown: f32, deltaTime: f32) f32 {
		if(!self.initialised) {
			self.accumulator = target;
			self.initialised = true;
			return self.accumulator;
		}
		const fade = if(target > self.accumulator) fadeUp else fadeDown;
		if(fade == 0) {
			self.accumulator = target;
			return self.accumulator;
		}
		const halfLife = fade*0.1;
		const decay: f32 = @floatCast(1.0/(@as(f64, halfLife)/@log(2.0)));
		const smoothing: f32 = 1.0 - @exp(-decay*deltaTime);
		self.accumulator = (1 - smoothing)*self.accumulator + smoothing*target;
		return self.accumulator;
	}
};

pub const Evaluator = struct {
	environment: Environment,
	deltaTime: f32 = 0,
	/// One slot per `smooth` call site, keyed by tree identity paired with node index.
	///
	/// The node index alone is not a call site. `parse` builds a fresh node list per
	/// declaration, so indices restart at 0 for every one of them, and a single `Evaluator` is
	/// shared across a pack's whole declaration set (`customuniforms.Set.evaluator`). Keying on the
	/// index alone therefore made every `smooth()` that happened to land at the same index in its
	/// own tree share one accumulator.
	///
	/// Complementary hits it squarely: `moved = smooth(2, moving, 0, 31536000)` and
	/// `rainFactor = smooth(1, rainStrength, 3, 3)` collide. `moved`'s fadeUp of 0 is a snap
	/// rather than a fade, and `moving` is a pure binary "did the camera translate this frame" - so
	/// walking pinned the shared slot to 1.0 and `rainFactor`, which must be a hard 0 because
	/// `rainStrength` is a documented constant 0, read 0.96. The pack was told it was raining at
	/// full strength for exactly as long as the player kept moving, which replaces its light and
	/// ambient colours wholesale and averages its colour multipliers to grey.
	///
	/// The tree's node array address is its identity. Trees outlive every evaluation that reads
	/// them - `customuniforms.Set` owns both the trees and this evaluator and frees them together -
	/// so an address cannot be recycled underneath a live accumulator.
	smoothStates: std.AutoHashMapUnmanaged(u64, SmoothState) = .empty,
	allocator: NeverFailingAllocator,

	pub fn deinit(self: *Evaluator) void {
		self.smoothStates.deinit(self.allocator.allocator);
	}

	pub fn evaluate(self: *Evaluator, tree: Tree) EvalError!Value {
		return self.evaluateNode(tree, tree.root);
	}

	fn evaluateNode(self: *Evaluator, tree: Tree, index: u32) EvalError!Value {
		switch(tree.nodes[index]) {
			.constant => |value| return value,
			.variable => |name| return self.environment.lookup(name) orelse error.UnknownVariable,
			.access => |access| {
				const base = try self.evaluateNode(tree, access.base);
				return component(base, access.name) orelse error.TypeMismatch;
			},
			.call => |call| return self.evaluateCall(tree, index, call.name, tree.arguments[call.first .. call.first + call.count]),
		}
	}

	fn evaluateCall(self: *Evaluator, tree: Tree, nodeIndex: u32, name: []const u8, argumentNodes: []const u32) EvalError!Value {
		// `if` is lazy: only the taken branch is evaluated, which matters when a branch calls
		// `smooth` or `random`.
		if(std.mem.eql(u8, name, "if")) return self.evaluateIf(tree, argumentNodes);

		var buffer: [maxArguments]Value = undefined;
		if(argumentNodes.len > buffer.len) return error.BadArity;
		for(argumentNodes, 0..) |argument, i| buffer[i] = try self.evaluateNode(tree, argument);
		const args = buffer[0..argumentNodes.len];

		if(std.mem.eql(u8, name, "smooth")) return self.evaluateSmooth(tree, nodeIndex, args);
		return apply(name, args);
	}

	fn evaluateIf(self: *Evaluator, tree: Tree, argumentNodes: []const u32) EvalError!Value {
		// Valid arities are 3, 5, 7, ... - condition/value pairs plus a final else.
		if(argumentNodes.len < 3 or argumentNodes.len % 2 == 0) return error.BadArity;
		var i: usize = 0;
		while(i + 1 < argumentNodes.len - 1) : (i += 2) {
			const condition = try self.evaluateNode(tree, argumentNodes[i]);
			if(condition != .boolean) return error.TypeMismatch;
			if(condition.boolean) return self.evaluateNode(tree, argumentNodes[i + 1]);
		}
		// Evaluated once, unlike Iris, which re-evaluates it per failing condition.
		return self.evaluateNode(tree, argumentNodes[argumentNodes.len - 1]);
	}

	fn evaluateSmooth(self: *Evaluator, tree: Tree, nodeIndex: u32, args: []const Value) EvalError!Value {
		// A leading bare literal binds the `id` slot, which has higher overload priority. The id
		// is then never read: state belongs to the call site.
		const hasId = args.len == 2 or args.len == 4;
		const rest = if(hasId) args[1..] else args;
		if(rest.len == 0 or rest.len > 3) return error.BadArity;

		const target = rest[0].asFloat() orelse return error.TypeMismatch;
		const fadeUp = if(rest.len >= 2) rest[1].asFloat() orelse return error.TypeMismatch else 1.0;
		const fadeDown = if(rest.len >= 3) rest[2].asFloat() orelse return error.TypeMismatch else fadeUp;

		// The call site is (which tree, which node) - node index alone collides across
		// declarations, which is the whole bug this key exists to avoid.
		const key = (@as(u64, tree.id) << 32) | nodeIndex;
		const entry = self.smoothStates.getOrPut(self.allocator.allocator, key) catch unreachable;
		if(!entry.found_existing) entry.value_ptr.* = .{};
		return .{.float = entry.value_ptr.update(target, fadeUp, fadeDown, self.deltaTime)};
	}
};

/// Component index for an accessor name. `.0` is an exact synonym for `.x`/`.r`/`.s`.
fn componentIndex(name: []const u8) ?usize {
	if(name.len != 1) return null; // Multi-component swizzles do not exist in this language.
	return switch(name[0]) {
		'0', 'r', 'x', 's' => 0,
		'1', 'g', 'y', 't' => 1,
		'2', 'b', 'z', 'p' => 2,
		'3', 'a', 'w', 'q' => 3,
		else => null,
	};
}

fn component(base: Value, name: []const u8) ?Value {
	const index = componentIndex(name) orelse return null;
	return switch(base) {
		.vec2 => |v| if(index < 2) Value{.float = lane(v, index)} else null,
		.vec3 => |v| if(index < 3) Value{.float = lane(v, index)} else null,
		.vec4 => |v| if(index < 4) Value{.float = lane(v, index)} else null,
		.ivec2 => |v| if(index < 2) Value{.int = if(index == 0) v[0] else v[1]} else null,
		// A matrix component is a whole column, which is what makes `m.0.0` chain to a float.
		.mat4 => |m| Value{.vec4 = matrixColumn(m, index)},
		else => null,
	};
}

// MARK: function table

fn bothInt(args: []const Value) bool {
	for(args) |arg| {
		if(arg != .int) return false;
	}
	return true;
}

fn floats(args: []const Value, out: []f32) ?void {
	for(args, 0..) |arg, i| out[i] = arg.asFloat() orelse return null;
	return {};
}

/// Applies a non-lazy, non-stateful function.
///
/// Arithmetic stays in f32 to match Java's `float`, while transcendentals go through f64 because
/// Iris routes them through `java.lang.Math`, which computes in double and narrows on return.
pub fn apply(name: []const u8, args: []const Value) EvalError!Value {
	// Sized to the call limit rather than to the widest fixed arity, because `min`, `max` and `in`
	// take any count and `floats` writes one slot per argument.
	var buffer: [maxArguments]f32 = undefined;

	// Constructors.
	if(std.mem.eql(u8, name, "vec2") and args.len == 2) {
		floats(args, &buffer) orelse return error.TypeMismatch;
		return .{.vec2 = .{buffer[0], buffer[1]}};
	}
	if(std.mem.eql(u8, name, "vec3") and args.len == 3) {
		floats(args, &buffer) orelse return error.TypeMismatch;
		return .{.vec3 = .{buffer[0], buffer[1], buffer[2]}};
	}
	if(std.mem.eql(u8, name, "vec4") and args.len == 4) {
		floats(args, &buffer) orelse return error.TypeMismatch;
		return .{.vec4 = .{buffer[0], buffer[1], buffer[2], buffer[3]}};
	}

	// Logical.
	if(std.mem.eql(u8, name, "and") or std.mem.eql(u8, name, "or")) {
		if(args.len != 2) return error.BadArity;
		if(args[0] != .boolean or args[1] != .boolean) return error.TypeMismatch;
		// Not short-circuiting in Iris; both operands are already evaluated here anyway.
		return .{.boolean = if(std.mem.eql(u8, name, "and"))
			args[0].boolean and args[1].boolean
		else
			args[0].boolean or args[1].boolean};
	}
	if(std.mem.eql(u8, name, "not")) {
		if(args.len != 1) return error.BadArity;
		if(args[0] != .boolean) return error.TypeMismatch;
		return .{.boolean = !args[0].boolean};
	}

	// Comparisons. Booleans compare only for equality.
	if(std.mem.eql(u8, name, "equals") or std.mem.eql(u8, name, "notEquals")) {
		if(args.len == 2 and args[0] == .boolean and args[1] == .boolean) {
			const same = args[0].boolean == args[1].boolean;
			return .{.boolean = if(std.mem.eql(u8, name, "equals")) same else !same};
		}
	}
	if(comparisonOf(name)) |compare| {
		if(args.len == 3 and std.mem.eql(u8, name, "equals")) {
			floats(args, &buffer) orelse return error.TypeMismatch;
			return .{.boolean = @abs(buffer[0] - buffer[1]) <= buffer[2]};
		}
		if(args.len != 2) return error.BadArity;
		if(bothInt(args)) return .{.boolean = compare(@floatFromInt(args[0].int), @floatFromInt(args[1].int))};
		floats(args, &buffer) orelse return error.TypeMismatch;
		return .{.boolean = compare(buffer[0], buffer[1])};
	}

	// Arithmetic. Integer overloads exist for everything except division.
	if(arithmeticOf(name)) |arithmetic| {
		if(args.len != 2) return error.BadArity;
		if(bothInt(args) and !std.mem.eql(u8, name, "divide")) {
			return .{.int = arithmetic.integer(args[0].int, args[1].int)};
		}
		if(args[0] == .vec3 and args[1] == .vec3) {
			var result: Vec3f = undefined;
			inline for(0..3) |i| result[i] = arithmetic.real(args[0].vec3[i], args[1].vec3[i]);
			return .{.vec3 = result};
		}
		if(args[0] == .vec2 and args[1] == .vec2) {
			var result: Vec2f = undefined;
			inline for(0..2) |i| result[i] = arithmetic.real(args[0].vec2[i], args[1].vec2[i]);
			return .{.vec2 = result};
		}
		floats(args, &buffer) orelse return error.TypeMismatch;
		return .{.float = arithmetic.real(buffer[0], buffer[1])};
	}

	if(std.mem.eql(u8, name, "negate")) {
		if(args.len != 1) return error.BadArity;
		return switch(args[0]) {
			.int => |value| .{.int = -value},
			.float => |value| .{.float = -value},
			.vec2 => |value| .{.vec2 = -value},
			.vec3 => |value| .{.vec3 = -value},
			.vec4 => |value| .{.vec4 = -value},
			else => error.TypeMismatch,
		};
	}

	if(std.mem.eql(u8, name, "abs")) {
		if(args.len != 1) return error.BadArity;
		return switch(args[0]) {
			.int => |value| .{.int = @intCast(@abs(value))},
			.float => |value| .{.float = @abs(value)},
			else => error.TypeMismatch,
		};
	}

	if(std.mem.eql(u8, name, "min") or std.mem.eql(u8, name, "max")) {
		if(args.len < 2) return error.BadArity;
		// Iris ignores every argument after the second here; computing correctly instead.
		if(bothInt(args)) {
			var result = args[0].int;
			for(args[1..]) |arg| {
				result = if(std.mem.eql(u8, name, "min")) @min(result, arg.int) else @max(result, arg.int);
			}
			return .{.int = result};
		}
		floats(args, &buffer) orelse return error.TypeMismatch;
		var result = buffer[0];
		for(buffer[1..args.len]) |value| {
			result = if(std.mem.eql(u8, name, "min")) @min(result, value) else @max(result, value);
		}
		return .{.float = result};
	}

	if(std.mem.eql(u8, name, "clamp")) {
		if(args.len != 3) return error.BadArity;
		if(bothInt(args)) return .{.int = @max(args[1].int, @min(args[2].int, args[0].int))};
		floats(args, &buffer) orelse return error.TypeMismatch;
		// max(min, min(max, value)) - if the bounds are inverted, the minimum wins.
		return .{.float = @max(buffer[1], @min(buffer[2], buffer[0]))};
	}

	if(std.mem.eql(u8, name, "between")) {
		if(args.len != 3) return error.BadArity;
		floats(args, &buffer) orelse return error.TypeMismatch;
		return .{.boolean = buffer[0] >= buffer[1] and buffer[0] <= buffer[2]};
	}

	// `in(x, a, b, ...)` is membership: true when the first argument equals any later one. This is
	// how every biome test in the corpus is written - `in(biome, BIOME_SWAMP, BIOME_MANGROVE_SWAMP)`
	// - and without it BSL, Solas and Complementary dropped the whole `is*`/`in*` family with
	// `UnknownFunction`. Iris registers it over floats only, ints arriving through the implicit
	// cast and comparing with `==` on the float (`IrisFunctions.java:718`); done the same way here,
	// which is exact for the small ids packs pass.
	if(std.mem.eql(u8, name, "in")) {
		if(args.len < 2) return error.BadArity;
		floats(args, &buffer) orelse return error.TypeMismatch;
		for(buffer[1..args.len]) |candidate| {
			if(candidate == buffer[0]) return .{.boolean = true};
		}
		return .{.boolean = false};
	}

	if(std.mem.eql(u8, name, "mix")) {
		if(args.len != 3) return error.BadArity;
		floats(args, &buffer) orelse return error.TypeMismatch;
		return .{.float = buffer[0] + (buffer[1] - buffer[0])*buffer[2]};
	}

	// `edge` is GLSL's `step`; there is no function actually named `step`.
	if(std.mem.eql(u8, name, "edge")) {
		if(args.len != 2) return error.BadArity;
		floats(args, &buffer) orelse return error.TypeMismatch;
		return .{.float = if(buffer[1] < buffer[0]) 0 else 1};
	}

	// `fmod` is GLSL's `mod` (sign follows the divisor), unlike `%`.
	if(std.mem.eql(u8, name, "fmod")) {
		if(args.len != 2) return error.BadArity;
		floats(args, &buffer) orelse return error.TypeMismatch;
		return .{.float = buffer[0] - buffer[1]*@floor(buffer[0]/buffer[1])};
	}

	if(unaryRealOf(name)) |function| {
		if(args.len != 1) return error.BadArity;
		const value = args[0].asFloat() orelse return error.TypeMismatch;
		return .{.float = function(value)};
	}

	if(std.mem.eql(u8, name, "toFloat")) {
		if(args.len != 1) return error.BadArity;
		return .{.float = args[0].asFloat() orelse return error.TypeMismatch};
	}
	if(std.mem.eql(u8, name, "toInt")) {
		if(args.len != 1) return error.BadArity;
		const value = args[0].asFloat() orelse return error.TypeMismatch;
		return .{.int = @intFromFloat(@trunc(value))}; // truncation toward zero, not rounding
	}

	if(std.mem.eql(u8, name, "pow") or std.mem.eql(u8, name, "atan2") or std.mem.eql(u8, name, "log")) {
		if(args.len == 2) {
			floats(args, &buffer) orelse return error.TypeMismatch;
			const a: f64 = buffer[0];
			const b: f64 = buffer[1];
			if(std.mem.eql(u8, name, "pow")) return .{.float = @floatCast(std.math.pow(f64, a, b))};
			if(std.mem.eql(u8, name, "atan2")) return .{.float = @floatCast(std.math.atan2(a, b))};
			// Two-argument log takes the base FIRST.
			return .{.float = @floatCast(@log(b)/@log(a))};
		}
	}

	return error.UnknownFunction;
}

fn comparisonOf(name: []const u8) ?*const fn (f32, f32) bool {
	const table = .{
		.{"equals", struct {
			fn f(a: f32, b: f32) bool {
				return a == b;
			}
		}.f},
		.{"notEquals", struct {
			fn f(a: f32, b: f32) bool {
				return a != b;
			}
		}.f},
		.{"lessThan", struct {
			fn f(a: f32, b: f32) bool {
				return a < b;
			}
		}.f},
		.{"moreThan", struct {
			fn f(a: f32, b: f32) bool {
				return a > b;
			}
		}.f},
		.{"lessThanOrEquals", struct {
			fn f(a: f32, b: f32) bool {
				return a <= b;
			}
		}.f},
		.{"moreThanOrEquals", struct {
			fn f(a: f32, b: f32) bool {
				return a >= b;
			}
		}.f},
	};
	inline for(table) |entry| {
		if(std.mem.eql(u8, name, entry[0])) return entry[1];
	}
	return null;
}

const Arithmetic = struct {
	real: *const fn (f32, f32) f32,
	integer: *const fn (i32, i32) i32,
};

fn arithmeticOf(name: []const u8) ?Arithmetic {
	const table = .{
		.{"add", struct {
			fn r(a: f32, b: f32) f32 {
				return a + b;
			}
			fn i(a: i32, b: i32) i32 {
				return a +% b;
			}
		}},
		.{"subtract", struct {
			fn r(a: f32, b: f32) f32 {
				return a - b;
			}
			fn i(a: i32, b: i32) i32 {
				return a -% b;
			}
		}},
		.{"multiply", struct {
			fn r(a: f32, b: f32) f32 {
				return a*b;
			}
			fn i(a: i32, b: i32) i32 {
				return a *% b;
			}
		}},
		.{"divide", struct {
			fn r(a: f32, b: f32) f32 {
				return a/b;
			}
			fn i(a: i32, b: i32) i32 {
				return @divTrunc(a, b);
			}
		}},
		.{"remainder", struct {
			// Java's `%`: the sign follows the dividend, unlike GLSL's `mod`.
			fn r(a: f32, b: f32) f32 {
				return @rem(a, b);
			}
			fn i(a: i32, b: i32) i32 {
				return @rem(a, b);
			}
		}},
	};
	inline for(table) |entry| {
		if(std.mem.eql(u8, name, entry[0])) return .{.real = entry[1].r, .integer = entry[1].i};
	}
	return null;
}

fn unaryRealOf(name: []const u8) ?*const fn (f32) f32 {
	const table = .{
		.{"frac", struct {
			// GLSL `fract`: frac(-0.25) == 0.75.
			fn f(a: f32) f32 {
				return a - @floor(a);
			}
		}.f},
		.{"floor", struct {
			fn f(a: f32) f32 {
				return @floor(a);
			}
		}.f},
		.{"ceil", struct {
			fn f(a: f32) f32 {
				return @ceil(a);
			}
		}.f},
		.{"sqrt", struct {
			fn f(a: f32) f32 {
				return @floatCast(@sqrt(@as(f64, a)));
			}
		}.f},
		.{"sin", struct {
			fn f(a: f32) f32 {
				return @floatCast(@sin(@as(f64, a)));
			}
		}.f},
		.{"cos", struct {
			fn f(a: f32) f32 {
				return @floatCast(@cos(@as(f64, a)));
			}
		}.f},
		.{"tan", struct {
			fn f(a: f32) f32 {
				return @floatCast(@tan(@as(f64, a)));
			}
		}.f},
		.{"asin", struct {
			fn f(a: f32) f32 {
				return @floatCast(std.math.asin(@as(f64, a)));
			}
		}.f},
		.{"acos", struct {
			fn f(a: f32) f32 {
				return @floatCast(std.math.acos(@as(f64, a)));
			}
		}.f},
		.{"atan", struct {
			fn f(a: f32) f32 {
				return @floatCast(std.math.atan(@as(f64, a)));
			}
		}.f},
		.{"exp", struct {
			fn f(a: f32) f32 {
				return @floatCast(@exp(@as(f64, a)));
			}
		}.f},
		.{"log", struct {
			fn f(a: f32) f32 {
				return @floatCast(@log(@as(f64, a)));
			}
		}.f},
		.{"exp2", struct {
			fn f(a: f32) f32 {
				return @floatCast(@exp2(@as(f64, a)));
			}
		}.f},
		.{"log2", struct {
			fn f(a: f32) f32 {
				return @floatCast(@log2(@as(f64, a)));
			}
		}.f},
		.{"sign", struct {
			fn f(a: f32) f32 {
				return std.math.sign(a);
			}
		}.f},
		.{"signum", struct {
			fn f(a: f32) f32 {
				return std.math.sign(a);
			}
		}.f},
		.{"torad", struct {
			fn f(a: f32) f32 {
				return @floatCast(@as(f64, a)*std.math.pi/180.0);
			}
		}.f},
		.{"radians", struct {
			fn f(a: f32) f32 {
				return @floatCast(@as(f64, a)*std.math.pi/180.0);
			}
		}.f},
		.{"todeg", struct {
			fn f(a: f32) f32 {
				return @floatCast(@as(f64, a)*180.0/std.math.pi);
			}
		}.f},
		.{"degrees", struct {
			fn f(a: f32) f32 {
				return @floatCast(@as(f64, a)*180.0/std.math.pi);
			}
		}.f},
	};
	inline for(table) |entry| {
		if(std.mem.eql(u8, name, entry[0])) return entry[1];
	}
	return null;
}

pub fn parseDeclaredType(text: []const u8) ?Type {
	if(std.mem.eql(u8, text, "bool")) return .boolean;
	if(std.mem.eql(u8, text, "int")) return .int;
	if(std.mem.eql(u8, text, "float")) return .float;
	if(std.mem.eql(u8, text, "vec2")) return .vec2;
	if(std.mem.eql(u8, text, "vec3")) return .vec3;
	if(std.mem.eql(u8, text, "vec4")) return .vec4;
	return null;
}

/// Converts an evaluated value to the type its declaration promised.
///
/// The declared type is a *contract with the shader*, not a hint. Uploading dispatches on the
/// value's own type, so a mismatch means calling `glUniform1f` against a `uniform int` - which GL
/// rejects with `GL_INVALID_OPERATION: Wrong component type or count`, leaving the uniform at
/// whatever it held before.
///
/// That is not hypothetical. Sildur's declares
///
///     uniform.int.framemod8=fmod(frameCounter, 8)
///
/// and `fmod` returns a float. Every program reading `framemod8` - for a pack using it to rotate
/// temporal sample patterns, nearly all of them - got a rejected upload every frame and a value
/// permanently stuck at 0, which is 20k GL errors a minute and a visibly broken image.
///
/// An earlier version converted int to float but not the reverse, reasoning that "nothing in the
/// language returns int from a float, so a float in an `int` slot is a pack error". The premise is
/// right and the conclusion does not follow: packs write this, Iris accepts it, and refusing the
/// conversion breaks the pack rather than the declaration.
pub fn coerceTo(value: Value, declared: Type) Value {
	return switch(declared) {
		.float => switch(value) {
			.int => |v| .{.float = @floatFromInt(v)},
			.boolean => |v| .{.float = if(v) 1 else 0},
			else => value,
		},
		// Truncation toward zero, matching a C-style cast. `fmod(frameCounter, 8)` is already
		// integral, so this is exact for the case that motivates it.
		.int => switch(value) {
			.float => |v| .{.int = @intFromFloat(@trunc(v))},
			.boolean => |v| .{.int = if(v) 1 else 0},
			else => value,
		},
		.boolean => switch(value) {
			.float => |v| .{.boolean = v != 0},
			.int => |v| .{.boolean = v != 0},
			else => value,
		},
		// The vector and matrix types have no meaningful widening, and a mismatch there is a pack
		// error this cannot paper over.
		else => value,
	};
}

// MARK: tests

const testing = std.testing;
const testingAllocator = main.heap.testingAllocator;

/// A fixed environment standing in for one frame's uniform values.
const TestEnvironment = struct {
	values: std.StringHashMapUnmanaged(Value) = .empty,

	fn lookupImpl(ptr: *anyopaque, name: []const u8) ?Value {
		const self: *TestEnvironment = @ptrCast(@alignCast(ptr));
		return self.values.get(name);
	}

	fn env(self: *TestEnvironment) Environment {
		return .{.ptr = self, .lookupFn = &lookupImpl};
	}

	fn set(self: *TestEnvironment, name: []const u8, value: Value) void {
		self.values.put(testingAllocator.allocator, name, value) catch unreachable;
	}

	fn deinit(self: *TestEnvironment) void {
		self.values.deinit(testingAllocator.allocator);
	}
};

fn evalWith(source: []const u8, environment: *TestEnvironment) !Value {
	const tree = try parse(testingAllocator, source);
	defer tree.deinit(testingAllocator);
	var evaluator = Evaluator{.environment = environment.env(), .allocator = testingAllocator};
	defer evaluator.deinit();
	return evaluator.evaluate(tree);
}

fn evalFloat(source: []const u8, environment: *TestEnvironment) !f32 {
	const value = try evalWith(source, environment);
	return value.asFloat() orelse error.TypeMismatch;
}

test "T1: vec3 of literals" {
	var e = TestEnvironment{};
	defer e.deinit();
	const value = try evalWith("vec3(0.0, 1.0, 0.0)", &e);
	try testing.expectEqual(Vec3f{0, 1, 0}, value.vec3);
}

test "T2: two-argument min does not take a vararg path" {
	var e = TestEnvironment{};
	defer e.deinit();
	e.set("viewHeight", .{.float = 1440});
	try testing.expectEqual(@as(f32, 1080), try evalFloat("min(1080.0, viewHeight)", &e));
	e.set("viewHeight", .{.float = 720});
	try testing.expectEqual(@as(f32, 720), try evalFloat("min(1080.0, viewHeight)", &e));
}

test "T3: 33-digit literal, int widened by divide, frac" {
	var e = TestEnvironment{};
	defer e.deinit();
	const source = "frac(0.5 + frameCounter / 1.61803398874989484820458683436563)";
	e.set("frameCounter", .{.int = 0});
	try testing.expectApproxEqAbs(@as(f32, 0.5), try evalFloat(source, &e), 1e-6);
	e.set("frameCounter", .{.int = 1});
	try testing.expectApproxEqAbs(@as(f32, 0.118034), try evalFloat(source, &e), 1e-4);
}

test "T5: precedence puts remainder before addition" {
	var e = TestEnvironment{};
	defer e.deinit();
	e.set("worldDay", .{.int = 100});
	e.set("worldTime", .{.int = 6000});
	// (worldDay % 48) + (worldTime / 24000.0) = 4 + 0.25
	try testing.expectApproxEqAbs(@as(f32, 4.25), try evalFloat("worldDay % 48 + worldTime / 24000.0", &e), 1e-6);
}

test "T6: member access on a vec3 input, nested grouping, no whitespace" {
	var e = TestEnvironment{};
	defer e.deinit();
	e.set("upPosition", .{.vec3 = .{0, 1, 0}});
	try testing.expectApproxEqAbs(@as(f32, 1.0), try evalFloat(
		"1.0 / sqrt((upPosition.x*upPosition.x) + (upPosition.y*upPosition.y) + (upPosition.z*upPosition.z))", &e), 1e-6);
}

test "T7: the .0.0 matrix accessor, and it reads a column" {
	var e = TestEnvironment{};
	defer e.deinit();
	// Deliberately non-symmetric, so a row/column mix-up changes the answer.
	e.set("gbufferModelViewInverse", .{.mat4 = Mat4f{.rows = .{
		Vec4f{1, 2, 3, 4},
		Vec4f{5, 6, 7, 8},
		Vec4f{9, 10, 11, 12},
		Vec4f{13, 14, 15, 16},
	}}});
	const source = "gbufferModelViewInverse.0.0 * sunPosition.x + gbufferModelViewInverse.1.0 * sunPosition.y + gbufferModelViewInverse.2.0 * sunPosition.z";

	// Column 0 is {1,5,9,13}, so `.0.0` is 1.
	e.set("sunPosition", .{.vec3 = .{1, 0, 0}});
	try testing.expectApproxEqAbs(@as(f32, 1.0), try evalFloat(source, &e), 1e-6);

	// Along y it must pick column 1's x, which is 2. Reading rows instead would give 5 - this is
	// the assertion that catches the transpose bug.
	e.set("sunPosition", .{.vec3 = .{0, 1, 0}});
	try testing.expectApproxEqAbs(@as(f32, 2.0), try evalFloat(source, &e), 1e-6);
}

test "T7b: photon's sun_dir chain recovers the world sun from a real view matrix" {
	// T7 above uses a synthetic matrix, which pins the accessor's convention but not whether the
	// whole chain a pack writes recovers a direction. This is photon's `shaders.properties`,
	// lines 423-432, evaluated on the matrices `uniforms.capture` really hands the language: the
	// inverse of `matrix.gbufferModelView`, a similarity transform with the Z-up change of basis
	// folded in, and a `sunPosition` placed by `matrix.celestialPosition` through the same view.
	// The sun is put 25 degrees under the horizon, where the 2026-09-07 screenshot showed photon
	// lighting its sky as if it were up.
	const matrix = @import("matrix.zig");
	const cubyzView = Mat4f.rotationX(0.3).mul(Mat4f.rotationZ(-1.1));
	const modelView = matrix.gbufferModelView(cubyzView);
	const inverse = matrix.inverse(modelView).?;
	const sunPathRotation: f32 = -40.0;
	const skyAngleDegrees: f32 = 120.0;
	const sunView = matrix.celestialPosition(modelView, sunPathRotation, skyAngleDegrees, 100);
	const expected = matrix.celestialWorldDirection(sunPathRotation, skyAngleDegrees);

	var e = TestEnvironment{};
	defer e.deinit();
	e.set("gbufferModelViewInverse", .{.mat4 = inverse});
	e.set("sunPosition", .{.vec3 = sunView});

	const norm = try evalFloat("1.0 / sqrt((sunPosition.x * sunPosition.x) + (sunPosition.y * sunPosition.y) + (sunPosition.z * sunPosition.z))", &e);
	e.set("view_sun_dir_norm", .{.float = norm});
	e.set("view_sun_dir_x", .{.float = try evalFloat("sunPosition.x * view_sun_dir_norm", &e)});
	e.set("view_sun_dir_y", .{.float = try evalFloat("sunPosition.y * view_sun_dir_norm", &e)});
	e.set("view_sun_dir_z", .{.float = try evalFloat("sunPosition.z * view_sun_dir_norm", &e)});
	const x = try evalFloat("gbufferModelViewInverse.0.0 * view_sun_dir_x + gbufferModelViewInverse.1.0 * view_sun_dir_y + gbufferModelViewInverse.2.0 * view_sun_dir_z", &e);
	const y = try evalFloat("gbufferModelViewInverse.0.1 * view_sun_dir_x + gbufferModelViewInverse.1.1 * view_sun_dir_y + gbufferModelViewInverse.2.1 * view_sun_dir_z", &e);
	const z = try evalFloat("gbufferModelViewInverse.0.2 * view_sun_dir_x + gbufferModelViewInverse.1.2 * view_sun_dir_y + gbufferModelViewInverse.2.2 * view_sun_dir_z", &e);

	try testing.expectApproxEqAbs(expected[0], x, 1e-3);
	try testing.expectApproxEqAbs(expected[1], y, 1e-3);
	try testing.expectApproxEqAbs(expected[2], z, 1e-3);
	// And it is night: the pack's `time_midnight` and `moonlit` both hinge on this sign.
	try testing.expect(y < -0.3);
}

test "T8: two accessors immediately followed by a real float literal" {
	var e = TestEnvironment{};
	defer e.deinit();
	e.set("shadowModelViewInverse", .{.mat4 = Mat4f{.rows = .{
		Vec4f{0, 0, 7, 0},
		Vec4f{0, 0, 0, 0},
		Vec4f{0, 0, 0, 0},
		Vec4f{0, 0, 0, 0},
	}}});
	// Column 2 is {7,0,0,0}. The trailing `1.0` must lex as a number, not as two accessors.
	try testing.expectApproxEqAbs(@as(f32, 7.0), try evalFloat("shadowModelViewInverse.2.0 * 1.0", &e), 1e-6);
}

test "T9: clamp nested deeply, with division binding tighter than subtraction" {
	var e = TestEnvironment{};
	defer e.deinit();
	e.set("sunAngle", .{.float = 0.0});
	try testing.expectApproxEqAbs(@as(f32, 1.0), try evalFloat(
		"((clamp(sunAngle, 0.97, 1.00) - 0.97) / 0.03) + (1.0 - (clamp(sunAngle, 0.01, 0.10) - 0.01) / 0.09)", &e), 1e-5);
}

test "T10: unary minus where the stack top is not an expression" {
	var e = TestEnvironment{};
	defer e.deinit();
	e.set("sunY", .{.float = 0.0});
	try testing.expectApproxEqAbs(@as(f32, 1.0), try evalFloat(
		"(1.0 - ((clamp(-sunY, 0.002, 0.04) - 0.002) / 0.038)) * (1.0 - ((clamp(sunY, 0.002, 0.04) - 0.002) / 0.038))", &e), 1e-5);
}

test "T11: comparisons bind tighter than the logical operator" {
	var e = TestEnvironment{};
	defer e.deinit();
	const source = "(worldTime>23000 || worldTime<12900)";
	e.set("worldTime", .{.int = 13000});
	try testing.expectEqual(false, (try evalWith(source, &e)).boolean);
	e.set("worldTime", .{.int = 23500});
	try testing.expectEqual(true, (try evalWith(source, &e)).boolean);
	e.set("worldTime", .{.int = 12000});
	try testing.expectEqual(true, (try evalWith(source, &e)).boolean);
}

test "the two logical operators share one precedence level" {
	var e = TestEnvironment{};
	defer e.deinit();
	// Equal precedence with left associativity gives (a || b) && c, which is false.
	// C's precedence would give a || (b && c), which is true.
	try testing.expectEqual(false, (try evalWith("1>0 || 0>1 && 0>1", &e)).boolean);
}

test "T12: an if() result feeds a binary operator" {
	var e = TestEnvironment{};
	defer e.deinit();
	e.set("sunDirX", .{.float = 3});
	e.set("moonDirX", .{.float = 5});
	e.set("sunDirNorm", .{.float = 2});
	e.set("isCloudSunlit", .{.boolean = true});
	try testing.expectApproxEqAbs(@as(f32, 6), try evalFloat("if(isCloudSunlit, sunDirX, moonDirX)*sunDirNorm", &e), 1e-6);
	e.set("isCloudSunlit", .{.boolean = false});
	try testing.expectApproxEqAbs(@as(f32, 10), try evalFloat("if(isCloudSunlit, sunDirX, moonDirX)*sunDirNorm", &e), 1e-6);
}

test "T17: three-argument smooth returns the raw target on the first frame" {
	var e = TestEnvironment{};
	defer e.deinit();
	e.set("sunDirZ", .{.float = 0.75});
	e.set("frameTime", .{.float = 0.016});

	const tree = try parse(testingAllocator, "smooth(sunDirZ, frameTime*8.0, frameTime*8.0)");
	defer tree.deinit(testingAllocator);
	var evaluator = Evaluator{.environment = e.env(), .allocator = testingAllocator, .deltaTime = 0.016};
	defer evaluator.deinit();

	try testing.expectApproxEqAbs(@as(f32, 0.75), (try evaluator.evaluate(tree)).asFloat().?, 1e-6);
	// Afterwards it moves toward a new target without reaching it in one step.
	e.set("sunDirZ", .{.float = 1.75});
	const second = (try evaluator.evaluate(tree)).asFloat().?;
	try testing.expect(second > 0.75);
	try testing.expect(second < 1.75);
}

test "smooth binds a leading literal to the id slot, which is then ignored" {
	var e = TestEnvironment{};
	defer e.deinit();
	e.set("target", .{.float = 4.0});
	// Four arguments: id, target, fadeUp, fadeDown. Treating the id as the target would give 72.
	const tree = try parse(testingAllocator, "smooth(72, target, 32.0, 32.0)");
	defer tree.deinit(testingAllocator);
	var evaluator = Evaluator{.environment = e.env(), .allocator = testingAllocator, .deltaTime = 0.016};
	defer evaluator.deinit();
	try testing.expectApproxEqAbs(@as(f32, 4.0), (try evaluator.evaluate(tree)).asFloat().?, 1e-6);
}

test "two smooth call sites in different declarations do not share an accumulator" {
	// The bug this pins. `smoothStates` was keyed by node index alone, and `parse` builds a
	// fresh node list per declaration - so node indices restart at 0 and two `smooth()` calls that
	// happen to land at the same index in their own trees shared one accumulator.
	//
	// Complementary hits this exactly. It declares
	//     variable.float.moved      = smooth(2, moving, 0, 31536000)
	//     uniform.float.rainFactor  = smooth(1, rainStrength, 3, 3)
	// and both land on the same node index. `moved`'s fadeUp is 0, which `SmoothState.update`
	// treats as a snap rather than a fade, and `moving` is a pure binary "is the player translating".
	// So walking snapped the shared slot to 1.0 and `rainFactor` - which must be a hard 0, since
	// `rainStrength` is a documented constant 0 - read ~0.95 instead, telling the pack it was raining
	// at full strength for exactly as long as the player kept moving.
	var e = TestEnvironment{};
	defer e.deinit();
	e.set("moving", .{.float = 1.0});
	e.set("rainStrength", .{.float = 0.0});

	const moved = try parse(testingAllocator, "smooth(2, moving, 0, 31536000)");
	defer moved.deinit(testingAllocator);
	const rainFactor = try parse(testingAllocator, "smooth(1, rainStrength, 3, 3)");
	defer rainFactor.deinit(testingAllocator);

	var evaluator = Evaluator{.environment = e.env(), .allocator = testingAllocator, .deltaTime = 0.016};
	defer evaluator.deinit();

	// Several frames, in the order the pack declares them, as `customuniforms` evaluates them.
	var last: f32 = 0;
	for(0..8) |_| {
		_ = try evaluator.evaluate(moved);
		last = (try evaluator.evaluate(rainFactor)).asFloat().?;
	}
	// `rainStrength` is 0 and never changes, so its smoothed form can only ever be 0.
	try testing.expectApproxEqAbs(@as(f32, 0.0), last, 1e-6);
}

test "a snapping smooth does not disturb a neighbouring one" {
	// The same defect stated as a general property rather than as Complementary's instance, so a
	// future change that reintroduces shared state fails here even if that pack is gone.
	var e = TestEnvironment{};
	defer e.deinit();
	e.set("high", .{.float = 1.0});
	e.set("zero", .{.float = 0.0});

	const snapping = try parse(testingAllocator, "smooth(9, high, 0, 100)");
	defer snapping.deinit(testingAllocator);
	const gentle = try parse(testingAllocator, "smooth(9, zero, 3, 3)");
	defer gentle.deinit(testingAllocator);

	var evaluator = Evaluator{.environment = e.env(), .allocator = testingAllocator, .deltaTime = 0.016};
	defer evaluator.deinit();
	for(0..8) |_| _ = try evaluator.evaluate(snapping);
	// Identical `id` arguments too - Iris ignores the id and gives each *resolution* its own
	// accumulator, so even a deliberate id collision must not couple them.
	try testing.expectApproxEqAbs(@as(f32, 0.0), (try evaluator.evaluate(gentle)).asFloat().?, 1e-6);
}

test "T19: a long left-associative chain with mixed precedence" {
	var e = TestEnvironment{};
	defer e.deinit();
	inline for(.{"timeMorning", "timeForenoon", "timeNoon", "timeAfternoon", "timeEvening", "timeDusk", "timeDawn"}) |name| {
		e.set(name, .{.float = 0});
	}
	e.set("wetness", .{.float = 0});
	const source = "1.00 * timeMorning + 0.85 * timeForenoon + 0.73 * timeNoon + 0.64 * timeAfternoon + 0.60 * timeEvening + 0.57 * timeDusk + 0.65 * timeDawn + wetness * 2.5";
	try testing.expectApproxEqAbs(@as(f32, 0), try evalFloat(source, &e), 1e-6);
	e.set("timeForenoon", .{.float = 2});
	try testing.expectApproxEqAbs(@as(f32, 1.7), try evalFloat(source, &e), 1e-5);
}

test "T15: an unknown variable is an error rather than a silent zero" {
	var e = TestEnvironment{};
	defer e.deinit();
	try testing.expectError(error.UnknownVariable, evalWith("biome_category == CAT_DESERT", &e));
}

test "division always produces a float, even between two ints" {
	var e = TestEnvironment{};
	defer e.deinit();
	// Iris registers no integer overload of divide, so this is 3.5 rather than 3.
	try testing.expectApproxEqAbs(@as(f32, 3.5), try evalFloat("7 / 2", &e), 1e-6);
}

test "remainder stays integral and follows the dividend's sign" {
	var e = TestEnvironment{};
	defer e.deinit();
	// Java's `%`, not GLSL's `mod`: the result is negative.
	try testing.expectEqual(@as(i32, -1), (try evalWith("-7 % 3", &e)).int);
}

test "number decoding follows the integer-first rule" {
	try testing.expectEqual(@as(i32, 15), decodeNumber("017").?.int);
	try testing.expectEqual(@as(i32, 31), decodeNumber("0x1F").?.int);
	try testing.expectEqual(@as(i32, 10), decodeNumber("0b1010").?.int);
	try testing.expectEqual(@as(i32, 48), decodeNumber("48").?.int);
	// `0.5` only becomes a float because the octal attempt fails first.
	try testing.expectApproxEqAbs(@as(f32, 0.5), decodeNumber("0.5").?.float, 1e-9);
	// An invalid octal falls through to float rather than erroring.
	try testing.expectApproxEqAbs(@as(f32, 8.0), decodeNumber("08").?.float, 1e-9);
}

test "a lone ampersand is rejected rather than treated as bitwise and" {
	try testing.expectError(error.UnexpectedCharacter, tokenize(testingAllocator, "a & b"));
}

test "access is rejected on a call result" {
	var e = TestEnvironment{};
	defer e.deinit();
	// `.` binds only to identifiers and other accesses, so this must not parse.
	try testing.expectError(error.UnexpectedToken, evalWith("vec3(1.0,2.0,3.0).x", &e));
}

test "multi-component swizzles do not exist" {
	var e = TestEnvironment{};
	defer e.deinit();
	e.set("v", .{.vec3 = .{1, 2, 3}});
	try testing.expectError(error.TypeMismatch, evalWith("v.xy", &e));
}

test "the whole expression must be consumed" {
	var e = TestEnvironment{};
	defer e.deinit();
	try testing.expectError(error.UnexpectedToken, evalWith("1.0 2.0", &e));
}

test "frac matches GLSL fract for negatives" {
	var e = TestEnvironment{};
	defer e.deinit();
	try testing.expectApproxEqAbs(@as(f32, 0.75), try evalFloat("frac(-0.25)", &e), 1e-6);
}

test "clamp with inverted bounds lets the minimum win" {
	var e = TestEnvironment{};
	defer e.deinit();
	try testing.expectApproxEqAbs(@as(f32, 5.0), try evalFloat("clamp(1.0, 5.0, 2.0)", &e), 1e-6);
}

test "in() is membership over the first argument, ints compared through the float cast" {
	var e = TestEnvironment{};
	defer e.deinit();
	e.set("biome", .{.int = 7});
	try testing.expect((try evalWith("in(biome, 3, 7)", &e)).boolean);
	try testing.expect(!(try evalWith("in(biome, 3, 8)", &e)).boolean);
	// A float member matches an int subject, as Iris's single float overload family makes it.
	try testing.expect((try evalWith("in(biome, 7.0)", &e)).boolean);
	// The subject is only ever compared against the rest, never the rest against each other.
	e.set("biome", .{.int = 1});
	try testing.expect(!(try evalWith("in(biome, 3, 3)", &e)).boolean);
}

test "in() wrapped in if() and smooth(), the shape every pack writes" {
	var e = TestEnvironment{};
	defer e.deinit();
	e.set("biome", .{.int = 14});
	const source = "smooth(4, if(in(biome, 14, 15), 1, 0), 10, 10)";
	try testing.expectApproxEqAbs(@as(f32, 1.0), try evalFloat(source, &e), 1e-6);
	e.set("biome", .{.int = 2});
	try testing.expectApproxEqAbs(@as(f32, 0.0), try evalFloat(source, &e), 1e-6);
}

test "in() needs a subject and at least one member, and only numbers" {
	var e = TestEnvironment{};
	defer e.deinit();
	try testing.expectError(error.BadArity, evalWith("in(1)", &e));
	e.set("flag", .{.boolean = true});
	try testing.expectError(error.TypeMismatch, evalWith("in(flag, 1, 2)", &e));
}

test "a call takes up to 32 arguments, which covers BSL's eleven-biome isCold and Bliss's eighteen" {
	var e = TestEnvironment{};
	defer e.deinit();
	e.set("biome", .{.int = 30});
	// 31 members plus the subject: the widest overload Iris registers.
	var source = std.ArrayList(u8).empty;
	defer source.deinit(testingAllocator.allocator);
	source.appendSlice(testingAllocator.allocator, "in(biome") catch unreachable;
	for(0..31) |i| source.print(testingAllocator.allocator, ", {}", .{i}) catch unreachable;
	source.appendSlice(testingAllocator.allocator, ")") catch unreachable;
	try testing.expect((try evalWith(source.items, &e)).boolean);
	// One more and Iris has no overload for it either.
	source.items.len -= 1;
	source.appendSlice(testingAllocator.allocator, ", 31)") catch unreachable;
	try testing.expectError(error.BadArity, evalWith(source.items, &e));
}

test "min and max keep working past eight arguments" {
	// `apply` converts every argument into a float buffer; it used to hold eight, which the call
	// limit above would have let a wide `min` overrun.
	var e = TestEnvironment{};
	defer e.deinit();
	try testing.expectApproxEqAbs(@as(f32, -2.0), try evalFloat("min(9.0, 8.0, 7.0, 6.0, 5.0, 4.0, 3.0, 2.0, 1.0, 0.0, -1.0, -2.0)", &e), 1e-6);
	try testing.expectEqual(@as(i32, 12), (try evalWith("max(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)", &e)).int);
}
