const std = @import("std");

const main = @import("../main");
const chunk = main.chunk;
const Entity = main.entity.Entity;
const game = main.game;
const graphics = main.graphics;
const ZonElement = main.ZonElement;
const renderer = main.renderer;
const settings = main.settings;
const utils = main.utils;
const BinaryReader = utils.BinaryReader;
const BinaryWriter = utils.BinaryWriter;
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const blocks = main.blocks;
const physics = main.physics;
const World = game.World;
const ServerWorld = main.server.ServerWorld;

const c = @import("c");
const Self = @This();

pub var entityComponentID: main.entity.EntityComponentId = undefined;
pub const entityComponentVersion = 0;

// ############################# Boat Component Definition ################################
pub const Boat = struct {
    // Mounted player info
    rider: ?main.entity.Entity = null,
    riderOffset: Vec3d = Vec3d{0, 0, 0.4},
    
    // State
    isInWater: bool = false,
    waterLevel: f64 = 0,
    yaw: f64 = 0,
    
    // Movement properties
    maxSpeed: f64 = 8.0,
    currentForwardSpeed: f64 = 0,
    
    pub const width: f64 = 0.9;
    pub const length: f64 = 1.8;
    pub const height: f64 = 0.6;
    pub const sinkDepth: f64 = 0.3;
    pub const waterBuoyancy: f64 = 9.81;
    pub const acceleration: f64 = 15.0;
    pub const friction: f64 = 0.95;
    pub const waterFriction: f64 = 0.92;
    pub const turnSpeed: f64 = 3.0;
    
    pub fn save(self: Boat, writer: *utils.BinaryWriter, audience: main.entity.AudienceInfo) main.entity.ComponentSaveBehaviour {
        _ = audience;
        writer.writeVarInt(u64, if (self.rider) |r| @intFromEnum(r) else std.math.maxInt(u32));
        writer.writeVec(Vec3d, self.riderOffset);
        writer.writeInt(u8, if (self.isInWater) 1 else 0);
        writer.writeFloat(f64, self.waterLevel);
        writer.writeFloat(f64, self.yaw);
        writer.writeFloat(f64, self.currentForwardSpeed);
        return .save;
    }
};

// ############################# Client only stuff ################################
pub const client = struct {
    pub var components: main.utils.SparseSet(Boat, Entity) = .{};

    pub fn init() void {}
    
    pub fn deinit() void {
        components.deinit(main.globalAllocator);
    }
    
    pub fn clear() void {
        components.clear();
    }
    
    pub fn load(entity: Entity, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
        if (version != 0) return error.InvalidComponentVersion;

        const riderId = reader.readVarInt(u64) catch return error.UnreadableComponentData;
        const riderOffset = reader.readVec(Vec3d) catch return error.UnreadableComponentData;
        const isInWater = (reader.readInt(u8) catch return error.UnreadableComponentData) != 0;
        const waterLevel = reader.readFloat(f64) catch return error.UnreadableComponentData;
        const yaw = reader.readFloat(f64) catch return error.UnreadableComponentData;
        const currentForwardSpeed = reader.readFloat(f64) catch return error.UnreadableComponentData;

        var boat = Boat{
            .rider = if (riderId == std.math.maxInt(u32)) null else @enumFromInt(riderId),
            .riderOffset = riderOffset,
            .isInWater = isInWater,
            .waterLevel = waterLevel,
            .yaw = yaw,
            .currentForwardSpeed = currentForwardSpeed,
        };

        const ptr = components.get(entity) orelse components.add(main.globalAllocator, entity);
        ptr.* = boat;
    }
    
    pub fn unload(entity: Entity) void {
        components.remove(entity) catch {};
    }
    
    pub fn get(entity: Entity) ?*Boat {
        return components.get(entity);
    }
};

