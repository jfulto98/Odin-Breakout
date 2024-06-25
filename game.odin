package breakout

import "core:fmt"
import "core:os"
import "core:strings"
import "core:math/rand"

import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import stbi "vendor:stb/image"
import SDL "vendor:sdl2"

import mix "vendor:sdl2/mixer"

spriteVAO: u32

GameState :: enum{ GAME_ACTIVE, GAME_MENU, GAME_WIN}
Direction :: enum{ UP, DOWN, LEFT, RIGHT}

gameState : GameState

PLAYER_SIZE :: glm.vec2{100.0, 20.0}
PLAYER_VELOCITY :: f32(500.0)

BALL_RADIUS :: 12.5
INITIAL_BALL_VELOCITY :: glm.vec2{100.0, -350.0}

POWER_UP_SIZE :: glm.vec2{60.0, 20.0}
POWER_UP_VELOCITY :: glm.vec2{0.0, 150.0}


//gameobjects : search "frog" on the odin overview page for 
//inheritance for structs, and how to do polymorphism

GameObject :: struct{
    position, size, velocity : glm.vec2,
    color : glm.vec3,
    rotation : f32,
    isSolid : bool,
    destroyed : bool,

    texture_name : string
}

BallObject :: struct{
    
    using gameObject : GameObject,
  
    /*
        //see Overview page -> using statement section for more details, but 
        //basically using acts as a way of bringing the members/entities of a given
        //scope/namespace into the current scope. 
        //So here this means, instead of doing ballObject.gameObject.position 
        //(which is what you would have to do if you omitted the using keyword)
        //you can just do ballObject.position (the position is from gameObject)
        //This is how you do inheritance with structs.
        //You can even do polymorphism, eg a proc that takes in a GameObject can now
        //take in a ball object 
    */

    radius: f32,
    stuck: bool,

    sticky: bool,
    passThrough:bool,
}

PowerUpObject :: struct{

    using gameObject : GameObject,

    type : string,
    duration : f32,
    activated : bool

}

player : GameObject
ball : BallObject


//doing this instead of having a gameobject class/struct,
//for a bigger project with more stuff in each level it might make more sense 
//to have an object, but it looks like in the tut they're basically doing this
//anyways, since switching/reloading a level involves clearing that level object's brick vector,
//and refilling it with data from file. (I guess it's more for organizing the functions, which
//isn't required here)

//currentLevelFile exists so that eg when you call reset, you reset the same file

currentLevelndex : u32
levelPaths : [dynamic]string


bricks : [dynamic]GameObject 


proj : glm.mat4
//the projection matrix is here since it's meant to be used as a uniform for both
//the default and particle shader, and to be consistent with the other uniforms,
//I'm going to use it each time in the respective draw/render functions
//I'm currently setting it once in the init game func


powerUps : [dynamic]PowerUpObject

DEFAULT_LIVES :: u32(3)
lives : u32 


keysProcessed : [1024]bool

