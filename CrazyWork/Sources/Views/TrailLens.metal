#include <metal_stdlib>
using namespace metal;

// Gravitational lens for the trail: pixels within `radius` of a node sample
// toward the node's center, magnifying the strands behind the figure — light
// bends around the mass. Quadratic falloff melts the distortion to nothing
// well before any visible edge, so it reads as an aura, not a disc.
[[ stitchable ]] float2 trailLens(float2 position,
                                  device const float *centers, int count,
                                  float radius, float strength) {
    float2 p = position;
    for (int i = 0; i + 1 < count; i += 2) {
        float2 c = float2(centers[i], centers[i + 1]);
        float2 d = position - c;
        float r = length(d);
        if (r < radius && r > 0.5) {
            float f = 1.0 - r / radius;
            p = c + d * (1.0 - strength * f * f);
        }
    }
    return p;
}
