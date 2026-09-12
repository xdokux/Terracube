const std = @import("std");

const main = @import("main");
const game = main.game;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const ContinuousSlider = @import("../components/ContinuousSlider.zig");
const CheckBox = @import("../components/CheckBox.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeIfMouseIsGrabbed = true,
};

const padding: f32 = 8;

fn flySpeedCallback(newValue: f32) void {
	game.Freecam.flySpeed = newValue;
}
fn flySpeedFormatter(allocator: main.heap.NeverFailingAllocator, value: f32) []const u8 {
	return std.fmt.allocPrint(allocator.allocator, "#ffffffFly Speed: {d:.0}", .{value}) catch unreachable;
}

fn sprintMultiplierCallback(newValue: f32) void {
	game.Freecam.sprintMultiplier = newValue;
}
fn sprintMultiplierFormatter(allocator: main.heap.NeverFailingAllocator, value: f32) []const u8 {
	return std.fmt.allocPrint(allocator.allocator, "#ffffffSprint Multiplier: {d:.1}x", .{value}) catch unreachable;
}

fn showPlayerModelCallback(newValue: bool) void {
	game.Freecam.showPlayerModel = newValue;
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(ContinuousSlider.init(.{0, 0}, 128, 5.0, 200.0, @floatCast(game.Freecam.flySpeed), &flySpeedCallback, &flySpeedFormatter));
	list.add(ContinuousSlider.init(.{0, 0}, 128, 1.0, 10.0, @floatCast(game.Freecam.sprintMultiplier), &sprintMultiplierCallback, &sprintMultiplierFormatter));
	list.add(CheckBox.init(.{0, 0}, 128, "Show player model", game.Freecam.showPlayerModel, &showPlayerModelCallback));
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}
