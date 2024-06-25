package breakout

import "core:fmt"

import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import "core:math/rand"


Particle :: struct{
    position, velocity : glm.vec2,
    color : glm.vec4,
    
    life : f32
}


nr_particles := 500
particles : [dynamic]Particle
lastUsedParticle := 0


particleVAO : u32


initParticles :: proc(){

    //note: tried to see if I could skip over doing
    //the vert struct thing like in the opengl/sdl demo,
    //and just have an array of floats like in the tutorial,
    //but I just want to get this working (confused about how to
    //do the equivalent of (void *)0 for the VertexAttribPointer proc
    //so I'm just copying the format of the demo.

    ParticleVertex :: struct{
        vertex: glm.vec4
    }

    particleQuad := []ParticleVertex{
        {{0.0, 1.0, 0.0, 0.0}},
        {{1.0, 0.0, 1.0, 1.0}},
        {{0.0, 0.0, 0.0, 1.0}},

        {{0.0, 1.0, 0.0, 0.0}},
        {{1.0, 1.0, 1.0, 0.0}},
        {{1.0, 0.0, 1.0, 1.0}}
    }

    particleVBO : u32

    gl.GenBuffers(1, &particleVBO)
    gl.GenVertexArrays(1, &particleVAO)

    gl.BindBuffer(gl.ARRAY_BUFFER, particleVBO)
    gl.BindVertexArray(particleVAO)

    gl.BufferData(gl.ARRAY_BUFFER, len(particleQuad) * size_of(particleQuad[0]), raw_data(particleQuad), gl.STATIC_DRAW)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 4, gl.FLOAT, gl.FALSE, size_of(ParticleVertex), offset_of(ParticleVertex, vertex))
    
    
    gl.BindVertexArray(0)
    
    for i in 0..<nr_particles{
        append(&particles, Particle{})
    }

}

updateParticles :: proc(dt:f32, object : GameObject, nr_new_particles:int, offset: glm.vec2){

    //add new particles -> sort of a pooling method
    //only add new particles if we can't recycle an existing dead one.
    for i in 0..<nr_new_particles{
        unusedParticle := getFirstUnusedParticle()
        respawnParticle(&particles[unusedParticle], object, offset)
    }

    //update existing particles
    for j in 0..<len(particles){

        ///!!!make sure to take the pointer here, forgot and nothing was applied
        p := &particles[j]
        p.life -= dt

        if p.life > 0.0{
            p.position -= p.velocity * dt
            p.color.a -= dt * 2.5
        }

    }
}


getFirstUnusedParticle :: proc() -> int{

    //search from last used particle to end of list (this should return almost instantly)
    //it's more likely to find the next dead particle after the last particle index
    for i in lastUsedParticle..<len(particles){
        if particles[i].life <- 0.0{
            lastUsedParticle = i
            return i
        }
    }

    //if not, search linearly
    for i in 0..<lastUsedParticle{
        if particles[i].life <- 0.0{
            lastUsedParticle = i
            return i
        }
    }

    //reset /override the first particle if all of them are in use
    //(kill it and use it as a new particle)
    lastUsedParticle = 0
    return 0

}

respawnParticle :: proc(particle : ^Particle, object : GameObject, offset: glm.vec2){
    //docs say the generated random int will always be positive

    random := rand.float32_range(-5, 5)
    rColor := 0.5 + rand.float32()//[0,1)

    particle.life = 1.0

    particle.position = object.position + random + offset
    particle.color = glm.vec4{rColor, rColor, rColor, 1.0}
    particle.velocity = object.velocity * 0.1
    
}

renderParticles :: proc(){

    //additive blend
    
    gl.BindVertexArray(particleVAO)
    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE)

    useShader("particle")

    for particle in particles{
        if particle.life >0.0{
            setUVec2("offset", particle.position)
            setUVec4("color", particle.color)
            
            //texture
            texture_id := texture_map["face"]

            gl.ActiveTexture(gl.TEXTURE0)
            gl.BindTexture(gl.TEXTURE_2D, texture_id)

            setUInt("sprite", 0)

            setUMat4fv("projection", proj)
            
    
            //in the tut, they have a different particle quad vertex array, 
            //but I'm just going to use the same quad, so not bothering to rebind anything.
            //if you want a different vertex array, you would have to bind here before drawing.

            // fmt.println("drawing particle")

            gl.DrawArrays(gl.TRIANGLES, 0,6)

        }


    }

}

killAllParicles :: proc(){
    for &particle in particles{
        particle.life = 0.0
    }
}

clearParticles :: proc(){
    delete(particles)
}