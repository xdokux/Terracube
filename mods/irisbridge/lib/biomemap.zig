//! The biome a pack thinks the player is standing in.
//!
//! Iris supplies `biome` as an integer id, `biome_category` as one of its own enum ordinals,
//! `biome_precipitation`, `temperature` and `rainfall` from the Minecraft biome under the player, and
//! defines a `BIOME_<NAME>` constant per registered biome for the custom-uniform language, so packs
//! write `in(biome, BIOME_SWAMP, BIOME_MANGROVE_SWAMP)` to decide whether the world is a swamp.
//!
//! Cubyz has biomes, and the client tracks the current one (`game.World.playerBiome`), but they are
//! not Minecraft's and carry no temperature or downfall. So this does for biomes what `blockmap`
//! does for blocks: match the Cubyz biome's *name* to a Minecraft biome and answer with that one's
//! climate. `cubyz:swamp/base` is a swamp; `cubyz:tundra/...` is snowy plains; `cubyz:rare/...`
//! matches nothing and reports a temperate default rather than the zeros an unsupplied uniform
//! would give - which read as a frozen biome to every pack and turned snow effects on everywhere.
//!
//! The climate numbers are Minecraft's own per-biome values, so a pack tuned against them sees the
//! world it expects. The ids are indices into the table below and only have to be self-consistent:
//! packs compare `biome` against the `BIOME_*` constants, never against literals - the one literal
//! form in the corpus, BSL's `in(biome, 6, 134)`, sits behind the OptiFine branch of an `#ifdef`.

const std = @import("std");

/// Iris's `BiomeCategories`, by ordinal - what `biome_category` reports.
pub const Category = enum(i32) {
	none = 0,
	taiga = 1,
	extremeHills = 2,
	jungle = 3,
	mesa = 4,
	plains = 5,
	savanna = 6,
	icy = 7,
	theEnd = 8,
	beach = 9,
	forest = 10,
	ocean = 11,
	desert = 12,
	river = 13,
	swamp = 14,
	mushroom = 15,
	nether = 16,
	mountain = 17,
	underground = 18,
};

/// `biome_precipitation`, as Iris encodes it.
pub const Precipitation = enum(i32) {none = 0, rain = 1, snow = 2};

pub const Entry = struct {
	/// The Minecraft path, which is also the `BIOME_<NAME>` constant in upper case.
	name: []const u8,
	category: Category,
	temperature: f32,
	downfall: f32,
	precipitation: Precipitation,
};

