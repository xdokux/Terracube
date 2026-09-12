const std = @import("std");
const main = @import("../main");
const game = @import("../game");
const entity = @import("../entity");
const boat_component = @import("../entityComponent/boat.zig");

const Vec3d = main.vec.Vec3d;
const Entity = main.entity.Entity;

pub const client = struct {
    pub fn init() void {}
    pub fn deinit() void {}
    pub fn update() void {}
};

pub const server = struct {
    pub fn init() void {}
    pub fn deinit() void {}
    
    pub fn update() void {
        if (main.server.world) |world| {
            var iter = boat_component.server.components.iterator();
            while (iter.next()) |entry| {
                const boatEntity = entry.key;
                boat_component.server.updateMovement(boatEntity, 0.016); // ~60fps delta
            }
        }
    }
    
    pub fn tryMountBoat(player: Entity, boat: Entity) void {
        if (main.server.world) |world| {
            const playerEnt = world.entities.get(player) orelse return;
            const boatEnt = world.entities.get(boat) orelse return;
            
            // Check distance
            const dx = playerEnt.pos[0] - boatEnt.pos[0];
            const dy = playerEnt.pos[1] - boatEnt.pos[1];
            const dz = playerEnt.pos[2] - boatEnt.pos[2];
            const dist = @sqrt(dx*dx + dy*dy + dz*dz);
            
            if (dist < 2.0) {
                boat_component.server.mount(boat, player);
            }
        }
    }
};
