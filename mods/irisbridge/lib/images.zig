//! Iris custom images and shader storage buffers: `image.<name>` and `bufferObject.N` in
//! `shaders.properties`.
//!
//! A pack declares an image once and writes it from anywhere. The shadow pass voxelises the world
//! into `voxel_img` through `imageStore`, a `shadowcomp` compute floods light through the volume,
//! and the deferred pass samples the result through `voxel_sampler` - the same texture under two
//! names. Every pack in the corpus but Kappa and Nostalgia declares at least one, and the two
//! voxel packs refuse to load without the three feature flags this module stands behind
//! (`pipeline.supportedFeatures`).
//!
//! The images are textures with a sampler view and an image view, as Iris's `GlImage`: allocated
//! at load (`IrisRenderingPipeline.java:229-238`), the ones marked `clear` zeroed before every
//! frame (`:864`), the relative ones re-sized with the window (`:933`), nearest-filtered when
//! integer and clamped on every axis (`GlImage.setup`). Buffers are immutable storage, zeroed once
//! and bound to their point for the life of the pack (`ShaderStorageBufferHolder`) - at
//! `storageBindingBase + N` here rather than at N, see `glsl.Options.storageBindingBase`.

const std = @import("std");

const main = @import("main");
const c = main.c;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const List = main.ListManaged;

const pack = @import("pack.zig");
const targets = @import("targets.zig");
const packtextures = @import("packtextures.zig");

pub const maxImages = pack.maxImages;

/// The first texture unit an image's sampler view lands on, past the noise and LabPBR units. Image
/// `i` samples from `samplerUnitBase + i` in every program, draw or compute, so one layout serves
/// them all - the same reason `colortexN` has one unit everywhere.
pub const samplerUnitBase: c_uint = packtextures.specularUnit + 1;

/// Where `bufferObject.N` is bound, and what a pack's `binding = N` is rewritten to. Above every
/// point Cubyz's own shaders use - 1, 3, 4, 6, 8, 9, 10 and 11 (`prologue.bindingsMatchEngine`,
/// `blockids.binding`) - with Iris's nine indices after it. A gbuffers program carries both sets at
/// once, so the two ranges cannot overlap anywhere.
pub const storageBindingBase: c_uint = 16;

pub const Image = struct {
	declaration: pack.ImageDeclaration,
	id: c_uint = 0,
	/// `GL_TEXTURE_1D`, `_2D` or `_3D`, named by both the sampler bind and the allocation.
	target: c_uint,
	format: targets.GlFormat,
	samplerUnit: c_uint,
	/// The current allocation, after any resize; a 1D image has no height and a 2D one no depth.
	width: u32 = 0,
	height: u32 = 0,
	depth: u32 = 0,
};

pub const Buffer = struct {
	index: u8,
	declaration: pack.BufferObject,
	id: c_uint = 0,
	binding: c_uint,
	bytes: u64 = 0,
};