/// Minecraft's overworld biomes with their vanilla climate, plus the two other dimensions' for
/// completeness of the constant set. Order defines the ids.
pub const entries = [_]Entry{
	.{.name = "the_void", .category = .none, .temperature = 0.5, .downfall = 0.5, .precipitation = .none},
	.{.name = "plains", .category = .plains, .temperature = 0.8, .downfall = 0.4, .precipitation = .rain},
	.{.name = "sunflower_plains", .category = .plains, .temperature = 0.8, .downfall = 0.4, .precipitation = .rain},
	.{.name = "snowy_plains", .category = .icy, .temperature = 0.0, .downfall = 0.5, .precipitation = .snow},
	.{.name = "ice_spikes", .category = .icy, .temperature = 0.0, .downfall = 0.5, .precipitation = .snow},
	.{.name = "desert", .category = .desert, .temperature = 2.0, .downfall = 0.0, .precipitation = .none},
	.{.name = "swamp", .category = .swamp, .temperature = 0.8, .downfall = 0.9, .precipitation = .rain},
	.{.name = "mangrove_swamp", .category = .swamp, .temperature = 0.8, .downfall = 0.9, .precipitation = .rain},
	.{.name = "forest", .category = .forest, .temperature = 0.7, .downfall = 0.8, .precipitation = .rain},
	.{.name = "flower_forest", .category = .forest, .temperature = 0.7, .downfall = 0.8, .precipitation = .rain},
	.{.name = "birch_forest", .category = .forest, .temperature = 0.6, .downfall = 0.6, .precipitation = .rain},
	.{.name = "dark_forest", .category = .forest, .temperature = 0.7, .downfall = 0.8, .precipitation = .rain},
	.{.name = "old_growth_birch_forest", .category = .forest, .temperature = 0.6, .downfall = 0.6, .precipitation = .rain},
	.{.name = "old_growth_pine_taiga", .category = .taiga, .temperature = 0.3, .downfall = 0.8, .precipitation = .rain},
	.{.name = "old_growth_spruce_taiga", .category = .taiga, .temperature = 0.25, .downfall = 0.8, .precipitation = .rain},
	.{.name = "taiga", .category = .taiga, .temperature = 0.25, .downfall = 0.8, .precipitation = .rain},
	.{.name = "snowy_taiga", .category = .taiga, .temperature = -0.5, .downfall = 0.4, .precipitation = .snow},
	.{.name = "savanna", .category = .savanna, .temperature = 2.0, .downfall = 0.0, .precipitation = .none},
	.{.name = "savanna_plateau", .category = .savanna, .temperature = 2.0, .downfall = 0.0, .precipitation = .none},
	.{.name = "windswept_hills", .category = .extremeHills, .temperature = 0.2, .downfall = 0.3, .precipitation = .rain},
	.{.name = "windswept_gravelly_hills", .category = .extremeHills, .temperature = 0.2, .downfall = 0.3, .precipitation = .rain},
	.{.name = "windswept_forest", .category = .extremeHills, .temperature = 0.2, .downfall = 0.3, .precipitation = .rain},
	.{.name = "windswept_savanna", .category = .savanna, .temperature = 2.0, .downfall = 0.0, .precipitation = .none},
	.{.name = "jungle", .category = .jungle, .temperature = 0.95, .downfall = 0.9, .precipitation = .rain},
	.{.name = "sparse_jungle", .category = .jungle, .temperature = 0.95, .downfall = 0.8, .precipitation = .rain},
	.{.name = "bamboo_jungle", .category = .jungle, .temperature = 0.95, .downfall = 0.9, .precipitation = .rain},
	.{.name = "badlands", .category = .mesa, .temperature = 2.0, .downfall = 0.0, .precipitation = .none},
	.{.name = "eroded_badlands", .category = .mesa, .temperature = 2.0, .downfall = 0.0, .precipitation = .none},
	.{.name = "wooded_badlands", .category = .mesa, .temperature = 2.0, .downfall = 0.0, .precipitation = .none},
	.{.name = "meadow", .category = .mountain, .temperature = 0.5, .downfall = 0.8, .precipitation = .rain},
	.{.name = "cherry_grove", .category = .mountain, .temperature = 0.5, .downfall = 0.8, .precipitation = .rain},
	.{.name = "grove", .category = .mountain, .temperature = -0.2, .downfall = 0.8, .precipitation = .snow},
	.{.name = "snowy_slopes", .category = .mountain, .temperature = -0.3, .downfall = 0.9, .precipitation = .snow},
	.{.name = "frozen_peaks", .category = .mountain, .temperature = -0.7, .downfall = 0.9, .precipitation = .snow},
	.{.name = "jagged_peaks", .category = .mountain, .temperature = -0.7, .downfall = 0.9, .precipitation = .snow},
	.{.name = "stony_peaks", .category = .mountain, .temperature = 1.0, .downfall = 0.3, .precipitation = .rain},
	.{.name = "river", .category = .river, .temperature = 0.5, .downfall = 0.5, .precipitation = .rain},
	.{.name = "frozen_river", .category = .river, .temperature = 0.0, .downfall = 0.5, .precipitation = .snow},
	.{.name = "beach", .category = .beach, .temperature = 0.8, .downfall = 0.4, .precipitation = .rain},
	.{.name = "snowy_beach", .category = .beach, .temperature = 0.05, .downfall = 0.3, .precipitation = .snow},
	.{.name = "stony_shore", .category = .beach, .temperature = 0.2, .downfall = 0.3, .precipitation = .rain},
	.{.name = "warm_ocean", .category = .ocean, .temperature = 0.5, .downfall = 0.5, .precipitation = .rain},
	.{.name = "lukewarm_ocean", .category = .ocean, .temperature = 0.5, .downfall = 0.5, .precipitation = .rain},
	.{.name = "deep_lukewarm_ocean", .category = .ocean, .temperature = 0.5, .downfall = 0.5, .precipitation = .rain},
	.{.name = "ocean", .category = .ocean, .temperature = 0.5, .downfall = 0.5, .precipitation = .rain},
	.{.name = "deep_ocean", .category = .ocean, .temperature = 0.5, .downfall = 0.5, .precipitation = .rain},
	.{.name = "cold_ocean", .category = .ocean, .temperature = 0.5, .downfall = 0.5, .precipitation = .rain},
	.{.name = "deep_cold_ocean", .category = .ocean, .temperature = 0.5, .downfall = 0.5, .precipitation = .rain},
	.{.name = "frozen_ocean", .category = .ocean, .temperature = 0.0, .downfall = 0.5, .precipitation = .snow},
	.{.name = "deep_frozen_ocean", .category = .ocean, .temperature = 0.5, .downfall = 0.5, .precipitation = .snow},
	.{.name = "mushroom_fields", .category = .mushroom, .temperature = 0.9, .downfall = 1.0, .precipitation = .rain},
	.{.name = "dripstone_caves", .category = .underground, .temperature = 0.8, .downfall = 0.4, .precipitation = .rain},
	.{.name = "lush_caves", .category = .underground, .temperature = 0.5, .downfall = 0.5, .precipitation = .rain},
	.{.name = "deep_dark", .category = .underground, .temperature = 0.8, .downfall = 0.4, .precipitation = .rain},
	.{.name = "pale_garden", .category = .forest, .temperature = 0.7, .downfall = 0.8, .precipitation = .rain},
	.{.name = "nether_wastes", .category = .nether, .temperature = 2.0, .downfall = 0.0, .precipitation = .none},
	.{.name = "warped_forest", .category = .nether, .temperature = 2.0, .downfall = 0.0, .precipitation = .none},
	.{.name = "crimson_forest", .category = .nether, .temperature = 2.0, .downfall = 0.0, .precipitation = .none},
	.{.name = "soul_sand_valley", .category = .nether, .temperature = 2.0, .downfall = 0.0, .precipitation = .none},
	.{.name = "basalt_deltas", .category = .nether, .temperature = 2.0, .downfall = 0.0, .precipitation = .none},
	.{.name = "the_end", .category = .theEnd, .temperature = 0.5, .downfall = 0.5, .precipitation = .none},
	.{.name = "end_highlands", .category = .theEnd, .temperature = 0.5, .downfall = 0.5, .precipitation = .none},
	.{.name = "end_midlands", .category = .theEnd, .temperature = 0.5, .downfall = 0.5, .precipitation = .none},
	.{.name = "small_end_islands", .category = .theEnd, .temperature = 0.5, .downfall = 0.5, .precipitation = .none},
	.{.name = "end_barrens", .category = .theEnd, .temperature = 0.5, .downfall = 0.5, .precipitation = .none},
};

