# SPDX-License-Identifier: Apache-2.0
## Distance and direction for live sounds: how loud, where in the stereo
## field, and how dull (air absorption) a source sounds from the listener.
##
## The listener is the viewport's current AudioListener2D/3D, else its
## camera, else (2D) the middle of the screen. Settings (all optional):
##   unit_size       distance at which the level starts to fall (px in 2D, m in 3D)
##   max_distance    beyond this the source is silent (it fades over the last 10%)
##   attenuation     "inverse" (default, like a point source), "inverse_square", "linear"
##   pan_width       2D: horizontal offset for a hard pan (0 = half the screen)
##   pan_amount      3D: how wide sources to the side pan (0..1, default 0.8)
##   air_absorption  0..1: how much the far end of the range loses its highs
class_name AKSpatial
extends RefCounted


## Level (linear) at `distance`.
static func attenuate(distance: float, s: Dictionary) -> float:
	var unit := maxf(1e-3, float(s.get("unit_size", 100.0)))
	var far := maxf(unit, float(s.get("max_distance", 2000.0)))
	var g := 1.0
	match String(s.get("attenuation", "inverse")):
		"linear":
			g = 1.0 - clampf((distance - unit) / maxf(1e-3, far - unit), 0.0, 1.0)
		"inverse_square":
			var r := unit / maxf(unit, distance)
			g = r * r
		_:
			g = unit / maxf(unit, distance)
	# Fade to silence over the last tenth of the range so nothing pops off.
	var edge := clampf((far - distance) / (0.1 * far), 0.0, 1.0)
	return g * edge


## Low-pass cutoff (Hz) for `distance`: `base_hz` near, down to a tenth of it
## (at full absorption) at max_distance.
static func air_cutoff(distance: float, s: Dictionary, base_hz := 18000.0) -> float:
	var a := clampf(float(s.get("air_absorption", 0.0)), 0.0, 1.0)
	if a <= 0.0:
		return base_hz
	var far := maxf(1e-3, float(s.get("max_distance", 2000.0)))
	return base_hz * pow(0.1, a * clampf(distance / far, 0.0, 1.0))


## {gain, pan, distance, cutoff_scale} for a 2D source at `pos` heard from `listener`.
static func compute_2d(listener: Vector2, pos: Vector2, s: Dictionary, half_width := 576.0) -> Dictionary:
	var d := listener.distance_to(pos)
	var w := float(s.get("pan_width", 0.0))
	if w <= 0.0:
		w = half_width
	return {gain = attenuate(d, s), pan = clampf((pos.x - listener.x) / maxf(1.0, w), -1.0, 1.0), distance = d,
		cutoff_scale = air_cutoff(d, s, 1.0)}


## The same for a 3D source; `listener` is the listener's global transform.
static func compute_3d(listener: Transform3D, pos: Vector3, s: Dictionary) -> Dictionary:
	var rel := pos - listener.origin
	var d := rel.length()
	var right := listener.basis.x.normalized()
	var p := right.dot(rel / d) * clampf(float(s.get("pan_amount", 0.8)), 0.0, 1.0) if d > 1e-6 else 0.0
	return {gain = attenuate(d, s), pan = clampf(p, -1.0, 1.0), distance = d, cutoff_scale = air_cutoff(d, s, 1.0)}


## Where a 2D listener is in `vp`, in canvas (world) coordinates.
static func listener_2d(vp: Viewport) -> Vector2:
	var l := vp.get_audio_listener_2d()
	if l:
		return l.global_position
	var cam := vp.get_camera_2d()
	if cam:
		return cam.get_screen_center_position()
	return vp.get_canvas_transform().affine_inverse() * (vp.get_visible_rect().size * 0.5)


static func listener_3d(vp: Viewport) -> Variant:
	var l := vp.get_audio_listener_3d()
	if l:
		return l.global_transform
	var cam := vp.get_camera_3d()
	if cam:
		return cam.global_transform
	return null


## Spatial values for `node` (a Node2D or Node3D in the tree), or {} when
## there's nothing to hear it from.
static func for_node(node: Node, s: Dictionary) -> Dictionary:
	if node == null or not node.is_inside_tree():
		return {}
	var vp := node.get_viewport()
	if node is Node2D:
		return compute_2d(listener_2d(vp), (node as Node2D).global_position, s, vp.get_visible_rect().size.x * 0.5)
	if node is Node3D:
		var l: Variant = listener_3d(vp)
		return compute_3d(l, (node as Node3D).global_position, s) if l != null else {}
	return {}
