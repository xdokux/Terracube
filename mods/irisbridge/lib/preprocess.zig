//! The `#if`/`#else`/`#endif` layer that `.properties` files are read through.
//!
//! Packs gate whole blocks of `block.properties` and `shaders.properties` on the Minecraft version
//! and on their own options:
//!
//!     #if MC_VERSION >= 11300
//!     block.10021=oak_leaves birch_leaves ...
//!     #else
//!     block.10021=leaves leaves2
//!     #endif
//!
//! Reading such a file without evaluating the conditionals does not merely miss a refinement - both
//! branches are taken, and since a later `block.10021=` overwrites an earlier one, the *legacy*
//! branch is the one that survives. Every modern block name would then be silently dropped in
//! favour of names from Minecraft 1.12.
//!
//! Iris runs these files through `org.anarres.cpp`, a real C preprocessor. That is the behaviour
//! reproduced here, and it is why the expression grammar below is C's rather than the one in
//! `expression.zig`: that evaluator deliberately gives `&&` and `||` a *shared* precedence level to
//! match a quirk of Iris's custom-uniform parser, which would be wrong here. `a || b && c` groups
//! as `a || (b && c)` in a `#if`, and as `(a || b) && c` in a `uniform.*` declaration. Two
//! languages that look alike, so they get two evaluators.
//!
//! Scope is deliberately the conditional layer only. Object-like macro *substitution* into ordinary
//! property lines is not performed: no pack in the fixtures relies on it, and a half-done expander
//! that silently rewrites block names would be worse than none.

const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const List = main.ListManaged;

/// The macro table a source is evaluated against.
///
/// A macro with no value is still *defined*, which is what `#ifdef` and `defined()` test. Its value
/// in an arithmetic context is 0, matching C.
pub const Defines = struct {
	map: std.StringHashMapUnmanaged([]const u8) = .empty,
	arena: std.heap.ArenaAllocator,

	pub fn init(allocator: NeverFailingAllocator) Defines {
		return .{.arena = std.heap.ArenaAllocator.init(allocator.allocator)};
	}

	pub fn deinit(self: *Defines) void {
		self.map.deinit(self.arena.allocator());
		self.arena.deinit();
	}

	pub fn put(self: *Defines, name: []const u8, value: []const u8) void {
		const arena = self.arena.allocator();
		self.map.put(arena, arena.dupe(u8, name) catch unreachable, arena.dupe(u8, value) catch unreachable) catch unreachable;
	}

	pub fn remove(self: *Defines, name: []const u8) void {
		_ = self.map.remove(name);
	}

	/// An independent copy, for running `run` over a source without the `#define`s it contains
	/// leaking into the next one.
	///
	/// `run` deliberately mutates its table - that is what lets a pack's own definitions take part in
	/// its own conditionals - so anything preprocessing several sources against one starting point
	/// needs a fresh table per source, or the second source is evaluated against the first's leftovers.
	pub fn clone(self: *const Defines, allocator: NeverFailingAllocator) Defines {
		var copy = Defines.init(allocator);
		var iterator = self.map.iterator();
		while(iterator.next()) |entry| copy.put(entry.key_ptr.*, entry.value_ptr.*);
		return copy;
	}

	pub fn isDefined(self: *const Defines, name: []const u8) bool {
		return self.map.contains(name);
	}

	/// Accepts the `NAME value` form the standard macro list already uses, so the same strings that
	/// are handed to the GLSL transformer can seed this table.
	pub fn putMacroString(self: *Defines, macro: []const u8) void {
		const trimmed = std.mem.trim(u8, macro, " \t");
		const space = std.mem.indexOfAny(u8, trimmed, " \t") orelse {
			self.put(trimmed, "");
			return;
		};
		self.put(trimmed[0..space], std.mem.trim(u8, trimmed[space..], " \t"));
	}
};

// MARK: expression evaluation

const EvalError = error{Malformed};

