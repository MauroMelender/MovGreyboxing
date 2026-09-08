extends Node3D
class_name CadenaFisicaPesada
## Simulación de cadena física (Verlet + restricciones de distancia) para
## huesos tipo cola/mechón. A diferencia de SpringBoneSimulator3D, acá el
## movimiento del primer eslabón arrastra literalmente al resto en cascada
## (restricción de distancia resuelta en cadena), no cada hueso oscilando
## de forma independiente hacia su propia pose de reposo.

@export var hueso_raiz: String = ""
@export var hueso_punta: String = ""

@export_group("Física")
@export var gravedad: float = 9.8
@export var direccion_gravedad: Vector3 = Vector3.DOWN
## 1.0 = sin pérdida de energía (péndulo pesado real, sigue oscilando por inercia).
## Bajalo solo si se ve demasiado "vivo"; para pesado real, cerca de 1.
@export_range(0.0, 1.0, 0.001) var amortiguacion: float = 0.985
## Pocas iteraciones = se nota MÁS el arrastre/lag entre eslabones (más pesado,
## el eslabón 2 tarda en "enterarse" de lo que hizo el 1). Muchas = cadena
## casi rígida e instantánea (menos sensación de peso).
@export_range(1, 20) var iteraciones_restriccion: int = 2
## Blend contra la pose animada original (1.0 = 100% física).
@export_range(0.0, 1.0, 0.01) var influencia: float = 1.0

@export_group("Forma del hueso")
## Asume que el eje local +Y de cada hueso apunta hacia su hijo (default
## típico al exportar desde Blender). Si tu cola se ve retorcida 90°, es
## la primera propiedad a revisar.
@export var largo_ultimo_segmento: float = 0.15  # el último hueso no tiene hijo real para medir su largo

var _huesos: PackedInt32Array = []
var _puntos_actuales: PackedVector3Array = []
var _puntos_anteriores: PackedVector3Array = []
var _largos_reposo: PackedFloat32Array = []
var _listo: bool = false


func _ready() -> void:
	_construir_cadena()


func _construir_cadena() -> void:
	var skeleton := get_skeleton()
	if not skeleton:
		push_warning("CadenaFisicaPesada: no encontré el Skeleton3D padre.")
		return

	var idx_raiz := skeleton.find_bone(hueso_raiz)
	var idx_punta := skeleton.find_bone(hueso_punta)
	if idx_raiz < 0 or idx_punta < 0:
		push_warning("CadenaFisicaPesada: hueso_raiz o hueso_punta no encontrados.")
		return

	var cadena: Array[int] = []
	var actual := idx_punta
	var seguridad := 0
	while actual != -1 and seguridad < 256:
		cadena.push_front(actual)
		if actual == idx_raiz:
			break
		actual = skeleton.get_bone_parent(actual)
		seguridad += 1

	if cadena.is_empty() or cadena[0] != idx_raiz:
		push_warning("CadenaFisicaPesada: hueso_punta no desciende de hueso_raiz.")
		return

	_huesos = PackedInt32Array(cadena)
	var n := _huesos.size()
	_puntos_actuales.resize(n + 1)
	_puntos_anteriores.resize(n + 1)
	_largos_reposo.resize(n)

	for i in range(n):
		var pos: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(_huesos[i]).origin
		_puntos_actuales[i] = pos
		_puntos_anteriores[i] = pos

	var pose_ultimo := skeleton.get_bone_global_pose(_huesos[n - 1])
	var punta_local: Vector3 = pose_ultimo.origin + pose_ultimo.basis * (Vector3.UP * largo_ultimo_segmento)
	var punta_global: Vector3 = skeleton.global_transform * punta_local
	_puntos_actuales[n] = punta_global
	_puntos_anteriores[n] = punta_global

	for i in range(n):
		_largos_reposo[i] = _puntos_actuales[i].distance_to(_puntos_actuales[i + 1])

	_listo = true


func _process_modification() -> void:
	if not _listo:
		return
	var skeleton := get_skeleton()
	if not skeleton:
		return
	var delta := get_process_delta_time()
	if delta <= 0.0:
		return

	var n := _huesos.size()

	# El punto 0 (raíz) NO se simula: sigue exactamente la animación.
	# Es el ancla que "tira" del resto de la cadena.
	var pos_raiz: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(_huesos[0]).origin
	_puntos_actuales[0] = pos_raiz
	_puntos_anteriores[0] = pos_raiz

	# Integración de Verlet: inercia real con gravedad, para el resto.
	var vector_gravedad: Vector3 = direccion_gravedad.normalized() * gravedad
	for i in range(1, n + 1):
		var actual := _puntos_actuales[i]
		var velocidad := (actual - _puntos_anteriores[i]) * amortiguacion
		_puntos_anteriores[i] = actual
		_puntos_actuales[i] = actual + velocidad + vector_gravedad * delta * delta

	# Restricciones de distancia: acá es donde el primer eslabón arrastra
	# físicamente al resto, eslabón por eslabón, en vez de moverse cada uno
	# por su cuenta.
	for _iter in range(iteraciones_restriccion):
		for i in range(n):
			var p0 := _puntos_actuales[i]
			var p1 := _puntos_actuales[i + 1]
			var diferencia := p1 - p0
			var distancia := diferencia.length()
			if distancia < 0.0001:
				continue
			var correccion := diferencia.normalized() * (distancia - _largos_reposo[i])
			if i == 0:
				_puntos_actuales[i + 1] = p1 - correccion
			else:
				_puntos_actuales[i] = p0 + correccion * 0.5
				_puntos_actuales[i + 1] = p1 - correccion * 0.5

	# Convertir posiciones -> rotaciones de hueso, propagando un vector
	# "arriba" de eslabón en eslabón para que no se retuerza/flippee.
	var arriba_referencia := Vector3.RIGHT
	for i in range(n):
		var direccion := (_puntos_actuales[i + 1] - _puntos_actuales[i]).normalized()
		if direccion.length_squared() < 0.0001:
			continue
		var referencia := arriba_referencia
		if abs(direccion.dot(referencia)) > 0.999:
			referencia = Vector3.UP
		var eje_x := referencia.cross(direccion).normalized()
		var eje_z := eje_x.cross(direccion).normalized()
		arriba_referencia = eje_z

		var basis_mundo := Basis(eje_x, direccion, eje_z)
		var basis_local := skeleton.global_transform.basis.inverse() * basis_mundo
		var rotacion_simulada := basis_local.get_rotation_quaternion()
		var rotacion_original := skeleton.get_bone_pose_rotation(_huesos[i])
		skeleton.set_bone_pose_rotation(_huesos[i], rotacion_original.slerp(rotacion_simulada, influencia))