initGame :: proc(){
    //!!!!REMEMBER, this proc calls procs that depend on opengl/sdl/etc being initialized already 
    //loads all the shaders/textures/levels etc, sets up the mats -> basically the setup for
    //the whole game, not just the 'game' logic, but the rendering as well.


    //moved this from main to here, since this is where the vao should be
    Vertex :: struct{
        pos: glm.vec3,
        texcoord: glm.vec2
    }

	vertices := []Vertex{
		//positions     //texcoords
        {{0.0, 0.0, 0}, {0.0, 1.0}},
		{{1.0, 1.0, 0}, {1.0, 0.0}},
		{{0.0, 1.0, 0}, {0.0, 0.0}},

        {{0.0, 0.0, 0}, {0.0, 1.0}},
		{{1.0, 0.0, 0}, {1.0, 1.0}},
		{{1.0, 1.0, 0}, {1.0, 0.0}},
    }
    
    //vbo: note-> vbo just stores all the data in a buffer, while the vao actaully defines which part of the 
    //data means what (pos, tex coord, color, etc)
    //ebo (element buffer) stores indices so you can reuse vertices)

    vbo: u32
    gl.GenBuffers(1, &vbo); 
	gl.GenVertexArrays(1, &spriteVAO); 
	
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
    gl.BindVertexArray(spriteVAO)
    //!!MAKE SURE THE VAO IS BOUND BEFORE DOING ALL THE BUFFER DATA STUFF
    //otherwise nothing will render.
    //see the comment in the sdl2 odin demo for details.

	gl.BufferData(gl.ARRAY_BUFFER, len(vertices)*size_of(vertices[0]), raw_data(vertices), gl.STATIC_DRAW)
	
    gl.EnableVertexAttribArray(0)
	gl.VertexAttribPointer(0, 3, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, pos))
	gl.EnableVertexAttribArray(1)
	gl.VertexAttribPointer(1, 2, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, texcoord))
	
 

    gl.BindVertexArray(0)



    proj = glm.mat4Ortho3d(0.0, WINDOW_WIDTH, WINDOW_HEIGHT, 0.0, -1.0, 1.0)
    //checked in c++, mat4Ortho3d is the  same as glm::ortho(...
    //I guess they just wanted the naming convention to be consistent
    // proj := glm.mat4(1.0)
    // proj := glm.mat4(1.0) * glm.mat4Translate(glm.vec3{0.3,0.3,0.3})


    //load levels
    //unlike textures/shaders, these are loaded dynamically, so
    //I'm just setting up the name map here
    //even this is overkill, could just have an array of paths, but 
    //doing it this way for now to be consistent
    append(&levelPaths, "levels/test.lvl")
    append(&levelPaths, "levels/one.lvl")
    append(&levelPaths, "levels/two.lvl")
    append(&levelPaths, "levels/three.lvl")
    append(&levelPaths, "levels/four.lvl")

    loadGameLevel(0, WINDOW_WIDTH, WINDOW_HEIGHT/2)


    //player
    playerPos := glm.vec2{WINDOW_WIDTH/2.0 - PLAYER_SIZE.x/2.0, WINDOW_HEIGHT - PLAYER_SIZE.y}

    player = GameObject{position = playerPos,
                            size = PLAYER_SIZE,
                            texture_name = "paddle",
                            isSolid = true, 
                            color = glm.vec3(1.0)}
    

    //ball
    ballPos := player.position + glm.vec2{player.size.x/2.0 - BALL_RADIUS, -BALL_RADIUS*2}
    ball = BallObject{position = ballPos,
                          size = glm.vec2(BALL_RADIUS*2),
                          texture_name = "face",
                          isSolid = true, 
                          color = glm.vec3(1.0),
                          velocity = INITIAL_BALL_VELOCITY,
                          radius = BALL_RADIUS,
                          stuck = true

                        }

    gameState = GameState.GAME_MENU

    initParticles()
    
    //!!don't forget to actually initPostProcessor
    initPostProcessor()

    mus := mix.LoadMUS("breakout.mo3")
    mix.PlayMusic(mus, 1)

	playMusic("breakout")
    
}



loadGameLevel :: proc(level_index: u32, level_width: int, level_height: int){
    //reads the level in from file, then calls initGameLevel and passes through the args, as
    //well as the loaded data, to actaully be processed and turned into a level struct

    file_path := levelPaths[level_index]

    tileData : [dynamic]rune
    defer delete(tileData)

    //https://odin-lang.org/news/read-a-file-line-by-line/

    data, ok := os.read_entire_file(file_path, context.allocator)

    if !ok{
        fmt.eprintln("Could not read file in loadGameLevel, file_path:", file_path)
        return
    }

    defer delete(data, context.allocator)

    it := string(data)

    rows, cols : u32
    lines := strings.split_lines(it, context.temp_allocator)
    rows = u32(len(lines))
    cols = u32(len(strings.fields(lines[0], context.temp_allocator)))


    fmt.println("rows, cols:", rows, cols)

    for line in lines{
        fmt.println("line:",line)


        line := line
        //!!note: after testing/looking at docs, for statements have their own scope,
        //so if you defer in a for loop the deferred statement will run at the end of the
        //iteration it's called in.

        for character in strings.fields(line, context.temp_allocator){
            // fmt.println("character:", character)
            append(&tileData, rune(character[0]))
        }

    }

    fmt.println("tileData:", tileData)

    fmt.println("len(tileData):", len(tileData))
    if len(tileData) > 0{
        initGameLevel(tileData, rows, cols, level_width, level_height)
    }


    currentLevelndex = level_index

}


