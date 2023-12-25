package main

import "core:fmt"
import "core:math"
import "core:math/rand"
import SDL "vendor:sdl2"
import SDL_Image "vendor:sdl2/image"
import SDL_Mixer "vendor:sdl2/mixer"

WINDOW_FLAGS :: SDL.WINDOW_SHOWN
RENDER_FLAGS :: SDL.RENDERER_ACCELERATED
TARGET_DELTA_TIME: f64 : 1000 / 60
WINDOW_WIDTH :: 800
WINDOW_HEIGHT :: 600
PLAYER_SPEED: f64 : 500
BALL_SPEED: f64 : 550
DELTA_PLAYER_MOTION :: TARGET_DELTA_TIME * PLAYER_SPEED / 1000
DELTA_BALL_MOTION :: TARGET_DELTA_TIME * BALL_SPEED / 1000

ball_angle: int
center_x: i32
center_y: i32

game := Game{}

main :: proc() {
	assert(SDL.Init(SDL.INIT_VIDEO | SDL.INIT_AUDIO) == 0, SDL.GetErrorString())
	assert(SDL_Image.Init(SDL_Image.INIT_PNG) != nil, SDL.GetErrorString())
	assert(
		SDL_Mixer.OpenAudio(44100, SDL_Mixer.DEFAULT_FORMAT, 2, 2048) == 0,
		string(SDL_Mixer.GetError()),
	)
	defer SDL.Quit()

	window := SDL.CreateWindow(
		"Pongdin",
		SDL.WINDOWPOS_CENTERED,
		SDL.WINDOWPOS_CENTERED,
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		WINDOW_FLAGS,
	)
	assert(window != nil, SDL.GetErrorString())
	defer SDL.DestroyWindow(window)

	game.renderer = SDL.CreateRenderer(window, -1, RENDER_FLAGS)
	assert(game.renderer != nil, SDL.GetErrorString())
	defer SDL.DestroyRenderer(game.renderer)

	game.music, game.sfx1, game.sfx2, game.sfx3 = load_media()
	defer SDL_Mixer.FreeMusic(game.music)
	defer SDL_Mixer.FreeChunk(game.sfx1)
	defer SDL_Mixer.FreeChunk(game.sfx2)
	defer SDL_Mixer.FreeChunk(game.sfx3)

	game.player1 = entity_init("assets/players.png", 40, WINDOW_HEIGHT / 2)
	game.player2 = entity_init("assets/players.png", WINDOW_WIDTH - 60, WINDOW_HEIGHT / 2)

	game.ball = entity_init("assets/ball.png", WINDOW_WIDTH / 2, WINDOW_HEIGHT / 2, 2)
	ball_angle = ball_get_angle(nil)
	center_x = game.ball.dest.x
	center_y = game.ball.dest.y
	fmt.println("centered ball: ", center_x, " ", center_y)


	game.perf_frequency = f64(SDL.GetPerformanceFrequency())
	start: f64
	end: f64
	event: SDL.Event
	state := SDL.GetKeyboardState(nil)
	defer free(state)

	SDL_Mixer.PlayMusic(game.music, -1)

	game_loop: for {
		start = get_time()
		SDL.PumpEvents()
		if state[SDL.SCANCODE_ESCAPE] == 1 {
			break game_loop
		}

		move_player1(state)
		move_player2(state)
		move_ball()
		check_score()


		end = get_time()
		for end - start < TARGET_DELTA_TIME {
			end = get_time()
		}
		SDL.RenderPresent(game.renderer)
		SDL.SetRenderDrawColor(game.renderer, 0, 0, 0, 100)
		SDL.RenderClear(game.renderer)
	}

	SDL_Mixer.HaltMusic()
}

// Init functions

load_media :: proc() -> (^SDL_Mixer.Music, ^SDL_Mixer.Chunk, ^SDL_Mixer.Chunk, ^SDL_Mixer.Chunk) {
	game_music := SDL_Mixer.LoadMUS("assets/music.mp3")
	assert(game_music != nil, string(SDL_Mixer.GetError()))

	player_collision_sfx := SDL_Mixer.LoadWAV("assets/sfx1.mp3")
	assert(player_collision_sfx != nil, string(SDL_Mixer.GetError()))

	wall_collision_sfx := SDL_Mixer.LoadWAV("assets/sfx2.mp3")
	assert(wall_collision_sfx != nil, string(SDL_Mixer.GetError()))

	score_sfx := SDL_Mixer.LoadWAV("assets/sfx3.mp3")
	assert(score_sfx != nil, string(SDL_Mixer.GetError()))

	return game_music, player_collision_sfx, wall_collision_sfx, score_sfx
}

entity_init :: proc(texture_file: cstring, pos_x: i32, pos_y: i32, shrink_by: i32 = 0) -> Entity {
	texture := SDL_Image.LoadTexture(game.renderer, texture_file)
	assert(texture != nil, SDL.GetErrorString())
	destination := SDL.Rect {
		x = pos_x,
		y = pos_y,
	}
	SDL.QueryTexture(texture, nil, nil, &destination.w, &destination.h)

	if shrink_by > 0 {
		destination.w /= shrink_by
		destination.h /= shrink_by
	}

	destination.x -= destination.w / 2
	destination.y -= destination.h / 2

	return Entity{tex = texture, dest = destination}
}