/// What a pack sees while no biome is known or matched: plains. Neutral in every effect a pack
/// keys on climate, where the zeros of an unsupplied uniform read as arctic.
pub const fallback = entries[1];

/// Cubyz biome families and the Minecraft biome each stands in for.
///
/// Cubyz names its biomes by family directory - `cubyz:desert/oasis`, `cubyz:tundra/...` - and it
/// is the family that carries the climate. Matched on that first path segment, so every variant of
/// a family lands on one answer.
const equivalents = [_]struct {family: []const u8, vanilla: []const u8}{
	.{.family = "autumn", .vanilla = "forest"},
	.{.family = "beach", .vanilla = "beach"},
	.{.family = "bog", .vanilla = "swamp"},
	.{.family = "bush_lands", .vanilla = "plains"},
	.{.family = "bush_mountains", .vanilla = "windswept_forest"},
	.{.family = "cave", .vanilla = "dripstone_caves"},
	.{.family = "desert", .vanilla = "desert"},
	.{.family = "ferrock_mountains", .vanilla = "windswept_hills"},
	.{.family = "forest", .vanilla = "forest"},
	.{.family = "glacier", .vanilla = "ice_spikes"},
	.{.family = "grassland", .vanilla = "plains"},
	.{.family = "highlands", .vanilla = "meadow"},
	.{.family = "hills", .vanilla = "windswept_hills"},
	.{.family = "jungle", .vanilla = "jungle"},
	.{.family = "limestone_mountains", .vanilla = "windswept_hills"},
	.{.family = "mountains", .vanilla = "windswept_hills"},
	.{.family = "ocean", .vanilla = "ocean"},
	.{.family = "peak", .vanilla = "jagged_peaks"},
	.{.family = "plateau", .vanilla = "savanna_plateau"},
	.{.family = "prairie", .vanilla = "plains"},
	.{.family = "rocky_grassland", .vanilla = "windswept_gravelly_hills"},
	.{.family = "savannah", .vanilla = "savanna"},
	.{.family = "snowcapped_hill", .vanilla = "snowy_slopes"},
	.{.family = "swamp", .vanilla = "swamp"},
	.{.family = "taiga", .vanilla = "taiga"},
	.{.family = "tall_mountain", .vanilla = "jagged_peaks"},
	.{.family = "thicket", .vanilla = "dark_forest"},
	.{.family = "tundra", .vanilla = "snowy_plains"},
	.{.family = "volcano", .vanilla = "stony_peaks"},
	.{.family = "wetlands", .vanilla = "swamp"},
};

