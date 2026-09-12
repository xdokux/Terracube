//! The coordinate-system bridge, and the matrix maths Cubyz's `Mat4f` does not provide.
//!
//! Shaderpacks are written against Minecraft's Y-up world: `upPosition` points along +Y, sky
//! gradients are sampled by `.y`, and the celestial path is built by rotating about Y then X.
//! Cubyz is Z-up. Rather than patch that assumption in a hundred places, the whole pack is handed
//! a Y-up world through a single change of basis folded into `gbufferModelView`.
//!
//! This is exact, not an approximation. `zUpToYUp` is a proper rotation (determinant +1), so
//! nothing is mirrored - a reflection here would silently invert winding order and flip every
//! normal, which is the kind of bug that looks like "the shader is just wrong somehow".
//!
//! Everything in this file is pure, and is tested by round-tripping against Cubyz's own `Mat4f`.

const std = @import("std");

const main = @import("main");
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;

/// Cubyz world space (X east, Y north, Z up) to Minecraft world space (X east, Y up, Z south).
///
///     mc.x =  cubyz.x
///     mc.y =  cubyz.z
///     mc.z = -cubyz.y
///
/// which is a -90° rotation about X. Determinant is +1, so handedness is preserved.
pub const zUpToYUp = Mat4f{.rows = .{
	Vec4f{1, 0, 0, 0},
	Vec4f{0, 0, 1, 0},
	Vec4f{0, -1, 0, 0},
	Vec4f{0, 0, 0, 1},
}};

/// The inverse of `zUpToYUp`. A rotation's inverse is its transpose.
pub const yUpToZUp = Mat4f{.rows = .{
	Vec4f{1, 0, 0, 0},
	Vec4f{0, 0, -1, 0},
	Vec4f{0, 1, 0, 0},
	Vec4f{0, 0, 0, 1},
}};

/// Rotates a Cubyz world-space vector into the Y-up world the pack believes it lives in.
pub fn toYUp(v: Vec3f) Vec3f {
	return .{v[0], v[2], -v[1]};
}

/// Rotates a Y-up vector back into Cubyz world space.
pub fn toZUp(v: Vec3f) Vec3f {
	return .{v[0], -v[2], v[1]};
}

/// Cubyz's sea level is z = 0; Minecraft's is 64, and packs hardcode that frame as absolute
/// altitudes rather than deriving it from anything the host supplies.
///
/// Handing across a raw Cubyz height therefore places a player standing on a beach 64 blocks
/// underground as far as the pack is concerned, and the atmosphere models are not gentle about it.
/// Nostalgia forces air density to 250 - its thick valley haze - for every sample below altitude 50:
///
///     density.x = mix(density.x, 250.0, (1-cave) * expf(-max0((altitude - 50.0) * 0.01)))
///
/// `max0` clamps the exponent at zero, so below 50 the mix factor is exactly 1 and the whole world
/// sits at maximum fog density permanently. The pack states the frame it expects outright, in
/// `skyboxPrep.fsh`: `const float eyeAltitude = 64.0`.
pub const seaLevel = 64.0;

/// Converts a Cubyz position into the pack's Y-up world, including the sea-level offset.
///
/// Positions only. `toYUp` remains the right call for directions and normals, where adding an
/// offset would be nonsense - which is exactly why this is a separate function rather than a flag.
pub fn positionToYUp(v: Vec3f) Vec3f {
	var result = toYUp(v);
	result[1] += seaLevel;
	return result;
}

/// `gbufferModelView` for a given Cubyz view matrix.
///
/// Cubyz's eye space is not the GL convention. Its projection matrix maps view Z to clip Y and
/// uses view Y as the W divide, so eye space is Z-up with +Y pointing into the screen, where GL
/// (and therefore every shaderpack) expects X-right, Y-up, -Z-forward. Both the world *and* the
/// eye basis need correcting.
///
/// The pack's world position is `p_mc = B·p_cz`, and it needs GL eye space:
///
///     glEye = B·cubyzEye = B·V·p_cz = B·V·B⁻¹·p_mc
///
/// so `gbufferModelView = B·V·B⁻¹` - a similarity transform, not the one-sided `V·B⁻¹` that would
/// be right if only world orientation differed.
///
/// This pairs with `glProjection`: together they reproduce exactly the clip coordinates Cubyz
/// computes, which is the property that actually matters. Getting it wrong is invisible until a
/// pack reads the projection matrix's individual entries - Nostalgia's fast-path
/// `diag4(gl_ProjectionMatrix)` reads zeros off a Cubyz matrix and collapses every vertex to the
/// origin, with no GL error to explain it.
pub fn gbufferModelView(cubyzViewMatrix: Mat4f) Mat4f {
	return zUpToYUp.mul(cubyzViewMatrix).mul(yUpToZUp);
}