// Ball functions

ball_get_angle :: proc(
	initial_angle: ^int,
	right := false,
	left := false,
	up := false,
	down := false,
) -> int {
	if initial_angle == nil {
		angle := 0
		for angle < 10 ||
		    angle > 90 && angle < 100 ||
		    angle > 170 && angle < 190 ||
		    angle > 260 && angle < 280 {
			angle = rand.int_max(350)
		}
		return angle
	}

	angle := initial_angle^

	if (right && angle > 90 && angle < 270) || left && (angle < 90 || angle > 270) {
		angle = ball_invert_direction_x()
	} else if (up && angle > 180) || (down && angle < 180) {
		angle = ball_invert_direction_y()
	}
	return angle
}

ball_invert_direction_x :: proc() -> int {
	new_angle := 180 - ball_angle
	if new_angle < 0 {
		new_angle += 360
	}
	return new_angle
}

ball_invert_direction_y :: proc() -> int {
	return 360 - ball_angle
}

ball_handle_collision :: proc() -> int {
	collided_with_player1 :=
		game.ball.dest.x <= game.player1.dest.x + game.player1.dest.w &&
		game.ball.dest.x + game.ball.dest.w >= game.player1.dest.x &&
		game.ball.dest.y + game.ball.dest.h >= game.player1.dest.y &&
		game.ball.dest.y <= game.player1.dest.y + game.player1.dest.h

	collided_with_player2 :=
		game.ball.dest.x + game.ball.dest.w >= game.player2.dest.x &&
		game.ball.dest.x <= game.player2.dest.x + game.player2.dest.w &&
		game.ball.dest.y + game.ball.dest.h >= game.player2.dest.y &&
		game.ball.dest.y <= game.player2.dest.y + game.player2.dest.h

	if collided_with_player1 {
		SDL_Mixer.PlayChannel(-1, game.sfx1, 0)
		return ball_get_angle(&ball_angle, right = true)
	}
	if collided_with_player2 {
		SDL_Mixer.PlayChannel(-1, game.sfx1, 0)
		return ball_get_angle(&ball_angle, left = true)
	}

	collided_with_ceiling := game.ball.dest.y <= 0 && game.ball.dest.x > 0
	collided_with_floor := game.ball.dest.y + game.ball.dest.h >= WINDOW_HEIGHT

	if collided_with_ceiling {
		SDL_Mixer.PlayChannel(-1, game.sfx2, 0)
		return ball_get_angle(&ball_angle, down = true)
	}
	if collided_with_floor {
		SDL_Mixer.PlayChannel(-1, game.sfx2, 0)
		return ball_get_angle(&ball_angle, up = true)
	}

	return ball_angle
}

ball_radians :: proc() -> f64 {
	return f64(ball_angle) * math.PI / 180
}

// Player functions

player_move :: proc(player: ^Entity, x, y: f64) {
	player.dest.x = clamp(player.dest.x + i32(x), 0, WINDOW_WIDTH - player.dest.w)
	player.dest.y = clamp(player.dest.y + i32(y), 0, WINDOW_HEIGHT - player.dest.h)
}

// Helper functions

score_and_reset :: proc() {
	fmt.println("score: ", game.score1, " - ", game.score2)
	SDL_Mixer.PlayChannel(-1, game.sfx3, 0)
	game.ball.dest.x = center_x
	game.ball.dest.y = center_y
	SDL.RenderCopy(game.renderer, game.ball.tex, nil, &game.ball.dest)
	ball_angle = ball_get_angle(nil)
}

get_time :: proc() -> f64 {
	return f64(SDL.GetPerformanceCounter()) * 1000 / game.perf_frequency
}

// Game loop functions

move_player1 :: proc(input: [^]u8) {
	if input[SDL.SCANCODE_W] == 1 {
		player_move(&game.player1, 0, -DELTA_PLAYER_MOTION)
	}
	if input[SDL.SCANCODE_S] == 1 {
		player_move(&game.player1, 0, DELTA_PLAYER_MOTION)
	}
	SDL.RenderCopy(game.renderer, game.player1.tex, nil, &game.player1.dest)
}

move_player2 :: proc(input: [^]u8) {
	if input[SDL.SCANCODE_UP] == 1 {
		player_move(&game.player2, 0, -DELTA_PLAYER_MOTION)
	}
	if input[SDL.SCANCODE_DOWN] == 1 {
		player_move(&game.player2, 0, DELTA_PLAYER_MOTION)
	}
	SDL.RenderCopy(game.renderer, game.player2.tex, nil, &game.player2.dest)
}

move_ball :: proc() {
	ball_angle = ball_handle_collision()
	radians := ball_radians()
	game.ball.dest.x += i32((math.cos_f64(radians) * f64(DELTA_BALL_MOTION)))
	game.ball.dest.y -= i32((math.sin_f64(radians) * f64(DELTA_BALL_MOTION)))
	SDL.RenderCopy(game.renderer, game.ball.tex, nil, &game.ball.dest)
}

check_score :: proc() {
	if game.ball.dest.x > WINDOW_WIDTH {
		game.score1 += 1
		score_and_reset()
	} else if game.ball.dest.x + game.ball.dest.w < 0 {
		game.score2 += 1
		score_and_reset()
	}
}
