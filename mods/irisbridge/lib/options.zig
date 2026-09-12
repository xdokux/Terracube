//! Pack options: the values a user would pick in a shader settings screen.
//!
//! Packs declare them in their own source:
//!
//!     #define ResolutionScale 0.75    //[0.25 0.5 0.75 1.0]
//!     #define windEffectsEnabled      //comment
//!     //#define pomEnabled            //comment
//!     const int shadowMapResolution = 2048;  //[1024 2048 4096]
//!
//! With no option system a pack silently runs at whatever its source says, and those defaults are
//! not always what you want on a different engine - Nostalgia ships `ResolutionScale 0.75`, which
//! renders geometry into a 75% sub-rectangle and upscales it, showing up as blurry block textures
//! that look like a UV bug.
//!
//! Overrides are applied by rewriting the declaring line, which is what Iris does
//! (`OptionAnnotatedSource` is line-based for the same reason). Injecting `#define NAME value`
//! ahead of the source instead would collide with the pack's own definition - redefining a macro
//! with a different value is not portable, and the pack's line would win anyway on the drivers
//! that allow it.
//!
//! Only names the user explicitly overrides are touched. Discovery exists to report what a pack
//! offers, not to decide anything: rewriting every define that merely looks like an option would
//! risk mangling ordinary internal constants.

const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const List = main.ListManaged;

const preprocess = @import("preprocess.zig");

pub const Kind = enum {boolean, value, constant};

pub const Option = struct {
	name: []const u8,
	kind: Kind,
	/// Current value in the pack's source: "1"/"0" for booleans.
	current: []const u8,
	/// Values offered in a `//[a b c]` comment, empty when the pack lists none.
	allowed: []const u8 = "",
};

pub const Overrides = struct {
	map: std.StringHashMapUnmanaged([]const u8) = .empty,
	arena: std.heap.ArenaAllocator,

	pub fn init(allocator: NeverFailingAllocator) Overrides {
		return .{.arena = std.heap.ArenaAllocator.init(allocator.allocator)};
	}

	pub fn deinit(self: *Overrides) void {
		self.map.deinit(self.arena.allocator());
		self.arena.deinit();
	}

	pub fn put(self: *Overrides, name: []const u8, value: []const u8) void {
		const arena = self.arena.allocator();
		self.map.put(arena, arena.dupe(u8, name) catch unreachable, arena.dupe(u8, value) catch unreachable) catch unreachable;
	}

	pub fn count(self: *const Overrides) usize {
		return self.map.count();
	}

	/// Removes an entry and returns its value.
	///
	/// For keys in the options file that are not shader options at all - `profile` names one of the
	/// pack's presets. Leaving it in would have `apply` hunt for a `#define profile` to rewrite.
	/// The returned slice stays valid: the arena is not rewound by a removal.
	pub fn take(self: *Overrides, name: []const u8) ?[]const u8 {
		const entry = self.map.fetchRemove(name) orelse return null;
		return entry.value;
	}

	/// Reads `NAME = value` lines, ignoring blanks and `#` comments.
	///
	/// A trailing `#` comment is stripped from the value, which matters because the generated file
	/// carries the legal values as exactly that:
	///
	///     # Clouds = 3        # one of: 0 1 2 3 4
	///
	/// and its own instructions are to uncomment the line. Without this the override would be the
	/// whole string after the `=`, and that is what gets written into the pack's declaring line - so
	/// following the file's advice produced a broken shader. No option value contains a `#`.
	pub fn parse(allocator: NeverFailingAllocator, source: []const u8) Overrides {
		var self = Overrides.init(allocator);
		var lines = std.mem.splitScalar(u8, source, '\n');
		while(lines.next()) |raw| {
			const line = std.mem.trim(u8, raw, " \t\r");
			if(line.len == 0 or line[0] == '#') continue;
			const separator = std.mem.indexOfScalar(u8, line, '=') orelse continue;
			const name = std.mem.trim(u8, line[0..separator], " \t");
			const rawValue = line[separator + 1 ..];
			const uncommented = rawValue[0 .. std.mem.indexOfScalar(u8, rawValue, '#') orelse rawValue.len];
			const value = std.mem.trim(u8, uncommented, " \t");
			if(name.len == 0) continue;
			self.put(name, value);
		}
		return self;
	}
};

// MARK: profiles

/// The `profile.<Name>` declarations from `shaders.properties`.
///
///     profile.Low=!cloudVolumeEnabled shadowMapResolution=1024 !ssptEnabled
///     profile.Medium=profile.Low cloudVolumeEnabled shadowMapResolution=2048
///     profile.High=profile.Medium shadowFilterIterations=12
///
/// A profile is the preset a settings screen would offer, and packs tune them as the *intended*
/// configurations - the raw `#define`s in the source are whatever the author last left there, which
/// is not always one of them. Without this, picking "Low" was impossible and the pack ran at its
/// source defaults whatever the machine could handle.
///
/// Entry forms, following Iris's `ProfileSet.parse`:
///
///   - `profile.Other` - inherit everything that profile sets, at this position in the list
///   - `!option` - set the option false
///   - `option=value` / `option:value` - set the option to that value
///   - `!program.name` - disable a program outright
///   - bare `option` - set the option true
///
/// Order is significant twice over, in opposite directions. *Within* a profile the last entry wins,
/// which is what lets `Medium` inherit `Low` and then raise `shadowMapResolution` from 1024 to 2048.
/// *Against* the user's own overrides the profile loses, because a value someone typed into
/// `<pack>.options.txt` is a deliberate choice and a profile is only a default.
pub const Profiles = struct {
	names: [][]const u8 = &.{},
	bodies: [][]const u8 = &.{},
	arena: std.heap.ArenaAllocator,

	pub fn deinit(self: *Profiles) void {
		self.arena.deinit();
	}

	pub fn count(self: *const Profiles) usize {
		return self.names.len;
	}

	fn bodyFor(self: *const Profiles, name: []const u8) ?[]const u8 {
		for(self.names, self.bodies) |candidate, body| {
			if(std.mem.eql(u8, candidate, name)) return body;
		}
		return null;
	}

	/// Folds a profile's settings into `into`, leaving anything already set there untouched.
	///
	/// Returns false when no such profile exists, so the caller can report the names that do.
	/// `disabledPrograms` collects `!program.x` entries; the caller owns the strings' lifetime
	/// through this `Profiles`.
	pub fn apply(
		self: *const Profiles,
		allocator: NeverFailingAllocator,
		name: []const u8,
		into: *Overrides,
		disabledPrograms: *List([]const u8),
	) bool {
		if(self.bodyFor(name) == null) return false;

		// Resolved into a scratch set first, so "last entry wins" applies across the whole
		// inheritance chain before "the user wins" is applied against the result. Merging directly
		// into `into` would let an inherited value block the overriding one.
		var resolved = Overrides.init(allocator);
		defer resolved.deinit();

		var chain = List([]const u8).init(allocator);
		defer chain.deinit();
		self.collect(allocator, name, &resolved, disabledPrograms, &chain);

		var iterator = resolved.map.iterator();
		while(iterator.next()) |entry| {
			if(into.map.get(entry.key_ptr.*) != null) continue;
			into.put(entry.key_ptr.*, entry.value_ptr.*);
		}
		return true;
	}

	fn collect(
		self: *const Profiles,
		allocator: NeverFailingAllocator,
		name: []const u8,
		out: *Overrides,
		disabledPrograms: *List([]const u8),
		chain: *List([]const u8),
	) void {
		// A profile that includes itself, directly or through a loop, would recurse forever. Iris
		// raises an error for this; dropping just the repeat keeps the rest of the profile usable.
		for(chain.items) |visited| {
			if(std.mem.eql(u8, visited, name)) {
				std.log.warn("irisbridge: profile '{s}' is recursively included; the repeat is ignored", .{name});
				return;
			}
		}
		const body = self.bodyFor(name) orelse {
			std.log.warn("irisbridge: profile '{s}' includes unknown profile", .{name});
			return;
		};
		chain.append(name);
		defer _ = chain.pop();

		var parts = std.mem.tokenizeAny(u8, body, " \t");
		while(parts.next()) |part| {
			if(part.len == 0) continue;

			if(std.mem.startsWith(u8, part, "!program.")) {
				disabledPrograms.append(part["!program.".len..]);
				continue;
			}
			if(std.mem.startsWith(u8, part, "profile.")) {
				self.collect(allocator, part["profile.".len..], out, disabledPrograms, chain);
				continue;
			}
			if(part[0] == '!') {
				if(part.len > 1) out.put(part[1..], "false");
				continue;
			}
			// `=` and `:` are both accepted separators. Whichever comes first wins, so a value
			// containing the other character is not split in the wrong place.
			const separator = blk: {
				const equals = std.mem.indexOfScalar(u8, part, '=');
				const colon = std.mem.indexOfScalar(u8, part, ':');
				if(equals != null and colon != null) break :blk @min(equals.?, colon.?);
				break :blk equals orelse colon orelse break :blk null;
			};
			if(separator) |at| {
				out.put(part[0..at], part[at + 1 ..]);
			} else {
				// A bare name is a boolean being switched on. `apply` writes "true", which
				// `rewriteLine` turns into an uncommented `#define` for a boolean option.
				out.put(part, "true");
			}
		}
	}
};

