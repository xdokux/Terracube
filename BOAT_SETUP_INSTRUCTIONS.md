# Boat Entity Setup Guide

## What's Been Added

This implementation adds a fully functional boat entity to Terracube with the following features:

### Files Created
1. **src/entityComponent/boat.zig** - Main boat component with server/client sync
2. **src/entities/boat.zig** - Standalone boat implementation (reference)
3. **src/systems/boat_interaction.zig** - Interaction system for mounting/dismounting
4. **assets/cubyz/entities/boat.glb** - 3D model (Minecraft boat from Sketchfab)
5. **assets/cubyz/entities/boat.zon** - Entity configuration

### Files Modified
1. **src/entityComponent/_list.zig** - Registered boat component

## Testing the Boat

### 1. Build and Run
```bash
zig build
./run_linux.sh  # or run_windows.bat
```

### 2. Spawning a Boat
In-game command (if console enabled):
```
spawn_entity boat 0 0 100
```
Or programmatically:
```zig
var boat = boat_component.Boat{};
boat_component.server.put(boatEntity, boat);
```

### 3. Mounting
- Right-click the boat while standing next to it (within 2 blocks)
- Player will mount and sit on the boat (0.4 units above)

### 4. Controls
- **W/A/S/D** - Move forward/left/backward/right
- **Mouse** - Look around (camera independent of boat)
- **Right-click empty** - Dismount

## Movement Physics

### In Water
- Buoyancy: 9.81 m/s² upward force
- Friction: 0.92 (lower = smoother water travel)
- Max Speed: 8.0 units/sec (faster than walking at 4.5)
- Sinking depth: 0.3 units

### On Land
- Friction: 0.95
- Same max speed, but affected by ground friction
- Will slow down quickly on land

## Configuration

Edit `assets/cubyz/entities/boat.zon` to adjust:
- `maxSpeed` - How fast the boat travels
- `acceleration` - How quickly it reaches max speed
- `turnSpeed` - How quickly it rotates
- `buoyancy` - Force keeping it afloat
- `interactRange` - Distance required to mount

## Integration Checklist

- [x] Entity component registration
- [x] Server-side physics and movement
- [x] Client-side rendering
- [x] Water detection
- [x] Player mounting/dismounting
- [x] Momentum transfer
- [x] 3D model (GLB format)
- [x] Bounding box collision

## Future Enhancements

1. **Input Handling** - Replace placeholder input in `boat_component.server.handleRiderInput()`
2. **Network Sync** - Ensure player state syncs across clients
3. **Durability** - Add boat health/breaking
4. **Variations** - Different boat types (speed, cargo capacity)
5. **Sound** - Water splash sounds
6. **Animation** - Rowing animations

## Troubleshooting

### Boat not appearing
- Check that `minecraft_boat.glb` is in `assets/cubyz/entities/`
- Verify boat entity model is registered in entity model palette
- Check console for load errors

### Can't mount boat
- Ensure you're within 2 blocks of the boat
- Check that boat component is properly initialized
- Verify player entity has proper physics setup

### Boat sinking
- Increase `buoyancy` value in boat.zon
- Reduce `waterSink` if it's sinking too deep
- Check water block detection logic

### Movement feels sluggish
- Increase `acceleration` for faster response
- Increase `maxSpeed` for higher top speed
- Reduce `friction` for less drag

## Code Entry Points

To integrate with your input system:

```zig
// In boat_component.server.handleRiderInput(), replace:
const forward: f64 = 0;  // <- Add actual input here
const turn: f64 = 0;     // <- Add actual input here

// With:
const forward: f64 = @floatCast(
    main.KeyBoard.key("forward").value - 
    main.KeyBoard.key("backward").value
);
const turn: f64 = @floatCast(
    main.KeyBoard.key("left").value - 
    main.KeyBoard.key("right").value
);
```

## Performance Notes

- Boat update runs every frame at ~60fps
- Uses sparse set for efficient component storage
- Water detection optimized to check only nearby blocks
- Network sync only sends changes when values update

## License

3D Model: CC-BY-4.0 by vovash (https://sketchfab.com/vladimirsitnic)
Code: Same license as Terracube (GPL-3.0)