/// A standard GL perspective matrix equivalent to Cubyz's, for `gbufferProjection`.
///
/// Derived from Cubyz's own matrix rather than from the FOV so the two cannot drift apart, and
/// because the field of view is not public. Cubyz stores `1/tanX` at row 0 column 0 and `1/tanY`
/// at row 1 column 2 - the latter being where the Z-up convention shows up.
pub fn glProjection(cubyzProjection: Mat4f, near: f32, far: f32) Mat4f {
	const invTanX = cubyzProjection.rows[0][0];
	const invTanY = cubyzProjection.rows[1][2];
	return .{.rows = .{
		Vec4f{invTanX, 0, 0, 0},
		Vec4f{0, invTanY, 0, 0},
		Vec4f{0, 0, -(far + near)/(far - near), -2*far*near/(far - near)},
		Vec4f{0, 0, -1, 0},
	}};
}

/// General 4x4 inverse, returning null for a singular matrix.
///
/// Cubyz's `Mat4f` has no inverse, and packs need `gbufferModelViewInverse`,
/// `gbufferProjectionInverse` and the shadow equivalents. Layout-agnostic: it produces the
/// inverse in whatever convention it was handed, since transposing input and output together is
/// consistent.
pub fn inverse(matrix: Mat4f) ?Mat4f {
	var m: [16]f32 = undefined;
	inline for(0..4) |row| {
		inline for(0..4) |column| m[row*4 + column] = matrix.rows[row][column];
	}

	var inv: [16]f32 = undefined;
	inv[0] = m[5]*m[10]*m[15] - m[5]*m[11]*m[14] - m[9]*m[6]*m[15] + m[9]*m[7]*m[14] + m[13]*m[6]*m[11] - m[13]*m[7]*m[10];
	inv[4] = -m[4]*m[10]*m[15] + m[4]*m[11]*m[14] + m[8]*m[6]*m[15] - m[8]*m[7]*m[14] - m[12]*m[6]*m[11] + m[12]*m[7]*m[10];
	inv[8] = m[4]*m[9]*m[15] - m[4]*m[11]*m[13] - m[8]*m[5]*m[15] + m[8]*m[7]*m[13] + m[12]*m[5]*m[11] - m[12]*m[7]*m[9];
	inv[12] = -m[4]*m[9]*m[14] + m[4]*m[10]*m[13] + m[8]*m[5]*m[14] - m[8]*m[6]*m[13] - m[12]*m[5]*m[10] + m[12]*m[6]*m[9];
	inv[1] = -m[1]*m[10]*m[15] + m[1]*m[11]*m[14] + m[9]*m[2]*m[15] - m[9]*m[3]*m[14] - m[13]*m[2]*m[11] + m[13]*m[3]*m[10];
	inv[5] = m[0]*m[10]*m[15] - m[0]*m[11]*m[14] - m[8]*m[2]*m[15] + m[8]*m[3]*m[14] + m[12]*m[2]*m[11] - m[12]*m[3]*m[10];
	inv[9] = -m[0]*m[9]*m[15] + m[0]*m[11]*m[13] + m[8]*m[1]*m[15] - m[8]*m[3]*m[13] - m[12]*m[1]*m[11] + m[12]*m[3]*m[9];
	inv[13] = m[0]*m[9]*m[14] - m[0]*m[10]*m[13] - m[8]*m[1]*m[14] + m[8]*m[2]*m[13] + m[12]*m[1]*m[10] - m[12]*m[2]*m[9];
	inv[2] = m[1]*m[6]*m[15] - m[1]*m[7]*m[14] - m[5]*m[2]*m[15] + m[5]*m[3]*m[14] + m[13]*m[2]*m[7] - m[13]*m[3]*m[6];
	inv[6] = -m[0]*m[6]*m[15] + m[0]*m[7]*m[14] + m[4]*m[2]*m[15] - m[4]*m[3]*m[14] - m[12]*m[2]*m[7] + m[12]*m[3]*m[6];
	inv[10] = m[0]*m[5]*m[15] - m[0]*m[7]*m[13] - m[4]*m[1]*m[15] + m[4]*m[3]*m[13] + m[12]*m[1]*m[7] - m[12]*m[3]*m[5];
	inv[14] = -m[0]*m[5]*m[14] + m[0]*m[6]*m[13] + m[4]*m[1]*m[14] - m[4]*m[2]*m[13] - m[12]*m[1]*m[6] + m[12]*m[2]*m[5];
	inv[3] = -m[1]*m[6]*m[11] + m[1]*m[7]*m[10] + m[5]*m[2]*m[11] - m[5]*m[3]*m[10] - m[9]*m[2]*m[7] + m[9]*m[3]*m[6];
	inv[7] = m[0]*m[6]*m[11] - m[0]*m[7]*m[10] - m[4]*m[2]*m[11] + m[4]*m[3]*m[10] + m[8]*m[2]*m[7] - m[8]*m[3]*m[6];
	inv[11] = -m[0]*m[5]*m[11] + m[0]*m[7]*m[9] + m[4]*m[1]*m[11] - m[4]*m[3]*m[9] - m[8]*m[1]*m[7] + m[8]*m[3]*m[5];
	inv[15] = m[0]*m[5]*m[10] - m[0]*m[6]*m[9] - m[4]*m[1]*m[10] + m[4]*m[2]*m[9] + m[8]*m[1]*m[6] - m[8]*m[2]*m[5];

	const determinant = m[0]*inv[0] + m[1]*inv[4] + m[2]*inv[8] + m[3]*inv[12];
	if(determinant == 0) return null;
	const scale = 1.0/determinant;

	var result: Mat4f = undefined;
	inline for(0..4) |row| {
		inline for(0..4) |column| result.rows[row][column] = inv[row*4 + column]*scale;
	}
	return result;
}

