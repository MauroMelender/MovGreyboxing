extends Area3D
## Ítem coleccionable tipo moneda.
## Flota, gira sobre sí misma, y al ser tocada por el jugador desaparece,
## suma su valor a un contador global y muestra un popup "+N" que sale
## flotando desde su posición.
##
## Estructura de escena esperada (raíz = este script en un Area3D):
##   Moneda (Area3D)
##     MeshInstance3D   -> CylinderMesh delgado, rotado -90° en X para que
##                          la cara circular mire hacia adelante (Z), no
##                          hacia arriba. Así al girar en Y se ve la típica
##                          "cara -> canto -> cara" de moneda clásica.
##     CollisionShape3D -> forma que define el radio de pickup.
##
## Configuración necesaria:
## - El jugador debe estar en el grupo indicado en `grupo_jugador`
##   (Node > Groups en el Inspector, o add_to_group("jugador") por código).
## - El collision_layer del jugador y el collision_mask de esta Area3D
##   deben coincidir para que se detecten mutuamente.
## - (Opcional) Un autoload llamado "GestorMonedas" (ver gestor_monedas.gd)
##   para llevar un contador global. Si no existe, la moneda igual
##   funciona: solo se salta ese paso.

@export var valor: int = 1
@export var grupo_jugador: String = "jugador"

# --- Flote ---
@export var altura_flote: float = 0.15
@export var velocidad_flote: float = 2.0

# --- Rotación ---
@export var velocidad_rotacion_grados: float = 120.0

# --- Popup "+N" ---
@export var duracion_popup: float = 0.8
@export var distancia_popup: float = 0.8
@export var color_popup: Color = Color(1.0, 0.85, 0.2)
@export var tamano_fuente_popup: int = 48

var _posicion_base: Vector3
var _tiempo: float = 0.0
var _recogida: bool = false

@onready var _mesh: Node3D = $MeshInstance3D
@onready var _colision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	_posicion_base = position
	body_entered.connect(_al_entrar_cuerpo)


func _process(delta: float) -> void:
	if _recogida:
		return

	_tiempo += delta
	rotate_y(deg_to_rad(velocidad_rotacion_grados) * delta)
	position.y = _posicion_base.y + sin(_tiempo * velocidad_flote) * altura_flote


func _al_entrar_cuerpo(cuerpo: Node3D) -> void:
	if _recogida or not cuerpo.is_in_group(grupo_jugador):
		return

	_recogida = true
	_recoger()


func _recoger() -> void:
	var gestor: Node = get_node_or_null("/root/GestorMonedas")
	if gestor and gestor.has_method("agregar"):
		gestor.agregar(valor)

	_mostrar_popup()

	# Oculta la moneda y apaga su colisión ya, pero espera a que el popup
	# termine su animación antes de destruir el nodo por completo.
	_mesh.visible = false
	_colision.set_deferred("disabled", true)
	monitoring = false

	await get_tree().create_timer(duracion_popup).timeout
	queue_free()


func _mostrar_popup() -> void:
	var etiqueta := Label3D.new()
	etiqueta.text = "+%d" % valor
	etiqueta.modulate = color_popup
	etiqueta.font_size = tamano_fuente_popup
	etiqueta.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	etiqueta.no_depth_test = true
	etiqueta.global_position = global_position

	# Se agrega a la escena actual (no a la moneda) para que el popup
	# sobreviva aunque la moneda se destruya antes de terminar la animación.
	get_tree().current_scene.add_child(etiqueta)

	var tween: Tween = etiqueta.create_tween()
	tween.set_parallel(true)
	tween.tween_property(
		etiqueta, "global_position", global_position + Vector3.UP * distancia_popup, duracion_popup
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(etiqueta, "modulate:a", 0.0, duracion_popup).set_delay(duracion_popup * 0.3)
	tween.finished.connect(etiqueta.queue_free)
