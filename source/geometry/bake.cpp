#define _USE_MATH_DEFINES
#include "bake.h"
#include "subdivide.h"
#include "mesh_ops.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

#include <vector>
#include <algorithm>
#include <cmath>

using namespace godot;

namespace gomo {

namespace {

float edge_fn(float ax, float ay, float bx, float by, float px, float py) {
    return (bx - ax) * (py - ay) - (by - ay) * (px - ax);
}

} // anonymous namespace

Ref<Image> bake_normal_map(const HalfEdgeMesh &mesh, int subdiv_levels, int resolution) {
    int w = resolution, h = resolution;

    // Subdivide and rasterize into UV space to get per-texel object-space normal
    Ref<ArrayMesh> subdivided = subdivide_to_mesh(mesh, subdiv_levels, true);
    if (!subdivided.is_valid()) return Ref<Image>();

    Array arrays = subdivided->surface_get_arrays(0);
    PackedVector3Array s_norms = arrays[ArrayMesh::ARRAY_NORMAL];
    PackedVector2Array s_uvs   = arrays[ArrayMesh::ARRAY_TEX_UV];
    PackedInt32Array   s_idx   = arrays[ArrayMesh::ARRAY_INDEX];

    std::vector<Vector3> texel_n(w * h, Vector3(0, 0, 0));
    std::vector<bool>    covered(w * h, false);

    int n_tris = s_idx.size() / 3;
    for (int t = 0; t < n_tris; ++t) {
        int i0 = s_idx[t*3+0], i1 = s_idx[t*3+1], i2 = s_idx[t*3+2];
        Vector3 N0 = s_norms[i0], N1 = s_norms[i1], N2 = s_norms[i2];
        Vector2 UV0 = s_uvs[i0],  UV1 = s_uvs[i1],  UV2 = s_uvs[i2];

        float u0 = UV0.x*w, v0 = UV0.y*h;
        float u1 = UV1.x*w, v1 = UV1.y*h;
        float u2 = UV2.x*w, v2 = UV2.y*h;

        int min_x = std::max(0,     (int)std::floor(std::min({u0, u1, u2})));
        int min_y = std::max(0,     (int)std::floor(std::min({v0, v1, v2})));
        int max_x = std::min(w - 1, (int)std::ceil( std::max({u0, u1, u2})));
        int max_y = std::min(h - 1, (int)std::ceil( std::max({v0, v1, v2})));

        float area = edge_fn(u0, v0, u1, v1, u2, v2);
        if (std::abs(area) < 1e-6f) continue;
        float inv = 1.0f / area;

        for (int py = min_y; py <= max_y; ++py) {
            for (int px = min_x; px <= max_x; ++px) {
                float sx = px + 0.5f, sy = py + 0.5f;
                float w0 = edge_fn(u1, v1, u2, v2, sx, sy) * inv;
                float w1 = edge_fn(u2, v2, u0, v0, sx, sy) * inv;
                float w2 = edge_fn(u0, v0, u1, v1, sx, sy) * inv;
                if (w0 < 0.0f || w1 < 0.0f || w2 < 0.0f) continue;
                int idx = py * w + px;
                texel_n[idx] += N0*w0 + N1*w1 + N2*w2;
                covered[idx] = true;
            }
        }
    }

    for (int i = 0; i < w * h; ++i) {
        if (covered[i]) {
            float len = texel_n[i].length();
            if (len > 1e-10f) texel_n[i] /= len;
        }
    }

    // Encode object-space normal as RGB
    PackedByteArray bytes;
    bytes.resize(w * h * 3);
    std::vector<bool> dil_mask(w * h, false);
    for (int i = 0; i < w * h; ++i) {
        if (covered[i]) {
            bytes[i*3+0] = (uint8_t)std::clamp((texel_n[i].x * 0.5f + 0.5f) * 255.0f, 0.0f, 255.0f);
            bytes[i*3+1] = (uint8_t)std::clamp((texel_n[i].y * 0.5f + 0.5f) * 255.0f, 0.0f, 255.0f);
            bytes[i*3+2] = (uint8_t)std::clamp((texel_n[i].z * 0.5f + 0.5f) * 255.0f, 0.0f, 255.0f);
            dil_mask[i] = true;
        } else {
            bytes[i*3+0] = 128;
            bytes[i*3+1] = 128;
            bytes[i*3+2] = 128;
        }
    }

    // Dilation
    for (int iter = 0; iter < 4; ++iter) {
        std::vector<bool> next_mask = dil_mask;
        for (int py = 0; py < h; ++py) {
            for (int px = 0; px < w; ++px) {
                if (dil_mask[py * w + px]) continue;
                bool filled = false;
                for (int dy = -1; dy <= 1 && !filled; ++dy) {
                    for (int dx = -1; dx <= 1 && !filled; ++dx) {
                        if (dx == 0 && dy == 0) continue;
                        int nx = px + dx, ny = py + dy;
                        if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
                        if (!dil_mask[ny * w + nx]) continue;
                        int src = (ny * w + nx) * 3, dst = (py * w + px) * 3;
                        bytes[dst+0] = bytes[src+0];
                        bytes[dst+1] = bytes[src+1];
                        bytes[dst+2] = bytes[src+2];
                        next_mask[py * w + px] = true;
                        filled = true;
                    }
                }
            }
        }
        dil_mask = std::move(next_mask);
    }

    return Image::create_from_data(w, h, false, Image::FORMAT_RGB8, bytes);
}

} // namespace gomo