/// Orthographic projection, for the shadow pass.
///
/// Packs read `shadowProjection` and its inverse to convert between shadow clip space and world
/// space, so this must be a real matrix rather than something the shadow renderer keeps privately.
pub fn ortho(halfExtent: f32, near: f32, far: f32) Mat4f {
	return .{.rows = .{
		Vec4f{1.0/halfExtent, 0, 0, 0},
		Vec4f{0, 1.0/halfExtent, 0, 0},
		Vec4f{0, 0, -2.0/(far - near), -(far + near)/(far - near)},
		Vec4f{0, 0, 0, 1},
	}};
}

/// View-space direction of the sun or moon, matching Iris's `CelestialUniforms`.
///
/// Iris builds this by taking `gbufferModelView`, rotating -90° about Y, then `sunPathRotation`
/// about Z, then the time-of-day angle about X, and transforming `(0, 100, 0)`. Reproduced rather
/// than reinvented: packs do not merely normalise this, they compare it against `upPosition` and
/// against view-space normals, so an axis convention that differs by a rotation would make
/// lighting subtly wrong at every time of day rather than obviously broken at one.
pub fn celestialPosition(modelView: Mat4f, sunPathRotationDegrees: f32, angleDegrees: f32, distance: f32) Vec3f {
	return celestialAxis(modelView, sunPathRotationDegrees, angleDegrees, .{0, distance, 0});
}

/// A vector of the celestial frame in view space: the frame `celestialPosition` measures the sun
/// along, with `local` in its own coordinates.
///
/// The frame's Y is the sun; its X is the axis the sky turns about, and its Z lies in the sun's
/// path. Minecraft's sun and moon quads are drawn in exactly this frame (`LevelRenderer.renderSky`,
/// after the same two rotations): the sun spans `x, z` in `[-30, 30]` at `y = 100`, the moon
/// `[-20, 20]` at `y = -100`. So the quads' edges are this function at `(1, 0, 0)` and `(0, 0, 1)`,
/// and their centres are `celestialPosition` at `100` and `-100`.
pub fn celestialAxis(modelView: Mat4f, sunPathRotationDegrees: f32, angleDegrees: f32, local: Vec3f) Vec3f {
	const toRadians = std.math.pi/180.0;
	const celestial = modelView
		.mul(Mat4f.rotationY(-90.0*toRadians))
		.mul(Mat4f.rotationZ(sunPathRotationDegrees*toRadians))
		.mul(Mat4f.rotationX(angleDegrees*toRadians));
	return transformDirection(celestial, local);
}