/// A recursive-descent evaluator over C's `#if` grammar.
///
/// Everything is `i64`. C evaluates `#if` in the widest integer type available and packs only ever
/// compare version numbers and option values, so a narrower type would only add overflow cases
/// without buying anything.
const Evaluator = struct {
	text: []const u8,
	pos: usize = 0,
	defines: *const Defines,
	/// How many macro values this evaluation is nested inside, for `expandMacro`.
	depth: u8 = 0,

	/// How deep a chain of macros defined in terms of other macros is followed before giving up.
	/// Complementary goes two levels (`SHADOW_QUALITY_INTERNAL` from `SHADOW_QUALITY`); a self-
	/// referential `#define A A`, legal in C and undefined here, has to stop somewhere.
	const maxDepth = 16;

	fn skipSpace(self: *Evaluator) void {
		while(self.pos < self.text.len and (self.text[self.pos] == ' ' or self.text[self.pos] == '\t')) self.pos += 1;
	}

	fn peek(self: *Evaluator) ?u8 {
		self.skipSpace();
		if(self.pos >= self.text.len) return null;
		return self.text[self.pos];
	}

	/// Consumes `token` if it is next. Longer operators must be tried before their prefixes, or
	/// `<=` lexes as `<` and the trailing `=` derails the parse.
	fn eat(self: *Evaluator, token: []const u8) bool {
		self.skipSpace();
		if(!std.mem.startsWith(u8, self.text[self.pos..], token)) return false;
		// `&` must not match the first half of `&&`, and `<` must not match `<<` or `<=`.
		const after = self.pos + token.len;
		if(token.len == 1 and after < self.text.len) {
			const next = self.text[after];
			const ambiguous = switch(token[0]) {
				'&' => next == '&',
				'|' => next == '|',
				'<' => next == '<' or next == '=',
				'>' => next == '>' or next == '=',
				'=' => next == '=',
				'!' => next == '=',
				else => false,
			};
			if(ambiguous) return false;
		}
		self.pos = after;
		return true;
	}

	fn identifier(self: *Evaluator) ?[]const u8 {
		self.skipSpace();
		const start = self.pos;
		while(self.pos < self.text.len and (std.ascii.isAlphanumeric(self.text[self.pos]) or self.text[self.pos] == '_')) self.pos += 1;
		if(self.pos == start) return null;
		return self.text[start..self.pos];
	}

	fn primary(self: *Evaluator) EvalError!i64 {
		self.skipSpace();
		if(self.pos >= self.text.len) return error.Malformed;

		if(self.eat("(")) {
			const value = try self.ternary();
			if(!self.eat(")")) return error.Malformed;
			return value;
		}
		if(self.eat("!")) return @intFromBool(try self.unary() == 0);
		if(self.eat("~")) return ~try self.unary();
		if(self.eat("-")) return -%try self.unary();
		if(self.eat("+")) return self.unary();

		const character = self.text[self.pos];
		if(std.ascii.isDigit(character)) return self.number();

		const name = self.identifier() orelse return error.Malformed;

		if(std.mem.eql(u8, name, "defined")) {
			// Both `defined(X)` and `defined X` are legal.
			const parenthesised = self.eat("(");
			const target = self.identifier() orelse return error.Malformed;
			if(parenthesised and !self.eat(")")) return error.Malformed;
			return @intFromBool(self.defines.isDefined(target));
		}

		// C's rule: an identifier that survives macro expansion is replaced by 0. A pack testing
		// `#if SOME_UNSET_OPTION` therefore takes the false branch rather than failing the file.
		const value = self.defines.map.get(name) orelse return 0;
		if(value.len == 0) return 0;
		return self.expandMacro(value);
	}

	/// The value of a macro in an arithmetic context.
	///
	/// A literal is the common case. Anything else is itself an expression over other macros -
	/// `#define COLORED_LIGHTING_INTERNAL COLORED_LIGHTING` or `#define A (B + 1)` - which C expands
	/// before evaluating, so it is evaluated here in its own right. Iris runs a real C
	/// preprocessor over every shader before reading a single directive (`ShaderPack.java:286`),
	/// and this evaluator is what stands in for that when a pack's `DRAWBUFFERS` sits behind an
	/// `#if`; a macro read as 0 because its value was another name picks the wrong branch as
	/// surely as ignoring the `#if` did. Anything unreadable is 0, as before.
	fn expandMacro(self: *Evaluator, value: []const u8) i64 {
		const trimmed = std.mem.trim(u8, value, " \t");
		if(std.fmt.parseInt(i64, trimmed, 0)) |literal| return literal else |_| {}
		if(self.depth >= maxDepth) return 0;
		var nested = Evaluator{.text = trimmed, .defines = self.defines, .depth = self.depth + 1};
		const result = nested.ternary() catch return 0;
		nested.skipSpace();
		if(nested.pos != nested.text.len) return 0;
		return result;
	}

	fn number(self: *Evaluator) EvalError!i64 {
		const start = self.pos;
		while(self.pos < self.text.len and (std.ascii.isAlphanumeric(self.text[self.pos]) or self.text[self.pos] == '_')) self.pos += 1;
		var digits = self.text[start..self.pos];
		// Integer suffixes are legal in C and appear in version comparisons now and then.
		while(digits.len > 1 and (digits[digits.len - 1] | 0x20) == 'u' or digits.len > 1 and (digits[digits.len - 1] | 0x20) == 'l') {
			digits = digits[0 .. digits.len - 1];
		}
		return std.fmt.parseInt(i64, digits, 0) catch error.Malformed;
	}

	fn unary(self: *Evaluator) EvalError!i64 {
		return self.primary();
	}

	fn multiplicative(self: *Evaluator) EvalError!i64 {
		var left = try self.unary();
		while(true) {
			if(self.eat("*")) {
				left *%= try self.unary();
			} else if(self.eat("/")) {
				const right = try self.unary();
				// C leaves division by zero undefined; a preprocessor that crashes on it would take
				// the whole pack down, so it yields 0 and carries on.
				left = if(right == 0) 0 else @divTrunc(left, right);
			} else if(self.eat("%")) {
				const right = try self.unary();
				left = if(right == 0) 0 else @rem(left, right);
			} else return left;
		}
	}

	fn additive(self: *Evaluator) EvalError!i64 {
		var left = try self.multiplicative();
		while(true) {
			if(self.eat("+")) {
				left +%= try self.multiplicative();
			} else if(self.eat("-")) {
				left -%= try self.multiplicative();
			} else return left;
		}
	}

	fn shift(self: *Evaluator) EvalError!i64 {
		var left = try self.additive();
		while(true) {
			if(self.eat("<<")) {
				const right = try self.additive();
				left = if(right < 0 or right > 63) 0 else left << @intCast(right);
			} else if(self.eat(">>")) {
				const right = try self.additive();
				left = if(right < 0 or right > 63) 0 else left >> @intCast(right);
			} else return left;
		}
	}

	fn relational(self: *Evaluator) EvalError!i64 {
		var left = try self.shift();
		while(true) {
			// `<=` and `>=` are tried first; `eat` also refuses to match `<` when `=` follows, so
			// this is belt and braces rather than the only guard.
			if(self.eat("<=")) {
				left = @intFromBool(left <= try self.shift());
			} else if(self.eat(">=")) {
				left = @intFromBool(left >= try self.shift());
			} else if(self.eat("<")) {
				left = @intFromBool(left < try self.shift());
			} else if(self.eat(">")) {
				left = @intFromBool(left > try self.shift());
			} else return left;
		}
	}

	fn equality(self: *Evaluator) EvalError!i64 {
		var left = try self.relational();
		while(true) {
			if(self.eat("==")) {
				left = @intFromBool(left == try self.relational());
			} else if(self.eat("!=")) {
				left = @intFromBool(left != try self.relational());
			} else return left;
		}
	}

	fn bitAnd(self: *Evaluator) EvalError!i64 {
		var left = try self.equality();
		while(self.eat("&")) left &= try self.equality();
		return left;
	}

	fn bitXor(self: *Evaluator) EvalError!i64 {
		var left = try self.bitAnd();
		while(self.eat("^")) left ^= try self.bitAnd();
		return left;
	}

	fn bitOr(self: *Evaluator) EvalError!i64 {
		var left = try self.bitXor();
		while(self.eat("|")) left |= try self.bitXor();
		return left;
	}

	fn logicalAnd(self: *Evaluator) EvalError!i64 {
		var left = try self.bitOr();
		while(self.eat("&&")) {
			const right = try self.bitOr();
			left = @intFromBool(left != 0 and right != 0);
		}
		return left;
	}

	fn logicalOr(self: *Evaluator) EvalError!i64 {
		var left = try self.logicalAnd();
		while(self.eat("||")) {
			const right = try self.logicalAnd();
			left = @intFromBool(left != 0 or right != 0);
		}
		return left;
	}

	fn ternary(self: *Evaluator) EvalError!i64 {
		const condition = try self.logicalOr();
		if(!self.eat("?")) return condition;
		const whenTrue = try self.ternary();
		if(!self.eat(":")) return error.Malformed;
		const whenFalse = try self.ternary();
		return if(condition != 0) whenTrue else whenFalse;
	}
};

