package breakout

import "core:fmt"
import "core:strings"


import glm "core:math/linalg/glsl"
import gl "vendor:OpenGL"
import SDL "vendor:sdl2"
// import "vendor:sdl2/ttf"
// import stbtt "vendor:stb/truetype"

import img "vendor:sdl2/image"
import FT "shared:odin-freetype"
//https://github.com/englerj/odin-freetype?tab=readme-ov-file

//the idea is to generate a bitmap and metrics for each glyph
//to render them, you use the metrics to generate a mesh,
//and then use the bitmap as a texture

tr_vao, tr_vbo : u32
Character :: struct{
    texID : u32, //id handle of glyph texture
    size : glm.ivec2, //size of glyph
    bearing : glm.ivec2,// oofset from baseline to left/top of glyph
    advance : u32//horizontal offset to advance to next glyph
}

characters := make(map[rune]Character)

initTextRenderer :: proc(){

    //!!! init SDL_ttf
    // if ttf.Init()<0{
    //     fmt.println("failed to initialize SDL_ttf, error:", ttf.GetError())
    //     return
    // }


    //setup voa/vbo -> the actual vbo data will change per char (see renderText proc)
    //but the number of verts/layout remains the same, so do this here.
    useShader("text")
    setUMat4fv("projection", glm.mat4Ortho3d(0.0, WINDOW_WIDTH, WINDOW_HEIGHT, 0.0, -1.0, 1.0))
    setUInt("text", 0)

    gl.GenVertexArrays(1, &tr_vao)
    gl.GenBuffers(1, &tr_vbo)

    gl.BindVertexArray(tr_vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, tr_vbo)
    
    gl.BufferData(gl.ARRAY_BUFFER, size_of(f32)*6*4, nil, gl.DYNAMIC_DRAW)
    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 4, gl.FLOAT, gl.FALSE, 4 * size_of(f32), 0)
    
    gl.BindVertexArray(0)
    gl.BindBuffer(gl.ARRAY_BUFFER, 0)



}

loadTextRenderer :: proc(path : string, fontSize : u32){

    clear(&characters)

    // loadedFont := ttf.OpenFont(strings.clone_to_cstring(fontPath), fontSize)
    // if loadedFont == nil{
    //     fmt.eprintfln("could not open/load font at path:", fontPath)
    //     return
    // }

    // fmt.println("loadedFont:", loadedFont)


    ft : FT.Library
    if FT.init_free_type(&ft) != .Ok{
        fmt.eprintln("Could not init Freetype Library")
    }
 
    face : FT.Face

        
    cstr := strings.clone_to_cstring(path)
    defer free(rawptr(cstr))

    if FT.new_face(ft, cstr, 0, &face) != .Ok{
        fmt.eprintln("Could not load freetype font")

    }

    FT.set_pixel_sizes(face, 0, fontSize)

    //disable byte alignement
    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)

    for c in "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!@#$%^&*()_+-=,./;'[]<>?:\"{}/\\`~ "{

        // fmt.println("rune:", c)

        if FT.load_char(face, u32(c), FT.Load_Flags{.Render}) != .Ok{
            fmt.eprintfln("could not load glyph for rune:", c)
            continue
        }
      
        //TEXTURE 
        char_tex : u32
        gl.GenTextures(1, &char_tex)
        gl.BindTexture(gl.TEXTURE_2D, char_tex)
 
        gl.TexImage2D(
            gl.TEXTURE_2D,
            0,
            gl.RED,
            i32(face.glyph.bitmap.width),
            i32(face.glyph.bitmap.rows),
            0,
            gl.RED,
            gl.UNSIGNED_BYTE,
            face.glyph.bitmap.buffer
        )

        //set texture options
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);


        character := Character{
            char_tex,
            glm.ivec2{cast(i32)face.glyph.bitmap.width, cast(i32)face.glyph.bitmap.rows},
            glm.ivec2{cast(i32)face.glyph.bitmap_left, cast(i32)face.glyph.bitmap_top},
            u32(cast(i32)face.glyph.advance.x)
        }

        characters[c] = character

    }

    gl.BindTexture(gl.TEXTURE_2D, 0)
    
    FT.done_face(face)
    FT.done_free_type(ft)
    
}