/// World-space direction of the sun or moon, in the pack's Y-up space.
///
/// The same construction as `celestialPosition` with no view transform, which is what the shadow
/// camera needs: the shadow map is built in world space, not relative to where the player looks.
pub fn celestialWorldDirection(sunPathRotationDegrees: f32, angleDegrees: f32) Vec3f {
	const direction = celestialPosition(Mat4f.identity(), sunPathRotationDegrees, angleDegrees, 1);
	return normalize(direction);
}

/// Whether the sun is above the horizon, in world space.
///
/// Exists as its own function because the obvious way to ask this is wrong. `sunPosition` is the sun
/// in view space, so `sunPosition.y` is its height on *screen*, not in the sky - testing it makes
/// day and night depend on where the camera points. That is what it did: pitching past the threshold
/// flipped the shadow light to the moon and negated the entire shadow map, mid-frame, on a stationary
/// player.
///
/// Takes no matrix, which is the point: there is nothing here for a view to get into.
pub fn isDaytime(sunPathRotationDegrees: f32, angleDegrees: f32) bool {
	return celestialWorldDirection(sunPathRotationDegrees, angleDegrees)[1] >= 0;
}

/// How far up the light ray Iris puts the shadow camera, in blocks (`ShadowMatrices.java`,
/// `translate(0, 0, -100)`), and the depth range it gives the ortho by default
/// (`PackShadowDirectives`: `nearPlane = 0.05f`, `farPlane = 256.0f`, overridable per pack by
/// `const float shadowNearPlane`/`shadowFarPlane`).
///
/// These three numbers are not a choice this bridge gets to make. Every pack calibrates its shadow
/// maths against them without reading them from anywhere: BSL's `shadowPos.z -= bias` is a bias in
/// the units of a depth buffer spanning 256 blocks, then compressed by the pack's own `z *= 0.2`;
/// Kappa's and Nostalgia's `shadowmapDepthScale = (2.0 * 256.0) / 0.2` name the range outright.
/// The ortho used to span two shadow distances either side of the player, 512 to 1024 blocks for
/// the packs in `shaderpacks/`, so every one of those biases stood for two to four times the
/// distance its author meant. That is a shadow detached from the block that casts it by up to a
/// block, and it is worst on the packs with the largest `shadowDistance`.
pub const shadowCameraDistance: f32 = 100.0;
pub const shadowNearDefault: f32 = 0.05;
pub const shadowFarDefault: f32 = 256.0;

/// `shadowModelView`, built exactly as Iris builds it.
///
/// `ShadowMatrices.createModelViewMatrix`: translate by `(0, 0, -100)`, rotate 90 degrees about X,
/// rotate about Z by minus the sky angle, rotate about X by `sunPathRotation`, then translate by the
/// grid snap. `lightAngleDegrees` is the sky angle of whichever body casts the shadow - the sun's raw
/// angle by day, the moon's (the sun's plus 180) by night - which is Iris's `skyAngle`, its
/// `shadowAngle` less a quarter turn.
///
/// The rotation is the transpose of the one `celestialWorldDirection` applies, so the light lands on
/// the camera's +Z: the camera sits 100 blocks up the ray looking back down it, the player 100 blocks
/// in front of it, and the ortho's `[0.05, 256]` reaches from just behind the camera to 156 blocks
/// past the player. A test below pins the whole matrix against the vector Iris ships in its own
/// unit test, translation included.
///
/// The old version built an orthonormal basis from the light direction and an up hint, centred on
/// the player with no translation. Self-consistent - the same matrix rendered the map and resolved
/// the lookups - but every constant a pack keeps about the shadow camera was then wrong by the
/// difference, and packs keep more of them than the depth range: photon rotates its stars by
/// `mat3(shadowModelViewInverse)` and undoes the night by negating two of its columns, which only
/// recovers the sun's frame from the moon's if the frame is this one.
pub fn shadowModelView(sunPathRotationDegrees: f32, lightAngleDegrees: f32, gridSnap: Vec3f) Mat4f {
	const toRadians = std.math.pi/180.0;
	return Mat4f.translation(.{0, 0, -shadowCameraDistance})
		.mul(Mat4f.rotationX(90.0*toRadians))
		.mul(Mat4f.rotationZ(-lightAngleDegrees*toRadians))
		.mul(Mat4f.rotationX(sunPathRotationDegrees*toRadians))
		.mul(Mat4f.translation(gridSnap));
}

