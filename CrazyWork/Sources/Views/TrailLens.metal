#include <metal_stdlib>
using namespace metal;

// Gravitational lens for the trail. Within `radius` of a node, sample
// positions are pulled toward the center (magnification: strands appear
// pushed outward around the figure) and rotated around it (frame-dragging:
// strands near the mass get swept into arcs). With strength > 1 the inner
// zone inverts — strands ghost into mirrored arcs on the far side, the
// Einstein-ring signature that makes lensing legible in a still frame.
// Quadratic falloff melts everything to nothing well before any visible
// edge, so it reads as an aura, not a disc.
[[ stitchable ]] float2 trailLens(float2 position,
                                  device const float *centers, int count,
                                  float radius, float strength, float swirl) {
    float2 p = position;
    for (int i = 0; i + 1 < count; i += 2) {
        float2 c = float2(centers[i], centers[i + 1]);
        float2 d = position - c;
        float r = length(d);
        if (r < radius && r > 0.5) {
            float k = 1.0 - r / radius;
            k = k * k;
            float a = -swirl * k;
            float cs = cos(a), sn = sin(a);
            float2 rd = float2(d.x * cs - d.y * sn, d.x * sn + d.y * cs);
            p = c + rd * (1.0 - strength * k);
        }
    }
    return p;
}