/// Reads every `profile.<Name>` line from a `shaders.properties` source.
///
/// The source is expected to have been through `preprocess`, since packs gate profiles on their own
/// options; parsing the raw file would collect profiles from branches that are switched off.
pub fn parseProfiles(allocator: NeverFailingAllocator, source: []const u8) Profiles {
	var self = Profiles{.arena = std.heap.ArenaAllocator.init(allocator.allocator)};
	const arena = NeverFailingAllocator{.allocator = self.arena.allocator(), .IAssertThatTheProvidedAllocatorCantFail = {}};

	var names = List([]const u8).init(arena);
	var bodies = List([]const u8).init(arena);

	var logical = List(u8).init(allocator);
	defer logical.deinit();

	var lines = std.mem.splitScalar(u8, source, '\n');
	while(lines.next()) |rawLine| {
		const line = std.mem.trimEnd(u8, rawLine, "\r");
		// Profile bodies are long and packs wrap them; without joining, everything after the first
		// line would be dropped and the profile would silently set only part of what it declares.
		if(std.mem.endsWith(u8, line, "\\")) {
			logical.appendSlice(line[0 .. line.len - 1]);
			logical.append(' ');
			continue;
		}
		logical.appendSlice(line);
		defer logical.clearRetainingCapacity();

		const trimmed = std.mem.trim(u8, logical.items, " \t");
		if(trimmed.len == 0 or trimmed[0] == '#') continue;
		if(!std.mem.startsWith(u8, trimmed, "profile.")) continue;

		const equals = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
		const name = std.mem.trim(u8, trimmed["profile.".len..equals], " \t");
		if(name.len == 0) continue;

		names.append(arena.dupe(u8, name));
		bodies.append(arena.dupe(u8, std.mem.trim(u8, trimmed[equals + 1 ..], " \t")));
	}

	self.names = names.toOwnedSlice();
	self.bodies = bodies.toOwnedSlice();
	return self;
}

// MARK: screens

/// The options a pack lists in its own settings screens.
///
///     screen=INFO <profile> <empty> [ATMOS] [LIGHT] [TERRAIN]
///     screen.ATMOS=sunPathRotation volumeWorldTimeAnim <empty> [CLOUDS] [FOG]
///     screen.CLOUDS=cloudVolumeEnabled cloudVolumeStoryMode cloudVolumeRounding
///     sliders=sunPathRotation cloudVolumeRounding shadowFilterIterations
///
/// This is the pack author's own answer to "what is worth tuning", and it is far more useful than
/// scanning the source for `#define`s: Nostalgia declares hundreds of those, of which a few dozen
/// are options and the rest are internal constants. Iris uses these keys to lay out its settings
/// GUI; here they decide what goes into the generated options file.
///
/// `sliders` marks which of them a GUI would draw as a slider rather than a cycle button. It has no
/// effect on a text options file, but it is recorded because it is the pack's own signal that an
/// option is a continuous range, which is worth showing next to the value.
pub const Screens = struct {
	/// Option names in the order the pack's screens list them.
	names: [][]const u8 = &.{},
	sliders: [][]const u8 = &.{},
	arena: std.heap.ArenaAllocator,

	pub fn deinit(self: *Screens) void {
		self.arena.deinit();
	}

	pub fn isSlider(self: *const Screens, name: []const u8) bool {
		for(self.sliders) |slider| {
			if(std.mem.eql(u8, slider, name)) return true;
		}
		return false;
	}
};

/// A screen entry that names an option, rather than a layout token.
///
/// `[GROUP]` links to a sub-screen, `<empty>` is a spacer and `<profile>` is the profile selector.
/// All three are layout, and treating them as options would put `[ATMOS]` in the options file.
fn isScreenOptionToken(token: []const u8) bool {
	if(token.len == 0) return false;
	return token[0] != '[' and token[0] != '<';
}

pub fn parseScreens(allocator: NeverFailingAllocator, source: []const u8) Screens {
	var self = Screens{.arena = std.heap.ArenaAllocator.init(allocator.allocator)};
	const arena = NeverFailingAllocator{.allocator = self.arena.allocator(), .IAssertThatTheProvidedAllocatorCantFail = {}};

	var names = List([]const u8).init(arena);
	var sliders = List([]const u8).init(arena);

	var logical = List(u8).init(allocator);
	defer logical.deinit();

	var lines = std.mem.splitScalar(u8, source, '\n');
	while(lines.next()) |rawLine| {
		const line = std.mem.trimEnd(u8, rawLine, "\r");
		if(std.mem.endsWith(u8, line, "\\")) {
			logical.appendSlice(line[0 .. line.len - 1]);
			logical.append(' ');
			continue;
		}
		logical.appendSlice(line);
		defer logical.clearRetainingCapacity();

		const trimmed = std.mem.trim(u8, logical.items, " \t");
		if(trimmed.len == 0 or trimmed[0] == '#') continue;

		const equals = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
		const key = std.mem.trim(u8, trimmed[0..equals], " \t");
		const value = trimmed[equals + 1 ..];

		const isSliderKey = std.mem.eql(u8, key, "sliders");
		const isScreenKey = std.mem.eql(u8, key, "screen") or std.mem.startsWith(u8, key, "screen.");
		if(!isSliderKey and !isScreenKey) continue;
		// `screen.TERRAIN.columns=2` is layout, and its value is a number that would otherwise be
		// collected as an option named "2".
		if(std.mem.endsWith(u8, key, ".columns")) continue;

		var parts = std.mem.tokenizeAny(u8, value, " \t");
		while(parts.next()) |token| {
			if(!isScreenOptionToken(token)) continue;
			const target = if(isSliderKey) &sliders else &names;
			// The same option legitimately appears on more than one screen; the file should list it
			// once.
			for(target.items) |existing| {
				if(std.mem.eql(u8, existing, token)) break;
			} else target.append(arena.dupe(u8, token));
		}
	}

	self.names = names.toOwnedSlice();
	self.sliders = sliders.toOwnedSlice();
	return self;
}