/// Iris's `snapModelViewToGrid`: the translation that pins the shadow map's texel grid to the world.
///
/// The shadow pass positions geometry relative to the camera, so without this the map's texels
/// slide under the world as the player moves and every shadow edge shimmers. Iris shifts the whole
/// scene by the camera's position within a cell of `shadowIntervalSize` blocks, less half a cell,
/// so the map's origin only ever sits at cell centres. Java's `%` keeps the sign of the dividend,
/// which puts negative coordinates in `(-interval, 0]` rather than `[0, interval)` - Iris's own
/// comment notes the asymmetry and keeps it, and so does this, because a pack that reconstructs
/// shadow-space positions from `cameraPosition` sees the same numbers Iris would give it.
pub fn shadowGridSnap(cameraPosition: Vec3f, intervalSize: f32) Vec3f {
	if(intervalSize == 0) return @splat(0);
	var result: Vec3f = undefined;
	inline for(0..3) |axis| {
		result[axis] = @rem(cameraPosition[axis], intervalSize) - intervalSize/2.0;
	}
	return result;
}

fn dot(a: Vec3f, b: Vec3f) f32 {
	return a[0]*b[0] + a[1]*b[1] + a[2]*b[2];
}

fn normalize(v: Vec3f) Vec3f {
	const magnitude = @sqrt(dot(v, v));
	if(magnitude == 0) return .{0, 0, 1};
	return v/@as(Vec3f, @splat(magnitude));
}

/// View-space up vector, `gbufferModelView` rotated -90° about Y applied to `(0, 100, 0)`.
pub fn upPosition(modelView: Mat4f) Vec3f {
	const rotated = modelView.mul(Mat4f.rotationY(-90.0*std.math.pi/180.0));
	return transformDirection(rotated, .{0, 100, 0});
}

/// Applies a matrix to a direction, ignoring translation.
pub fn transformDirection(matrix: Mat4f, direction: Vec3f) Vec3f {
	var result: Vec3f = @splat(0);
	inline for(0..3) |row| {
		result[row] = matrix.rows[row][0]*direction[0] + matrix.rows[row][1]*direction[1] + matrix.rows[row][2]*direction[2];
	}
	return result;
}

/// Applies a matrix to a point, including translation.
pub fn transformPoint(matrix: Mat4f, point: Vec3f) Vec3f {
	var result: Vec3f = @splat(0);
	inline for(0..3) |row| {
		result[row] = matrix.rows[row][0]*point[0] + matrix.rows[row][1]*point[1] + matrix.rows[row][2]*point[2] + matrix.rows[row][3];
	}
	return result;
}

// MARK: tests

const testing = std.testing;

fn expectMatrixApproxEqual(expected: Mat4f, actual: Mat4f, tolerance: f32) !void {
	inline for(0..4) |row| {
		inline for(0..4) |column| {
			try testing.expectApproxEqAbs(expected.rows[row][column], actual.rows[row][column], tolerance);
		}
	}
}

test "the basis change is a proper rotation" {
	// Determinant of the 3x3 part must be +1: a reflection would flip winding and normals.
	const m = zUpToYUp.rows;
	const determinant =
		m[0][0]*(m[1][1]*m[2][2] - m[1][2]*m[2][1]) -
		m[0][1]*(m[1][0]*m[2][2] - m[1][2]*m[2][0]) +
		m[0][2]*(m[1][0]*m[2][1] - m[1][1]*m[2][0]);
	try testing.expectApproxEqAbs(@as(f32, 1.0), determinant, 1e-6);
}

test "the basis change maps Cubyz up onto Minecraft up" {
	// Cubyz +Z (up) must become Minecraft +Y (up).
	try testing.expectEqual(Vec3f{0, 1, 0}, toYUp(.{0, 0, 1}));
	// East stays east.
	try testing.expectEqual(Vec3f{1, 0, 0}, toYUp(.{1, 0, 0}));
	// Cubyz +Y (north) becomes Minecraft -Z.
	try testing.expectEqual(Vec3f{0, 0, -1}, toYUp(.{0, 1, 0}));
}