/// Evaluates one `#if`/`#elif` expression.
///
/// A malformed expression reports false rather than aborting: a pack with a condition this code
/// cannot read should lose that one block, not fail to load at all.
pub fn evaluateCondition(text: []const u8, defines: *const Defines) bool {
	var evaluator = Evaluator{.text = text, .defines = defines};
	const value = evaluator.ternary() catch return false;
	evaluator.skipSpace();
	if(evaluator.pos != evaluator.text.len) return false;
	return value != 0;
}

// MARK: conditional stripping

/// One `#if` nesting level.
const Frame = struct {
	/// Whether the enclosing frames are all active. A branch inside a false `#if` stays dead
	/// however its own condition evaluates.
	parentActive: bool,
	/// Whether this level's currently selected branch emits.
	active: bool,
	/// Whether any branch at this level has already been taken, so `#elif`/`#else` know to stay
	/// dead even when their own condition is true.
	taken: bool,
};

fn directiveName(line: []const u8) ?[]const u8 {
	const trimmed = std.mem.trim(u8, line, " \t\r");
	if(trimmed.len == 0 or trimmed[0] != '#') return null;
	var rest = std.mem.trimStart(u8, trimmed[1..], " \t");
	var end: usize = 0;
	while(end < rest.len and std.ascii.isAlphabetic(rest[end])) end += 1;
	rest = rest[0..end];
	if(rest.len == 0) return null;
	return rest;
}

