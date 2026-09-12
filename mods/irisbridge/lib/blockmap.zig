//! `block.properties`: the pack's block identity table, and how Cubyz's blocks are matched into it.
//!
//! A shaderpack decides what waves, what glows and what is water by reading `mc_Entity.x` and
//! comparing it against numbers it declared itself:
//!
//!     block.10001=water flowing_water
//!     block.1020=torch wall_torch lantern
//!     block.10021=oak_leaves birch_leaves spruce_leaves ...
//!
//! With `mc_Entity` pinned at 0 - which is what the prologue emitted before this file existed -
//! every one of those tests fails, so nothing waves, nothing glows and water renders as ordinary
//! solid terrain. That is the single largest remaining behavioural gap between a pack running here
//! and the same pack running on Minecraft.
//!
//! ## Matching Cubyz blocks to Minecraft names
//!
//! There is no authoritative mapping and there cannot be one: Cubyz is a different game with its
//! own block set. What it does have is a block naming scheme that overlaps Minecraft's heavily -
//! `water`, `lava`, `ice`, `glass`, `torch`, `lantern`, `leaves`, `oak_log`, `sand`, `gravel` and
//! roughly forty more are spelled identically.
//!
//! So the namespace is ignored and the *path* is matched. `cubyz:water` matches the pack's
//! `minecraft:water`, because a comparison including the namespace would match nothing at all and
//! the feature would be dead on arrival.
//!
//! On top of exact matching there is one generalisation, and it earns its place: a pack entry also
//! matches when it ends with `_` followed by the Cubyz path. Minecraft splits by wood type where
//! Cubyz does not, so a pack lists `oak_leaves birch_leaves spruce_leaves ...` and never a bare
//! `leaves` - while Cubyz has exactly one `cubyz:leaves`. Without the suffix rule the most
//! visible foliage in the game would match nothing. The rule is narrow enough to stay safe: the
//! underscore is required, so `seagrass` does not match `grass`.
//!
//! Exact matches always beat suffix matches, and among equals the first declaration wins, which is
//! the ordering Iris relies on (`BlockMaterialMapping` uses `putIfAbsent` for the same reason).
//!
//! ## What is deliberately not supported
//!
//! Block *state* predicates (`tall_grass:half=upper`) are dropped. Cubyz's block `data` field is a
//! rotation/variant code with no named states, so there is nothing to compare a `half=upper`
//! against. Iris itself declines to support them in `item.properties` for a comparable reason.
//! They are counted and reported rather than passed over silently.
//!
//! `layer.*` lines, which move a block between render layers, are also ignored: Cubyz decides
//! transparency from the block definition, and a pack cannot move a block between Cubyz's opaque
//! and transparent meshes from here.

const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const List = main.ListManaged;

const preprocess = @import("preprocess.zig");

/// One name a pack listed under some `block.<id>`.
pub const Entry = struct {
	/// The part after the namespace: `minecraft:oak_leaves` -> `oak_leaves`.
	path: []const u8,
	/// The integer the pack wants `mc_Entity.x` to read for this block.
	id: i32,
	/// True for `%tag` entries, which match a Cubyz tag rather than a block name.
	isTag: bool,
};

pub const Map = struct {
	entries: []Entry = &.{},
	arena: std.heap.ArenaAllocator,
	/// Entries carrying a block-state predicate, which cannot be represented here.
	droppedStateEntries: usize = 0,

	pub fn deinit(self: *Map) void {
		self.arena.deinit();
	}

	/// The pack id for a Cubyz block, or 0 when the pack never mentioned anything matching it.
	///
	/// 0 is the correct miss value rather than a sentinel: it is what `mc_Entity.x` reads for an
	/// ordinary block in Minecraft too, so an unmatched Cubyz block behaves as a plain solid block
	/// instead of accidentally selecting some effect.
	pub fn idFor(self: *const Map, cubyzId: []const u8, tags: []const []const u8) i32 {
		const path = minecraftEquivalent(pathOf(cubyzId));
		if(path.len == 0) return 0;

		// Two passes so an exact match always wins, whatever the declaration order. A pack that
		// lists both `grass` and `short_grass` under different ids must resolve `cubyz:grass` to the
		// one that names it exactly.
		for(self.entries) |entry| {
			if(entry.isTag) continue;
			if(std.mem.eql(u8, entry.path, path)) return entry.id;
		}
		for(self.entries) |entry| {
			if(entry.isTag) continue;
			if(isWoodTypeVariantOf(entry.path, path)) return entry.id;
		}
		// Tags last: a pack naming a block outright meant that block, whereas a tag is a category.
		for(self.entries) |entry| {
			if(!entry.isTag) continue;
			for(tags) |tag| {
				if(std.mem.eql(u8, pathOf(tag), entry.path)) return entry.id;
			}
		}
		return 0;
	}
};