test "a Cubyz position lands at Minecraft's sea level" {
	// Cubyz sea level is z = 0 and packs read altitude as an absolute Minecraft height, so standing
	// on a beach must report 64 - the same number Nostalgia's own `skyboxPrep` hardcodes.
	try testing.expectEqual(@as(f32, 64), positionToYUp(.{0, 0, 0})[1]);
	try testing.expectEqual(@as(f32, 74), positionToYUp(.{0, 0, 10})[1]);
	// Below sea level stays below Minecraft's, rather than being clamped.
	try testing.expectEqual(@as(f32, 44), positionToYUp(.{0, 0, -20})[1]);
}

test "the sea-level offset touches only altitude" {
	const sample = Vec3f{3, -7, 11};
	const rotated = toYUp(sample);
	const positioned = positionToYUp(sample);
	try testing.expectEqual(rotated[0], positioned[0]);
	try testing.expectEqual(rotated[2], positioned[2]);
	try testing.expectEqual(rotated[1] + seaLevel, positioned[1]);
}

test "directions are not offset" {
	// The reason `toYUp` and `positionToYUp` are separate functions rather than one with a flag.
	// Offsetting a direction would tilt every normal and light vector by 64 units.
	try testing.expectEqual(Vec3f{0, 1, 0}, toYUp(.{0, 0, 1}));
	try testing.expectEqual(Vec3f{0, -1, 0}, toYUp(.{0, 0, -1}));
}

test "the offset cancels between two positions" {
	// Everything relative - reprojection against `previousCameraPosition`, geometry positioned
	// against the camera - must be unaffected, or shifting the frame would move the world.
	const a = Vec3f{1, 2, 3};
	const b = Vec3f{-4, 6, -9};
	const rawDelta = toYUp(a) - toYUp(b);
	const positionedDelta = positionToYUp(a) - positionToYUp(b);
	try testing.expectEqual(rawDelta, positionedDelta);
}

test "the basis change round-trips" {
	const samples = [_]Vec3f{.{1, 2, 3}, .{-4, 0.5, 7}, .{0, 0, 0}};
	for(samples) |sample| {
		try testing.expectEqual(sample, toZUp(toYUp(sample)));
	}
	try expectMatrixApproxEqual(Mat4f.identity(), zUpToYUp.mul(yUpToZUp), 1e-6);
}

test "inverse round-trips against a non-trivial matrix" {
	// Something with rotation, translation and non-uniform scale, so a layout mistake shows up.
	const matrix = Mat4f.translation(.{3, -7, 2})
		.mul(Mat4f.rotationY(0.9))
		.mul(Mat4f.rotationX(-0.4))
		.mul(Mat4f.scale(.{2, 0.5, 1.5}));
	const inverted = inverse(matrix).?;
	try expectMatrixApproxEqual(Mat4f.identity(), matrix.mul(inverted), 1e-4);
	try expectMatrixApproxEqual(Mat4f.identity(), inverted.mul(matrix), 1e-4);
}

test "inverse handles a projection matrix" {
	const projection = Mat4f.perspective(1.2, 16.0/9.0, 0.1, 1000.0);
	const inverted = inverse(projection).?;
	try expectMatrixApproxEqual(Mat4f.identity(), projection.mul(inverted), 1e-3);
}

test "a singular matrix has no inverse" {
	const singular = Mat4f.scale(.{1, 0, 1});
	try testing.expect(inverse(singular) == null);
}

test "gbufferModelView maps a Y-up world point the way the Cubyz view matrix maps its Z-up twin" {
	const cubyzView = Mat4f.rotationX(0.3).mul(Mat4f.rotationZ(-1.1)).mul(Mat4f.translation(.{5, -2, 8}));
	const modelView = gbufferModelView(cubyzView);

	// The same point expressed both ways must land in the same place - but not as the same
	// numbers, because the two eye spaces are themselves a change of basis apart.
	// `gbufferModelView` is the similarity transform `B·V·B⁻¹`, so
	//
	//     (B·V·B⁻¹)·(B·p)  =  B·(V·p)
	//
	// - Cubyz's view position, rotated into the pack's Y-up eye space. Asserting raw equality would
	// only hold if `B` were the identity, and it fails against the *correct* matrix, which is
	// exactly the trap the old one-sided `V·B⁻¹` version hid in.
	const cubyzPoint = Vec3f{4, -6, 9};
	const packPoint = toYUp(cubyzPoint);

	const viaCubyz = transformPoint(cubyzView, cubyzPoint);
	const viaPack = transformPoint(modelView, packPoint);
	const expected = toYUp(viaCubyz);
	inline for(0..3) |i| try testing.expectApproxEqAbs(expected[i], viaPack[i], 1e-4);
}

