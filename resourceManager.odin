package breakout

import "core:fmt"

import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import "core:strings"

import SDL "vendor:sdl2"
import mix "vendor:sdl2/mixer"
import stbi "vendor:stb/image"


WINDOW_WIDTH  :: 800
WINDOW_HEIGHT :: 600

shader_map := make(map[string]u32)
texture_map := make(map[string]u32)
music_map := make(map[string]^mix.Music)
chunk_map := make(map[string]^mix.Chunk)

loadResources :: proc(){



    stbi.set_flip_vertically_on_load(i32(1))

    //load shaders
    loadShader("default", "shaders/default_vert.shader", "shaders/default_frag.shader")
    loadShader("particle", "shaders/particle_vert.shader", "shaders/particle_frag.shader")
    loadShader("pp", "shaders/postProcess_vert.shader", "shaders/postProcess_frag.shader")
    loadShader("text", "shaders/text_vert.shader", "shaders/text_frag.shader")


    //load textures
    loadTexture("test", "textures/uv_map.png")

    loadTexture("block", "textures/block.png")
    loadTexture("block_solid", "textures/block_solid.png")
    loadTexture("background", "textures/background.jpg")
    loadTexture("paddle", "textures/paddle.png")
    loadTexture("face", "textures/face.png")

    loadTexture("speed", "textures/powerup_speed.png")
    loadTexture("sticky", "textures/powerup_sticky.png")
    loadTexture("pass-through", "textures/powerup_passthrough.png")
    loadTexture("pad-size-increase", "textures/powerup_increase.png")
    loadTexture("confuse", "textures/powerup_confuse.png")
    loadTexture("chaos", "textures/powerup_chaos.png")
	
    
    //load music
    loadMusic("breakout", "audio/breakout.mp3")

    loadChunk("bleep1", "audio/bleep.mp3")
    loadChunk("bleep2", "audio/bleep.wav")
    loadChunk("powerup", "audio/powerup.wav")
    loadChunk("solid", "audio/solid.wav")

}

clearResources :: proc(){
    for key, value in shader_map{
        gl.DeleteProgram(value)
    }

    for key, value in texture_map{
        value:=value
        //you have to do the same thing as procs, you can't take the pointer 
        //unless you do the x := x thing to make x mutable
        gl.DeleteTextures(1, &value)
    }

    for key, value in music_map{
        mix.FreeMusic(value)
    }

    for key, value in chunk_map{
        mix.FreeChunk(value)
    }

}


//SHADERS
//the load_shader_source/load_shader_file procs return a u32 id for the shader program.

loadShader :: proc(name, vs_path, fs_path:string)->(u32, bool){
    shader_program_id, program_ok := gl.load_shaders_file(vs_path, fs_path)
	
    if !program_ok {
		fmt.eprintln("Failed to create GLSL program")
	}
	// defer gl.DeleteProgram(program)
    //doing clear instead -> just clears everything, have to remember to call at end of program.	

    fmt.println("shader program id: ", shader_program_id)
    shader_map[name] = shader_program_id

    return shader_program_id, program_ok
}

useShader :: proc(name:string){
    gl.UseProgram(shader_map[name])
}

getUniformLocation :: proc(uniform_name:string)->i32{

    current_shader_program_id : i32
    gl.GetIntegerv(gl.CURRENT_PROGRAM, &current_shader_program_id)

    
    uniform_name_cstring := strings.clone_to_cstring(uniform_name)
    defer free(rawptr(uniform_name_cstring))
    

    return gl.GetUniformLocation(cast(u32)current_shader_program_id, uniform_name_cstring)

}

setUMat4fv :: proc(uniform_name:string, mat: glm.mat4){
    
    mat := mat
    //params are immuatable, unless you "do an explicit copy by shadowing the variable declaration"
    //need to do this here because it looks like you can't get the pointer to &mat[0,0] otherwise (gives error)

    uniform_location := getUniformLocation(uniform_name)

    gl.UniformMatrix4fv(uniform_location, 1, false, &mat[0, 0])


    //!!!old -> don't need to load all the uniforms, can just call getUniformLocation

    // current_shader_program_id : i32
    // gl.GetIntegerv(gl.CURRENT_PROGRAM, &current_shader_program_id)

    // uniforms := gl.get_uniforms_from_program(cast(u32)current_shader_program_id)
    // defer delete(uniforms)

    // //!! by default, if an element doesn't exist in a map, the zero value of the element's type will be returned.
    // //so you want to check to see if the uniform exists, because in this case, you get a 0 initialized uniform struct,
    // //with location = 0, which is the actual location you want. Without the check, you'll just always be setting the
    // //first uniform if you give an invalid uniform name.
    // if uniform_name in uniforms{
    //     gl.UniformMatrix4fv(uniforms[uniform_name].location, 1, false, &mat[0, 0])
    // }else{
    //     fmt.println("Uniform does not exist in shader program being used: ", uniform_name)
    // }

}