initGameLevel :: proc(tileData:[dynamic]rune, rows, cols :u32, level_width, level_height : int ){
    ///takes in data and fills the passed in level struct

    clear(&bricks)

    //calc dimensions
    dataHeight := rows
    dataWidth := cols

    fmt.println("data height, width:", dataHeight, dataWidth)
    fmt.println("level height, width:", level_height, level_width)


    unitWidth := f32(level_width)/f32(dataWidth)
    unitHeight := f32(level_height)/f32(dataHeight)
    
    fmt.println("unit height, width:", unitHeight, unitWidth)

    //init tiles based on tiledata
    for x in 0..<dataHeight{
        //rows

        for y in 0..<dataWidth{
            //cols

            tileDataIndex := (x * cols) + y

            if tileData[tileDataIndex] != '0'{
                
                pos := glm.vec2{unitWidth * f32(y), unitHeight * f32(x)}
                _size := glm.vec2{unitWidth, unitHeight}

                _color : glm.vec3

                switch tileData[tileDataIndex]{

                case '1':
                    _color = glm.vec3{0.8, 0.8, 0.7}
                
                case '2':
                    _color = glm.vec3{0.2, 0.6, 1.0}

                case '3':  
                    _color = glm.vec3{0.0, 0.7, 0.0}

                case '4':  
                    _color = glm.vec3{0.8, 0.8, 0.4}

                case '5':  
                    _color = glm.vec3{1.0, 0.5, 0.0}
                }

                tex_name : string
                isSolid : bool

                if tileData[tileDataIndex] == '1'{
                    //solid
                    tex_name = "block_solid"   
                    isSolid = true

                }else{
                    //not solid (destroyable
                    tex_name = "block"   
                    isSolid = false
                }
                

                append(&bricks, GameObject{position = pos, size = _size, texture_name = tex_name, color = _color, isSolid = isSolid})
            }
        }
    }   

    lives = DEFAULT_LIVES

}


update :: proc(dt: f32){

    if gameState == .GAME_ACTIVE{
        // fmt.println("pp_shake:", pp_shake, "shakeTime:",shakeTime)

        //ball stuff -> in the tut, these have their own funcs, for now just putting in here 
        processGameInput(dt)


        if !ball.stuck{
            ball.position += ball.velocity * dt

            if ball.position.x <= 0.0{
                ball.velocity.x = -ball.velocity.x
                ball.position.x = 0.0
            }
            else if ball.position.x>= WINDOW_WIDTH - ball.size.x {
                ball.velocity.x = -ball.velocity.x
                ball.position.x = WINDOW_WIDTH - ball.size.x
            }


            if ball.position.y <= 0.0{
                ball.velocity.y = -ball.velocity.y
                ball.position.y = 0.0
            }
        }

        doCollisions()

        if ball.position.y > WINDOW_HEIGHT{

            if lives == 0{
                reloadLevel()
                gameState = GameState.GAME_MENU
            }
            else{ 
                lives -= 1
                resetLevel()
            }
            
        }

        updateParticles(dt, ball, 2, glm.vec2(ball.radius/2.0))

        if shakeTime>0.0{
            shakeTime -= dt
            if shakeTime <= 0.0{
                pp_shake = false
            }
        }

        updatePowerUps(dt)

        if checkForWin(){
            fmt.println("WIN!!")
            gameState = .GAME_WIN            
            
            resetLevel()
            pp_chaos = true

        }

    }

    if gameState == .GAME_MENU{

        processMenuInput()

    }

    if gameState == .GAME_WIN{
        processWinInput()
    }
}