pub const Set = struct {
	allocator: NeverFailingAllocator = undefined,
	/// The parsed declarations, owned here because every `Image` borrows its name and sampler
	/// name from them; released with `pack.freeImages` in `deinit`.
	declarations: []pack.ImageDeclaration = &.{},
	images: []Image = &.{},
	buffers: []Buffer = &.{},
	width: u31 = 1,
	height: u31 = 1,

	/// Takes ownership of `declarations`, the result of `pack.parseImages`.
	pub fn init(allocator: NeverFailingAllocator, declarations: []pack.ImageDeclaration, bufferObjects: [pack.maxBufferObjects]?pack.BufferObject, width: u31, height: u31) Set {
		var self = Set{.allocator = allocator, .declarations = declarations, .width = @max(width, 1), .height = @max(height, 1)};

		var images = List(Image).init(allocator);
		for(declarations, 0..) |declaration, index| {
			var image = Image{
				.declaration = declaration,
				.target = switch(declaration.shape) {
					.oneD => @intCast(c.GL_TEXTURE_1D),
					.twoD, .relative => @intCast(c.GL_TEXTURE_2D),
					.threeD => @intCast(c.GL_TEXTURE_3D),
				},
				.format = targets.glFormat(declaration.format),
				.samplerUnit = samplerUnitBase + @as(c_uint, @intCast(index)),
			};
			c.glGenTextures(1, &image.id);
			allocate(&image, self.width, self.height);
			images.append(image);
		}
		self.images = images.toOwnedSlice();

		var buffers = List(Buffer).init(allocator);
		var maxBindings: c_int = 8;
		c.glGetIntegerv(c.GL_MAX_SHADER_STORAGE_BUFFER_BINDINGS, &maxBindings);
		for(bufferObjects, 0..) |declared, index| {
			const declaration = declared orelse continue;
			const binding = storageBindingBase + @as(c_uint, @intCast(index));
			if(binding >= @as(c_uint, @intCast(@max(maxBindings, 0)))) {
				std.log.err("irisbridge: bufferObject.{} needs storage binding point {}, and this driver has {}; the buffer is not allocated", .{index, binding, maxBindings});
				continue;
			}
			var buffer = Buffer{.index = @intCast(index), .declaration = declaration, .binding = binding};
			c.glGenBuffers(1, &buffer.id);
			if(!allocateBuffer(&buffer, self.width, self.height)) {
				c.glDeleteBuffers(1, &buffer.id);
				continue;
			}
			buffers.append(buffer);
		}
		self.buffers = buffers.toOwnedSlice();
		c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, 0);
		return self;
	}

	pub fn deinit(self: *Set) void {
		for(self.images) |*image| c.glDeleteTextures(1, &image.id);
		for(self.buffers) |*buffer| {
			c.glBindBufferBase(c.GL_SHADER_STORAGE_BUFFER, buffer.binding, 0);
			c.glDeleteBuffers(1, &buffer.id);
		}
		if(self.images.len != 0) self.allocator.free(self.images);
		if(self.buffers.len != 0) self.allocator.free(self.buffers);
		pack.freeImages(self.allocator, self.declarations);
		self.declarations = &.{};
		self.images = &.{};
		self.buffers = &.{};
	}

	/// Re-sizes what follows the screen: relative images, and buffers declared per screen texel.
	pub fn updateSize(self: *Set, width: u31, height: u31) void {
		const newWidth = @max(width, 1);
		const newHeight = @max(height, 1);
		if(newWidth == self.width and newHeight == self.height) return;
		self.width = newWidth;
		self.height = newHeight;
		for(self.images) |*image| {
			if(image.declaration.shape != .relative) continue;
			allocate(image, self.width, self.height);
		}
		for(self.buffers) |*buffer| {
			if(!buffer.declaration.relative) continue;
			// Immutable storage cannot be re-specified, so the buffer name is replaced, as Iris's
			// `ShaderStorageBuffer.resizeIfRelative` does.
			c.glDeleteBuffers(1, &buffer.id);
			c.glGenBuffers(1, &buffer.id);
			if(!allocateBuffer(buffer, self.width, self.height)) {
				std.log.err("irisbridge: bufferObject.{} could not be re-allocated for the new window size", .{buffer.index});
			}
		}
		c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, 0);
	}

	/// Zeroes every image the pack marked `clear`, before the frame.
	pub fn clearPerFrame(self: *const Set) void {
		for(self.images) |*image| {
			if(!image.declaration.clear) continue;
			clear(image);
		}
	}

	/// Puts each image with a sampler name on its unit, for the program about to run.
	pub fn bindSamplers(self: *const Set) void {
		if(self.images.len == 0) return;
		for(self.images) |*image| {
			if(image.declaration.samplerName == null) continue;
			c.glActiveTexture(@as(c_uint, @intCast(c.GL_TEXTURE0)) + image.samplerUnit);
			c.glBindTexture(image.target, image.id);
		}
		c.glActiveTexture(c.GL_TEXTURE0);
	}

	/// Points a program's image samplers at their units.
	pub fn bindSamplerUniforms(self: *const Set, program: c_uint) void {
		var name: [128]u8 = undefined;
		for(self.images) |*image| {
			const samplerName = image.declaration.samplerName orelse continue;
			const text = std.fmt.bufPrintZ(&name, "{s}", .{samplerName}) catch continue;
			const location = c.glGetUniformLocation(program, text.ptr);
			if(location >= 0) c.glUniform1i(location, @intCast(image.samplerUnit));
		}
	}

	/// Binds every buffer to its point. Iris does this once and relies on nothing touching the
	/// points; here it is repeated each frame, which costs a handful of calls and rules out any
	/// engine bind on the same point ever taking a buffer away.
	pub fn bindBuffers(self: *const Set) void {
		for(self.buffers) |*buffer| {
			c.glBindBufferBase(c.GL_SHADER_STORAGE_BUFFER, buffer.binding, buffer.id);
		}
	}

	pub fn imageIndex(self: *const Set, name: []const u8) ?usize {
		for(self.images, 0..) |*image, index| {
			if(std.mem.eql(u8, image.declaration.name, name)) return index;
		}
		return null;
	}

	/// Whether a storage block bound at `binding` has a pack buffer behind it.
	pub fn hasBufferBinding(self: *const Set, binding: c_uint) bool {
		for(self.buffers) |*buffer| {
			if(buffer.binding == binding) return true;
		}
		return false;
	}

	/// The names this set supplies to programs - every image and every sampler view - so the
	/// coverage report does not list them as uniforms nothing provides.
	pub fn appendSuppliedNames(self: *const Set, out: *List([]const u8)) void {
		for(self.images) |*image| {
			out.append(image.declaration.name);
			if(image.declaration.samplerName) |samplerName| out.append(samplerName);
		}
	}

	/// One line per image and buffer, for the load log.
	pub fn describe(self: *const Set, allocator: NeverFailingAllocator) []u8 {
		var text = List(u8).init(allocator);
		for(self.images) |*image| {
			text.print("\n    image {s}: {s} {s} {}", .{image.declaration.name, @tagName(image.declaration.shape), @tagName(image.declaration.format), image.width});
			if(image.height != 0) text.print("x{}", .{image.height});
			if(image.depth != 0) text.print("x{}", .{image.depth});
			if(image.declaration.samplerName) |samplerName| text.print(", sampled as {s} on unit {}", .{samplerName, image.samplerUnit});
			if(image.declaration.clear) text.appendSlice(", cleared per frame");
		}
		for(self.buffers) |*buffer| {
			text.print("\n    bufferObject.{}: {} bytes at binding {}{s}", .{buffer.index, buffer.bytes, buffer.binding, if(buffer.declaration.relative) " (per screen texel)" else ""});
		}
		return text.toOwnedSlice();
	}
};

