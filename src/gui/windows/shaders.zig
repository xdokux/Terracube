const std = @import("std");

const main = @import("main");
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const CheckBox = @import("../components/CheckBox.zig");
const DiscreteSlider = @import("../components/DiscreteSlider.zig");
const Label = @import("../components/Label.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeIfMouseIsGrabbed = true,
};

const padding: f32 = 8;

/// Pack names for the buttons on screen, owned for as long as the window is open.
///
/// The buttons carry an *index* into this rather than a string, because a callback only gets a
/// pointer-sized payload. Rebuilt on every open so a pack dropped into the folder while the game is
/// running shows up without a restart.
var packNames: main.ListManaged([]const u8) = undefined;
var listInitialised: bool = false;

fn freePackNames() void {
	if (!listInitialised) return;
	for (packNames.items) |name| main.globalAllocator.free(name);
	packNames.deinit();
	listInitialised = false;
}

/// Switches to the pack at `index`, or back to Cubyz's own rendering for the "None" entry.
///
/// Nothing is loaded here. `settings.shaderPack` is the single source of truth the render hook
/// polls each frame, so assigning it is the whole operation — the pipeline is rebuilt on the next
/// frame, on the render thread, where a GL context exists. Trying to load from a GUI callback would
/// be doing it from the wrong place at the wrong time.
fn selectPack(index: usize) void {
	const wanted: []const u8 = if (index >= packNames.items.len) "" else packNames.items[index];
	if (std.mem.eql(u8, wanted, settings.shaderPack)) return;

	main.globalAllocator.free(settings.shaderPack);
	settings.shaderPack = main.globalAllocator.dupe(u8, wanted);
	settings.save();

	// The list has to be rebuilt so the selection marker moves, but *not* from here. This runs
	// inside the callback of a Button that lives in the very component tree a rebuild frees, and
	// `Button.mainButtonReleased` is called through that tree — tearing it down mid-dispatch is a
	// use-after-free. `update` runs once a frame outside event handling, so the work is deferred to
	// there.
	refreshRequested = true;
}

fn openPackOptions() void {
	gui.openWindow("shader_options");
}


var refreshRequested: bool = false;

pub fn update() void {
	if (!refreshRequested) return;
	refreshRequested = false;
	onClose();
	onOpen();
}

/// The index used for "no shaderpack", one past the real entries.
fn noneIndex() usize {
	return packNames.items.len;
}

fn label(allocator: main.heap.NeverFailingAllocator, name: []const u8, selected: bool) []const u8 {
	// A leading marker rather than a colour change, so the selected row is still obvious to anyone
	// who cannot distinguish the two colours.
	return std.fmt.allocPrint(allocator.allocator, "{s}{s}", .{
		if (selected) "> " else "",
		if (name.len == 0) "None (Cubyz rendering)" else name,
	}) catch unreachable;
}

pub fn onOpen() void {
	freePackNames();
	packNames = .init(main.globalAllocator);
	listInitialised = true;
	main.renderer.renderhook.listShaderPacks(main.globalAllocator, &packNames);

	const list = VerticalList.init(.{padding, 16 + padding}, 300, 8);
	list.add(Label.init(.{0, 0}, 192, "#ffffffShaders", .center));

	if (packNames.items.len == 0) {
		// The likeliest reason someone opens this and finds it empty, answered in place.
		list.add(Label.init(.{0, 0}, 192, "#ffff00No packs found.\n#ffffffPut a shaderpack folder or .zip in the #ffff00shaderpacks/#ffffff directory next to the game.", .center));
	}

	for (packNames.items, 0..) |name, index| {
		const text = label(main.stackAllocator, name, std.mem.eql(u8, name, settings.shaderPack));
		defer main.stackAllocator.free(text);
		list.add(Button.initText(.{0, 0}, 192, text, .{.onAction = .initWithInt(selectPack, index)}));
	}

	const noneText = label(main.stackAllocator, "", settings.shaderPack.len == 0);
	defer main.stackAllocator.free(noneText);
	list.add(Button.initText(.{0, 0}, 192, noneText, .{.onAction = .initWithInt(selectPack, noneIndex())}));

	// The pack's own options live on their own screen: which options exist depends on the pack, so
	// the list has to be built after one is loaded rather than alongside the pack list.
	if (settings.shaderPack.len != 0) {
		list.add(Button.initText(.{0, 0}, 192, "Pack options...", .{.onAction = .init(openPackOptions)}));
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
}