const Split = struct {
	/// True when the line is a `//#define ...`, i.e. a boolean option currently switched off.
	commentedOut: bool,
	code: []const u8,
	comment: []const u8,
};

/// Separates a declaration line into its code and its trailing comment.
///
/// The leading `//` of a disabled boolean has to be recognised *before* looking for a trailing
/// comment, or the whole line reads as one comment and the option disappears. That is the entire
/// reason this is not a one-line `indexOf`.
fn splitLine(line: []const u8) Split {
	var body = std.mem.trim(u8, line, " \t\r");
	var commentedOut = false;
	if(std.mem.startsWith(u8, body, "//")) {
		const inner = std.mem.trim(u8, body[2..], " \t");
		if(!std.mem.startsWith(u8, inner, "#define")) return .{.commentedOut = false, .code = "", .comment = body};
		body = inner;
		commentedOut = true;
	}
	const index = std.mem.indexOf(u8, body, "//") orelse return .{.commentedOut = commentedOut, .code = body, .comment = ""};
	return .{.commentedOut = commentedOut, .code = body[0..index], .comment = body[index..]};
}

/// The `[a b c]` list from an option's trailing comment, or empty.
fn allowedValues(comment: []const u8) []const u8 {
	const open = std.mem.indexOfScalar(u8, comment, '[') orelse return "";
	const close = std.mem.indexOfScalarPos(u8, comment, open, ']') orelse return "";
	return comment[open + 1 .. close];
}

/// Lists the options a pack declares, for reporting.
///
/// Deliberately permissive: it reports anything shaped like an option, because the point is to
/// tell a user what they might set, not to decide what gets rewritten.
pub fn discover(allocator: NeverFailingAllocator, source: []const u8) []Option {
	var found = List(Option).init(allocator);
	var lines = std.mem.splitScalar(u8, source, '\n');
	while(lines.next()) |raw| {
		const line = std.mem.trim(u8, raw, " \t\r");
		if(std.mem.indexOf(u8, line, "#define") == null and !std.mem.startsWith(u8, line, "const")) continue;
		if(parseLine(line)) |option| found.append(option);
	}
	return found.toOwnedSlice();
}

fn parseLine(line: []const u8) ?Option {
	const split = splitLine(line);
	const code = std.mem.trim(u8, split.code, " \t");
	const allowed = allowedValues(split.comment);

	// A commented-out define is a boolean option that is currently off.
	if(split.commentedOut) {
		if(!std.mem.startsWith(u8, code, "#define")) return null;
		const name = firstWord(std.mem.trim(u8, code["#define".len..], " \t"));
		if(name.len == 0) return null;
		return .{.name = name, .kind = .boolean, .current = "0", .allowed = allowed};
	}

	if(std.mem.startsWith(u8, code, "#define")) {
		const rest = std.mem.trim(u8, code["#define".len..], " \t");
		const name = firstWord(rest);
		if(name.len == 0) return null;
		const value = std.mem.trim(u8, rest[name.len..], " \t");
		if(value.len == 0) return .{.name = name, .kind = .boolean, .current = "1", .allowed = allowed};
		return .{.name = name, .kind = .value, .current = value, .allowed = allowed};
	}

	if(std.mem.startsWith(u8, code, "const")) {
		const equals = std.mem.indexOfScalar(u8, code, '=') orelse return null;
		const beforeEquals = std.mem.trim(u8, code[0..equals], " \t");
		const name = lastWord(beforeEquals);
		if(name.len == 0) return null;
		const semicolon = std.mem.indexOfScalarPos(u8, code, equals, ';') orelse code.len;
		const value = std.mem.trim(u8, code[equals + 1 .. semicolon], " \t");
		return .{.name = name, .kind = .constant, .current = value, .allowed = allowed};
	}
	return null;
}

fn firstWord(text: []const u8) []const u8 {
	var end: usize = 0;
	while(end < text.len and (std.ascii.isAlphanumeric(text[end]) or text[end] == '_')) end += 1;
	return text[0..end];
}

fn lastWord(text: []const u8) []const u8 {
	var end = text.len;
	while(end > 0 and (text[end - 1] == ' ' or text[end - 1] == '\t')) end -= 1;
	var start = end;
	while(start > 0 and (std.ascii.isAlphanumeric(text[start - 1]) or text[start - 1] == '_')) start -= 1;
	return text[start..end];
}

/// Rewrites the declaring line of every overridden option.
///
/// Caller owns the result. Lines that declare nothing overridden are copied through byte for byte,
/// so a pack with no overrides gets back exactly what it supplied.
pub fn apply(allocator: NeverFailingAllocator, source: []const u8, overrides: *const Overrides, applied: ?*usize) []u8 {
	if(overrides.count() == 0) return allocator.dupe(u8, source);

	var out = List(u8).init(allocator);
	var lines = std.mem.splitScalar(u8, source, '\n');
	var first = true;
	while(lines.next()) |raw| {
		if(!first) out.append('\n');
		first = false;

		const rewritten = rewriteLine(&out, raw, overrides);
		if(rewritten) {
			if(applied) |counter| counter.* += 1;
		} else {
			out.appendSlice(raw);
		}
	}
	return out.toOwnedSlice();
}

/// Returns true when the line declared an overridden option and a replacement was written.
fn rewriteLine(out: *List(u8), raw: []const u8, overrides: *const Overrides) bool {
	const trimmed = std.mem.trim(u8, raw, " \t\r");
	if(std.mem.indexOf(u8, trimmed, "#define") == null and !std.mem.startsWith(u8, trimmed, "const")) return false;

	const option = parseLine(trimmed) orelse return false;
	const wanted = overrides.map.get(option.name) orelse return false;

	// Preserve the original indentation so diagnostics still line up with the pack's own file.
	const indentEnd = std.mem.indexOfNone(u8, raw, " \t") orelse raw.len;
	out.appendSlice(raw[0..indentEnd]);

	const split = splitLine(raw);

	switch(option.kind) {
		.boolean => {
			// A boolean is turned on by uncommenting its define and off by commenting it out.
			const on = !(std.mem.eql(u8, wanted, "0") or std.ascii.eqlIgnoreCase(wanted, "false"));
			if(!on) out.appendSlice("//");
			out.appendSlice("#define ");
			out.appendSlice(option.name);
		},
		.value => {
			out.appendSlice("#define ");
			out.appendSlice(option.name);
			out.append(' ');
			out.appendSlice(wanted);
		},
		.constant => {
			// The type is whatever the pack wrote between `const` and the name.
			const code = std.mem.trim(u8, split.code, " \t");
			const equals = std.mem.indexOfScalar(u8, code, '=') orelse return false;
			out.appendSlice(std.mem.trimEnd(u8, code[0..equals], " \t"));
			out.appendSlice(" = ");
			out.appendSlice(wanted);
			out.append(';');
		},
	}

	if(split.comment.len != 0) {
		out.append(' ');
		out.appendSlice(split.comment);
	}
	return true;
}

// MARK: options file template