fn directiveArgument(line: []const u8) []const u8 {
	const trimmed = std.mem.trim(u8, line, " \t\r");
	const afterHash = std.mem.trimStart(u8, trimmed[1..], " \t");
	var end: usize = 0;
	while(end < afterHash.len and std.ascii.isAlphabetic(afterHash[end])) end += 1;
	return std.mem.trim(u8, stripComment(afterHash[end..]), " \t");
}

/// The text of a directive line up to its first comment.
///
/// C removes comments before it reads directives, so `#define MOTION_BLUR_EFFECT -1 //[-1 1]`
/// defines the value `-1`, and `#if X == 1 /* see above */` tests `X == 1`. Every option a pack
/// declares carries exactly such a trailing `//[...]` list, so without this cut a shader source's
/// own `#define`s would all read as unparseable, and so as 0.
fn stripComment(text: []const u8) []const u8 {
	var end = text.len;
	if(std.mem.indexOf(u8, text, "//")) |index| end = @min(end, index);
	if(std.mem.indexOf(u8, text, "/*")) |index| end = @min(end, index);
	return text[0..end];
}

/// Strips inactive branches and the conditional directives themselves.
///
/// Every removed line becomes an empty line rather than disappearing, so line numbers in the result
/// still match the pack's own file - the whole point of a diagnostic that names a line.
///
/// `defines` is mutated by any `#define`/`#undef` the source contains, which is what makes a pack's
/// own definitions visible to later conditions in the same file.
pub fn run(allocator: NeverFailingAllocator, source: []const u8, defines: *Defines) []u8 {
	var out = List(u8).init(allocator);
	var stack = List(Frame).init(allocator);
	defer stack.deinit();

	var active = true;
	var lines = std.mem.splitScalar(u8, source, '\n');
	var first = true;
	while(lines.next()) |line| {
		if(!first) out.append('\n');
		first = false;

		const name = directiveName(line) orelse {
			if(active) out.appendSlice(line);
			continue;
		};
		const argument = directiveArgument(line);

		if(std.mem.eql(u8, name, "if") or std.mem.eql(u8, name, "ifdef") or std.mem.eql(u8, name, "ifndef")) {
			const condition = if(std.mem.eql(u8, name, "if"))
				evaluateCondition(argument, defines)
			else blk: {
				const target = firstWord(argument);
				const isDefined = defines.isDefined(target);
				break :blk if(std.mem.eql(u8, name, "ifdef")) isDefined else !isDefined;
			};
			stack.append(.{.parentActive = active, .active = active and condition, .taken = active and condition});
			active = stack.items[stack.items.len - 1].active;
			continue;
		}

		if(std.mem.eql(u8, name, "elif") or std.mem.eql(u8, name, "else")) {
			if(stack.items.len == 0) continue; // Unbalanced; the pack is malformed, so ignore it.
			const frame = &stack.items[stack.items.len - 1];
			const condition = if(std.mem.eql(u8, name, "else")) true else evaluateCondition(argument, defines);
			frame.active = frame.parentActive and !frame.taken and condition;
			if(frame.active) frame.taken = true;
			active = frame.active;
			continue;
		}

		if(std.mem.eql(u8, name, "endif")) {
			if(stack.items.len == 0) continue;
			const frame = stack.pop();
			active = frame.parentActive;
			continue;
		}

		if(active and std.mem.eql(u8, name, "define")) {
			const target = firstWord(argument);
			if(target.len != 0) defines.put(target, std.mem.trim(u8, argument[target.len..], " \t"));
			continue;
		}
		if(active and std.mem.eql(u8, name, "undef")) {
			const target = firstWord(argument);
			if(target.len != 0) defines.remove(target);
			continue;
		}

		// Anything else beginning with `#` is a comment in a properties file, and is dropped along
		// with the directives so callers see one uniform kind of line.
		if(active and !isKnownDirective(name)) out.appendSlice(line);
	}
	return out.toOwnedSlice();
}

