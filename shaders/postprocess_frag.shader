#version 330 core

in vec2 texCoords;
out vec4 color;

uniform sampler2D scene;
uniform vec2 offsets[9];
uniform int edge_kernel[9];
uniform float blur_kernel[9];

uniform bool chaos;
uniform bool confuse;
uniform bool shake;


void main(){

    color = vec4(0.0f);

    vec3 sample[9];

    if(chaos || shake){
        for(int i =0; i<9; i++)
            sample[i] = vec3(texture(scene, texCoords.st + offsets[i]));
    }

    if(chaos){
        for(int i=0; i<9; i++){
            color += vec4(sample[i] * edge_kernel[i], 0.0f);
        }
        color.a = 1.0f;
    
    }else if(confuse){
        color = vec4(1.0-texture(scene,texCoords).rgb, 1.0);
    }else if(shake){
        for(int i=0; i<9; i++){
            color += vec4(sample[i] * blur_kernel[i], 0.0f);
        }
        color.a = 1.0f;
    }else{
        color = texture(scene, texCoords);
    }

    // color = vec4(1.0, 0.0, 0.0, 1.0)

}