test "upPosition points up in view space for an identity view" {
	// With no view rotation the up vector should still be +Y after Iris's -90 degree Y rotation,
	// since that rotation is about the up axis itself.
	const up = upPosition(Mat4f.identity());
	try testing.expectApproxEqAbs(@as(f32, 0), up[0], 1e-3);
	try testing.expectApproxEqAbs(@as(f32, 100), up[1], 1e-3);
	try testing.expectApproxEqAbs(@as(f32, 0), up[2], 1e-3);
}

fn length(v: Vec3f) f32 {
	return @sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2]);
}

test "the raw celestial angle puts the sun overhead at zero and on the horizon at ninety" {
	// Worth pinning down, because it is the opposite of what the `sunAngle` *uniform* reads:
	// Iris adds 90 degrees when exposing it, so a sun directly overhead reports sunAngle 0.25.
	// This function takes the raw angle, where 0 is overhead.
	//
	// Working it through: rotY(-90) after rotX(angle) applied to (0, 100, 0) gives
	// (-100*sin(angle), 100*cos(angle), 0).
	const overhead = celestialPosition(Mat4f.identity(), 0, 0, 100);
	const horizon = celestialPosition(Mat4f.identity(), 0, 90, 100);

	try testing.expectApproxEqAbs(@as(f32, 100), overhead[1], 1e-2);
	try testing.expectApproxEqAbs(@as(f32, 0), horizon[1], 1e-2);
	// The sun travels a circle, so distance is constant.
	try testing.expectApproxEqAbs(@as(f32, 100), length(overhead), 1e-2);
	try testing.expectApproxEqAbs(@as(f32, 100), length(horizon), 1e-2);
}

test "the moon sits opposite the sun" {
	// Iris passes a negative distance for the moon, which mirrors it through the origin.
	const sun = celestialPosition(Mat4f.identity(), 0, 30, 100);
	const moon = celestialPosition(Mat4f.identity(), 0, 30, -100);
	inline for(0..3) |i| try testing.expectApproxEqAbs(-sun[i], moon[i], 1e-3);
}

test "sunPathRotation tilts the sun path" {
	const upright = celestialPosition(Mat4f.identity(), 0, 0, 100);
	const tilted = celestialPosition(Mat4f.identity(), -25, 0, 100);
	// A tilted path no longer passes exactly overhead, but stays the same distance away.
	try testing.expect(tilted[1] < upright[1]);
	try testing.expectApproxEqAbs(@as(f32, 100), length(tilted), 1e-2);
	// -25 degrees of tilt: the vertical component drops to cos(25 degrees).
	try testing.expectApproxEqAbs(@as(f32, 100)*@cos(@as(f32, 25)*std.math.pi/180.0), tilted[1], 1e-2);
}

test "the shadow camera reproduces the matrix Iris ships in its own unit test" {
	// `ShadowMatrices.Tests.main`, "model view at dawn": shadowAngle 0.03451777, interval 2,
	// sunPathRotation 0, camera (0.646045982837677, 82.53274536132812, -514.0264282226562). Iris's
	// shadowAngle is the sky angle plus a quarter turn, so the sky angle here is 0.78451777.
	// Iris lists the expected matrix column-major; it is transcribed here row by row.
	const snap = shadowGridSnap(.{0.646045982837677, 82.53274536132812, -514.0264282226562}, 2.0);
	const built = shadowModelView(0.0, 0.78451777*360.0, snap);
	const expected = Mat4f{.rows = .{
		Vec4f{0.21545040607452393, -0.9765147466795349, 0.0, 0.38002151250839233},
		Vec4f{5.820481518981069e-8, 1.2841844920785661e-8, -0.9999999403953552, 1.0264281034469604},
		Vec4f{0.9765146970748901, 0.21545039117336273, 5.960464477539063e-8, -100.4463119506836},
		Vec4f{0, 0, 0, 1},
	}};
	// The same tolerance Iris's test allows itself.
	try expectMatrixApproxEqual(expected, built, 5e-4);
}

