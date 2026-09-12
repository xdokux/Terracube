//! The GPU side of `mc_Entity`: a texture-index-keyed table of pack block ids.
//!
//! `blockmap.zig` decides *which* pack id each Cubyz block should report. This file gets that
//! answer to the vertex shader, and the way it does so is forced by what Cubyz's geometry actually
//! carries.
//!
//! ## Why the table is keyed by texture, not by block
//!
//! A chunk face is one `FaceData` in an SSBO:
//!
//!     position: {x: u5, y: u5, z: u5, isBackFace: bool, lightIndex: u16}
//!     blockAndQuad: {texture: u16, quadIndex: QuadIndex}
//!
//! Despite the field name, there is no block type in there - only a texture index. The block a
//! face came from is not recoverable in the shader, and putting it there would mean widening
//! `FaceData`, which is the hottest buffer in the renderer and is mirrored in four shaders plus
//! this mod's prologue.
//!
//! So the mapping is inverted on the CPU instead: for every block, every one of its sixteen
//! orientation textures is stamped with that block's pack id. The face's texture index then reads
//! the answer directly, at no per-vertex cost.
//!
//! The cost of the inversion is that two blocks sharing one texture must share one id. That is
//! genuinely ambiguous rather than a shortcut being taken, so a conflict is counted and reported
//! instead of being resolved silently - and the blocks packs care about (water, lava, leaves,
//! torches, foliage) all have textures of their own, which is why the approach is worth its
//! limitation.

const std = @import("std");

const main = @import("main");
const c = main.c;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const List = main.ListManaged;

const blockmap = @import("blockmap.zig");

/// SSBO binding for the table.
///
/// Cubyz's own shaders occupy 0-10 and 12; 11 is the one gap below them, which keeps this inside
/// the range every driver supports rather than relying on a generous
/// `GL_MAX_SHADER_STORAGE_BUFFER_BINDINGS`.
pub const binding: c_uint = 11;

/// Bit marking a texture as belonging to a fluid block.
///
/// Packed into the same table rather than given a second SSBO: the key is identical (texture index),
/// binding points are a scarce documented resource here, and the prologue reads both facts from one
/// fetch. Bit 30 is clear of every id the fixture packs use - Complementary's highest is 32004 - and
/// clear of the sign bit.
///
/// Why the shader needs to know at all. Minecraft renders water at 14/16 of a block, so a water
/// surface sits at `y = N + 0.875`; Cubyz's water is `.model = "cubyz:cube"`, a full cube whose
/// surface sits at an integer. Packs key on that height. Complementary's foam gate is
/// `clamp((fract(worldPos.y) - 0.7) * 10.0, 0.0, 1.0)`, which is a stable 0.875 in Minecraft and
/// lands exactly on a floating-point boundary in Cubyz - so `fract` rounds to either 0.99998 or
/// 0.00002 depending on the pixel and the frame, and the foam flickers on and off wholesale.
///
/// This is the same class as the Z-up basis change and the sea-level offset: reshape what the pack
/// sees so its own maths is asked a question it can answer, rather than patching the symptom.
pub const fluidBit: i32 = 1 << 30;

/// Bits 26 to 29 of an entry: the block's light emission on Minecraft's 0-15 scale, which Iris
/// hands packs in `at_midBlock.w` (`MixinChunkRenderRebuildTask.java:52`, `blockState.
/// getLightEmission()`) behind the `BLOCK_EMISSION_ATTRIBUTE` flag. Mellow's coloured lights
/// require the flag, and Rethinking Voxels, Nostalgic Red Voxels and Bliss read the value to
/// find light sources for their voxel lighting - so with it at zero, a torch lit nothing in any
/// of them. Above the id, which Iris itself keeps to a 16-bit short, and below the fluid bit.
pub const emissionShift = 26;
pub const emissionMask: i32 = 15 << emissionShift;

/// The pack id half of a table entry, once the emission and fluid bits are masked off.
pub const idMask: i32 = (1 << emissionShift) - 1;

/// Minecraft's light level for a Cubyz `emittedLight` colour: the strongest channel, on 0-15, so
/// a torch (0xa58d73) is 10 and lava (0xff7b00) 15. Zero for a block that emits nothing.
pub fn emissionLevel(emittedLight: u32) u4 {
	const r = (emittedLight >> 16) & 255;
	const g = (emittedLight >> 8) & 255;
	const b = emittedLight & 255;
	const strongest = @max(r, @max(g, b));
	return @intCast((strongest*15 + 127)/255);
}

/// One table entry: the id in the low bits, the emission above it, the fluid bit on top.
pub fn packEntry(id: i32, isFluid: bool, emission: u4) i32 {
	return (id & idMask) | (@as(i32, emission) << emissionShift) | (if(isFluid) fluidBit else 0);
}

pub const Table = struct {
	buffer: c_uint = 0,
	/// Block count the table was built for, so a world change rebuilds it.
	builtForBlockCount: u32 = 0,
	length: usize = 0,
	matchedBlocks: usize = 0,
	conflicts: usize = 0,
	/// Blocks carrying Cubyz's `fluid` tag, whose top rim is lowered to Minecraft's 14/16 height.
	///
	/// Counted and logged because a zero here is indistinguishable from the height fix being the
	/// wrong idea: both leave the water exactly where it was. This project's notes are explicit that
	/// a fix with an observable consequence has to log it, and that a silent no-op reads as a failed
	/// hypothesis.
	fluidBlocks: usize = 0,

	pub fn deinit(self: *Table) void {
		if(self.buffer != 0) c.glDeleteBuffers(1, &self.buffer);
		self.buffer = 0;
	}

	pub fn bind(self: *const Table) void {
		if(self.buffer == 0) return;
		c.glBindBufferBase(c.GL_SHADER_STORAGE_BUFFER, binding, self.buffer);
	}
};