/// Renders a commented options file listing everything the pack exposes.
///
/// This is what stands in for an in-game settings screen. The values a pack accepts are otherwise
/// invisible: they live in `//[0.25 0.5 0.75 1.0]` comments scattered through its source, and
/// without the list there is no way to know that `ResolutionScale` takes four specific values or
/// that the pack ships four profiles. Writing them out once, commented, turns "edit this file" from
/// guesswork into picking from a list.
///
/// Every line is commented out, so a freshly written file changes nothing until someone edits it.
/// `declared` supplies each option's current value and allowed list; `screens` decides *which*
/// options appear and in what order, because that is the pack author's own curation - scanning for
/// `#define` instead would list several hundred internal constants alongside the real options.
pub fn renderTemplate(
	allocator: NeverFailingAllocator,
	packName: []const u8,
	declared: []const Option,
	screens: *const Screens,
	profiles: *const Profiles,
) []u8 {
	var out = List(u8).init(allocator);

	out.print("# Shader options for {s}.\n", .{packName});
	out.appendSlice(
		\\#
		\\# Uncomment a line and change its value to override what the pack's own source declares.
		\\# Everything here is commented out, so this file has no effect until you edit it.
		\\#
		\\# Values are written back into the pack's declaring line when it loads, which is how a
		\\# shader settings screen would apply them.
		\\
	);

	if(profiles.count() != 0) {
		out.appendSlice("\n# Presets the pack ships. Selecting one sets many options at once; anything you\n");
		out.appendSlice("# set explicitly below still wins over it.\n");
		out.appendSlice("#\n# profile = ");
		out.appendSlice(profiles.names[0]);
		out.appendSlice("\n#\n# Available: ");
		for(profiles.names, 0..) |profileName, index| {
			if(index != 0) out.appendSlice(", ");
			out.appendSlice(profileName);
		}
		out.append('\n');
	}

	// Screen order first, then anything declared with an allowed-values list that no screen
	// mentions - a pack with no screens at all would otherwise produce an empty file.
	var written: usize = 0;
	out.appendSlice("\n# ---- options ----\n");
	for(screens.names) |name| {
		const option = findOption(declared, name) orelse continue;
		writeOptionLine(&out, option, screens.isSlider(name));
		written += 1;
	}
	if(written == 0) {
		for(declared) |option| {
			if(option.allowed.len == 0) continue;
			writeOptionLine(&out, option, false);
			written += 1;
		}
	}
	if(written == 0) {
		out.appendSlice("# (this pack declares no options)\n");
	}
	return out.toOwnedSlice();
}

/// Sets one option in an options file's text, returning the new text.
///
/// An empty `value` clears the option instead of setting it: the line is commented out rather than
/// deleted, so the option and its legal values stay visible in the file. That is the only way back
/// to what the pack itself declares once a choice has been made, and a settings screen that can set
/// a value but never unset it is a trap.
///
/// Editing the file rather than regenerating it is the whole point: the generated template carries
/// the legal values as trailing comments, and a user's own notes sit between the lines. Rewriting
/// from the option list would discard both.
///
/// A matching line is replaced whether it was active or commented out, since "commented out" is how
/// the template ships every option and toggling one from a settings screen has to uncomment it. The
/// trailing `# one of: ...` hint is preserved, so a line stays self-describing after being set. Later
/// duplicates of the same key are dropped, because `Overrides.parse` lets the last one win and a
/// file where the visible edit is overridden further down is a trap.
pub fn updateFile(allocator: NeverFailingAllocator, source: []const u8, name: []const u8, value: []const u8) []u8 {
	var out = List(u8).init(allocator);
	var written = false;

	var lines = std.mem.splitScalar(u8, source, '\n');
	var first = true;
	while(lines.next()) |raw| {
		const line = std.mem.trimEnd(u8, raw, "\r");
		if(!first) out.append('\n');
		first = false;

		if(settingKey(line)) |key| {
			if(std.mem.eql(u8, key, name)) {
				if(written) {
					// Drop the duplicate. The newline for it was already emitted, which leaves a blank
					// line rather than joining two unrelated lines together.
					continue;
				}
				written = true;
				if(value.len == 0) out.appendSlice("# ");
				out.appendSlice(name);
				out.appendSlice(" = ");
				// Clearing keeps whatever value was there, so the line still shows what it was set to
				// when it is uncommented again.
				out.appendSlice(if(value.len == 0) currentValueOf(line) else value);
				// The hint, if the line carries one. Searched from after the `=`, because a
				// commented-out line opens with a `#` of its own and that one is the comment marker.
				const afterEquals = std.mem.indexOfScalar(u8, line, '=').? + 1;
				if(std.mem.indexOfScalarPos(u8, line, afterEquals, '#')) |hash| {
					out.appendSlice("        ");
					out.appendSlice(std.mem.trim(u8, line[hash..], " \t"));
				}
				continue;
			}
		}
		out.appendSlice(line);
	}

	// Nothing to clear if the file never mentioned it, so only a real value is appended.
	if(!written and value.len != 0) {
		if(out.items.len != 0 and out.items[out.items.len - 1] != '\n') out.append('\n');
		out.appendSlice(name);
		out.appendSlice(" = ");
		out.appendSlice(value);
		out.append('\n');
	}
	return out.toOwnedSlice();
}

/// The value a setting line carries, without its trailing hint. Empty when there is none.
fn currentValueOf(line: []const u8) []const u8 {
	const equals = std.mem.indexOfScalar(u8, line, '=') orelse return "";
	const after = line[equals + 1 ..];
	const uncommented = after[0 .. std.mem.indexOfScalar(u8, after, '#') orelse after.len];
	return std.mem.trim(u8, uncommented, " \t");
}

/// The option name a line sets, whether the line is active or commented out.
///
/// Returns null for prose comments, blank lines and anything without a `=`, so a header paragraph in
/// the generated file is never mistaken for a setting.
fn settingKey(line: []const u8) ?[]const u8 {
	var text = std.mem.trim(u8, line, " \t");
	// A commented-out setting is still a setting for this purpose: it is how the template ships
	// every option, and toggling one has to replace that line rather than append a second.
	while(text.len != 0 and text[0] == '#') text = std.mem.trimStart(u8, text[1..], " \t");
	const equals = std.mem.indexOfScalar(u8, text, '=') orelse return null;
	const key = std.mem.trim(u8, text[0..equals], " \t");
	if(key.len == 0) return null;
	// Prose in the header can contain an `=`; a real key is one identifier.
	for(key) |char| {
		if(!std.ascii.isAlphanumeric(char) and char != '_' and char != '.') return null;
	}
	return key;
}

fn findOption(declared: []const Option, name: []const u8) ?Option {
	for(declared) |option| {
		if(std.mem.eql(u8, option.name, name)) return option;
	}
	return null;
}

fn writeOptionLine(out: *List(u8), option: Option, isSlider: bool) void {
	out.appendSlice("# ");
	out.appendSlice(option.name);
	out.appendSlice(" = ");
	// Booleans read better as the words the file accepts than as the pack's internal 1/0.
	if(option.kind == .boolean) {
		out.appendSlice(if(std.mem.eql(u8, option.current, "0")) "false" else "true");
	} else {
		out.appendSlice(option.current);
	}

	if(option.kind == .boolean and option.allowed.len == 0) {
		out.appendSlice("        # true or false");
	} else if(option.allowed.len != 0) {
		out.appendSlice(if(isSlider) "        # range: " else "        # one of: ");
		out.appendSlice(option.allowed);
	}
	out.append('\n');
}

