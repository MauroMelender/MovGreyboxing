extends CharacterBody3D
## Controlador de locomoción base para Ziel.
## Maneja movimiento relativo a cámara, salto, caída y aterrizaje,
## y alimenta la máquina de estados del AnimationTree.
##
## Requiere las acciones de Input Map: mover_adelante, mover_atras,
## mover_izquierda, mover_derecha, correr, saltar.
##
## Estructura esperada del AnimationTree (AnimationNodeStateMachine):
##   Locomocion (BlendSpace1D: Idle/Caminar/Correr según velocidad)
##   SaltoBlend (Blend2: in_0 = Locomocion, in_1 = Anim_Z_RunJumping)
##   Anim_Z_FallingCycle
##   Anim_Z_FallingLanding

# --- Velocidades (candidatas a escalar luego con la estadística AGY) ---
@export var velocidad_caminar: float = 2.0
@export var velocidad_correr: float = 5.0
@export var aceleracion: float = 12.0
@export var friccion: float = 14.0
@export var velocidad_rotacion: float = 10.0

# --- Salto y gravedad ---
@export var fuerza_salto: float = 4.5
@export var gravedad: float = 12.0
@export var gravedad_maxima: float = 25.0

# --- Blend de entrada al salto (SaltoBlend en el AnimationTree) ---
@export var duracion_blend_salto: float = 0.12  # segundos que tarda en pasar de Locomocion a RunJumping

# --- Suavizado del blend de locomoción (independiente de la física) ---
## Qué tan rápido el blend_position de la animación "alcanza" a la velocidad
## real. Más alto = responde más rápido (más brusco en giros de 180°).
## Más bajo = más gradual, evita saltos de Idle/Walk/Run en cambios bruscos
## de dirección, a costa de un pequeño desfase entre input y animación.
@export var velocidad_suavizado_blend: float = 8.0

# --- Referencias de escena (asignar en el Inspector, no dependen de nombres fijos) ---
@export var animation_tree_path: NodePath
@export var camara_rig_path: NodePath
var arbol_animacion: AnimationTree
var camara_rig: Node3D


enum Estado {
	LOCOMOCION,
	EN_EL_AIRE,  # cubre salto y caída; el AnimationTree pasa solo de SaltoBlend a FallingCycle
	ATERRIZANDO,
}

const NOMBRES_ESTADO: Dictionary = {
	Estado.LOCOMOCION: "Locomocion",
	Estado.EN_EL_AIRE: "SaltoBlend",
	Estado.ATERRIZANDO: "Anim_Z_FallingLanding",
}

var tiempo_aterrizaje_maximo: float = 1.0  # red de seguridad si el Auto del AnimationTree no dispara
var temporizador_aterrizaje: float = 0.0
var estado_actual: Estado = Estado.LOCOMOCION
var _ultimo_estado_animado: int = -1
var estaba_en_el_aire: bool = false
var frames_en_el_piso: int = 0
const FRAMES_CONFIRMACION_PISO: int = 3

var _tiempo_en_el_aire: float = 0.0  # acumulador para rampear SaltoBlend/blend_amount
var _blend_position_suavizado: float = 0.0  # valor amortiguado que se manda al BlendSpace1D


func _ready() -> void:
	if animation_tree_path != NodePath():
		arbol_animacion = get_node(animation_tree_path)
	else:
		push_warning("jugador.gd: falta asignar animation_tree_path en el inspector.")

	if camara_rig_path != NodePath():
		camara_rig = get_node(camara_rig_path)
	else:
		push_warning("jugador.gd: falta asignar camara_rig_path en el inspector.")


func _physics_process(delta: float) -> void:
	_aplicar_gravedad(delta)
	_procesar_movimiento(delta)
	_procesar_salto()
	_actualizar_estado(delta)
	_reproducir_estado(delta)
	move_and_slide()