/// Number of orientations `blocks.meshes.textureIndex` accepts before it switches to indexing by
/// block *data* rather than block type. Only the first sixteen describe this block's own faces.
const orientationCount = 16;

/// Builds the texture-index table from the pack's block map and Cubyz's live block registry.
///
/// The buffer is always created, even with no world loaded and no `block.properties` to read. The
/// prologue declares this SSBO unconditionally and calls `.length()` on it, and `.length()` against
/// an *unbound* binding point is undefined rather than zero - so "nothing to map" has to be
/// expressed as a real one-element buffer of zeroes, not as an absent one.
pub fn build(allocator: NeverFailingAllocator, map: *const blockmap.Map) Table {
	var self = Table{};
	const blockCount = main.blocks.typeCount();
	self.builtForBlockCount = blockCount;

	// One pass to find how far the texture indices reach, so the table is exactly as long as it
	// needs to be and the shader's bounds check has something meaningful to compare against.
	var highestTexture: u32 = 0;
	for(0..blockCount) |typ| {
		const block = main.blocks.Block{.typ = @intCast(typ), .data = 0};
		for(0..orientationCount) |orientation| {
			highestTexture = @max(highestTexture, main.blocks.meshes.textureIndex(block, orientation));
		}
	}

	const table = allocator.alloc(i32, @max(highestTexture + 1, 1));
	defer allocator.free(table);
	@memset(table, 0);

	var tagNames = List([]const u8).init(allocator);
	defer tagNames.deinit();

	for(0..blockCount) |typ| {
		const block = main.blocks.Block{.typ = @intCast(typ), .data = 0};

		tagNames.clearRetainingCapacity();
		for(block.tags()) |tag| tagNames.append(tag.getName());

		const id = map.idFor(block.id(), tagNames.items);
		// Fluid is Cubyz's own tag, not anything the pack declares, so it is recorded even for a
		// block the pack maps to nothing - the water-height convention it drives is a property of
		// the two engines rather than of any one shaderpack.
		var isFluid = false;
		for(tagNames.items) |tag| {
			if(std.mem.eql(u8, tag, "fluid")) isFluid = true;
		}
		// Emission is Cubyz's own too, so a light source the pack never named still reports it.
		const emission = emissionLevel(block.light());
		if(id == 0 and !isFluid and emission == 0) continue;
		if(id != 0) self.matchedBlocks += 1;
		const entry = packEntry(id, isFluid, emission);

		for(0..orientationCount) |orientation| {
			const texture = main.blocks.meshes.textureIndex(block, orientation);
			// Two different blocks resolving to two different ids through one shared texture is the
			// one case this encoding cannot represent. First writer wins, matching the first-wins
			// rule `blockmap.idFor` already uses, and the count surfaces it.
			//
			// Compared on the id half only: the fluid bit is not in conflict with anything, and a
			// fluid sharing a texture with a mapped block must not be counted as an id clash.
			const existing = table[texture];
			if(existing & idMask != 0 and existing & idMask != id) {
				self.conflicts += 1;
				continue;
			}
			table[texture] = existing | entry;
		}
	}

	c.glGenBuffers(1, &self.buffer);
	c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, self.buffer);
	c.glBufferData(c.GL_SHADER_STORAGE_BUFFER, @intCast(table.len*@sizeOf(i32)), table.ptr, c.GL_STATIC_DRAW);
	c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, 0);
	self.length = table.len;
	return self;
}

/// Rebuilds the table when the block registry has changed underneath it.
///
/// The registry is repopulated on every world load, and the pipeline outlives that. Comparing the
/// block count catches it: a different world registers a different number of blocks, and the only
/// case this misses - two worlds with identical block counts but different block sets - needs a
/// different addon set at the same size, which no vanilla configuration produces.
pub fn rebuildIfStale(allocator: NeverFailingAllocator, self: *Table, map: *const blockmap.Map) void {
	const blockCount = main.blocks.typeCount();
	if(blockCount == self.builtForBlockCount) return;
	self.deinit();
	self.* = build(allocator, map);
	if(self.length != 0) {
		std.log.info("irisbridge: mc_Entity table built for {} block(s), {} matched the pack{s}", .{
			blockCount,
			self.matchedBlocks,
			if(self.conflicts != 0) " (with shared-texture conflicts)" else "",
		});
		if(self.conflicts != 0) {
			std.log.warn("irisbridge: {} texture(s) are shared by blocks the pack maps differently; the first id wins", .{self.conflicts});
		}
	}
}

// MARK: tests

const testing = std.testing;

test "emission is the strongest channel on Minecraft's scale, and packs beside the id and fluid bit" {
	// Iris hands `blockState.getLightEmission()` over in `at_midBlock.w`; Cubyz has a colour.
	try testing.expectEqual(@as(u4, 0), emissionLevel(0));
	try testing.expectEqual(@as(u4, 15), emissionLevel(0xffffff));
	try testing.expectEqual(@as(u4, 10), emissionLevel(0xa58d73));
	try testing.expectEqual(@as(u4, 15), emissionLevel(0xff7b00));
	try testing.expectEqual(@as(u4, 4), emissionLevel(0x214200));

	const entry = packEntry(10001, true, 14);
	try testing.expectEqual(@as(i32, 10001), entry & idMask);
	try testing.expectEqual(@as(i32, 14), (entry >> emissionShift) & 15);
	try testing.expect(entry & fluidBit != 0);
	// An id the size of anything a pack writes fits under the emission bits.
	try testing.expectEqual(@as(i32, 65535), packEntry(65535, false, 0) & idMask);
	try testing.expectEqual(@as(i32, 0), packEntry(65535, false, 0) & emissionMask);
}