renderGame :: proc(){
    //goes through everything that needs to be drawn and draws it.

    beginRenderPostProcessor()

        
    // drawSprite("test", glm.vec2{100,100}, glm.vec2{400,400}, 0.0)

    drawSprite("background", glm.vec2(0.0), glm.vec2{WINDOW_WIDTH, WINDOW_HEIGHT}, 0.0, glm.vec3(1.0))

    //draw bricks
    for &tile in bricks{
        if !tile.destroyed{
            drawSprite(tile.texture_name, tile.position, tile.size, tile.rotation, tile.color)    
        }    
    }    

    //player
    drawSprite(player.texture_name, player.position, player.size, player.rotation, player.color)

    //particles
    renderParticles()

    //ball
    drawSprite(ball.texture_name, ball.position, ball.size, ball.rotation, ball.color)


    for powerUp in powerUps{
        if !powerUp.destroyed{
            drawSprite(powerUp.texture_name, powerUp.position, powerUp.size, powerUp.rotation, powerUp.color)

        }
    }
    
    if gameState == GameState.GAME_MENU{
        renderText("Press ENTER to start", 210.0, WINDOW_HEIGHT/2, 0.5, glm.vec3(1.0))
        renderText("Press UP or DOWN to select level", 219.0, WINDOW_HEIGHT/2 + 30.0, 0.3, glm.vec3(1.0))
    }

    if gameState == GameState.GAME_WIN{
        renderText("You WON!!!", 330.0, WINDOW_HEIGHT/2, 0.5, glm.vec3{0.0, 1.0, 0.0})
        renderText("Press ENTER to continue or ESC to quit", 200.0, WINDOW_HEIGHT/2 + 30.0, 0.3, glm.vec3{1.0, 1.0, 0.0})
    }

    //tprintf uses the temp allocator, which is a part of the context (along side the normal allocator)
    //it's meant for short lived allocations, and you're supposed to call free_all(context.temp_allocator) once per
    //frame -> I added this to the main loop
    livesStr := fmt.tprintf("Lives: %d", lives)
    renderText(livesStr, 5.0, 5.0, 0.5, glm.vec3(1.0))

    endRenderPostProcessor()
    renderPostProcessor(f32(SDL.GetTicks()) / 1000.0)
    //want total time here, not dt -> shaders have sin functions 
    
}


processGameInput :: proc(dt: f32){
    //!!for when game is active, not in menu/etc

    keyboardState := SDL.GetKeyboardState(nil)

    // fmt.println("keyboardState[SDL.SCANCODE_LEFT]:", keyboardState[SDL.SCANCODE_LEFT])

    velocity := PLAYER_VELOCITY * dt

    // fmt.println("velocity:", velocity)

    if keyboardState[SDL.SCANCODE_LEFT] == 1{

        amountToMove := player.position.x - velocity <= 0 ? -player.position.x : -velocity 
        
        player.position.x += amountToMove
        if ball.stuck do ball.position.x += amountToMove

    }

    if keyboardState[SDL.SCANCODE_RIGHT] == 1{
        amountToMove := player.position.x + velocity >= WINDOW_WIDTH - player.size.x ? WINDOW_WIDTH - (player.position.x + player.size.x) : velocity 
        
        player.position.x += amountToMove
        if ball.stuck do ball.position.x += amountToMove

    }

    if keyboardState[SDL.SCANCODE_SPACE] == 1{
        if ball.stuck{
            ball.stuck = false
            playChunk("bleep2")
        }
    }
}

