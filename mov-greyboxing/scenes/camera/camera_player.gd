extends Node3D
## Rig de cámara en tercera persona cercana, estilo Souls-like
## (Dark Souls 3 / Sekiro / GoW Ragnarok, según el GDD).
##
## Este nodo es independiente del personaje: sigue su posición pero
## su rotación la controla el mouse, así el giro de Ziel al moverse
## no arrastra la cámara.
##
## Jerarquía esperada:
## CamaraPivote (este script)
##   └── SpringArm3D  (spring_length y collision_mask configurados en el inspector)
##         └── Camera3D

@export var objetivo: Node3D
@export var altura_objetivo: float = 1.6  # offset vertical: el origen de Ziel suele estar a nivel de los pies
@export var sensibilidad_mouse: float = 0.005
@export var angulo_minimo_grados: float = -40.0
@export var angulo_maximo_grados: float = 60.0
@export var suavizado_posicion: float = 12.0

@onready var brazo: SpringArm3D = $SpringArm3D

var rotacion_x: float = 0.0
var rotacion_y: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if objetivo:
		global_position = objetivo.global_position + Vector3.UP * altura_objetivo


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotacion_y -= event.relative.x * sensibilidad_mouse
		rotacion_x -= event.relative.y * sensibilidad_mouse
		rotacion_x = clamp(
			rotacion_x, deg_to_rad(angulo_minimo_grados), deg_to_rad(angulo_maximo_grados)
		)

	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if not objetivo:
		return
	var posicion_deseada: Vector3 = objetivo.global_position + Vector3.UP * altura_objetivo
	global_position = global_position.lerp(posicion_deseada, suavizado_posicion * delta)
	global_rotation.y = rotacion_y   # antes: rotation.y = rotacion_y
	brazo.rotation.x = rotacion_x
