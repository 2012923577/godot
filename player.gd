extends CharacterBody2D
var default_gravity :=ProjectSettings.get("physics/2d/default_gravity") as float

@onready var state_machine: StateMachine = $StateMachine
@onready var checker: Node2D = $checker
@onready var headchecker: RayCast2D = $checker/headchecker
@onready var footchecker: RayCast2D = $checker/footchecker


@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var coyote_timer: Timer = $CoyoteTimer
@onready var jump_request_timer: Timer = $JumpRequestTimer
@onready var attack_request_timer: Timer = $AttackRequestTimer
@onready var attack_late_timer: Timer = $AttackLateTimer
enum State{
	IDLE,
	RUNNING,
	JUMP,
	FALL,
	LANDING,
	WALL_SLIDING,
	WALL_JUMP,
	ATTACK_1,
	ATTACK_2,
	ATTACK_3,
}
const GROUND_STATES:=[State.IDLE,State.RUNNING,State.LANDING,State.ATTACK_1,State.ATTACK_2,State.ATTACK_3]
const RUN_SPEED:=300
const FLOOR_ACCELERATION:=RUN_SPEED/0.2
const AIR_ACCELERATION:=RUN_SPEED/0.2 
const JUMP_VELOCITY:=-420
const  WALL_JUMP_VELOCITY:=Vector2(500,-320)
var is_first_tick:=false
var last_attack:=0

	
@export var can_combo:=false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		jump_request_timer.start()
	if event.is_action_released("jump"):
		jump_request_timer.stop()
		if velocity.y<JUMP_VELOCITY/2:
			velocity.y=JUMP_VELOCITY/2
	if event.is_action_pressed("attack"):
		attack_request_timer.start()

func tick_physics(state:State,delta: float) -> void:
	var direction:=Input.get_axis("move_left","move_right")
	if attack_late_timer.time_left==0.01:
		last_attack=0
	match state:
		State.IDLE:
			move(default_gravity,delta)
		State.RUNNING:
			move(default_gravity,delta)
		State.JUMP:
			move(0 if is_first_tick else default_gravity,delta)
		State.FALL:
			move(default_gravity,delta)
		State.LANDING:
			stand(default_gravity,delta)
		State.WALL_SLIDING:
			move(default_gravity/3,delta)
			sprite_2d.scale.x= -get_wall_normal().x
			
		State.WALL_JUMP:
			if is_first_tick:
				sprite_2d.scale.x= get_wall_normal().x				
			if state_machine.state_time<0.1:
				stand(0 if is_first_tick else default_gravity,delta)			
			move( default_gravity,delta)
		State.ATTACK_1,State.ATTACK_2,State.ATTACK_3:	
			stand(0 if is_first_tick else default_gravity,delta)
	is_first_tick=false
	
	
func move(gravity:float,delta: float)->void:
	var direction:=Input.get_axis("move_left","move_right")
	var ACCELERATION:=FLOOR_ACCELERATION if is_on_floor() else AIR_ACCELERATION
	velocity.x=move_toward(velocity.x,direction*RUN_SPEED,ACCELERATION*delta)
	velocity.y += gravity*delta
	if not is_zero_approx(direction):
		sprite_2d.scale.x=-1 if direction<0 else 1
		checker.scale.x=-1 if direction<0 else 1
		
		
	move_and_slide()
	
func stand(gravity:float,delta: float)->void:
	var ACCELERATION:=FLOOR_ACCELERATION if is_on_floor() else AIR_ACCELERATION
	velocity.x=move_toward(velocity.x,0.0,ACCELERATION*delta)
	velocity.y += gravity*delta
	move_and_slide()

func  can_wall_slide()->bool:
	return is_on_wall() and headchecker.is_colliding() and footchecker.is_colliding()
	
func get_next_state(state:State)->State:
	var direction:=Input.get_axis("move_left","move_right")
	var is_still:=is_zero_approx(direction) and is_zero_approx(velocity.x)
	var can_jump:=is_on_floor() or coyote_timer.time_left>0
	var should_jump:=can_jump and jump_request_timer.time_left>0
	
	var should_attack:=is_on_floor() and attack_request_timer.time_left>0
	var should_combo:=can_combo and attack_request_timer.time_left>0
	
	if state in GROUND_STATES and not is_on_floor():
		return State.FALL 
	
	if should_jump:
		return State.JUMP
	match state:
	
		State.IDLE:	
			if not is_still:
				return State.RUNNING
			if should_attack:
				match last_attack:
					0:
						return State.ATTACK_1
					1:
						return State.ATTACK_2
					2:
						return State.ATTACK_3
				
		State.RUNNING:
			if is_still:
				return State.IDLE
			if should_attack:
				match last_attack:
					0:
						return State.ATTACK_1
					1:
						return State.ATTACK_2
					2:
						return State.ATTACK_3	
		State.JUMP:
			if velocity.y>=0:
				return State.FALL
			
		State.FALL:
			if is_on_floor() :
				return State.LANDING if is_still else State.RUNNING
			if (can_wall_slide() and not is_first_tick and direction!=0) or (can_wall_slide() and velocity.x!=0):
				return State.WALL_SLIDING
		State.LANDING:
			if not animation_player.is_playing():
				return State.IDLE
			if not is_still:
				return State.RUNNING
		State.WALL_SLIDING:
			if is_on_floor() :
				return State.IDLE 
			if  direction==get_wall_normal().x:
				return State.FALL
			if jump_request_timer.time_left>0 and not is_first_tick:
				return State.WALL_JUMP 
		State.WALL_JUMP:
			if can_wall_slide() and not is_first_tick :
				return State.WALL_SLIDING
			if velocity.y>=0:
				return State.FALL
		State.ATTACK_1:
			
			if  not animation_player.is_playing():
				attack_late_timer.start()
				return State.ATTACK_2 if should_combo else State.IDLE
	
		State.ATTACK_2:			
			
			if not animation_player.is_playing():
				
				attack_late_timer.start()
				return State.ATTACK_3 if should_combo else State.IDLE
			
		State.ATTACK_3:
			
			if  not animation_player.is_playing():
				return State.IDLE
			
	return state
	
func transition_state(from: State,to: State)->void:
	print("[%s] %s=>%s" % [Engine.get_physics_frames(),State.keys()[from] if from !=-1 else "start",State.keys()[to]])
	
	if from not in GROUND_STATES and to in GROUND_STATES:
		coyote_timer.stop()
	match to:
		State.IDLE:
			animation_player.play("idle")
		State.RUNNING:
			animation_player.play("running")
		State.JUMP:
			animation_player.play("jump")
			velocity.y=JUMP_VELOCITY
			coyote_timer.stop()
			jump_request_timer.stop()
		State.FALL:
			animation_player.play("fall")
			if from in GROUND_STATES:
				coyote_timer.start()
		State.LANDING:
			animation_player.play("landing")
		State.WALL_SLIDING:
			animation_player.play("wall_sliding")
			
			velocity.y=0
		State.WALL_JUMP:
			animation_player.play("jump")
			velocity=WALL_JUMP_VELOCITY
			velocity.x *=get_wall_normal().x
			jump_request_timer.stop()
			checker.scale.x=get_wall_normal().x
			
		State.ATTACK_1:
			animation_player.play("attack_1")
			last_attack=1
		State.ATTACK_2:
			animation_player.play("attack_2")
			attack_request_timer.stop()
			last_attack=2
		State.ATTACK_3:
			animation_player.play("attack_3")
			attack_request_timer.stop()
			last_attack=0
	is_first_tick=true