renderText :: proc(text : string, x, y, scale : f32, color : glm.vec3){

    x := x
    //going to be updating x in the loop as you draw each character

    useShader("text")

    setUVec3("textColor", color)
    setUMat4fv("projection", glm.mat4Ortho3d(0.0, WINDOW_WIDTH, WINDOW_HEIGHT, 0.0, -1.0, 1.0))
    setUInt("text", 0)
    
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindVertexArray(tr_vao)

    for c in text{

        if !(c in characters){
            // fmt.eprintln("could not find character", c, "in loaded characters")
        }else{
        
            ch := characters[c]
        
            xpos := x + f32(ch.bearing.x) * scale
            ypos := y + f32(characters['H'].bearing.y - ch.bearing.y) * scale + (glm.sin_f32(f32(SDL.GetTicks())*2/1000.0 + xpos*14/WINDOW_WIDTH) * 10)
            
            //The H char y bearing should be the max hight of a glyph. Because we're rendering top to bottom, 
            //you push the glyphs down by subtracting their y bearing (the distance from the midline to their top)
            //from the H char's
            //!!! Make sure capital 'H' actually has a character struct created. 

            w := f32(ch.size.x) * scale
            h := f32(ch.size.y) * scale


            // fmt.println("\'", c, "\' xpos, ypos, w, h:", xpos, ypos, w, h)

            //update vbo for each character
            verts := [6][4]f32{
                { xpos,     ypos + h,   0.0, 1.0 },
                { xpos + w, ypos,       1.0, 0.0 },
                { xpos,     ypos,       0.0, 0.0 },

                { xpos,     ypos + h,   0.0, 1.0 },
                { xpos + w, ypos + h,   1.0, 1.0 },
                { xpos + w, ypos,       1.0, 0.0 }
            }

            // fmt.println("verts:", verts)
            // fmt.println("textid:", ch.texID)

            //render glyph texture over quad
            gl.BindTexture(gl.TEXTURE_2D, ch.texID)
            // gl.BindTexture(gl.TEXTURE_2D, texture_map["face"])


            //update vbo content
            gl.BindBuffer(gl.ARRAY_BUFFER, tr_vbo)
            gl.BufferSubData(gl.ARRAY_BUFFER, 0, size_of(verts), &verts)
            gl.BindBuffer(gl.ARRAY_BUFFER, 0)

            //render quad
            gl.DrawArrays(gl.TRIANGLES, 0, 6)
            x += f32(ch.advance >> 6) * scale
            //bitshift by 6 == *1/64 -> this gives you the advance in pixels
            //so the current behaviour is that if a char is missing, it won't skip a space or anything 
        }
        
    }    

    gl.BindVertexArray(0)
    gl.BindTexture(gl.TEXTURE_2D, 0)

}