/// Collects the options declared across a set of already-include-resolved sources.
///
/// Deduplicated by name, keeping the first sighting: an option declared in a shared header is seen
/// once per program that includes it, and all those sightings are the same declaration.
///
/// The returned `Option`s borrow from `sources`, which must outlive them.
pub fn discoverAll(allocator: NeverFailingAllocator, sources: []const []const u8) []Option {
	var found = List(Option).init(allocator);
	for(sources) |source| {
		const inSource = discover(allocator, source);
		defer allocator.free(inSource);
		outer: for(inSource) |option| {
			for(found.items) |existing| {
				if(std.mem.eql(u8, existing.name, option.name)) continue :outer;
			}
			found.append(option);
		}
	}
	return found.toOwnedSlice();
}

/// Adds an option set to the macro table a `.properties` file is read through, in the shape Iris's
/// `PropertiesPreprocessor` gives it (`getBooleanValues`, `getStringValues`): a boolean that is on
/// is a defined name with no value, a boolean that is off is not defined, and a valued option - a
/// `#define` with a value or a `const` declaration - carries its value.
///
/// This is what lets `#ifdef MILKY_WAY` around a texture binding, or
/// `#if CLOUDS_TEMPORAL_UPSCALING == 4` around a buffer size, see the pack's own defaults rather
/// than only what the user overrode.
///
/// `discover` is permissive by design and reports anything shaped like an option; Iris's
/// `OptionAnnotatedSource` is not, and two of its rules matter here. A `#define` with a value is an
/// option only when a `//[...]` list follows it, so BSL's fallback `#define MC_RENDER_STAGE_MOON 1`
/// under `#ifndef MC_RENDER_STAGE_MOON` is not one and must not replace the environment's 5. And
/// a name the environment already defines is never touched by an option, whichever way the pack
/// spells it - a debugging `//#define IS_IRIS` would otherwise take the real one out of the table.
pub fn putDefines(defines: *preprocess.Defines, declared: []const Option) void {
	for(declared) |option| {
		if(defines.isDefined(option.name)) continue;
		switch(option.kind) {
			.boolean => if(std.mem.eql(u8, option.current, "1")) defines.put(option.name, ""),
			.value, .constant => if(option.allowed.len != 0) defines.put(option.name, option.current),
		}
	}
}

// MARK: program.<name>.enabled

/// Whether a `program.<name>.enabled` condition holds.
///
/// The value of that directive is a boolean expression over the pack's own options, not a
/// literal, and five of the six packs in the corpus use it - none of them with `true`/`false`:
///
///     Kappa        program.world0/deferred5.enabled  = ssptEnabled
///     Nostalgia    program.world0/composite.enabled  = reflectionCaptureEnabled
///     Sildur's     program.composite.enabled         = Bloom || Godrays || Volumetric_Lighting
///     Sundial      program.composite4.enabled        = !UNDERGROUND_MODE
///     photon       program.world0/composite2.enabled = DOF
///
/// Ignoring it meant every one of them ran programs it had asked to have switched off. For photon
/// that is load-bearing: its `composite2` opens with
/// `#error "This program should be disabled if Depth of Field is disabled"`, and its `composite3`
/// includes a file with an unmatched `#endif` that is only ever safe *because* the program is not
/// compiled.
///
/// Grammar transcribed from Iris's `BooleanParser`: `true`/`1` and `false`/`0` are literals, any
/// other name is looked up as a boolean option, `!` negates, `&&` and `||` combine and parentheses
/// group. `&&` binds tighter than `||` - worth stating outright, because `expression.zig`, the
/// custom-uniform language, deliberately gives them one shared precedence to match a quirk of *that*
/// language, and the two must not be made to agree.
///
/// A malformed expression returns true, which is Iris's behaviour and the safer direction: the
/// failure mode of a directive nobody can parse is a program that still runs, not one silently
/// dropped from the chain.
pub fn evaluateCondition(expression: []const u8, declared: []const Option, unknown: ?*[]const u8) bool {
	var parser = ConditionParser{.text = expression, .declared = declared, .unknown = unknown};
	const value = parser.parseOr() orelse return true;
	parser.skipSpaces();
	// Trailing junk means this was not the language we think it was, so leave the program alone.
	if(parser.position != parser.text.len) return true;
	return value;
}

const ConditionParser = struct {
	text: []const u8,
	declared: []const Option,
	/// Set to the first name that matches no declared option, for the caller to report. That case is
	/// the one way this can wrongly switch a program off, so it is surfaced rather than swallowed.
	unknown: ?*[]const u8 = null,
	position: usize = 0,

	fn skipSpaces(self: *ConditionParser) void {
		while(self.position < self.text.len and (self.text[self.position] == ' ' or self.text[self.position] == '\t')) self.position += 1;
	}

	fn eat(self: *ConditionParser, token: []const u8) bool {
		self.skipSpaces();
		if(!std.mem.startsWith(u8, self.text[self.position..], token)) return false;
		self.position += token.len;
		return true;
	}

	fn parseOr(self: *ConditionParser) ?bool {
		var value = self.parseAnd() orelse return null;
		while(self.eat("||")) {
			const right = self.parseAnd() orelse return null;
			value = value or right;
		}
		return value;
	}

	fn parseAnd(self: *ConditionParser) ?bool {
		var value = self.parseUnary() orelse return null;
		while(self.eat("&&")) {
			const right = self.parseUnary() orelse return null;
			value = value and right;
		}
		return value;
	}

	fn parseUnary(self: *ConditionParser) ?bool {
		if(self.eat("!")) return !(self.parseUnary() orelse return null);
		if(self.eat("(")) {
			const value = self.parseOr() orelse return null;
			if(!self.eat(")")) return null;
			return value;
		}
		return self.parseName();
	}

	fn parseName(self: *ConditionParser) ?bool {
		self.skipSpaces();
		const start = self.position;
		while(self.position < self.text.len and (std.ascii.isAlphanumeric(self.text[self.position]) or self.text[self.position] == '_')) {
			self.position += 1;
		}
		if(self.position == start) return null;
		const name = self.text[start..self.position];

		if(std.mem.eql(u8, name, "true") or std.mem.eql(u8, name, "1")) return true;
		if(std.mem.eql(u8, name, "false") or std.mem.eql(u8, name, "0")) return false;

		for(self.declared) |option| {
			if(!std.mem.eql(u8, option.name, name)) continue;
			// `discover` records a boolean's state as "1" uncommented and "0" commented out; a value
			// option is on for any value other than zero, which is how Iris reads one too.
			return !std.mem.eql(u8, option.current, "0");
		}
		// A name the pack never declares. Iris's option lookup answers false for one, and that is the
		// honest reading - the `#define` is absent, so the feature is off. It is also the only way
		// this can wrongly disable a program, so the caller is told.
		if(self.unknown) |slot| {
			if(slot.*.len == 0) slot.* = name;
		}
		return false;
	}
};

// MARK: tests

const testing = std.testing;
const testingAllocator = main.heap.testingAllocator;

test "value options are discovered with their allowed list" {
	const source = "#define ResolutionScale 0.75    //[0.25 0.5 0.75 1.0]\n";
	const found = discover(testingAllocator, source);
	defer testingAllocator.free(found);
	try testing.expectEqual(@as(usize, 1), found.len);
	try testing.expectEqualStrings("ResolutionScale", found[0].name);
	try testing.expectEqual(Kind.value, found[0].kind);
	try testing.expectEqualStrings("0.75", found[0].current);
	try testing.expectEqualStrings("0.25 0.5 0.75 1.0", found[0].allowed);
}