setUInt :: proc(uniform_name:string, value:i32){
    
    value := value

    uniform_location := getUniformLocation(uniform_name)

    gl.Uniform1i(uniform_location, value)
}


setUFloat :: proc(uniform_name:string, value:f32){
    
    value := value

    uniform_location := getUniformLocation(uniform_name)

    gl.Uniform1f(uniform_location, value)
}


setUVec2 :: proc(uniform_name:string, value:glm.vec2){
    
    value := value

    uniform_location := getUniformLocation(uniform_name)

  
    gl.Uniform2f(uniform_location,value.x, value.y)
}

setUVec3 :: proc(uniform_name:string, value:glm.vec3){
    
    value := value
  
    uniform_location := getUniformLocation(uniform_name)


    gl.Uniform3f(uniform_location,value.x, value.y, value.z)
}

setUVec4 :: proc(uniform_name:string, value:glm.vec4){
    
    value := value

    uniform_location := getUniformLocation(uniform_name)

    gl.Uniform4f(uniform_location,value.x, value.y, value.z, value.w)
}



//TEXTURES


loadTexture := proc(name, path: string){
    //faciliates using stbi.load to load a texture, then calls generateTexture to actually create 
    //the texture and get the id setup etc.

    width, height, nrComponents : i32
    
    cstr := strings.clone_to_cstring(path)
    defer free(rawptr(cstr))

    data := stbi.load(cstr, &width, &height, &nrComponents, 0)
    defer(stbi.image_free(data))


    if data == nil{
        fmt.eprintln("texture failed to load at path:", path) 
        
    }else{

        texture_map[name] = generateTexture(width, height, nrComponents, data, gl.CLAMP_TO_EDGE)
    }

}

generateTexture :: proc(width, height, nrComponents : i32, data : [^]u8, wrapmode : i32)-> u32{
    //actually create the texture with the given data
    //sending null data should create an exmpty texture ->
    //currently needed for the post processor

    //added wrapmode param since you want to clamp for regular textures, but you do want to repeat for the framebuffer texture for 
    //some of the post processing shader effects

    textureID : u32 
    gl.GenTextures(1, &textureID)

    format : gl.GL_Enum

    switch nrComponents{
        case 1:
            format = gl.GL_Enum.RED
        case 3:
            format = gl.GL_Enum.RGB
        case:
            //expecting 4 for rgba, but just have this as the default
            format = gl.GL_Enum.RGBA
    }

    gl.BindTexture(gl.TEXTURE_2D, textureID)

    gl.TexImage2D(gl.TEXTURE_2D, 0, cast(i32)format, width, height, 0, cast(u32)format, gl.UNSIGNED_BYTE, data)

    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
    
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrapmode);//clamp to edge for transparent rgba textures prevent weird effect -> without it, the pixels at the top of the quad are interpolated between the top, and the bottom of the texture. if the top of the texture is transparent, and that's the desired color you want for the quad, you need to clamp_to_edge, otherwise you'll there will be non transparent pixels at the top of the texture.
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrapmode);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);

    return textureID
}

getTexture :: proc(name :string)->(u32, bool){

    tid : u32
    ok : bool

    if name in texture_map{
        tid = texture_map[name]
        ok = true
    }else{
        fmt.eprintln("could not find texture in map, probably not loaded, name:", name)
        ok = false
    }
        
    return texture_map[name], ok      
}


//AUDIO

loadMusic :: proc(name, path :string){

    // music := mix.LoadMUS(strings.clone_to_cstring(path))
        
    cstr := strings.clone_to_cstring(path)
    defer free(rawptr(cstr))

    music := mix.LoadMUS(cstr)

    if music == nil{
        fmt.eprintfln("could not load music at path:", path)
        return
    }

    music_map[name] = music

}

playMusic :: proc(name : string){
    mix.PlayMusic(music_map[name], -1)
    //last arg is number of repeats
    //-1 loops the audio indefinately
}


loadChunk :: proc(name, path :string){
    
    cstr := strings.clone_to_cstring(path)
    defer free(rawptr(cstr))
    chunk := mix.LoadWAV(cstr)

    if chunk == nil{
        fmt.eprintfln("could not load chunk at path:", path)
        return
    }

    chunk_map[name] = chunk

}

playChunk :: proc(name : string){
    mix.PlayChannel(-1, chunk_map[name], 0)
    //first arg is channel index, -1 just picks the nearest available channel
    //last arg is # of repeats, 0 since you want it to play once, no repeats
}

toggleMute :: proc(){

    //-1 is for querying (just sends the current volume without modifying, I guess)
    //note: tried using GetMusicVolume, but it gave me a linker error 

    // breakout.obj : error LNK2019: unresolved external symbol Mix_GetMusicVolume referenced in function fmt.eprintf
    // (path)\breakout.exe : fatal error LNK1120: 1 unresolved externals

    fmt.printfln("volume", mix.VolumeMusic(-1))
    mix.VolumeMusic(mix.VolumeMusic(-1) > 0 ? 0 : 128)

}