/// Rewrites a Cubyz block path to the Minecraft block the pack means by it.
///
/// The two games use the same word for different blocks. `cubyz:grass` is the solid ground cube
/// - `.model = "cubyz:cube"`, with `cubyz:soil` for its underside. Minecraft's `grass` is the *plant*;
/// its ground block is `grass_block`. Nostalgia lists `grass` in `block.10022` alongside `fern`,
/// `wheat` and the saplings, and `program/gbuffer/solid.vsh` displaces exactly ids 10021-10024 and
/// 10027 by wind - so matching on the bare name made the ground wave like foliage.
///
/// It also spread past the block itself. `blockids.zig` keys its table by *texture index* and stamps
/// a block's id onto all sixteen of its textures, so `cubyz:grass` claiming a foliage id also
/// stamped `cubyz:soil`, and every plain soil block in the world waved too. That is the documented
/// cost of the texture-keyed table showing up for real: a wrong id does not stay on one block.
///
/// The inverse holds as well. Cubyz's actual plants are `*_vegetation`, which matches nothing a pack
/// declares, so the blocks that *should* wave did not.
fn minecraftEquivalent(path: []const u8) []const u8 {
	if(std.mem.startsWith(u8, path, "glass/")) return stainedGlassFor(path["glass/".len..]);
	if(std.mem.endsWith(u8, path, "_vegetation")) {
		const base = path[0 .. path.len - "_vegetation".len];
		// `grass`, `cold_grass`, `dry_grass`, `lush_grass` - all the plant, which Minecraft calls
		// `grass`. The underscore is required so a hypothetical `seagrass_vegetation` is left alone,
		// matching the rule `isWoodTypeVariantOf` already uses.
		if(std.mem.eql(u8, base, "grass") or std.mem.endsWith(u8, base, "_grass")) return "grass";
		return base;
	}
	if(std.mem.eql(u8, path, "grass") or std.mem.endsWith(u8, path, "_grass")) return "grass_block";
	return path;
}

/// Cubyz keeps its glass as `glass/<colour>`: twenty-one colours behind one alpha-0 texture, the
/// colour in each block's `absorbedLight`. Minecraft spells the set `glass` plus sixteen
/// `<dye>_stained_glass`, and that is what packs list - BSL, Complementary, photon, Solas and the
/// voxel packs give the colours separate ids, so the colour has to be named and not just the kind.
/// Before this, no colour matched anything and every pack drew all of them as one unnamed
/// translucent block.
///
/// `white` is Minecraft's plain `glass`: its `absorbedLight` is 0x0f0f0f, all but clear, where
/// `white_stained_glass` is a white-tinted pane. The colours Minecraft has no dye for go to the dye
/// of nearest hue by their transmitted colour - `indigo` (47, 62, 146) is a deep blue, `viridian`
/// (15, 101, 41) a dark green, `uranium` (191, 254, 0) lime - and a colour this table has never
/// heard of goes to `stained_glass`, which the variant rule matches against whichever
/// `<dye>_stained_glass` a pack lists first.
fn stainedGlassFor(colour: []const u8) []const u8 {
	const table = [_]struct {cubyz: []const u8, minecraft: []const u8}{
		.{.cubyz = "white", .minecraft = "glass"},
		.{.cubyz = "aqua", .minecraft = "light_blue_stained_glass"},
		.{.cubyz = "black", .minecraft = "black_stained_glass"},
		.{.cubyz = "blue", .minecraft = "blue_stained_glass"},
		.{.cubyz = "brown", .minecraft = "brown_stained_glass"},
		.{.cubyz = "crimson", .minecraft = "red_stained_glass"},
		.{.cubyz = "cyan", .minecraft = "cyan_stained_glass"},
		.{.cubyz = "dark_grey", .minecraft = "gray_stained_glass"},
		.{.cubyz = "green", .minecraft = "green_stained_glass"},
		.{.cubyz = "grey", .minecraft = "light_gray_stained_glass"},
		.{.cubyz = "indigo", .minecraft = "blue_stained_glass"},
		.{.cubyz = "lime", .minecraft = "lime_stained_glass"},
		.{.cubyz = "magenta", .minecraft = "magenta_stained_glass"},
		.{.cubyz = "orange", .minecraft = "orange_stained_glass"},
		.{.cubyz = "pink", .minecraft = "pink_stained_glass"},
		.{.cubyz = "purple", .minecraft = "purple_stained_glass"},
		.{.cubyz = "red", .minecraft = "red_stained_glass"},
		.{.cubyz = "uranium", .minecraft = "lime_stained_glass"},
		.{.cubyz = "violet", .minecraft = "magenta_stained_glass"},
		.{.cubyz = "viridian", .minecraft = "green_stained_glass"},
		.{.cubyz = "yellow", .minecraft = "yellow_stained_glass"},
	};
	for(table) |entry| {
		if(std.mem.eql(u8, entry.cubyz, colour)) return entry.minecraft;
	}
	return "stained_glass";
}

