const std = @import("std");
const main = @import("../main");
const game = @import("../game");
const vec = @import("../vec");
const physics = @import("../physics");
const entity = @import("../entity");

const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const Mat4f = vec.Mat4f;
const BinaryReader = main.utils.BinaryReader;
const BinaryWriter = main.utils.BinaryWriter;

pub const Boat = struct {
    // Movement properties
    pub const maxSpeed: f64 = 8.0; // Units per second (faster than walking)
    pub const acceleration: f64 = 15.0;
    pub const friction: f64 = 0.95;
    pub const waterFriction: f64 = 0.92; // Lower friction in water for realistic movement
    pub const turnSpeed: f64 = 3.0;
    pub const width: f64 = 0.9;
    pub const length: f64 = 1.8;
    pub const height: f64 = 0.6;
    pub const sinkDepth: f64 = 0.3; // How deep the boat sinks into water
    pub const waterBuoyancy: f64 = 9.81; // Force that keeps boat afloat
    
    // Mounted player info
    rider: ?main.entity.Entity = null,
    riderOffset: Vec3d = Vec3d{0, 0, 0.4}, // Offset for rider's position on boat
    
    // State
    isInWater: bool = false,
    waterLevel: f64 = 0,
    yaw: f64 = 0, // Rotation in radians
    
    // Damping for smoother motion
    movementDamping: f64 = 0.85,
    
    pub fn updateMovement(self: *Boat, boatEntity: main.entity.Entity, deltaTime: f64) void {
        // Get boat from entity system - implementation depends on your entity management
        if (getBoatComponent(boatEntity)) |boat| {
            const entityData = getEntityData(boatEntity) orelse return;
            
            // Calculate water level at boat position
            var waterLevel: f64 = -100; // Below world by default
            if (main.server.world) |world| {
                const blockX = @as(i32, @intFromFloat(@floor(entityData.pos[0])));
                const blockY = @as(i32, @intFromFloat(@floor(entityData.pos[1])));
                const blockZ = @as(i32, @intFromFloat(@floor(entityData.pos[2])));
                
                // Check blocks above and below to find water level
                var checkZ = blockZ;
                while (checkZ < blockZ + 10) : (checkZ += 1) {
                    if (world.getBlock(blockX, blockY, checkZ)) |block| {
                        if (isWaterBlock(block)) {
                            waterLevel = @floatFromInt(checkZ);
                            break;
                        }
                    }
                }
            }
            
            boat.isInWater = entityData.pos[2] < waterLevel + boat.sinkDepth;
            boat.waterLevel = waterLevel;
            
            // Apply buoyancy if in water
            if (boat.isInWater) {
                var vel = entityData.vel;
                vel[2] += boat.waterBuoyancy * deltaTime;
                setEntityVelocity(boatEntity, vel);
            }
        }
    }
    
    pub fn handleRiderInput(self: *Boat, boatEntity: main.entity.Entity, deltaTime: f64) void {
        if (self.rider == null or game.world == null) return;
        
        const entityData = getEntityData(boatEntity) orelse return;
        const riderData = getEntityData(self.rider.?) orelse return;
        
        // Get rider input (reuse game player input system)
        const forward = main.KeyBoard.key("forward").value - main.KeyBoard.key("backward").value;
        const turn = main.KeyBoard.key("left").value - main.KeyBoard.key("right").value;
        
        var vel = entityData.vel;
        
        // Apply forward/backward acceleration
        if (forward != 0) {
            const forwardDir = Vec3d{
                @cos(self.yaw),
                @sin(self.yaw),
                0
            };
            const currentForwardSpeed = @reduce(.Add, vel[0..2] * forwardDir[0..2]);
            const maxForwardSpeed = self.maxSpeed * @as(f64, if (forward > 0) 1.0 else 0.5);
            
            if (@abs(currentForwardSpeed) < maxForwardSpeed) {
                vel += forwardDir * @as(Vec3d, @splat(self.acceleration * forward * deltaTime));
            }
        }
        
        // Apply turning
        if (turn != 0) {
            self.yaw += turn * self.turnSpeed * deltaTime;
        }
        
        // Apply friction
        const frictionCoeff = if (self.isInWater) self.waterFriction else self.friction;
        vel[0] *= frictionCoeff;
        vel[1] *= frictionCoeff;
        
        // Clamp speed
        const speed = @sqrt(vel[0]*vel[0] + vel[1]*vel[1]);
        if (speed > self.maxSpeed) {
            const scale = self.maxSpeed / speed;
            vel[0] *= scale;
            vel[1] *= scale;
        }
        
        setEntityVelocity(boatEntity, vel);
        
        // Update rider position to be on the boat
        if (self.rider) |rider| {
            const riderPos = entityData.pos + self.riderOffset;
            setEntityPosition(rider, riderPos);
        }
    }
    
    pub fn mount(self: *Boat, boatEntity: main.entity.Entity, player: main.entity.Entity) void {
        self.rider = player;
        
        // Remove player gravity and collision while mounted
        if (getEntityData(player)) |playerData| {
            var playerVel = playerData.vel;
            playerVel[2] = 0; // Stop vertical movement
            setEntityVelocity(player, playerVel);
        }
    }
    
    pub fn dismount(self: *Boat, boatEntity: main.entity.Entity) void {
        if (self.rider) |rider| {
            // Preserve boat velocity to rider
            if (getEntityData(boatEntity)) |boatData| {
                if (getEntityData(rider)) |riderData| {
                    var riderVel = riderData.vel;
                    riderVel[0] = boatData.vel[0] * 0.5;
                    riderVel[1] = boatData.vel[1] * 0.5;
                    setEntityVelocity(rider, riderVel);
                }
            }
        }
        self.rider = null;
    }
    
    pub fn getBoundingBox() physics.collision.Box {
        return .{
            .min = -Vec3d{Boat.width/2, Boat.length/2, 0},
            .max = Vec3d{Boat.width/2, Boat.length/2, Boat.height},
        };
    }
};

// Helper functions to interface with entity system
fn getBoatComponent(boatEntity: main.entity.Entity) ?*Boat {
    // This would need to be implemented based on your entity component system
    // For now, returning null as placeholder
    return null;
}

fn getEntityData(ent: main.entity.Entity) ?*main.server.Entity {
    // This would need to retrieve entity data from your server world
    if (main.server.world) |world| {
        // Implementation depends on your entity storage system
        return null;
    }
    return null;
}

fn setEntityPosition(ent: main.entity.Entity, pos: Vec3d) void {
    if (getEntityData(ent)) |data| {
        data.pos = pos;
    }
}

fn setEntityVelocity(ent: main.entity.Entity, vel: Vec3d) void {
    if (getEntityData(ent)) |data| {
        data.vel = vel;
    }
}

fn isWaterBlock(block: main.blocks.Block) bool {
    const blockId = block.typ;
    // Check if block is water - implementation depends on your block system
    // This is a placeholder
    return false;
}
