//! Minimal stand-in for Cubyz's `main` module, so `glsl.zig` can be tested without building the
//! whole game. Only the surface `glsl.zig` actually touches is implemented.

const std = @import("std");

/// The real Cubyz vector maths, not a stand-in. `src/vec.zig` imports nothing but `std`, so it is
/// passed in as its own module and the matrix tests exercise exactly the code the engine uses.
pub const vec = @import("vec");

pub const heap = struct {
	pub const NeverFailingAllocator = struct {
		allocator: std.mem.Allocator,
		/// Carried over from the engine's real type. It is inert, but code under test constructs
		/// this struct by hand, so a stub without the field would compile here and fail there -
		/// exactly the divergence a stub is supposed to avoid.
		IAssertThatTheProvidedAllocatorCantFail: void = {},

		pub fn alloc(self: NeverFailingAllocator, comptime T: type, n: usize) []T {
			return self.allocator.alloc(T, n) catch unreachable;
		}

		pub fn free(self: NeverFailingAllocator, memory: anytype) void {
			self.allocator.free(memory);
		}

		pub fn dupe(self: NeverFailingAllocator, comptime T: type, m: []const T) []T {
			return self.allocator.dupe(T, m) catch unreachable;
		}

		pub fn realloc(self: NeverFailingAllocator, old: anytype, n: usize) @TypeOf(old) {
			return self.allocator.realloc(old, n) catch unreachable;
		}
	};

	pub const testingAllocator = NeverFailingAllocator{.allocator = std.testing.allocator};
};

pub var stackAllocator = heap.NeverFailingAllocator{.allocator = std.testing.allocator};

pub fn ListManaged(comptime T: type) type {
	return struct {
		const Self = @This();

		items: []T,
		capacity: usize,
		allocator: heap.NeverFailingAllocator,

		pub fn init(allocator: heap.NeverFailingAllocator) Self {
			return .{.items = &.{}, .capacity = 0, .allocator = allocator};
		}

		pub fn deinit(self: Self) void {
			self.allocator.free(self.items.ptr[0..self.capacity]);
		}

		fn ensure(self: *Self, extra: usize) void {
			if(self.items.len + extra <= self.capacity) return;
			const newCapacity = @max(self.items.len + extra, @max(self.capacity*2, 16));
			const old = self.items.ptr[0..self.capacity];
			const new = self.allocator.alloc(T, newCapacity);
			@memcpy(new[0..self.items.len], self.items);
			self.allocator.free(old);
			self.items = new[0..self.items.len];
			self.capacity = newCapacity;
		}

		pub fn append(self: *Self, item: T) void {
			self.ensure(1);
			self.items.len += 1;
			self.items[self.items.len - 1] = item;
		}

		pub fn appendSlice(self: *Self, slice: []const T) void {
			self.ensure(slice.len);
			const start = self.items.len;
			self.items.len += slice.len;
			@memcpy(self.items[start..], slice);
		}

		/// Mirrors `src/utils/list.zig`'s `print`, which grows without limit.
		///
		/// It used to format into a fixed `[1024]u8` and `catch unreachable` the overflow, which
		/// made the stub fail where the real type succeeds - the precise divergence this file's
		/// header says a stub exists to avoid. `prologue.skyVertex` emits a ~1.8 KB block in one
		/// call, so the first test ever to cover it panicked with `NoSpaceLeft` on code the engine
		/// runs happily every load.
		pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) void {
			var writer = std.Io.Writer.Allocating.init(self.allocator.allocator);
			defer writer.deinit();
			writer.writer.print(fmt, args) catch unreachable;
			self.appendSlice(writer.written());
		}

		pub fn pop(self: *Self) T {
			const item = self.items[self.items.len - 1];
			self.items.len -= 1;
			return item;
		}

		pub fn clearRetainingCapacity(self: *Self) void {
			self.items.len = 0;
		}

		pub fn toOwnedSlice(self: *Self) []T {
			const result = self.allocator.realloc(self.items.ptr[0..self.capacity], self.items.len);
			self.* = Self.init(self.allocator);
			return result;
		}
	};
}