func _aplicar_gravedad(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravedad * delta
		velocity.y = max(velocity.y, -gravedad_maxima)
	elif velocity.y < 0.0:
		velocity.y = -0.1  # mantiene el snap al piso sin acumular caída


func _procesar_movimiento(delta: float) -> void:
	var entrada: Vector2 = Input.get_vector(
		"mover_izquierda", "mover_derecha", "mover_adelante", "mover_atras"
	)

	var direccion: Vector3 = Vector3.ZERO
	if camara_rig:
		var base_camara: Basis = camara_rig.global_transform.basis
		direccion = base_camara.x * entrada.x + base_camara.z * entrada.y
		direccion.y = 0.0
		direccion = direccion.normalized()

	var corriendo: bool = Input.is_action_pressed("correr") and direccion.length() > 0.0
	var velocidad_objetivo: float = velocidad_correr if corriendo else velocidad_caminar

	if direccion.length() > 0.0:
		var destino: Vector3 = direccion * velocidad_objetivo
		velocity.x = move_toward(velocity.x, destino.x, aceleracion * delta)
		velocity.z = move_toward(velocity.z, destino.z, aceleracion * delta)
		_rotar_hacia(direccion, delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friccion * delta)
		velocity.z = move_toward(velocity.z, 0.0, friccion * delta)


func _rotar_hacia(direccion: Vector3, delta: float) -> void:
	var angulo_objetivo: float = atan2(direccion.x, direccion.z)
	rotation.y = lerp_angle(rotation.y, angulo_objetivo, velocidad_rotacion * delta)


func _procesar_salto() -> void:
	if is_on_floor() and Input.is_action_just_pressed("saltar"):
		velocity.y = fuerza_salto
		frames_en_el_piso = 0


func _actualizar_estado(delta: float) -> void:
	if is_on_floor():
		frames_en_el_piso += 1
	else:
		frames_en_el_piso = 0

	var confirmado_en_piso: bool = frames_en_el_piso >= FRAMES_CONFIRMACION_PISO

	if not confirmado_en_piso:
		if not estaba_en_el_aire:
			_tiempo_en_el_aire = 0.0
		estaba_en_el_aire = true
		estado_actual = Estado.EN_EL_AIRE
		return

	if estaba_en_el_aire:
		estaba_en_el_aire = false
		estado_actual = Estado.ATERRIZANDO
		temporizador_aterrizaje = tiempo_aterrizaje_maximo
		return

	if estado_actual == Estado.ATERRIZANDO:
		var animacion_terminada: bool = true
		if arbol_animacion:
			var maquina = arbol_animacion.get("parameters/playback")
			if maquina and maquina.get_current_node() == "Anim_Z_FallingLanding":
				animacion_terminada = false

		temporizador_aterrizaje -= delta
		var tiempo_agotado: bool = temporizador_aterrizaje <= 0.0

		if not animacion_terminada and not tiempo_agotado:
			return

	estado_actual = Estado.LOCOMOCION


func _reproducir_estado(delta: float) -> void:
	if not arbol_animacion:
		return

	if estado_actual == Estado.LOCOMOCION:
		var velocidad_horizontal: float = Vector2(velocity.x, velocity.z).length()
		# Suavizado independiente de la física: evita que el blend de
		# animación "salte" cuando la velocidad real cambia de golpe
		# (ej. invertir dirección de golpe, frenar en seco).
		_blend_position_suavizado = move_toward(
			_blend_position_suavizado, velocidad_horizontal, velocidad_suavizado_blend * delta
		)
		arbol_animacion.set("parameters/Locomocion/blend_position", _blend_position_suavizado)

	if estado_actual == Estado.EN_EL_AIRE:
		_tiempo_en_el_aire += delta
		var t: float = clamp(_tiempo_en_el_aire / duracion_blend_salto, 0.0, 1.0)
		var suavizado: float = smoothstep(0.0, 1.0, t)
		arbol_animacion.set("parameters/SaltoBlend/Blend_RunToJumping/blend_amount", suavizado)

	if estado_actual == _ultimo_estado_animado:
		return

	var nombre_nodo: String = NOMBRES_ESTADO.get(estado_actual, "")
	if nombre_nodo == "":
		return

	var maquina = arbol_animacion.get("parameters/playback")
	maquina.travel(nombre_nodo)
	_ultimo_estado_animado = estado_actual