fn isKnownDirective(name: []const u8) bool {
	const known = [_][]const u8{"if", "ifdef", "ifndef", "elif", "else", "endif", "define", "undef"};
	for(known) |entry| {
		if(std.mem.eql(u8, entry, name)) return true;
	}
	return false;
}

fn firstWord(text: []const u8) []const u8 {
	var end: usize = 0;
	while(end < text.len and (std.ascii.isAlphanumeric(text[end]) or text[end] == '_')) end += 1;
	return text[0..end];
}

/// Joins `\`-continued lines into one.
///
/// `block.properties` leans on this heavily - Nostalgia's emitter lists run to five continued
/// lines. Without joining, everything after the first line parses as a key-less fragment and is
/// dropped, which loses most of the block names in the file while still looking like it worked.
///
/// Run this *after* `run`, never before. A pack may open a continuation and then branch inside
/// it, and joining first pulls those `#if` lines into the middle of a value where nothing
/// recognises them as directives any more. Sundial does it on twelve `block.` entries:
///
///     block.8192 = \
///     #if MC_VERSION < 11300
///                  flowing_water \
///     #endif
///     #ifdef IRIS_TAG_SUPPORT
///                  %minecraft:water \
///     #endif
///                  water
///
/// Joined first, that id collects `#if`, `MC_VERSION`, `11300`, `#endif`, `IRIS_TAG_SUPPORT` and
/// both branches' names - which is the failure `parse`'s own header warns about, since a legacy
/// `#else` branch redeclares the same keys rather than merely adding to them.
///
/// Iris reaches the same order by the opposite route: `PropertiesPreprocessor.process` rewrites
/// every `\` to `IRIS_PASSTHROUGHBACKSLASH` before handing the text to its C preprocessor and puts
/// them back afterwards, with the comment "trick the preprocessor into not seeing the backslashes
/// during processing" - so its directives are evaluated while the continuations are still intact,
/// and `Properties.load` joins them last. `run` is line-based and never spliced lines itself, so
/// here the same result needs only the call order and the blank-line rule below.
///
/// Line count is preserved for the same reason as in `run`: the joined text keeps a trailing blank
/// line for each continuation consumed.
pub fn joinContinuations(allocator: NeverFailingAllocator, source: []const u8) []u8 {
	var out = List(u8).init(allocator);
	var pending: usize = 0;
	var lines = std.mem.splitScalar(u8, source, '\n');
	var first = true;
	while(lines.next()) |raw| {
		const line = std.mem.trimEnd(u8, raw, "\r");
		// A blank line does not close an open continuation. No properties author writes one -
		// `foo = a \` followed by nothing is meaningless - but it is exactly what `run` leaves where
		// it removed a directive or an inactive branch, and running `run` first is what the header
		// above requires. Without this the continuation ends on the first line the preprocessor took
		// out, and everything after it becomes a key-less fragment that `parse` drops.
		if(pending != 0 and line.len == 0) {
			pending += 1;
			continue;
		}
		if(std.mem.endsWith(u8, line, "\\")) {
			if(!first) {} // The join happens by simply not emitting a newline.
			out.appendSlice(line[0 .. line.len - 1]);
			out.append(' ');
			pending += 1;
			first = false;
			continue;
		}
		out.appendSlice(line);
		// Give back the newlines the joins swallowed, so later line numbers still line up.
		while(pending != 0) : (pending -= 1) out.append('\n');
		out.append('\n');
		first = false;
	}
	// A file whose last line is inside a continuation still owes its newlines, or every line number
	// after it shifts. `splitScalar` yields a trailing empty piece for any text ending in a newline,
	// so with the rule above this is the normal exit rather than a malformed-input case.
	while(pending != 0) : (pending -= 1) out.append('\n');
	return out.toOwnedSlice();
}