// ############################# Server only stuff ################################
pub const server = struct {
    var components: main.utils.SparseSet(Boat, Entity) = undefined;
    
    pub fn init() void {
        components = .{};
    }
    
    pub fn deinit() void {
        components.deinit(main.globalAllocator);
    }
    
    pub fn loadFromData(entity: Entity, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
        if (version != 0) return error.InvalidComponentVersion;
        
        const riderId = reader.readVarInt(u64) catch return error.UnreadableComponentData;
        const riderOffset = reader.readVec(Vec3d) catch return error.UnreadableComponentData;
        const isInWater = (reader.readInt(u8) catch return error.UnreadableComponentData) != 0;
        const waterLevel = reader.readFloat(f64) catch return error.UnreadableComponentData;
        const yaw = reader.readFloat(f64) catch return error.UnreadableComponentData;
        const currentForwardSpeed = reader.readFloat(f64) catch return error.UnreadableComponentData;

        var boat = Boat{
            .rider = if (riderId == std.math.maxInt(u32)) null else @enumFromInt(riderId),
            .riderOffset = riderOffset,
            .isInWater = isInWater,
            .waterLevel = waterLevel,
            .yaw = yaw,
            .currentForwardSpeed = currentForwardSpeed,
        };

        put(entity, boat);
    }
    
    pub fn unload(entity: Entity) void {
        components.remove(entity) catch {};
    }
    
    pub fn put(entity: Entity, boat: Boat) void {
        const ptr = components.get(entity) orelse components.add(main.globalAllocator, entity);
        ptr.* = boat;
        main.entity.server.transmitChange(Self, entity);
    }
    
    pub fn get(entity: Entity) ?*Boat {
        return components.get(entity);
    }
    
    pub fn mount(entity: Entity, player: main.entity.Entity) void {
        if (get(entity)) |boat| {
            boat.rider = player;
            
            // Stop player vertical movement
            if (main.server.world) |world| {
                if (world.entities.get(player)) |playerEnt| {
                    playerEnt.vel[2] = 0;
                }
            }
            
            main.entity.server.transmitChange(Self, entity);
        }
    }
    
    pub fn dismount(entity: Entity) void {
        if (get(entity)) |boat| {
            if (boat.rider) |rider| {
                // Transfer momentum to player
                if (main.server.world) |world| {
                    if (world.entities.get(entity)) |boatEnt| {
                        if (world.entities.get(rider)) |playerEnt| {
                            playerEnt.vel[0] = boatEnt.vel[0] * 0.5;
                            playerEnt.vel[1] = boatEnt.vel[1] * 0.5;
                        }
                    }
                }
            }
            boat.rider = null;
            main.entity.server.transmitChange(Self, entity);
        }
    }
    
    pub fn updateMovement(entity: Entity, deltaTime: f64) void {
        if (get(entity)) |boat| {
            if (main.server.world) |world| {
                if (world.entities.get(entity)) |boatEnt| {
                    // Find water level
                    var waterLevel: f64 = -100;
                    const blockX = @as(i32, @intFromFloat(@floor(boatEnt.pos[0])));
                    const blockY = @as(i32, @intFromFloat(@floor(boatEnt.pos[1])));
                    const blockZ = @as(i32, @intFromFloat(@floor(boatEnt.pos[2])));
                    
                    var checkZ = blockZ;
                    while (checkZ < blockZ + 10) : (checkZ += 1) {
                        if (world.getBlock(blockX, blockY, checkZ)) |block| {
                            if (isWaterBlock(block)) {
                                waterLevel = @floatFromInt(checkZ);
                                break;
                            }
                        }
                    }
                    
                    boat.isInWater = boatEnt.pos[2] < waterLevel + boat.sinkDepth;
                    boat.waterLevel = waterLevel;
                    
                    // Apply buoyancy if in water
                    if (boat.isInWater) {
                        boatEnt.vel[2] += boat.waterBuoyancy * deltaTime;
                    }
                    
                    // Handle rider input
                    if (boat.rider) |rider| {
                        if (world.entities.get(rider)) |playerEnt| {
                            handleRiderInput(entity, boatEnt, playerEnt, boat, deltaTime);
                        }
                    }
                    
                    // Apply friction
                    const frictionCoeff = if (boat.isInWater) boat.waterFriction else boat.friction;
                    boatEnt.vel[0] *= frictionCoeff;
                    boatEnt.vel[1] *= frictionCoeff;
                    
                    // Clamp speed
                    const speed = @sqrt(boatEnt.vel[0]*boatEnt.vel[0] + boatEnt.vel[1]*boatEnt.vel[1]);
                    if (speed > boat.maxSpeed) {
                        const scale = boat.maxSpeed / speed;
                        boatEnt.vel[0] *= scale;
                        boatEnt.vel[1] *= scale;
                    }
                    
                    // Update rider position
                    if (boat.rider) |rider| {
                        if (world.entities.get(rider)) |playerEnt| {
                            const riderPos = boatEnt.pos + boat.riderOffset;
                            playerEnt.pos = riderPos;
                        }
                    }
                    
                    main.entity.server.transmitChange(Self, entity);
                }
            }
        }
    }
    
    fn handleRiderInput(boatEntity: Entity, boatEnt: *main.server.Entity, playerEnt: *main.server.Entity, boat: *Boat, deltaTime: f64) void {
        _ = boatEntity;
        _ = playerEnt;
        
        // Get rider input from player if they're on the server
        // This is a placeholder - implement based on your input system
        const forward: f64 = 0;
        const turn: f64 = 0;
        
        // Apply forward/backward acceleration
        if (forward != 0) {
            const forwardDir = Vec3d{
                @cos(boat.yaw),
                @sin(boat.yaw),
                0
            };
            const currentForwardSpeed = boatEnt.vel[0] * forwardDir[0] + boatEnt.vel[1] * forwardDir[1];
            const maxForwardSpeed = boat.maxSpeed * @as(f64, if (forward > 0) 1.0 else 0.5);
            
            if (@abs(currentForwardSpeed) < maxForwardSpeed) {
                boatEnt.vel[0] += forwardDir[0] * boat.acceleration * forward * deltaTime;
                boatEnt.vel[1] += forwardDir[1] * boat.acceleration * forward * deltaTime;
            }
        }
        
        // Apply turning
        if (turn != 0) {
            boat.yaw += turn * boat.turnSpeed * deltaTime;
        }
    }
};

pub fn getBoundingBox() physics.collision.Box {
    return .{
        .min = -Vec3d{Boat.width/2, Boat.length/2, 0},
        .max = Vec3d{Boat.width/2, Boat.length/2, Boat.height},
    };
}

fn isWaterBlock(block: blocks.Block) bool {
    // Check if block is water
    const blockId = block.id();
    return std.mem.startsWith(u8, blockId, "cubyz:water");
}