/// The part of an id after its namespace. Handles both `minecraft:stone` and a bare `stone`.
fn pathOf(id: []const u8) []const u8 {
	const colon = std.mem.lastIndexOfScalar(u8, id, ':') orelse return id;
	return id[colon + 1 ..];
}

/// Whether `candidate` is a wood/colour-prefixed variant of `base`, as in `oak_leaves` of `leaves`.
///
/// The underscore is required rather than a plain `endsWith`, so `seagrass` does not read as a
/// variant of `grass` - those are different plants with different pack behaviour, and a bare
/// suffix test would silently conflate them.
fn isWoodTypeVariantOf(candidate: []const u8, base: []const u8) bool {
	if(candidate.len <= base.len + 1) return false;
	if(!std.mem.endsWith(u8, candidate, base)) return false;
	return candidate[candidate.len - base.len - 1] == '_';
}

/// Reads a `block.properties` source into a name table.
///
/// `defines` seeds the conditionals; packs gate whole sections of this file on `MC_VERSION`, and
/// evaluating those wrong does not merely lose the modern names - the legacy `#else` branch
/// redeclares the same keys, so it *replaces* them.
pub fn parse(allocator: NeverFailingAllocator, source: []const u8, defines: *preprocess.Defines) Map {
	var self = Map{.arena = std.heap.ArenaAllocator.init(allocator.allocator)};
	// An arena over a never-failing backing allocator cannot fail either, which is what the marker
	// field asserts.
	const arena = NeverFailingAllocator{.allocator = self.arena.allocator(), .IAssertThatTheProvidedAllocatorCantFail = {}};

	// Preprocess first, join second. The other order was silently corrupting every entry a pack
	// continues across a conditional - see `preprocess.joinContinuations`, which derives it and
	// records what Iris does to reach the same order from the other direction.
	const stripped = preprocess.run(allocator, source, defines);
	defer allocator.free(stripped);
	const joined = preprocess.joinContinuations(allocator, stripped);
	defer allocator.free(joined);

	var entries = List(Entry).init(arena);

	// `joined` is the final text now that the order is preprocess-then-join; iterating `stripped`
	// here would read the unjoined form and drop every continued entry's tail.
	var lines = std.mem.splitScalar(u8, joined, '\n');
	while(lines.next()) |raw| {
		const line = std.mem.trim(u8, raw, " \t\r");
		if(line.len == 0 or line[0] == '#') continue;
		if(!std.mem.startsWith(u8, line, "block.")) continue;

		const equals = std.mem.indexOfScalar(u8, line, '=') orelse continue;
		const key = std.mem.trim(u8, line["block.".len..equals], " \t");
		const id = std.fmt.parseInt(i32, key, 10) catch continue;

		var parts = std.mem.tokenizeAny(u8, line[equals + 1 ..], " \t");
		while(parts.next()) |part| {
			if(part.len == 0) continue;

			var text = part;
			const isTag = text[0] == '%';
			if(isTag) text = text[1..];
			if(text.len == 0) continue;

			// A state predicate makes this entry conditional on something Cubyz does not model.
			// Counted rather than dropped quietly: a pack whose foliage is mostly `:half=upper`
			// entries would otherwise look like it matched when it did not.
			if(std.mem.indexOfScalar(u8, text, '=') != null) {
				self.droppedStateEntries += 1;
				continue;
			}

			entries.append(.{.path = arena.dupe(u8, pathOf(text)), .id = id, .isTag = isTag});
		}
	}

	self.entries = entries.toOwnedSlice();
	return self;
}