// MARK: tests

const testing = std.testing;
const testingAllocator = main.heap.testingAllocator;

fn definesWith(pairs: []const [2][]const u8) Defines {
	var defines = Defines.init(testingAllocator);
	for(pairs) |pair| defines.put(pair[0], pair[1]);
	return defines;
}

test "a version comparison selects the modern branch" {
	// The exact shape Nostalgia's block.properties uses. Getting this wrong does not drop the
	// modern names, it *replaces* them with the legacy ones, because the later key wins.
	var defines = definesWith(&.{.{"MC_VERSION", "12100"}});
	defer defines.deinit();

	const source =
		\\#if MC_VERSION >= 11300
		\\block.10021=oak_leaves
		\\#else
		\\block.10021=leaves
		\\#endif
		\\
	;
	const result = run(testingAllocator, source, &defines);
	defer testingAllocator.free(result);

	try testing.expect(std.mem.indexOf(u8, result, "oak_leaves") != null);
	try testing.expect(std.mem.indexOf(u8, result, "block.10021=leaves") == null);
}

test "line numbers survive stripping" {
	var defines = definesWith(&.{.{"MC_VERSION", "12100"}});
	defer defines.deinit();

	const source = "#if 0\na\n#endif\nkept\n";
	const result = run(testingAllocator, source, &defines);
	defer testingAllocator.free(result);

	// "kept" was on line 4 of the input and must still be on line 4 of the output.
	var lines = std.mem.splitScalar(u8, result, '\n');
	var index: usize = 1;
	while(lines.next()) |line| : (index += 1) {
		if(std.mem.eql(u8, line, "kept")) break;
	} else return error.NotFound;
	try testing.expectEqual(@as(usize, 4), index);
}

test "an undefined name is zero rather than an error" {
	var defines = definesWith(&.{});
	defer defines.deinit();
	try testing.expect(!evaluateCondition("UNSET_OPTION", &defines));
	try testing.expect(evaluateCondition("!UNSET_OPTION", &defines));
	try testing.expect(evaluateCondition("UNSET_OPTION == 0", &defines));
}

test "logical operators use C precedence, not the custom-uniform grouping" {
	// `expression.zig` gives && and || one shared level on purpose, to match Iris's custom-uniform
	// parser. Applying that here would be wrong: this is a C preprocessor. Under C's grouping
	// `1 || 0 && 0` is `1 || (0 && 0)` = 1; under the shared-level grouping it is `(1 || 0) && 0` = 0.
	var defines = definesWith(&.{});
	defer defines.deinit();
	try testing.expect(evaluateCondition("1 || 0 && 0", &defines));
	try testing.expect(!evaluateCondition("(1 || 0) && 0", &defines));
}

