#version 440

// Halo of the note's leading edge (docs/SPEC.md section 7). The 2 px core
// line is a Rectangle drawn on top, so its pixel snapping stays Qt's. This
// pass draws only the light around it, in one pass and without a source:
//
// - a horizontal Gaussian around the core, the same over the whole bar
//   height (a blurred shadow fades out towards the top and bottom edges,
//   where the bar's clip then cuts it);
// - a trail behind the edge, inside the note region, whose strength the
//   view sets from the wipe's progress (0 while the edge stands still).
//
// Coordinates are logical px of the item. Output is premultiplied.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 color;      // Theme.base0D
    vec2 size;       // item size, logical px
    float edge;      // x of the core's center, logical px
    float strength;  // halo opacity (the critical pulse moves it)
    float radius;    // Gaussian sigma, logical px
    float trail;     // 0..1, trail opacity
    float trailLen;  // trail decay length, logical px
};

void main() {
    float x = qt_TexCoord0.x * size.x;
    float d = x - edge;
    float halo = exp(-0.5 * d * d / (radius * radius));
    float behind = d < 0.0 ? trail * exp(d / trailLen) : 0.0;
    float a = clamp(strength * halo + behind * (1.0 - halo), 0.0, 1.0);
    fragColor = vec4(color.rgb, 1.0) * color.a * a * qt_Opacity;
}