test "a commented-out define is a boolean that is currently off" {
	const found = discover(testingAllocator, "//#define pomEnabled //parallax\n");
	defer testingAllocator.free(found);
	try testing.expectEqual(@as(usize, 1), found.len);
	try testing.expectEqualStrings("pomEnabled", found[0].name);
	try testing.expectEqual(Kind.boolean, found[0].kind);
	try testing.expectEqualStrings("0", found[0].current);
}

test "a bare define is a boolean that is currently on" {
	const found = discover(testingAllocator, "#define windEffectsEnabled //wind\n");
	defer testingAllocator.free(found);
	try testing.expectEqual(Kind.boolean, found[0].kind);
	try testing.expectEqualStrings("1", found[0].current);
}

test "const options are discovered" {
	const found = discover(testingAllocator, "const int shadowMapResolution = 2048; //[1024 2048 4096]\n");
	defer testingAllocator.free(found);
	try testing.expectEqual(@as(usize, 1), found.len);
	try testing.expectEqualStrings("shadowMapResolution", found[0].name);
	try testing.expectEqual(Kind.constant, found[0].kind);
	try testing.expectEqualStrings("2048", found[0].current);
}

test "overriding a value rewrites the declaring line and keeps the comment" {
	var overrides = Overrides.init(testingAllocator);
	defer overrides.deinit();
	overrides.put("ResolutionScale", "1.0");

	const source = "    #define ResolutionScale 0.75    //[0.25 0.5 0.75 1.0]\nvoid main() {}\n";
	var applied: usize = 0;
	const result = apply(testingAllocator, source, &overrides, &applied);
	defer testingAllocator.free(result);

	try testing.expectEqual(@as(usize, 1), applied);
	try testing.expect(std.mem.indexOf(u8, result, "#define ResolutionScale 1.0") != null);
	// The old value must be gone from the *declaration*; it legitimately survives in the
	// allowed-values comment, which is why this checks the define rather than the whole line.
	try testing.expect(std.mem.indexOf(u8, result, "#define ResolutionScale 0.75") == null);
	// Indentation, the allowed-values comment and unrelated lines all survive.
	try testing.expect(std.mem.startsWith(u8, result, "    #define"));
	try testing.expect(std.mem.indexOf(u8, result, "//[0.25 0.5 0.75 1.0]") != null);
	try testing.expect(std.mem.indexOf(u8, result, "void main() {}") != null);
}

test "turning a boolean off comments its define out" {
	var overrides = Overrides.init(testingAllocator);
	defer overrides.deinit();
	overrides.put("windEffectsEnabled", "0");

	const result = apply(testingAllocator, "#define windEffectsEnabled //wind\n", &overrides, null);
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "//#define windEffectsEnabled") != null);
}

test "turning a boolean on uncomments its define" {
	var overrides = Overrides.init(testingAllocator);
	defer overrides.deinit();
	overrides.put("pomEnabled", "1");

	const result = apply(testingAllocator, "//#define pomEnabled //parallax\n", &overrides, null);
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "#define pomEnabled") != null);
	try testing.expect(std.mem.indexOf(u8, result, "//#define pomEnabled") == null);
}

test "a const override keeps the declared type" {
	var overrides = Overrides.init(testingAllocator);
	defer overrides.deinit();
	overrides.put("shadowMapResolution", "4096");

	const result = apply(testingAllocator, "const int shadowMapResolution = 2048; //[1024 2048 4096]\n", &overrides, null);
	defer testingAllocator.free(result);
	try testing.expect(std.mem.indexOf(u8, result, "const int shadowMapResolution = 4096;") != null);
}

test "source without overrides is returned unchanged" {
	var overrides = Overrides.init(testingAllocator);
	defer overrides.deinit();
	overrides.put("SomethingElse", "1");

	const source = "#define ResolutionScale 0.75\n#define other 2\nvoid main() {}\n";
	const result = apply(testingAllocator, source, &overrides, null);
	defer testingAllocator.free(result);
	try testing.expectEqualStrings(source, result);
}

test "names are matched whole, not by prefix" {
	var overrides = Overrides.init(testingAllocator);
	defer overrides.deinit();
	overrides.put("Shadow", "1");

	// `shadowMapResolution` must not be rewritten by an override named `Shadow`.
	const source = "const int shadowMapResolution = 2048;\n";
	const result = apply(testingAllocator, source, &overrides, null);
	defer testingAllocator.free(result);
	try testing.expectEqualStrings(source, result);
}

// MARK: profile tests

const nostalgiaProfiles =
	\\profile.Low=!cloudVolumeEnabled shadowMapResolution=1024 !ssptEnabled indirectResReduction=4
	\\profile.Medium=profile.Low cloudVolumeEnabled shadowMapResolution=2048
	\\profile.High=profile.Medium shadowFilterIterations=12
	\\
;

fn applyProfile(profiles: *const Profiles, name: []const u8, into: *Overrides) bool {
	var disabled = List([]const u8).init(testingAllocator);
	defer disabled.deinit();
	return profiles.apply(testingAllocator, name, into, &disabled);
}

test "profiles are read in declaration order" {
	var profiles = parseProfiles(testingAllocator, nostalgiaProfiles);
	defer profiles.deinit();
	try testing.expectEqual(@as(usize, 3), profiles.count());
	try testing.expectEqualStrings("Low", profiles.names[0]);
	try testing.expectEqualStrings("High", profiles.names[2]);
}

test "a bare name switches a boolean on and a bang switches it off" {
	var profiles = parseProfiles(testingAllocator, nostalgiaProfiles);
	defer profiles.deinit();

	var overrides = Overrides.init(testingAllocator);
	defer overrides.deinit();
	try testing.expect(applyProfile(&profiles, "Low", &overrides));
	try testing.expectEqualStrings("false", overrides.map.get("cloudVolumeEnabled").?);
	try testing.expectEqualStrings("false", overrides.map.get("ssptEnabled").?);
}

test "a later entry overrides an inherited one" {
	// The property that makes inheritance useful at all: Medium inherits Low's 1024 and must end up
	// at 2048, not the other way round.
	var profiles = parseProfiles(testingAllocator, nostalgiaProfiles);
	defer profiles.deinit();

	var overrides = Overrides.init(testingAllocator);
	defer overrides.deinit();
	try testing.expect(applyProfile(&profiles, "Medium", &overrides));
	try testing.expectEqualStrings("2048", overrides.map.get("shadowMapResolution").?);
	// Inherited untouched values still come through.
	try testing.expectEqualStrings("4", overrides.map.get("indirectResReduction").?);
	// And an inherited `!flag` that the child re-enables ends up on.
	try testing.expectEqualStrings("true", overrides.map.get("cloudVolumeEnabled").?);
}

test "inheritance is transitive" {
	var profiles = parseProfiles(testingAllocator, nostalgiaProfiles);
	defer profiles.deinit();

	var overrides = Overrides.init(testingAllocator);
	defer overrides.deinit();
	try testing.expect(applyProfile(&profiles, "High", &overrides));
	try testing.expectEqualStrings("12", overrides.map.get("shadowFilterIterations").?);
	try testing.expectEqualStrings("2048", overrides.map.get("shadowMapResolution").?);
	try testing.expectEqualStrings("false", overrides.map.get("ssptEnabled").?);
}

test "an explicit user override beats the profile" {
	// A profile is a default; a value the user typed is a decision. Getting this backwards would
	// make the options file look broken whenever a profile was selected.
	var profiles = parseProfiles(testingAllocator, nostalgiaProfiles);
	defer profiles.deinit();

	var overrides = Overrides.init(testingAllocator);
	defer overrides.deinit();
	overrides.put("shadowMapResolution", "4096");
	try testing.expect(applyProfile(&profiles, "High", &overrides));
	try testing.expectEqualStrings("4096", overrides.map.get("shadowMapResolution").?);
}