processMenuInput :: proc(){
    keyboardState := SDL.GetKeyboardState(nil)

    if keyboardState[SDL.SCANCODE_RETURN] == 1 && !keysProcessed[SDL.SCANCODE_RETURN]{
        gameState = GameState.GAME_ACTIVE
        keysProcessed[SDL.SCANCODE_RETURN] = true
    }

    if keyboardState[SDL.SCANCODE_UP] == 1 && !keysProcessed[SDL.SCANCODE_UP]{
        currentLevelndex = (currentLevelndex + 1) % u32(len(levelPaths))
        loadGameLevel(currentLevelndex, WINDOW_WIDTH, WINDOW_HEIGHT/2)
        keysProcessed[SDL.SCANCODE_UP] = true

    }

    if keyboardState[SDL.SCANCODE_DOWN] == 1 && !keysProcessed[SDL.SCANCODE_DOWN]{
        currentLevelndex = currentLevelndex - 1 if currentLevelndex >0 else u32(len(levelPaths)-1) 
        loadGameLevel(currentLevelndex, WINDOW_WIDTH, WINDOW_HEIGHT/2)
        keysProcessed[SDL.SCANCODE_DOWN] = true
    
    }
}


processWinInput :: proc(){
    keyboardState := SDL.GetKeyboardState(nil)
    //quitting is handled by the event polling in the main loop


    if keyboardState[SDL.SCANCODE_RETURN] == 1 && !keysProcessed[SDL.SCANCODE_RETURN]{
        
        keysProcessed[SDL.SCANCODE_RETURN] = true
        gameState = GameState.GAME_MENU
        
        pp_chaos = false
        reloadLevel()
    }
}

checkCollisionAABBToAABB :: proc(one : GameObject, two: GameObject)-> bool{
    collisionX := one.position.x + one.size.x > two.position.x && 
        two.position.x + two.size.x >= one.position.x 
    
    collisionY := one.position.y + one.size.y >= two.position.y &&
        two.position.y + two.size.y >= one.position.y 

    return collisionX && collisionY

}

checkCollisionCircleToAABB :: proc(one: BallObject, two:GameObject)->(bool, Direction, glm.vec2){
    
    //idea is to find closest position on the aabb to the ball's center.
    //if the distance btw the ball's center and the position is < radius, then the ball is colliding.
    //to get the distance, you need to find that position
    //to find the position, you take the vector from the ball's center to the aabb's center
    //then you clamp that vector to the half extents of the aabb, effectively projecting the endpoint
    //to the side of the aabb -> this is your position, then you take the distance btw it and the ball center,
    //compare against radius.

    // fmt.println("doingCircleCollision!!!")

    //get center point circle
    ball_center := one.position + one.radius
    
    //half extents and center
    aabb_half_extents := glm.vec2{two.size.x/2.0, two.size.y/2.0}
    aabb_center := two.position + aabb_half_extents
    
    //get difference vector between both centers
    difference_vec := ball_center - aabb_center
    clamped_difference_vec := glm.clamp(difference_vec, -aabb_half_extents, aabb_half_extents)

    closest_point := aabb_center + clamped_difference_vec

    difference := closest_point - ball_center
    
    // return glm.length(difference) < one.radius
    if glm.length(difference) < one.radius{
        return true, vectorDirection(difference), difference
    }else{
        return false, Direction.UP, glm.vec2(0.0)
    }

}

checkCollision :: proc{checkCollisionAABBToAABB, checkCollisionCircleToAABB}


checkForWin :: proc()->bool{
    for brick in bricks{
        if !brick.isSolid && !brick.destroyed do return false
    }

    return true
}


shakeTime : f32 = 0.0