/// The id of a Minecraft biome by path, or null.
pub fn idOf(name: []const u8) ?i32 {
	for(entries, 0..) |entry, index| {
		if(std.mem.eql(u8, entry.name, name)) return @intCast(index);
	}
	return null;
}

/// The value of a `BIOME_<NAME>`, `CAT_<CATEGORY>` or `PPT_<PRECIPITATION>` constant as the
/// custom-uniform language sees it, or null when the name is not one.
///
/// Iris defines the first two families side by side (`IrisDefines.java:28-33`): one `BIOME_`
/// constant per registered biome, and one `CAT_` per `BiomeCategories` ordinal, the enum name in
/// upper case - so `CAT_EXTREME_HILLS` and `CAT_THE_END`, which is where `Category` above needs the
/// spelling converted. Kappa's entire weather chain and photon's biome effects compare
/// `biome_category` against these, and every one of those uniforms was dropped with
/// `UnknownVariable` while the constants were missing.
///
/// `PPT_NONE`, `PPT_RAIN` and `PPT_SNOW` are OptiFine's names for the three values
/// `biome_precipitation` takes, and are not in Iris 1.7.3 at all. Supplied anyway: the encoding is
/// the one `BiomeUniforms.java:42` reports, so they can only make a comparison evaluate that would
/// otherwise be dropped. Kappa spells its precipitation rule against them, commented out in v5.3.
pub fn constant(name: []const u8) ?i32 {
	if(std.mem.startsWith(u8, name, "BIOME_")) {
		const upper = name["BIOME_".len..];
		for(entries, 0..) |entry, index| {
			if(std.ascii.eqlIgnoreCase(entry.name, upper)) return @intCast(index);
		}
		return null;
	}
	if(std.mem.startsWith(u8, name, "CAT_")) return enumConstant(Category, name["CAT_".len..]);
	if(std.mem.startsWith(u8, name, "PPT_")) return enumConstant(Precipitation, name["PPT_".len..]);
	return null;
}

/// The ordinal of the enum field whose upper-snake spelling is `upper`: `extremeHills` answers to
/// `EXTREME_HILLS`. That is how Iris's constant names relate to the enums above.
fn enumConstant(comptime Enum: type, upper: []const u8) ?i32 {
	inline for(@typeInfo(Enum).@"enum".fields) |field| {
		if(std.mem.eql(u8, upper, comptime upperSnake(field.name))) return field.value;
	}
	return null;
}

fn upperSnake(comptime camel: []const u8) []const u8 {
	comptime {
		var out: [camel.len*2]u8 = undefined;
		var len: usize = 0;
		for(camel) |ch| {
			if(std.ascii.isUpper(ch)) {
				out[len] = '_';
				len += 1;
			}
			out[len] = std.ascii.toUpper(ch);
			len += 1;
		}
		const result = out[0..len].*;
		return &result;
	}
}

