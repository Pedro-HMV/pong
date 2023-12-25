package main

import SDL "vendor:sdl2"
import SDL_Mixer "vendor:sdl2/mixer"


Game :: struct {
	perf_frequency: f64,
	renderer:       ^SDL.Renderer,
	player1:        Entity,
	player2:        Entity,
	ball:           Entity,
	score1:         i32,
	score2:         i32,
	music:          ^SDL_Mixer.Music,
	sfx1:           ^SDL_Mixer.Chunk,
	sfx2:           ^SDL_Mixer.Chunk,
	sfx3:           ^SDL_Mixer.Chunk,
}