// MARK: tests

const testing = std.testing;
const testingAllocator = main.heap.testingAllocator;

fn modernDefines() preprocess.Defines {
	var defines = preprocess.Defines.init(testingAllocator);
	defines.put("MC_VERSION", "12100");
	return defines;
}

test "a block name resolves to the id the pack declared" {
	var defines = modernDefines();
	defer defines.deinit();
	var map = parse(testingAllocator, "block.10001=water flowing_water\n", &defines);
	defer map.deinit();

	try testing.expectEqual(@as(i32, 10001), map.idFor("cubyz:water", &.{}));
	// A block the pack never mentioned reads as an ordinary solid block, not as some other effect.
	try testing.expectEqual(@as(i32, 0), map.idFor("cubyz:stone", &.{}));
}

test "the namespace is ignored, because no pack knows Cubyz's" {
	var defines = modernDefines();
	defer defines.deinit();
	var map = parse(testingAllocator, "block.10002=minecraft:lava\n", &defines);
	defer map.deinit();
	try testing.expectEqual(@as(i32, 10002), map.idFor("cubyz:lava", &.{}));
}

test "glass resolves to Minecraft's glass, and its colours to the stained glass of the same dye" {
	// Cubyz's `glass/<colour>` blocks share one alpha-0 texture and differ only in absorption, so
	// nothing a pack names ever matched them and every pack drew every colour as the same unnamed
	// translucent block. Complementary, BSL and the voxel packs id the colours separately.
	var defines = modernDefines();
	defer defines.deinit();
	var map = parse(testingAllocator, "block.30000=glass glass_pane\nblock.31000=stained_glass white_stained_glass\nblock.31004=light_blue_stained_glass\nblock.31011=blue_stained_glass\nblock.31014=red_stained_glass\n", &defines);
	defer map.deinit();
	try testing.expectEqual(@as(i32, 30000), map.idFor("cubyz:glass/white", &.{}));
	try testing.expectEqual(@as(i32, 31011), map.idFor("cubyz:glass/blue", &.{}));
	// The dye of nearest hue where Minecraft has none of that name.
	try testing.expectEqual(@as(i32, 31004), map.idFor("cubyz:glass/aqua", &.{}));
	try testing.expectEqual(@as(i32, 31011), map.idFor("cubyz:glass/indigo", &.{}));
	try testing.expectEqual(@as(i32, 31014), map.idFor("cubyz:glass/crimson", &.{}));
	// A colour the table does not know still lands on a stained glass.
	try testing.expectEqual(@as(i32, 31000), map.idFor("cubyz:glass/chartreuse", &.{}));
}

test "a continuation that spans a conditional keeps only the branch that is taken" {
	// Sundial's shape, verbatim in structure: an entry opened with a trailing `\` and then branched
	// inside. Joining before preprocessing pulls `#if` into the middle of the value, where nothing
	// recognises it - the id then collects both branches plus `#if`, `MC_VERSION` and `11300` as if
	// they were block names.
	var defines = modernDefines();
	defer defines.deinit();
	var map = parse(testingAllocator,
		\\block.8192 = \
		\\#if MC_VERSION < 11300
		\\             flowing_water \
		\\#endif
		\\#ifdef IRIS_TAG_SUPPORT
		\\             %minecraft:water \
		\\#endif
		\\             water
		\\
	, &defines);
	defer map.deinit();

	// The taken branches survive the join.
	try testing.expectEqual(@as(i32, 8192), map.idFor("cubyz:water", &.{}));
	// The untaken one does not. `MC_VERSION` is 12100 here, so the 1.12 name must not be mapped -
	// this is the half that a legacy `#else` turns from noise into a wrong answer, since those
	// branches redeclare the same keys rather than merely adding to them.
	for([_][]const u8{"cubyz:flowing_water", "cubyz:MC_VERSION", "cubyz:11300", "cubyz:IRIS_TAG_SUPPORT"}) |name| {
		try testing.expectEqual(@as(i32, 0), map.idFor(name, &.{}));
	}
}