test "an unknown profile is reported rather than silently ignored" {
	var profiles = parseProfiles(testingAllocator, nostalgiaProfiles);
	defer profiles.deinit();
	var overrides = Overrides.init(testingAllocator);
	defer overrides.deinit();
	try testing.expect(!applyProfile(&profiles, "Ultra", &overrides));
}

test "a recursive profile drops the repeat instead of hanging" {
	var profiles = parseProfiles(testingAllocator, "profile.A=profile.B x=1\nprofile.B=profile.A y=2\n");
	defer profiles.deinit();

	var overrides = Overrides.init(testingAllocator);
	defer overrides.deinit();
	try testing.expect(applyProfile(&profiles, "A", &overrides));
	try testing.expectEqualStrings("1", overrides.map.get("x").?);
	try testing.expectEqualStrings("2", overrides.map.get("y").?);
}

test "disabled programs are collected separately from options" {
	var profiles = parseProfiles(testingAllocator, "profile.Low=!program.composite5 !bloomEnabled\n");
	defer profiles.deinit();

	var overrides = Overrides.init(testingAllocator);
	defer overrides.deinit();
	var disabled = List([]const u8).init(testingAllocator);
	defer disabled.deinit();

	try testing.expect(profiles.apply(testingAllocator, "Low", &overrides, &disabled));
	try testing.expectEqual(@as(usize, 1), disabled.items.len);
	try testing.expectEqualStrings("composite5", disabled.items[0]);
	// The program entry must not also land as an option named `program.composite5`.
	try testing.expectEqual(@as(usize, 1), overrides.count());
	try testing.expectEqualStrings("false", overrides.map.get("bloomEnabled").?);
}

test "a colon separator works like an equals sign" {
	var profiles = parseProfiles(testingAllocator, "profile.P=quality:3\n");
	defer profiles.deinit();
	var overrides = Overrides.init(testingAllocator);
	defer overrides.deinit();
	try testing.expect(applyProfile(&profiles, "P", &overrides));
	try testing.expectEqualStrings("3", overrides.map.get("quality").?);
}

test "a wrapped profile body contributes all of its entries" {
	var profiles = parseProfiles(testingAllocator, "profile.Low=a=1 b=2 \\\n    c=3\n");
	defer profiles.deinit();
	var overrides = Overrides.init(testingAllocator);
	defer overrides.deinit();
	try testing.expect(applyProfile(&profiles, "Low", &overrides));
	try testing.expectEqual(@as(usize, 3), overrides.count());
	try testing.expectEqualStrings("3", overrides.map.get("c").?);
}

// MARK: screen and template tests

const nostalgiaScreens =
	\\screen=INFO <profile> <empty> [ATMOS] [TERRAIN]
	\\screen.columns=1
	\\screen.ATMOS=sunPathRotation <empty> [CLOUDS]
	\\    screen.CLOUDS=cloudVolumeEnabled cloudVolumeRounding
	\\screen.TERRAIN=pomEnabled cloudVolumeEnabled
	\\screen.TERRAIN.columns=2
	\\sliders= sunPathRotation cloudVolumeRounding
	\\
;

test "screen entries name options, and layout tokens are skipped" {
	var screens = parseScreens(testingAllocator, nostalgiaScreens);
	defer screens.deinit();

	// `<profile>`, `<empty>` and `[ATMOS]` are layout; `INFO` is a plain word and does count.
	for(screens.names) |name| {
		try testing.expect(name[0] != '[' and name[0] != '<');
	}
	try testing.expect(findOption(&.{.{.name = "sunPathRotation", .kind = .value, .current = ""}}, "sunPathRotation") != null);

	var sawPom = false;
	for(screens.names) |name| {
		if(std.mem.eql(u8, name, "pomEnabled")) sawPom = true;
	}
	try testing.expect(sawPom);
}

test "an option on two screens is listed once" {
	var screens = parseScreens(testingAllocator, nostalgiaScreens);
	defer screens.deinit();
	var count: usize = 0;
	for(screens.names) |name| {
		if(std.mem.eql(u8, name, "cloudVolumeEnabled")) count += 1;
	}
	try testing.expectEqual(@as(usize, 1), count);
}

test "a columns key is layout, not an option named after its number" {
	var screens = parseScreens(testingAllocator, nostalgiaScreens);
	defer screens.deinit();
	for(screens.names) |name| {
		try testing.expect(!std.mem.eql(u8, name, "1"));
		try testing.expect(!std.mem.eql(u8, name, "2"));
	}
}

test "sliders are recorded separately from screen options" {
	var screens = parseScreens(testingAllocator, nostalgiaScreens);
	defer screens.deinit();
	try testing.expect(screens.isSlider("sunPathRotation"));
	try testing.expect(!screens.isSlider("pomEnabled"));
}

test "options declared in several sources are collected once" {
	const shared = "#define SharedOption 2 //[1 2 3]\n";
	const other = "#define SharedOption 2 //[1 2 3]\n#define OwnOption 1\n";
	const all = discoverAll(testingAllocator, &.{shared, other});
	defer testingAllocator.free(all);

	try testing.expectEqual(@as(usize, 2), all.len);
	try testing.expectEqualStrings("SharedOption", all[0].name);
	try testing.expectEqualStrings("OwnOption", all[1].name);
}

test "the template lists screen options with their allowed values" {
	var screens = parseScreens(testingAllocator, "screen=pomEnabled ResolutionScale\nsliders=ResolutionScale\n");
	defer screens.deinit();
	var profiles = parseProfiles(testingAllocator, nostalgiaProfiles);
	defer profiles.deinit();

	const declared = discoverAll(testingAllocator, &.{
		"//#define pomEnabled //parallax\n#define ResolutionScale 0.75 //[0.25 0.5 0.75 1.0]\n",
	});
	defer testingAllocator.free(declared);

	const text = renderTemplate(testingAllocator, "Nostalgia", declared, &screens, &profiles);
	defer testingAllocator.free(text);

	// The allowed list is the whole point: it is otherwise buried in a comment in the pack's source.
	try testing.expect(std.mem.indexOf(u8, text, "ResolutionScale = 0.75") != null);
	try testing.expect(std.mem.indexOf(u8, text, "0.25 0.5 0.75 1.0") != null);
	// A slider says "range", a cycle says "one of".
	try testing.expect(std.mem.indexOf(u8, text, "# range: 0.25") != null);
	// A commented-out `#define` is a boolean that is off, and reads as the word the parser accepts.
	try testing.expect(std.mem.indexOf(u8, text, "pomEnabled = false") != null);
	// Profiles are offered by name.
	try testing.expect(std.mem.indexOf(u8, text, "# profile = Low") != null);
	try testing.expect(std.mem.indexOf(u8, text, "Low, Medium, High") != null);
}

test "every line of a fresh template is inert" {
	// A generated file must change nothing until someone edits it, or writing one would silently
	// pin every option to whatever the pack happened to declare that day.
	var screens = parseScreens(testingAllocator, "screen=ResolutionScale\n");
	defer screens.deinit();
	var profiles = parseProfiles(testingAllocator, nostalgiaProfiles);
	defer profiles.deinit();
	const declared = discoverAll(testingAllocator, &.{"#define ResolutionScale 0.75 //[0.25 0.5 1.0]\n"});
	defer testingAllocator.free(declared);

	const text = renderTemplate(testingAllocator, "Pack", declared, &screens, &profiles);
	defer testingAllocator.free(text);

	var parsed = Overrides.parse(testingAllocator, text);
	defer parsed.deinit();
	try testing.expectEqual(@as(usize, 0), parsed.count());
}