test "defined() reports macro presence, including valueless macros" {
	var defines = definesWith(&.{.{"IS_IRIS", ""}, .{"MC_VERSION", "12100"}});
	defer defines.deinit();
	try testing.expect(evaluateCondition("defined(IS_IRIS)", &defines));
	try testing.expect(evaluateCondition("defined IS_IRIS", &defines));
	try testing.expect(!evaluateCondition("defined(NOT_SET)", &defines));
	// A valueless macro is defined but arithmetically zero, exactly as in C.
	try testing.expect(!evaluateCondition("IS_IRIS", &defines));
}

test "elif chains take only the first true branch" {
	var defines = definesWith(&.{.{"QUALITY", "2"}});
	defer defines.deinit();

	const source =
		\\#if QUALITY == 1
		\\low
		\\#elif QUALITY == 2
		\\medium
		\\#elif QUALITY >= 2
		\\also_true_but_later
		\\#else
		\\fallback
		\\#endif
		\\
	;
	const result = run(testingAllocator, source, &defines);
	defer testingAllocator.free(result);

	try testing.expect(std.mem.indexOf(u8, result, "medium") != null);
	try testing.expect(std.mem.indexOf(u8, result, "also_true_but_later") == null);
	try testing.expect(std.mem.indexOf(u8, result, "fallback") == null);
	try testing.expect(std.mem.indexOf(u8, result, "low") == null);
}

test "a nested conditional stays dead inside a false parent" {
	var defines = definesWith(&.{});
	defer defines.deinit();

	const source =
		\\#if 0
		\\#if 1
		\\should_not_appear
		\\#endif
		\\#endif
		\\after
		\\
	;
	const result = run(testingAllocator, source, &defines);
	defer testingAllocator.free(result);

	try testing.expect(std.mem.indexOf(u8, result, "should_not_appear") == null);
	try testing.expect(std.mem.indexOf(u8, result, "after") != null);
}

test "relational operators are not mis-lexed as their prefixes" {
	var defines = definesWith(&.{.{"V", "11300"}});
	defer defines.deinit();
	// If `<=` lexed as `<` the trailing `=` would derail the parse and the condition would report
	// false, silently taking the wrong branch.
	try testing.expect(evaluateCondition("V <= 11300", &defines));
	try testing.expect(evaluateCondition("V >= 11300", &defines));
	try testing.expect(!evaluateCondition("V < 11300", &defines));
	try testing.expect(!evaluateCondition("V > 11300", &defines));
	try testing.expect(evaluateCondition("V != 11200", &defines));
}

test "define and undef inside the file affect later conditions" {
	var defines = definesWith(&.{});
	defer defines.deinit();

	const source =
		\\#define FEATURE 1
		\\#if FEATURE
		\\on
		\\#endif
		\\#undef FEATURE
		\\#ifdef FEATURE
		\\still_on
		\\#endif
		\\
	;
	const result = run(testingAllocator, source, &defines);
	defer testingAllocator.free(result);

	try testing.expect(std.mem.indexOf(u8, result, "on") != null);
	try testing.expect(std.mem.indexOf(u8, result, "still_on") == null);
}

test "a shader's option defines carry a trailing comment, and still evaluate" {
	// Every option in every pack is declared this way; the `//[...]` list is what makes it an
	// option. Complementary's composite4 keys its `DRAWBUFFERS` on the first line.
	var defines = definesWith(&.{});
	defer defines.deinit();

	const source =
		\\#define MOTION_BLUR_EFFECT -1 //[-1 1]
		\\#define SHADOW_QUALITY 3 // [1 2 3 4]
		\\#define TAA /* on by default */
		\\#if MOTION_BLUR_EFFECT == 1
		\\blur_on
		\\#endif
		\\#if MOTION_BLUR_EFFECT == -1 && SHADOW_QUALITY == 3 // both defaults
		\\defaults
		\\#endif
		\\#ifdef TAA
		\\taa
		\\#endif
		\\
	;
	const result = run(testingAllocator, source, &defines);
	defer testingAllocator.free(result);

	try testing.expect(std.mem.indexOf(u8, result, "blur_on") == null);
	try testing.expect(std.mem.indexOf(u8, result, "defaults") != null);
	try testing.expect(std.mem.indexOf(u8, result, "taa") != null);
	try testing.expectEqualStrings("-1", defines.map.get("MOTION_BLUR_EFFECT").?);
	try testing.expectEqualStrings("", defines.map.get("TAA").?);
}