doCollisions :: proc(){

    for &box in bricks{
        if !box.destroyed{

            collided, differenceDirection, differenceVector := checkCollision(ball, box)
            //collided = whether or not there was a collision

            //differenceDirection is the cardinal direction the most closesly matches
            //the vector from the closest point on the aabb's edge to the ball's center

            //differenceVector is the actual vector from closest point on the edge to the ball's center

            if collided{
                
                if !box.isSolid{
                    box.destroyed = true
                    spawnPowerUps(box)

                    playChunk("bleep1")

                }else{
                    shakeTime = 0.05
                    pp_shake = true
                    playChunk("solid")

                }

                //only do collision resolution for the ball if 
                if !(ball.passThrough && !box.isSolid){
                    //change the velocity, and move the ball out of the aabb if there is any penetration
                    if differenceDirection == Direction.LEFT || differenceDirection == Direction.RIGHT{
                        //horizontal

                        ball.velocity.x = -ball.velocity.x

                        penetration := ball.radius - glm.abs(differenceVector.x)

                        if differenceDirection == Direction.LEFT{
                            ball.position.x += penetration
                        }
                        else{
                            ball.position.x -= penetration
                        }

                    }else{
                        //vertical
                        ball.velocity.y = -ball.velocity.y

                    
                        penetration := ball.radius - glm.abs(differenceVector.y)

                        if differenceDirection == Direction.UP{
                            ball.position.y += penetration
                        }
                        else{
                            ball.position.y -= penetration
                        }


                    }
                }

            }

        }
    }//block collisions

    //powerups
    for &powerUp in powerUps{

        if !powerUp.destroyed{
            if powerUp.position.y > WINDOW_HEIGHT do powerUp.destroyed = true

            if checkCollision(player, powerUp){
                activatePowerUp(powerUp)
                powerUp.destroyed = true
                powerUp.activated = true

                playChunk("powerup")

            }

        }

    }




    collidedPlayer, differenceDirectionPlayer, differenceVectorPlayer  := checkCollision(ball, player) 
    
    if !ball.stuck && collidedPlayer{
        
        //change velocity depending on where on the paddle the ball collided
        //further away for center of paddle/side of paddle affect the angle
        
        centerBoard := player.position.x + (player.size.x / 2.0)
        distance := (ball.position.x + ball.radius) - centerBoard
        percent := distance/(player.size.x/2.0)

        strength : f32 = 2.0
        oldVelocity := ball.velocity

        ball.velocity.x = INITIAL_BALL_VELOCITY.x * percent * strength
        ball.velocity.y = -1.0 * glm.abs(ball.velocity.y)
        ball.velocity = glm.normalize(ball.velocity) * glm.length(oldVelocity)

        
        ball.stuck = ball.sticky

        playChunk("bleep2")

    }

}

vectorDirection :: proc(target : glm.vec2)->Direction{
    //find the direction the ball hit an aabb
    //this way we know which side the ball hit the aabb, 
    //and therefore how to react

    //the side of the aabb that was hit can be estimated by
    //determining which cardinal direction the vector from !!!!! the ball's
    //center to the closest point to the center on the edge of the aabb is. !!!!!

    //use the dot prod to determine which of the cardinal directions best matches,
    //then that is the direction that we use for collision resolution.

    //note: don't know why, but in the tut they have 0,1 for up and 0,-1 for down
    //swapped it here since otherwise, you get collision issues
    //maybe I messed up in one of the collision functions and I should be negating it,
    //but this works
    compass := [4]glm.vec2{
        glm.vec2{0.0,-1.0},
        glm.vec2{0.0,1.0},
        glm.vec2{-1.0,0.0},
        glm.vec2{1.0,0.0}
    }

    max : f32 = 0.0

    best_match := -1

    for i in 0..<4{
        dot_prod := glm.dot(glm.normalize(target), compass[i])
        if dot_prod > max{
            max = dot_prod
            best_match = i
        }
    }

    // fmt.println(best_match)
    return Direction(best_match)
}

reloadLevel :: proc(){
    loadGameLevel(currentLevelndex, WINDOW_WIDTH, WINDOW_HEIGHT/2)
    lives = 3
    resetLevel()

    killAllParicles()
}

resetLevel :: proc(){

    resetPlayer()
    resetBall()
    resetPowerUps()

    pp_chaos = false
    pp_confuse = false

}

resetPlayer :: proc(){

    player.size = PLAYER_SIZE
    player.position = glm.vec2{WINDOW_WIDTH/2 - player.size.x/2, WINDOW_HEIGHT - player.size.y}
    player.color = glm.vec3(1.0)
}

