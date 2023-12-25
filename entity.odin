package main

import SDL "vendor:sdl2"

Entity :: struct {
	tex:  ^SDL.Texture,
	dest: SDL.Rect,
}