test "a macro defined as another macro expands, and a self-referential one stops" {
	var defines = definesWith(&.{});
	defer defines.deinit();

	const source =
		\\#define COLORED_LIGHTING 2
		\\#define COLORED_LIGHTING_INTERNAL COLORED_LIGHTING
		\\#define DOUBLED (COLORED_LIGHTING_INTERNAL * 2)
		\\#define LOOP LOOP
		\\#if COLORED_LIGHTING_INTERNAL > 0
		\\lit
		\\#endif
		\\#if DOUBLED == 4
		\\four
		\\#endif
		\\#if LOOP == 0
		\\looped
		\\#endif
		\\
	;
	const result = run(testingAllocator, source, &defines);
	defer testingAllocator.free(result);

	try testing.expect(std.mem.indexOf(u8, result, "lit") != null);
	try testing.expect(std.mem.indexOf(u8, result, "four") != null);
	try testing.expect(std.mem.indexOf(u8, result, "looped") != null);
}

test "joining before preprocessing hides the directives, and the two orders genuinely differ" {
	// The rule `joinContinuations`' header states, asserted rather than described - and asserted in
	// both directions, so neither half can rot: the wrong order must still be wrong, or this
	// test would keep passing while quietly measuring nothing.
	const source = "block.1 = \\\n#if MC_VERSION < 11300\n    old \\\n#endif\n    new\n";

	var defines = definesWith(&.{.{"MC_VERSION", "12100"}});
	defer defines.deinit();
	const stripped = run(testingAllocator, source, &defines);
	defer testingAllocator.free(stripped);
	const right = joinContinuations(testingAllocator, stripped);
	defer testingAllocator.free(right);

	// Preprocess first: the directive is seen, its branch is dropped, and the join still spans the
	// blank lines it left behind.
	try testing.expect(std.mem.indexOf(u8, right, "new") != null);
	try testing.expect(std.mem.indexOf(u8, right, "old") == null);
	try testing.expect(std.mem.indexOf(u8, right, "MC_VERSION") == null);

	var otherDefines = definesWith(&.{.{"MC_VERSION", "12100"}});
	defer otherDefines.deinit();
	const joinedFirst = joinContinuations(testingAllocator, source);
	defer testingAllocator.free(joinedFirst);
	const wrong = run(testingAllocator, joinedFirst, &otherDefines);
	defer testingAllocator.free(wrong);

	// Join first and the `#if` is no longer at the start of a line, so nothing evaluates it: the
	// directive text and the branch that should have gone both survive into the value.
	try testing.expect(std.mem.indexOf(u8, wrong, "MC_VERSION") != null);
	try testing.expect(std.mem.indexOf(u8, wrong, "old") != null);
}

test "continuations are joined without losing later line numbers" {
	const source = "block.1=a b \\\n    c d\nblock.2=e\n";
	const result = joinContinuations(testingAllocator, source);
	defer testingAllocator.free(result);

	var lines = std.mem.splitScalar(u8, result, '\n');
	const firstLine = lines.next().?;
	try testing.expect(std.mem.indexOf(u8, firstLine, "a b") != null);
	try testing.expect(std.mem.indexOf(u8, firstLine, "c d") != null);
	// `block.2` was on line 3 of the input and must stay on line 3.
	_ = lines.next();
	try testing.expect(std.mem.startsWith(u8, lines.next().?, "block.2"));
}

test "a malformed condition drops its branch instead of failing the file" {
	var defines = definesWith(&.{});
	defer defines.deinit();
	try testing.expect(!evaluateCondition("1 +", &defines));
	try testing.expect(!evaluateCondition("((", &defines));
	try testing.expect(!evaluateCondition("", &defines));
}
