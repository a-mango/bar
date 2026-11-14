#version 440

// Leading edge of the note wipe (docs/SPEC.md section 7). M0 ships a
// pass-through so that `make shaders` has something to build. M7 writes
// the real effect, or drops the shader for a MultiEffect glow.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    fragColor = texture(source, qt_TexCoord0) * qt_Opacity;
}