resetBall :: proc(){

    ball.position = player.position + glm.vec2{player.size.x/2.0 - ball.radius, -ball.radius * 2.0}
    ball.velocity = INITIAL_BALL_VELOCITY
    ball.stuck = true

    ball.sticky = false
    ball.passThrough = false
    ball.color = glm.vec3(1.0)

}

resetPowerUps :: proc(){
    clear(&powerUps)
}

drawSprite :: proc(texture_name:string, position : glm.vec2, size: glm.vec2, rot_deg : f32, color : glm.vec3){

    gl.BindVertexArray(spriteVAO)
    //!!!remember to enable blend mode so alpha works
    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

    useShader("default")
    //call use shader here since, now with particles using their own shader, need to switch

    //currently the proj mat and vertices/buffers etc are set in main. (in init game)
    //so this proc assumes everything is setup properly

    // fmt.println("drawSprite")
    model := glm.mat4(1.0)
    //the single arg constructor inits the diagonal values to the arg, everything else is 0,
    //so this is identity matrix.
    
    //!! in order for the screen dimension proj matrix to work, you have to
    //make sure the model matrix is being done (specifically the scale, so 
    //when it gets ortho projected it will get scaled back to the desired
    //size (while testing to get stuff working, I removed *proj in the shader,
    //made sure identity model was working, then put * proj back in. It wasn't working
    //because I also had all transf stuff commented, so I guess it was just infinitesimal
    model *= glm.mat4Translate( glm.vec3{position.x, position.y, 0.0})

    model *= glm.mat4Translate( glm.vec3{.5 * size.x, .5*size.y, 0.0})
    model *= glm.mat4Rotate( glm.vec3{0.0, 0.0, 1.0}, glm.radians(rot_deg)) 
    model *= glm.mat4Translate( glm.vec3{-.5 * size.x, -.5*size.y, 0.0})
    
    model *= glm.mat4Scale( glm.vec3{size.x, size.y, 1.0})

    // fmt.println("model", model)
    setUMat4fv("model", model)
    setUMat4fv("proj", proj)
    

    setUVec3("spriteColor", color)
    
    //texture
    texture_id := texture_map[texture_name]

    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, texture_id)

    setUInt("texture1", 0)
    
    //actually draw
    gl.DrawArrays(gl.TRIANGLES, 0, 6)
}



shouldSpawn :: proc(chance : i32) -> bool{
    random := rand.int31_max(chance)
    //creates a random 31 bit int (i32 -1 since the result is always positive, so
    //the sign bit isn't random) in the range [0, n)
    // return random == 0
    return random == 0
}

spawnPowerUps :: proc(block : GameObject){

    //speed
    if shouldSpawn(75){
        append(&powerUps, 
                PowerUpObject{
                    type = "speed", 
                    color = glm.vec3{0.5, 0.5, 1.0},
                    duration = 0.0,
                    position = block.position,
                    texture_name = "speed",

                    size = POWER_UP_SIZE,
                    velocity = POWER_UP_VELOCITY,
                    activated = true
                }
            )
    }

    //sticky
    if shouldSpawn(75){
        append(&powerUps, 
                PowerUpObject{
                    type = "sticky", 
                    color = glm.vec3{1.0, 0.5, 1.0},
                    duration = 20.0,
                    position = block.position,
                    texture_name = "sticky",

                    size = POWER_UP_SIZE,
                    velocity = POWER_UP_VELOCITY,
                    activated = true
                }
            )
    }

    //pass through
    if shouldSpawn(75){
        append(&powerUps, 
                PowerUpObject{
                    type = "pass-through", 
                    color = glm.vec3{0.5, 1.0, 0.5},
                    duration = 10.0,
                    position = block.position,
                    texture_name = "pass-through",

                    size = POWER_UP_SIZE,
                    velocity = POWER_UP_VELOCITY,
                    activated = true
                }
            )
    }

    //pad size increase
    if shouldSpawn(75){
        append(&powerUps, 
                PowerUpObject{
                    type = "pad-size-increase", 
                    color = glm.vec3{1.0, 0.6, 0.4},
                    duration = 0.0,
                    position = block.position,
                    texture_name = "pad-size-increase",

                    size = POWER_UP_SIZE,
                    velocity = POWER_UP_VELOCITY,
                    activated = true
                }
            )
    }

    //confuse
    if shouldSpawn(15){
        append(&powerUps, 
                PowerUpObject{
                    type = "confuse", 
                    color = glm.vec3{1.0, 0.3, 0.3},
                    duration = 15.0,
                    position = block.position,
                    texture_name = "confuse",

                    size = POWER_UP_SIZE,
                    velocity = POWER_UP_VELOCITY,
                    activated = true
                }
            )
    }

    //chaos
    if shouldSpawn(15){
        append(&powerUps, 
                PowerUpObject{
                    type = "chaos", 
                    color = glm.vec3{0.9, 0.25, 0.25},
                    duration = 15.0,
                    position = block.position,
                    texture_name = "chaos",

                    size = POWER_UP_SIZE,
                    velocity = POWER_UP_VELOCITY,
                    activated = true
                }
            )
    }

}