/*
loadTextRendererSDL :: proc(fontPath : string, fontSize : i32){
    //kept having issues converting the SDL surface to texture, then I found
    //someone made bindings for freetype itself, so I'm using that now.

    clear(&characters)

    // loadedFont := ttf.OpenFont(strings.clone_to_cstring(fontPath), fontSize)
    // if loadedFont == nil{
    //     fmt.eprintfln("could not open/load font at path:", fontPath)
    //     return
    // }

    // fmt.println("loadedFont:", loadedFont)

    for c in "abcdefghijklmnopqrstuvwxyz"{

        //in the tutorial, they use the FreeType library. They use the method FT_Load_Char
        //which gives you an FT_Face struct, which contains the bitmap + all the glyph metrics
        //(it looks like)

        //here, using SDL_ttf, you can get the bitmap in the form of an SDL surface,
        //but you have to get the glyph metrics for the corresponding char using the GlyphMetrics proc.

        loadedGlyphSurface := ttf.RenderGlyph32_Blended(loadedFont, 'A', SDL.Color{100, 255, 255, 255})
        // loadedGlyphSurface := SDL.LoadBMP(strings.clone_to_cstring("textures/hello_world.bmp"))

        //!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        //!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        //SDL Color struct uses an 8 bit int to represent the color components, NOT a float btw 0.0 and 1.0
        //I kept testing with 0.0 and 1.0, which I guess were passed as u8s, so the alpha would've been 0 or just
        //barely noticable. (spent a while on this one)

        //this renders the glyph to an sdl surface. Then you generate the texture using
        //TexImage2D below

        if loadedGlyphSurface == nil{
            fmt.eprintfln("failed to load glyph, c:", c, ", rune(c):", rune(c))
            continue
        }
        
        //get glyph metric for the given char
        minx, maxx, miny, maxy, advance : i32
        if ttf.GlyphMetrics32(loadedFont, c, &minx, &maxx, &miny, &maxy, &advance) < 0{
            fmt.eprintfln("failed to get glyph metrics, c:", c, ", rune(c):", rune(c))
            continue
        }

        
        // fmt.println("succesfully loaded glyph/metrics for rune:", c)
        // fmt.println("metrics: minx, maxx, miny, maxy, advance:", minx, maxx, miny, maxy, advance)
        // fmt.println("surface: w, h, pitch, clip_rect:", loadedGlyphSurface.w, loadedGlyphSurface.h, loadedGlyphSurface.pitch, loadedGlyphSurface.clip_rect)

        // fmt.println("loadedGlyphSurface.format.BytesPerPixel:",loadedGlyphSurface.format.BytesPerPixel)
        // fmt.println("loadedGlyphSurface.userdata:",loadedGlyphSurface.userdata)
        

        //test blitting
        //NOTE: for testing blitting, I had to comment out all the opengl stuff, since
        //aparently you can't SDL blit while using opengl with sdl. (didn't bother testing to see
        //if it's not possible though)

        // testSurface := SDL.LoadBMP(strings.clone_to_cstring("textures/hello_world.bmp"))
        
        // SDL.BlitSurface(testSurface, nil, SDL.GetWindowSurface(window), nil)
        
        // SDL.BlitSurface(loadedGlyphSurface, nil, SDL.GetWindowSurface(window), nil)
        
        //TEXTURE 
        char_tex : u32
        gl.GenTextures(1, &char_tex)
        gl.BindTexture(gl.TEXTURE_2D, char_tex)
        
        //set texture options
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

        //disable byte alignement
        gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
        // gl.PixelStorei(gl.UNPACK_ROW_LENGTH, loadedGlyphSurface.pitch/4)

 
        textureFormat := gl.RGBA
        
        //rmask is literally the red-mask, so it's where in the 4 bytes the red component is 
        //->the sdl format struc also has g/b/a masks
        if loadedGlyphSurface.format.BytesPerPixel == 4{    
            textureFormat = loadedGlyphSurface.format.Rmask == 0x000000ff? gl.RGBA : gl.BGRA

        }else{
            textureFormat = loadedGlyphSurface.format.Rmask == 0x000000ff? gl.RGB : gl.BGR
        }

        gl.TexImage2D(
            gl.TEXTURE_2D,
            0,
            i32(loadedGlyphSurface.format.BytesPerPixel),
            loadedGlyphSurface.w,
            loadedGlyphSurface.h,
            0,
            u32(textureFormat),
            gl.UNSIGNED_BYTE,
            loadedGlyphSurface.pixels
        )

        character := Character{
            char_tex,
            glm.ivec2{loadedGlyphSurface.w, loadedGlyphSurface.h},
            glm.ivec2{minx, maxy},
            u32(advance)
        }

        characters[c] = character

        //based on the chart/description here: https://freetype.sourceforge.net/freetype2/docs/tutorial/step2.html
        //(same chart here: https://learnopengl.com/In-Practice/Text-Rendering)
        //it looks like the bearing_x/y are the same as xMin and ymax, respectively.
        //sdl ttf doesn't give you the names explicitly

        SDL.FreeSurface(loadedGlyphSurface)

    }

    gl.BindTexture(gl.TEXTURE_2D, 0)

}

*/