test "a pack with no screens falls back to options that list allowed values" {
	var screens = parseScreens(testingAllocator, "");
	defer screens.deinit();
	var profiles = parseProfiles(testingAllocator, "");
	defer profiles.deinit();
	const declared = discoverAll(testingAllocator, &.{
		"#define Tunable 2 //[1 2 3]\n#define InternalConstant 4\n",
	});
	defer testingAllocator.free(declared);

	const text = renderTemplate(testingAllocator, "Pack", declared, &screens, &profiles);
	defer testingAllocator.free(text);

	try testing.expect(std.mem.indexOf(u8, text, "Tunable = 2") != null);
	// Without an allowed list it is indistinguishable from an ordinary internal constant, and
	// listing hundreds of those would bury the real options.
	try testing.expect(std.mem.indexOf(u8, text, "InternalConstant") == null);
}

test "the values hint is not read as part of the value" {
	// The generated file ships every option commented out and tells you to uncomment it, so this is
	// the exact text a user ends up with. Taking the hint as part of the value writes it into the
	// pack's declaring line.
	var overrides = Overrides.parse(testingAllocator,
		\\Clouds = 3        # one of: 0 1 2 3 4
		\\SSDO = true        # true or false
		\\
	);
	defer overrides.deinit();
	try testing.expectEqualStrings("3", overrides.map.get("Clouds").?);
	try testing.expectEqualStrings("true", overrides.map.get("SSDO").?);
}

test "setting an option uncomments its line and keeps the hint" {
	const source =
		\\# ---- options ----
		\\# Clouds = 3        # one of: 0 1 2 3 4
		\\# TAA = true        # true or false
		\\
	;
	const updated = updateFile(testingAllocator, source, "Clouds", "1");
	defer testingAllocator.free(updated);
	try testing.expectEqualStrings(
		\\# ---- options ----
		\\Clouds = 1        # one of: 0 1 2 3 4
		\\# TAA = true        # true or false
		\\
	, updated);
}

test "setting an option the file does not mention appends it" {
	const source = "# ---- options ----\n";
	const updated = updateFile(testingAllocator, source, "profile", "High");
	defer testingAllocator.free(updated);
	try testing.expectEqualStrings("# ---- options ----\nprofile = High\n", updated);
}

test "setting an option twice leaves one line" {
	// `Overrides.parse` lets the last entry win, so a leftover duplicate further down would silently
	// override the line the settings screen just wrote.
	const source = "Clouds = 3\nother = 1\nClouds = 4\n";
	const updated = updateFile(testingAllocator, source, "Clouds", "0");
	defer testingAllocator.free(updated);
	var overrides = Overrides.parse(testingAllocator, updated);
	defer overrides.deinit();
	try testing.expectEqualStrings("0", overrides.map.get("Clouds").?);
	try testing.expectEqualStrings("1", overrides.map.get("other").?);
}

test "prose in the header is not mistaken for a setting" {
	const source =
		\\# Uncomment a line and change its value = that is how it works.
		\\# Clouds = 3
		\\
	;
	const updated = updateFile(testingAllocator, source, "Clouds", "2");
	defer testingAllocator.free(updated);
	try testing.expectEqualStrings(
		\\# Uncomment a line and change its value = that is how it works.
		\\Clouds = 2
		\\
	, updated);
}

test "clearing an option comments it out and keeps it visible" {
	const source = "Clouds = 1        # one of: 0 1 2 3 4\nTAA = true\n";
	const updated = updateFile(testingAllocator, source, "Clouds", "");
	defer testingAllocator.free(updated);
	try testing.expectEqualStrings("# Clouds = 1        # one of: 0 1 2 3 4\nTAA = true\n", updated);

	// And the loader then sees no override for it, so the pack's own value applies again.
	var overrides = Overrides.parse(testingAllocator, updated);
	defer overrides.deinit();
	try testing.expect(overrides.map.get("Clouds") == null);
	try testing.expectEqualStrings("true", overrides.map.get("TAA").?);
}

test "clearing an option the file never set adds nothing" {
	const source = "# ---- options ----\n";
	const updated = updateFile(testingAllocator, source, "Clouds", "");
	defer testingAllocator.free(updated);
	try testing.expectEqualStrings(source, updated);
}

test "a round trip through the file reads back what was set" {
	// The property that matters for the settings screen: what it writes is what the loader reads.
	var text: []u8 = testingAllocator.dupe(u8, "# ---- options ----\n# Clouds = 3        # one of: 0 1 2 3 4\n");
	defer testingAllocator.free(text);
	for([_][]const u8{"1", "4", "0"}) |value| {
		const next = updateFile(testingAllocator, text, "Clouds", value);
		testingAllocator.free(text);
		text = next;
		var overrides = Overrides.parse(testingAllocator, text);
		defer overrides.deinit();
		try testing.expectEqualStrings(value, overrides.map.get("Clouds").?);
	}
}

test "the option set reaches a properties macro table in Iris's shape" {
	// Solas's Milky Way, photon's cloud upscaling, a switched-off boolean, a valued define with no
	// list (BSL's render-stage fallback) and a boolean spelling an environment name.
	const source =
		\\#define MILKY_WAY
		\\//#define SNOW_MODE
		\\#define CLOUDS_TEMPORAL_UPSCALING 4 // [1 2 3 4]
		\\const int shadowMapResolution = 2048; //[1024 2048 4096]
		\\#ifndef MC_RENDER_STAGE_MOON
		\\#define MC_RENDER_STAGE_MOON 1
		\\#endif
		\\//#define IS_IRIS
		\\
	;
	const declared = discover(testingAllocator, source);
	defer testingAllocator.free(declared);

	var defines = preprocess.Defines.init(testingAllocator);
	defer defines.deinit();
	defines.putMacroString("MC_RENDER_STAGE_MOON 5");
	defines.putMacroString("IS_IRIS");
	putDefines(&defines, declared);

	try testing.expect(defines.isDefined("MILKY_WAY"));
	try testing.expect(!defines.isDefined("SNOW_MODE"));
	try testing.expectEqualStrings("4", defines.map.get("CLOUDS_TEMPORAL_UPSCALING").?);
	try testing.expectEqualStrings("2048", defines.map.get("shadowMapResolution").?);
	// The environment is never overridden or removed by an option.
	try testing.expectEqualStrings("5", defines.map.get("MC_RENDER_STAGE_MOON").?);
	try testing.expect(defines.isDefined("IS_IRIS"));
	// And the conditions the corpus writes come out the way Iris evaluates them.
	try testing.expect(preprocess.evaluateCondition("CLOUDS_TEMPORAL_UPSCALING == 4", &defines));
	try testing.expect(preprocess.evaluateCondition("defined MILKY_WAY && !defined SNOW_MODE", &defines));
}

test "override files ignore blanks and comments" {
	var overrides = Overrides.parse(testingAllocator,
		\\# a comment
		\\ResolutionScale = 1.0
		\\
		\\shadowMapResolution=4096
		\\
	);
	defer overrides.deinit();
	try testing.expectEqual(@as(usize, 2), overrides.count());
	try testing.expectEqualStrings("1.0", overrides.map.get("ResolutionScale").?);
	try testing.expectEqualStrings("4096", overrides.map.get("shadowMapResolution").?);
}
