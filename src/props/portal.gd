extends Node3D

## A doorway that shows, live, what's beyond its partner doorway, and takes you there when you
## walk through: a room that can't be where it looks like it is.
## The doorway is `size` (width x height): centred on local x, from local y 0 up, in the local XY
## plane, its face looking along +Z. Cross it going toward -Z and you come out of the partner's
## face, along its +Z, with your speed and facing turned to match. Works for any Character.

const _SHADER := preload("res://assets/gdshaders/portal_view.gdshader")
const _TRIGGER := 0.25 # crossing happens this far in front of the face (the view never clips)

@export var partner_path: NodePath
@export var size := Vector2(4.0, 5.0)
## The far side is only rendered while a camera is in front and this close.
@export var view_range := 50.0

var partner: Node3D
var _vp: SubViewport
var _cam: Camera3D
var _area: Area3D


func _ready() -> void:
	partner = get_node_or_null(partner_path) as Node3D
	_area = Area3D.new()
	_area.collision_mask = 0xFFFFFFFF
	_area.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y + 1.0, 3.0)
	shape.shape = box
	shape.position = Vector3(0.0, size.y * 0.5, 0.5)
	_area.add_child(shape)
	add_child(_area)
	if DisplayServer.get_name() == "headless": return # nothing to look at
	_vp = SubViewport.new()
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_cam = Camera3D.new()
	_vp.add_child(_cam)
	add_child(_vp)
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size
	quad.mesh = mesh
	quad.position = Vector3(0.0, size.y * 0.5, 0.0)
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = _SHADER
	mat.set_shader_parameter(&"view", _vp.get_texture())
	quad.material_override = mat
	add_child(quad)


## Through this doorway: here -> the partner's side.
func through() -> Transform3D:
	return partner.global_transform * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * global_transform.affine_inverse()


func _process(_delta: float) -> void:
	if not partner or not _vp: return
	var cam := get_viewport().get_camera_3d()
	if not cam: return
	var local := global_transform.affine_inverse() * cam.global_position
	var near := local.z > -0.5 and cam.global_position.distance_to(global_position) < view_range
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if near else SubViewport.UPDATE_DISABLED
	if not near: return
	var root := get_tree().root
	_vp.size = Vector2i(Vector2(root.get_visible_rect().size) * root.scaling_3d_scale)
	if not _cam.environment:
		# the main view tone-maps the doorway's pixels again: keep this one linear (no double look)
		var world_env := get_viewport().find_world_3d().environment
		if world_env:
			_cam.environment = world_env.duplicate()
			_cam.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
			_cam.environment.glow_enabled = false
	_cam.global_transform = through() * cam.global_transform
	_cam.fov = cam.fov
	_cam.far = cam.far
	# nothing between the camera and the partner's face may show (the wall the doorway sits in)
	var behind := absf((partner.global_transform.affine_inverse() * _cam.global_position).z)
	_cam.near = clampf(behind - 0.3, 0.05, 50.0)


func _physics_process(_delta: float) -> void:
	if not partner: return
	for body: Node3D in _area.get_overlapping_bodies():
		var c := body as Character
		if not c: continue
		var local := global_transform.affine_inverse() * (c.global_position + Vector3.UP * 0.9)
		if local.z < _TRIGGER and absf(local.x) < size.x * 0.5 and local.y > -0.5 and local.y < size.y:
			_send(c)


func _send(c: Character) -> void:
	var m := through()
	var vel := m.basis * c.velocity
	var to := m * c.global_position
	var out := partner.global_transform.affine_inverse() * to # come out clear of the partner's own trigger
	if out.z < _TRIGGER + 0.4: to += partner.global_basis.z * (_TRIGGER + 0.4 - out.z)
	c.teleport(to)
	c.velocity = vel
	var yaw := m.basis.get_euler().y
	var rig := c.get_node_or_null(^"CameraRig")
	if rig and rig.has_method(&"add_yaw"): rig.call(&"add_yaw", yaw)
	if c.visual: c.visual.rotation.y += yaw
