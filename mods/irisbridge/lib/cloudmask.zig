//! A stand-in for Minecraft's `textures/environment/clouds.png`.
//!
//! Packs bind the game's own cloud texture into a stage with a line like Mellow's
//! `texture.deferred.colortex3=minecraft:textures/environment/clouds.png` or photon's
//! `texture.deferred.depthtex2=minecraft:textures/environment/clouds.png`, and read its alpha as a
//! tiling cloud mask: white where a cloud is, transparent where the sky is clear, 256 texels to the
//! side, blocky. Cubyz ships no such file and nothing may be downloaded, so the binding used to be
//! skipped, which left the sampler on whatever occupied that unit - a screen-sized render target
//! for Mellow, whose blocky clouds then stepped through the alpha of its own colour buffer.
//!
//! The mask here is tiling value noise thresholded to Minecraft's coverage. It is not the original
//! image, and a pack keyed to particular cloud shapes will draw different clouds; what it keeps is
//! everything a shader can measure - the size, the binary alpha, the tiling and the coverage - so
//! the pack's cloud code runs against data of the kind it was written for.
//!
//! Free of GL so the coverage and tiling can be tested.

const std = @import("std");

/// The asset path packs name, as Iris resolves it.
pub const minecraftPath = "minecraft:textures/environment/clouds.png";

/// Side length of the vanilla texture, which packs assume when they step it texel by texel.
pub const size: usize = 256;

/// Bytes in the RGBA8 image `fill` produces.
pub const byteCount: usize = size*size*4;

fn hash(x: u32, y: u32, octave: u32) f32 {
	var h: u32 = x*%374761393 +% y*%668265263 +% octave*%2246822519;
	h = (h ^ (h >> 13))*%1274126177;
	h ^= h >> 16;
	return @as(f32, @floatFromInt(h & 0xffff))/65535.0;
}

fn smoothstep(t: f32) f32 {
	return t*t*(3.0 - 2.0*t);
}

/// Value noise on a lattice of `cells` points per side, sampled at texel (x, y) with the lattice
/// wrapping, so the result tiles at `size`.
fn lattice(x: usize, y: usize, cells: u32, octave: u32) f32 {
	const cellSize: f32 = @as(f32, @floatFromInt(size))/@as(f32, @floatFromInt(cells));
	const fx = @as(f32, @floatFromInt(x))/cellSize;
	const fy = @as(f32, @floatFromInt(y))/cellSize;
	const x0: u32 = @intFromFloat(@floor(fx));
	const y0: u32 = @intFromFloat(@floor(fy));
	const tx = smoothstep(fx - @floor(fx));
	const ty = smoothstep(fy - @floor(fy));
	const x1 = (x0 + 1)%cells;
	const y1 = (y0 + 1)%cells;
	const top = hash(x0, y0, octave)*(1 - tx) + hash(x1, y0, octave)*tx;
	const bottom = hash(x0, y1, octave)*(1 - tx) + hash(x1, y1, octave)*tx;
	return top*(1 - ty) + bottom*ty;
}

/// Coverage-weighted noise in [0, 1] at one texel: three octaves, the coarsest dominant, so the
/// clouds come out as blobs a few dozen texels across with ragged edges rather than as static.
pub fn density(x: usize, y: usize) f32 {
	return lattice(x, y, 4, 1)*0.55 + lattice(x, y, 8, 2)*0.3 + lattice(x, y, 16, 3)*0.15;
}

/// Where the mask reads as cloud. Minecraft's texture covers roughly a third of its area; value
/// noise piles up near the middle of its range, so the cut sits just above it.
pub const threshold: f32 = 0.53;

/// Writes the RGBA8 image into `out`, which must hold `byteCount` bytes: opaque white on a cloud
/// texel, transparent black elsewhere, exactly the two values the vanilla image holds.
pub fn fill(out: []u8) void {
	std.debug.assert(out.len >= byteCount);
	for(0..size) |y| {
		for(0..size) |x| {
			const cloud = density(x, y) > threshold;
			const value: u8 = if(cloud) 255 else 0;
			const index = (y*size + x)*4;
			out[index + 0] = value;
			out[index + 1] = value;
			out[index + 2] = value;
			out[index + 3] = value;
		}
	}
}

const testing = std.testing;

test "the mask covers roughly a third of the sky, in blobs rather than static" {
	const pixels = try testing.allocator.alloc(u8, byteCount);
	defer testing.allocator.free(pixels);
	fill(pixels);

	var covered: usize = 0;
	var edges: usize = 0;
	for(0..size) |y| {
		for(0..size) |x| {
			const here = pixels[(y*size + x)*4 + 3];
			if(here == 255) covered += 1;
			// A transition between neighbouring texels. Static would have one at nearly every
			// texel; blobs a few dozen texels across have far fewer.
			const right = pixels[(y*size + (x + 1)%size)*4 + 3];
			if(here != right) edges += 1;
		}
	}
	const coverage = @as(f32, @floatFromInt(covered))/@as(f32, @floatFromInt(size*size));
	try testing.expect(coverage > 0.2 and coverage < 0.5);
	const edgeRate = @as(f32, @floatFromInt(edges))/@as(f32, @floatFromInt(size*size));
	try testing.expect(edgeRate < 0.1);
	try testing.expect(edgeRate > 0.005);
}

test "the mask tiles and holds only the two vanilla values" {
	const pixels = try testing.allocator.alloc(u8, byteCount);
	defer testing.allocator.free(pixels);
	fill(pixels);
	for(pixels) |byte| try testing.expect(byte == 0 or byte == 255);
	// The lattice wraps, so the density is continuous across the seam: a texel on the last column
	// and its neighbour on the first differ by no more than adjacent texels elsewhere do.
	var seamJump: f32 = 0;
	var interiorJump: f32 = 0;
	for(0..size) |y| {
		seamJump = @max(seamJump, @abs(density(size - 1, y) - density(0, y)));
		interiorJump = @max(interiorJump, @abs(density(100, y) - density(101, y)));
	}
	try testing.expect(seamJump <= interiorJump*1.5 + 0.02);
}