/// The Minecraft biome standing in for a Cubyz biome id such as `cubyz:swamp/base`, or null when
/// the family is not one this table knows.
pub fn equivalent(cubyzId: []const u8) ?*const Entry {
	const path = if(std.mem.indexOfScalar(u8, cubyzId, ':')) |colon| cubyzId[colon + 1 ..] else cubyzId;
	const family = if(std.mem.indexOfScalar(u8, path, '/')) |slash| path[0..slash] else path;
	for(equivalents) |pair| {
		if(!std.mem.eql(u8, pair.family, family)) continue;
		const id = idOf(pair.vanilla) orelse return null;
		return &entries[@intCast(id)];
	}
	return null;
}

// MARK: tests

const testing = std.testing;

test "every equivalence names a biome the table has" {
	// A typo here would silently turn a family into "no match", which is the fallback climate.
	for(equivalents) |pair| try testing.expect(idOf(pair.vanilla) != null);
}

test "constants resolve to the id the uniform reports for the same biome" {
	try testing.expectEqual(idOf("swamp").?, constant("BIOME_SWAMP").?);
	try testing.expectEqual(idOf("snowy_plains").?, constant("BIOME_SNOWY_PLAINS").?);
	try testing.expectEqual(@as(?i32, null), constant("BIOME_NOT_A_PLACE"));
	try testing.expectEqual(@as(?i32, null), constant("viewWidth"));
}

test "category and precipitation constants carry Iris's ordinals" {
	// `CAT_<NAME>` is the `BiomeCategories` ordinal, and the two-word names are the ones a naive
	// spelling of the enum field would get wrong.
	try testing.expectEqual(@as(?i32, 0), constant("CAT_NONE"));
	try testing.expectEqual(@as(?i32, 2), constant("CAT_EXTREME_HILLS"));
	try testing.expectEqual(@as(?i32, 8), constant("CAT_THE_END"));
	try testing.expectEqual(@as(?i32, 12), constant("CAT_DESERT"));
	try testing.expectEqual(@as(?i32, 18), constant("CAT_UNDERGROUND"));
	try testing.expectEqual(@as(?i32, 0), constant("PPT_NONE"));
	try testing.expectEqual(@as(?i32, 1), constant("PPT_RAIN"));
	try testing.expectEqual(@as(?i32, 2), constant("PPT_SNOW"));
	try testing.expectEqual(@as(?i32, null), constant("CAT_TUNDRA"));
	try testing.expectEqual(@as(?i32, null), constant("PPT_HAIL"));
	try testing.expectEqual(@as(?i32, null), constant("CAT_"));
	// The constant and the uniform it is compared against agree, which is all a pack relies on.
	const desert = equivalent("cubyz:desert/base").?;
	try testing.expectEqual(@intFromEnum(desert.category), constant("CAT_DESERT").?);
	try testing.expectEqual(@intFromEnum(desert.precipitation), constant("PPT_NONE").?);
}

test "a Cubyz biome matches by family, whatever the variant" {
	try testing.expectEqualStrings("swamp", equivalent("cubyz:swamp/base").?.name);
	try testing.expectEqualStrings("swamp", equivalent("cubyz:wetlands/marsh").?.name);
	try testing.expectEqualStrings("snowy_plains", equivalent("cubyz:tundra/base").?.name);
	try testing.expectEqualStrings("desert", equivalent("cubyz:desert/hoodoos/mound").?.name);
	try testing.expectEqual(@as(?*const Entry, null), equivalent("cubyz:rare/crystal_cave"));
}

test "the climate a pack keys on is Minecraft's" {
	const desert = equivalent("cubyz:desert/base").?;
	try testing.expectEqual(Precipitation.none, desert.precipitation);
	try testing.expectEqual(Category.desert, desert.category);
	const tundra = equivalent("cubyz:tundra/base").?;
	try testing.expectEqual(Precipitation.snow, tundra.precipitation);
	try testing.expect(tundra.temperature < 0.15);
	try testing.expectEqual(@as(i32, 14), @intFromEnum(Category.swamp));
}