activatePowerUp :: proc(powerUp : PowerUpObject){

    //not sure why they didn't bother to do an enum for power up type, 
    //but they use strings in the tutorial.

    switch powerUp.type{

        case "speed":
            ball.velocity *= 1.2
        
        case "sticky":
            ball.sticky = true
            player.color = glm.vec3{1.0, 0.5, 1.0}

        case "pass-through":
            ball.passThrough = true
            ball.color = glm.vec3{1.0, 0.5, 0.5}
        
        case "pad-size-increase":
            player.size.x += 50

        case "confuse":
            if !pp_chaos do pp_confuse = true
            fmt.println("pp_confuse!!!")
        case "chaos":
            if !pp_confuse do pp_chaos = true
            fmt.println("pp_chaos!!!")
            
    }

}

updatePowerUps :: proc(dt:f32){

    // fmt.println("dt:", dt)
    // fmt.println("pp_chaos:", pp_chaos)

    for &powerUp in powerUps{
        // fmt.println("powerup.duration:", powerUp.duration)

        powerUp.position += powerUp.velocity *dt
        if powerUp.activated{
            powerUp.duration -= dt

            if powerUp.duration <=0{
                powerUp.activated = false

                switch powerUp.type{
                    case "sticky":
                        if !isOtherPowerupActive("sticky"){
                            ball.sticky = false
                            player.color = glm.vec3(1.0)
                        }
                    
                    case "passThrough":
                        if !isOtherPowerupActive("pass-through"){
                            ball.passThrough = false
                            ball.color = glm.vec3(1.0)
                        }
                    
                    case "confuse":
                        if !isOtherPowerupActive("confuse"){
                            pp_confuse = false
                        }

                    case "chaos":
                        if !isOtherPowerupActive("chaos"){
                            pp_chaos = false                        
                        }

                }
            
            }

        }

    }

    remove_if(&powerUps, proc(pu:PowerUpObject)->bool{
        return pu.destroyed && !pu.activated
    })

}


isOtherPowerupActive :: proc(type:string)->bool{

    for powerUp in powerUps{
        if powerUp.activated && powerUp.type == type do return true
    }

    return false

}

//this is taken from user 2DArray in the odin discord beginner channel
//it is supposed to be an equivalent to c++'s remove_if function, 
//which is used in the tutorial

//todo: will have to check back on how this works with deleting/freeing memory
remove_if :: proc(list: ^[dynamic]$T, RemoveIfTrueProc: proc(T) -> bool){
    nextIndex := 0

    for element in list {
        if RemoveIfTrueProc(element) == false {
            list[nextIndex] = element
            nextIndex += 1
        }
    }

    // this never reallocates, because
    // nextIndex is never greater than len(list)
    resize(list, nextIndex)
}

clearGame :: proc(){

    delete(levelPaths)
    delete(bricks) 
    delete(powerUps)
}