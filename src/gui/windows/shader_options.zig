const std = @import("std");

const main = @import("main");
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const HorizontalList = @import("../components/HorizontalList.zig");
const Label = @import("../components/Label.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window = GuiWindow{
	.contentSize = Vec2f{192, 256},
	.closeIfMouseIsGrabbed = true,
};

const padding: f32 = 8;

/// The loaded pack's options, owned for as long as the window is open.
///
/// Buttons carry an *index* into this rather than a name, because a callback gets one pointer-sized
/// payload and nothing else. Rebuilt on every open, so editing `<pack>.options.txt` by hand while
/// the game runs shows up here without a restart.
var packOptions: main.ListManaged(main.renderer.ShaderPackOption) = undefined;
var listInitialised: bool = false;

fn freeOptions() void {
	if (!listInitialised) return;
	for (packOptions.items) |option| option.free(main.globalAllocator);
	packOptions.deinit();
	listInitialised = false;
}

/// A button's payload: which option it belongs to, and which way it steps.
///
/// One `usize` is all a callback carries, so the direction rides in the low bit. Stepping backwards
/// matters because a pack's sliders declare long value lists — Sildur's `shadowDistance` offers 35 —
/// and a forward-only control makes overshooting cost a full lap.
fn payloadFor(index: usize, backwards: bool) usize {
	return index << 1 | @intFromBool(backwards);
}

fn cycleOption(payload: usize) void {
	const index = payload >> 1;
	const backwards = payload & 1 != 0;
	if (index >= packOptions.items.len) return;
	const option = packOptions.items[index];
	if (option.values.len == 0) return;

	// Where the current value sits in the list. A value the pack does not offer — the "not set"
	// placeholder on the profile row, or something typed into the file by hand — has no position, so
	// stepping starts from the beginning rather than from an invented index.
	var position: ?usize = null;
	for (option.values, 0..) |value, i| {
		if (std.mem.eql(u8, value, option.value)) {
			position = i;
			break;
		}
	}

	const next = if (position) |current|
		(if (backwards) (current + option.values.len - 1) % option.values.len else (current + 1) % option.values.len)
	else if (backwards) option.values.len - 1 else 0;

	main.renderer.renderhook.setPackOption(option.name, option.values[next]);
	refreshRequested = true;
}

/// Drops an option's override, so the pack's own declared value applies again.
///
/// Without this the screen could set a value but never unset one: every option would be pinned to
/// whatever it was last clicked to, with no way back to what the pack shipped.
fn resetOption(index: usize) void {
	if (index >= packOptions.items.len) return;
	main.renderer.renderhook.setPackOption(packOptions.items[index].name, "");
	refreshRequested = true;
}

var refreshRequested: bool = false;

pub fn update() void {
	if (!refreshRequested) return;
	refreshRequested = false;
	onClose();
	onOpen();
}

pub fn onOpen() void {
	freeOptions();
	packOptions = .init(main.globalAllocator);
	listInitialised = true;
	main.renderer.renderhook.listPackOptions(main.globalAllocator, &packOptions);

	const list = VerticalList.init(.{padding, 16 + padding}, 320, 8);
	list.add(Label.init(.{0, 0}, 288, "#ffffffShader Options", .center));

	if (settings.shaderPack.len == 0) {
		list.add(Label.init(.{0, 0}, 288, "#ffff00No shaderpack loaded.\n#ffffffPick one under #ffff00Shaders#ffffff first.", .center));
	} else if (packOptions.items.len == 0) {
		// The two reasons this is empty are worth separating: a pack that genuinely exposes nothing,
		// and a pack that has not finished loading yet.
		list.add(Label.init(.{0, 0}, 288, "#ffff00This pack exposes no options.\n#ffffffIf it just changed, give it a frame to load.", .center));
	} else {
		list.add(Label.init(.{0, 0}, 288, "#808080Changes reload the pack on the next frame.", .center));
	}

	for (packOptions.items, 0..) |option, index| {
		const row = HorizontalList.init();

		// A marker rather than only a colour, so an overridden row is still distinguishable to
		// anyone who cannot tell the two colours apart.
		const text = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}{s}: #ffff00{s}", .{
			if (option.overridden) "* " else "",
			option.name,
			option.value,
		}) catch unreachable;
		defer main.stackAllocator.free(text);

		row.add(Button.initText(.{0, 0}, 24, "<", .{.onAction = .initWithInt(cycleOption, payloadFor(index, true))}));
		row.add(Button.initText(.{0, 0}, 232, text, .{.onAction = .initWithInt(cycleOption, payloadFor(index, false))}));
		// Only offered where there is something to undo, so the row does not suggest an action that
		// would do nothing.
		if (option.overridden) {
			row.add(Button.initText(.{0, 0}, 24, "x", .{.onAction = .initWithInt(resetOption, index)}));
		}

		row.finish(.{0, 0}, .center);
		list.add(row);
	}

	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if (window.rootComponent) |*comp| {
		comp.deinit();
		window.rootComponent = null;
	}
	freeOptions();
}