test "a wood-type variant matches the unprefixed Cubyz block" {
	// The case that motivates the rule: modern packs list every wood type and never a bare
	// `leaves`, while Cubyz has exactly one `cubyz:leaves`.
	var defines = modernDefines();
	defer defines.deinit();
	var map = parse(testingAllocator, "block.10021=oak_leaves birch_leaves spruce_leaves\n", &defines);
	defer map.deinit();
	try testing.expectEqual(@as(i32, 10021), map.idFor("cubyz:leaves", &.{}));
	try testing.expectEqual(@as(i32, 10021), map.idFor("cubyz:oak_leaves", &.{}));
}

test "the variant rule requires an underscore" {
	// `seagrass` must not read as a variant of `grass`: they are different plants and packs give
	// them different waving behaviour.
	var defines = modernDefines();
	defer defines.deinit();
	var map = parse(testingAllocator, "block.10027=seagrass\n", &defines);
	defer map.deinit();
	// The plant, so the underscore rule is what is being tested rather than `minecraftEquivalent`
	// rewriting the ground block out of the way.
	try testing.expectEqual(@as(i32, 0), map.idFor("cubyz:grass_vegetation", &.{}));
}

test "an exact match beats a variant match regardless of order" {
	var defines = modernDefines();
	defer defines.deinit();
	// `tall_grass` is declared first and would win a single-pass scan.
	var map = parse(testingAllocator, "block.10023=tall_grass\nblock.10022=grass\n", &defines);
	defer map.deinit();
	// The vegetation block, since that is what Minecraft's bare `grass` names - see
	// `minecraftEquivalent`. The property under test is the two-pass ordering, not which block.
	try testing.expectEqual(@as(i32, 10022), map.idFor("cubyz:grass_vegetation", &.{}));
}

test "tags match Cubyz's own tags and lose to a named block" {
	var defines = modernDefines();
	defer defines.deinit();
	var map = parse(testingAllocator, "block.500=%minecraft:logs\nblock.501=oak_log\n", &defines);
	defer map.deinit();

	try testing.expectEqual(@as(i32, 500), map.idFor("cubyz:birch_log", &.{"cubyz:logs"}));
	// Named outright, so the tag does not get a say.
	try testing.expectEqual(@as(i32, 501), map.idFor("cubyz:oak_log", &.{"cubyz:logs"}));
}

test "state predicates are dropped and counted" {
	var defines = modernDefines();
	defer defines.deinit();
	var map = parse(testingAllocator, "block.10023=tall_grass:half=lower sunflower:half=lower fern\n", &defines);
	defer map.deinit();

	try testing.expectEqual(@as(usize, 2), map.droppedStateEntries);
	// The entry without a predicate still lands.
	try testing.expectEqual(@as(i32, 10023), map.idFor("cubyz:fern", &.{}));
}

test "the version conditional picks the modern names" {
	// Nostalgia's real structure. The legacy branch redeclares the same key, so evaluating this
	// wrong replaces the modern names rather than merely missing them.
	var defines = modernDefines();
	defer defines.deinit();
	const source =
		\\#if MC_VERSION >= 11300
		\\block.10021=oak_leaves birch_leaves
		\\#else
		\\block.10021=leaves leaves2
		\\#endif
		\\
	;
	var map = parse(testingAllocator, source, &defines);
	defer map.deinit();

	try testing.expectEqual(@as(usize, 2), map.entries.len);
	try testing.expectEqualStrings("oak_leaves", map.entries[0].path);
}

test "continued lines contribute all of their names" {
	var defines = modernDefines();
	defer defines.deinit();
	const source = "block.1002=redstone_block magma_block \\\n    beacon crying_obsidian\n";
	var map = parse(testingAllocator, source, &defines);
	defer map.deinit();

	try testing.expectEqual(@as(usize, 4), map.entries.len);
	try testing.expectEqual(@as(i32, 1002), map.idFor("cubyz:beacon", &.{}));
}

test "layer lines and comments are ignored" {
	var defines = modernDefines();
	defer defines.deinit();
	var map = parse(testingAllocator, "## a comment\nlayer.solid=nether_portal\nblock.7=ice\n", &defines);
	defer map.deinit();

	try testing.expectEqual(@as(usize, 1), map.entries.len);
	try testing.expectEqual(@as(i32, 7), map.idFor("cubyz:ice", &.{}));
}
