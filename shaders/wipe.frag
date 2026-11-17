#version 440

// Halo of the note's leading edge (docs/SPEC.md section 7). The 2 px core
// line is a Rectangle drawn on top, so its pixel snapping stays Qt's. This
// pass draws only the light around it, in one pass and without a source:
// a horizontal Gaussian around the core, the same over the whole bar
// height (a blurred shadow fades out towards the top and bottom edges,
// where the bar's clip then cuts it). M7 chose it over a MultiEffect
// shadow, and over a trail behind the moving edge.
//
// Coordinates are logical px of the item. Output is premultiplied.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 color;      // Theme.base0D
    vec2 size;       // item size, logical px
    float center;    // x of the core's center, logical px
    float strength;  // peak opacity (the critical pulse moves it)
    float radius;    // Gaussian sigma, logical px
};

void main() {
    float d = qt_TexCoord0.x * size.x - center;
    float a = strength * exp(-0.5 * d * d / (radius * radius));
    fragColor = vec4(color.rgb, 1.0) * color.a * a * qt_Opacity;
}
