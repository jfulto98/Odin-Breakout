package breakout

import "core:fmt"
import "core:time"
import "core:os"
import "core:strings"

import SDL "vendor:sdl2"
import mix "vendor:sdl2/mixer"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"

import "core:log"
import "core:mem"


oldTime:f32

window : ^SDL.Window

main :: proc() {

	//https://www.youtube.com/watch?v=dg6qogN8kIE&ab_channel=KarlZylinski
	//https://odin-lang.org/docs/overview/#file-suffixes
	//(code block under the when statement table
	context.logger = log.create_console_logger()

	tracking_allocator : mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking_allocator, context.allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)

	defer{
		if len(tracking_allocator.allocation_map) > 0{
			fmt.eprintf("=== %v allocations not freed: ===\n", len(tracking_allocator.allocation_map))
			for _, entry in tracking_allocator.allocation_map{
				fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
			}
		}

		if len(tracking_allocator.bad_free_array) > 0{
			fmt.eprintf("=== %v incorrect frees: ===\n", len(tracking_allocator.bad_free_array))
			for entry in tracking_allocator.bad_free_array{
				fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
			}

		}

		mem.tracking_allocator_destroy(&tracking_allocator)

	}


    //SDL setup

	// if SDL.Init( SDL.INIT_VIDEO ) < 0 {
    //     fmt.eprintln( "SDL could not initialize! SDL_Error:", SDL.GetError())
	// 	return
    // }

	// window = SDL.CreateWindow("Odin Breakout", SDL.WINDOWPOS_UNDEFINED, SDL.WINDOWPOS_UNDEFINED, WINDOW_WIDTH, WINDOW_HEIGHT, SDL.WINDOW_SHOWN)
	window := SDL.CreateWindow("Odin Breakout", SDL.WINDOWPOS_UNDEFINED, SDL.WINDOWPOS_UNDEFINED, WINDOW_WIDTH, WINDOW_HEIGHT, {.OPENGL})
	if window == nil {
		fmt.eprintln("Failed to create window")
		return
	}

	//AUDIO setup: based on https://lazyfoo.net/SDL_tutorials/lesson11/index.php
	if SDL.Init(SDL.INIT_AUDIO) < 0{
		fmt.eprintln("Failed to init all SDL subsystems")
	}

	//!!!FOR MP3s, you need to have the libmpg123-0.dll in your directory, otherwise
	//you get an mp3 not supported error and you can't load/play mp3s
	result := mix.Init(mix.INIT_MP3) 
	if result != i32(mix.INIT_MP3){
		fmt.eprintln("could not init mp3 with mixer, result:", result)
		fmt.eprintln("mix.GetError:", mix.GetError())
		
	}

	//init the audio functions
	//params are: sound freq, format, number of channels, sample size
	//DEFAULT_FORMAT is AUDIO_S16SYS
	if mix.OpenAudio(22050, mix.DEFAULT_FORMAT, 2, 640) < 0{
		fmt.eprintfln("sdl2/mixer OpenAudio proc failed")
		return
	}


	defer SDL.DestroyWindow(window)
	defer SDL.Quit()

	
    // //OpenGL setup
	gl_context := SDL.GL_CreateContext(window)
	SDL.GL_MakeCurrent(window, gl_context)
	// load the OpenGL procedures once an OpenGL context has been established
	gl.load_up_to(3, 3, SDL.gl_set_proc_address)


	loadResources()

    initGame()

	initTextRenderer()
	loadTextRenderer("OCRAEXT.TTF", 64)
	

	// high precision timer
	start_tick := time.tick_now()
	
	/*
		//SDL Surface testing
		// screenSurface := SDL.GetWindowSurface(window)
		// testSurface := SDL.LoadBMP(strings.clone_to_cstring("textures/hello_world.bmp"))
		// // testSurface := SDL.LoadBMP(strings.clone_to_cstring("textures/face.png"))
		// // doesn't seem to work with pngs, you need bmp

		// fmt.println("screenSurface, testSurface:", screenSurface, testSurface)

		// SDL.BlitSurface(testSurface, nil, screenSurface, nil)

		// //swap the window
		// SDL.UpdateWindowSurface(window)		
	*/

    //main loop
    //
	loop: for {
		duration := time.tick_since(start_tick)
		t := f32(time.duration_seconds(duration))
        deltaTimeSeconds := t - oldTime
        oldTime = t

        // fmt.println("deltaTimeSeconds:", deltaTimeSeconds)
        update(deltaTimeSeconds)
        //update handles the input for the game as well.

		//INPUT event polling
		event: SDL.Event
		
		for SDL.PollEvent(&event) {
			// #partial switch tells the compiler not to error if every case is not present
			#partial switch event.type {
				case .KEYDOWN:
					#partial switch event.key.keysym.sym {
						case .ESCAPE:
							break loop

						case .R:
							reloadLevel()
						case .M:
							toggleMute()
					}

				case .QUIT:
					break loop
				}


			if event.type == .KEYUP{
				// fmt.println("scancode up:",event.key.keysym.scancode)
				keysProcessed[event.key.keysym.scancode] = false
			}

		}
		
        gl.Viewport(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)

        renderGame()


		SDL.GL_SwapWindow(window)	


		if len(tracking_allocator.bad_free_array)>0{
			for b in tracking_allocator.bad_free_array{
				log.errorf("bad free at %v", b.location) 
			}

			panic("bad free detected")

		}
		
		free_all(context.temp_allocator)
		
    }//main loop

    clearResources()
	clearGame()
	clearParticles()


}