test "the shadow light lands on the camera's +Z at every hour and tilt" {
	// The rotation half of `shadowModelView` has to be the transpose of the one that places the
	// sun, or the map is rendered from somewhere other than where the pack shades from. Checked
	// across the path rotations the packs ship (Nostalgia -25, BSL -40, Complementary 35) and
	// through a full day, including the night angles the moon takes.
	const tilts = [_]f32{0, -25, -40, 35};
	const hours = [_]f32{0, 30, 77.57, 90, 120, 180, 200, 282.43, 330};
	for(tilts) |tilt| {
		for(hours) |hour| {
			const light = celestialWorldDirection(tilt, hour);
			const view = shadowModelView(tilt, hour, .{0, 0, 0});
			const inView = transformDirection(view, light);
			try testing.expectApproxEqAbs(@as(f32, 0), inView[0], 1e-4);
			try testing.expectApproxEqAbs(@as(f32, 0), inView[1], 1e-4);
			try testing.expectApproxEqAbs(@as(f32, 1), inView[2], 1e-4);
		}
	}
}

test "the shadow camera sits 100 blocks up the light ray from the player" {
	const light = celestialWorldDirection(-25, 40);
	const view = shadowModelView(-25, 40, .{0, 0, 0});
	// The player is 100 blocks in front of the camera...
	const player = transformPoint(view, .{0, 0, 0});
	try testing.expectApproxEqAbs(@as(f32, -shadowCameraDistance), player[2], 1e-4);
	// ...and the point 100 blocks towards the light is the camera itself.
	const eye = transformPoint(view, light*@as(Vec3f, @splat(shadowCameraDistance)));
	inline for(0..3) |i| try testing.expectApproxEqAbs(@as(f32, 0), eye[i], 1e-3);
}

test "the shadow ortho is Iris's, depth mapping included" {
	// `ShadowMatrices.Tests`: `createOrthoMatrix(32.0f, 0.05f, 256.0f)` has 1/32 on the diagonal,
	// -0.007814026437699795 for the depth scale and -1.000390648841858 for the depth offset.
	const projection = ortho(32.0, shadowNearDefault, shadowFarDefault);
	try testing.expectApproxEqAbs(@as(f32, 0.03125), projection.rows[0][0], 1e-7);
	try testing.expectApproxEqAbs(@as(f32, 0.03125), projection.rows[1][1], 1e-7);
	try testing.expectApproxEqAbs(@as(f32, -0.007814026437699795), projection.rows[2][2], 1e-7);
	try testing.expectApproxEqAbs(@as(f32, -1.000390648841858), projection.rows[2][3], 1e-6);
	// With the camera 100 blocks up the ray, the player lands at depth 0.39 of the map: 100 blocks
	// of the 256 lie in front of the player and 156 behind, which is the split every pack's bias and
	// depth-scale constants were written against.
	const player = projection.mulVec(.{0, 0, -shadowCameraDistance, 1});
	try testing.expectApproxEqAbs(@as(f32, 0.3905), player[2]*0.5 + 0.5, 1e-3);
}

test "the grid snap keeps Java's sign convention" {
	// `(float) cameraX % intervalSize` keeps the sign of the dividend, then half a cell is taken off.
	const snap = shadowGridSnap(.{3.5, -3.5, 0.0}, 2.0);
	try testing.expectApproxEqAbs(@as(f32, 0.5), snap[0], 1e-6);
	try testing.expectApproxEqAbs(@as(f32, -2.5), snap[1], 1e-6);
	try testing.expectApproxEqAbs(@as(f32, -1.0), snap[2], 1e-6);
	// A zero interval means no snapping, as in Iris, rather than a division by zero.
	try testing.expectEqual(Vec3f{0, 0, 0}, shadowGridSnap(.{3.5, -3.5, 0.0}, 0.0));
	// Moving within a cell changes the snap by exactly the movement, so the map's origin holds
	// still in the world until the player crosses into the next cell.
	const before = shadowGridSnap(.{10.2, 0, 0}, 2.0);
	const after = shadowGridSnap(.{11.7, 0, 0}, 2.0);
	try testing.expectApproxEqAbs(@as(f32, 1.5), after[0] - before[0], 1e-5);
}