/// (Re)specifies an image's storage at the size its declaration resolves to, sets Iris's sampling
/// state, and zeroes it.
fn allocate(image: *Image, screenWidth: u31, screenHeight: u31) void {
	const declaration = image.declaration;
	switch(declaration.shape) {
		.relative => {
			// Truncated as Iris's `(int) (currentWidth * relativeWidth)` is, never zero.
			image.width = @max(1, @as(u32, @intFromFloat(@as(f32, @floatFromInt(screenWidth))*declaration.relativeWidth)));
			image.height = @max(1, @as(u32, @intFromFloat(@as(f32, @floatFromInt(screenHeight))*declaration.relativeHeight)));
			image.depth = 0;
		},
		else => {
			image.width = declaration.width;
			image.height = declaration.height;
			image.depth = declaration.depth;
		},
	}

	c.glBindTexture(image.target, image.id);
	switch(declaration.shape) {
		.oneD => c.glTexImage1D(c.GL_TEXTURE_1D, 0, image.format.internal, @intCast(image.width), 0, image.format.format, image.format.dataType, null),
		.twoD, .relative => c.glTexImage2D(c.GL_TEXTURE_2D, 0, image.format.internal, @intCast(image.width), @intCast(image.height), 0, image.format.format, image.format.dataType, null),
		.threeD => c.glTexImage3D(c.GL_TEXTURE_3D, 0, image.format.internal, @intCast(image.width), @intCast(image.height), @intCast(image.depth), 0, image.format.format, image.format.dataType, null),
	}
	// Integer texels can only be sampled nearest; everything else linear, as `GlImage.setup`.
	const filter: c_int = if(targets.isIntegerFormat(declaration.format)) c.GL_NEAREST else c.GL_LINEAR;
	c.glTexParameteri(image.target, c.GL_TEXTURE_MIN_FILTER, filter);
	c.glTexParameteri(image.target, c.GL_TEXTURE_MAG_FILTER, filter);
	c.glTexParameteri(image.target, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
	if(image.height != 0) c.glTexParameteri(image.target, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
	if(image.depth != 0) c.glTexParameteri(image.target, c.GL_TEXTURE_WRAP_R, c.GL_CLAMP_TO_EDGE);
	// One level only: an image is written by shaders, never mipmapped, and a linear-mipmap filter
	// over a chain nobody built samples an undefined level.
	c.glTexParameteri(image.target, c.GL_TEXTURE_MAX_LEVEL, 0);
	c.glBindTexture(image.target, 0);

	// A fresh allocation is undefined memory, and Iris clears every image on creation
	// (`GlImage.setup`), the `clear = false` ones included.
	clear(image);
}

/// Fills an image with zeros. A null pointer to `glClearTexImage` is the zero texel in the
/// texture's own format, whatever that format is.
fn clear(image: *const Image) void {
	c.glClearTexImage(image.id, 0, image.format.format, image.format.dataType, null);
}

/// Gives a buffer its immutable storage, zeroed, and binds it to its point.
fn allocateBuffer(buffer: *Buffer, screenWidth: u31, screenHeight: u31) bool {
	const declaration = buffer.declaration;
	// Iris: `(long) (width * scaleX)` by `(long) (height * scaleY)` texels of `size` bytes each.
	const bytes: u64 = if(declaration.relative) blk: {
		const columns: u64 = @intFromFloat(@max(0, @as(f32, @floatFromInt(screenWidth))*declaration.scaleX));
		const rows: u64 = @intFromFloat(@max(0, @as(f32, @floatFromInt(screenHeight))*declaration.scaleY));
		break :blk @max(1, columns*rows)*declaration.size;
	} else declaration.size;

	var maxBlock: c_int = 0;
	c.glGetIntegerv(c.GL_MAX_SHADER_STORAGE_BLOCK_SIZE, &maxBlock);
	if(maxBlock > 0 and bytes > @as(u64, @intCast(maxBlock))) {
		std.log.err("irisbridge: bufferObject.{} asks for {} bytes, over the driver's {} per storage block; the buffer is not allocated", .{buffer.index, bytes, maxBlock});
		return false;
	}

	// Errors are read before and after: a stale error from earlier in the frame must not be
	// blamed on this allocation, and an out-of-memory here is the one GL error worth a message.
	while(c.glGetError() != c.GL_NO_ERROR) {}
	c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, buffer.id);
	c.glBufferStorage(c.GL_SHADER_STORAGE_BUFFER, @intCast(bytes), null, 0);
	const err = c.glGetError();
	if(err != c.GL_NO_ERROR) {
		std.log.err("irisbridge: bufferObject.{} could not be allocated at {} bytes (GL error {}); the buffer is not available", .{buffer.index, bytes, err});
		c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, 0);
		return false;
	}
	// Zeroed as Iris zeroes it (`clearBufferSubData(GL_R8, ..., GL_RED, GL_BYTE, {0})`): a pack
	// reads its counters and hash tables before it has ever written them.
	const zero: u8 = 0;
	c.glClearBufferData(c.GL_SHADER_STORAGE_BUFFER, c.GL_R8, c.GL_RED, c.GL_UNSIGNED_BYTE, &zero);
	c.glBindBufferBase(c.GL_SHADER_STORAGE_BUFFER, buffer.binding, buffer.id);
	buffer.bytes = bytes;
	return true;
}
