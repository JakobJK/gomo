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

struct TexelFrame {
    Vector3 T, B, N;
    bool valid = false;
};

} // anonymous namespace

Ref<Image> bake_normal_map(const HalfEdgeMesh &mesh, int subdiv_levels, int resolution) {
    int w = resolution, h = resolution;

    // --- Pass 1: rasterize base mesh faces → tangent frame per texel ---
    // Tangent uses first-edge direction, matching to_array_mesh exactly.
    std::vector<TexelFrame> frames(w * h);

    for (int32_t fi = 0; fi < mesh.face_count(); ++fi) {
        if (mesh.faces[fi].half_edge == -1) continue;

        std::vector<Vector3> fv;
        std::vector<Vector2> fuv;
        int32_t he = mesh.faces[fi].half_edge;
        do {
            fv.push_back(mesh.vertices[mesh.half_edges[he].vertex].position);
            fuv.push_back(mesh.half_edges[he].uv);
            he = mesh.half_edges[he].next;
        } while (he != mesh.faces[fi].half_edge);
        if ((int)fv.size() < 3) continue;

        Vector3 N = get_face_normal(mesh, fi);
        Vector3 geom_tan = (fv.size() >= 2) ? (fv[1] - fv[0]).normalized() : Vector3(1,0,0);

        // One tangent frame per face (matches to_array_mesh per-face tangent).
        Vector3 T_face = geom_tan;
        Vector3 B_face = N.cross(T_face).normalized();
        {
            Vector3 dP1 = fv[1] - fv[0], dP2 = fv[fv.size() - 1] - fv[0];
            Vector2 dUV1 = fuv[1] - fuv[0], dUV2 = fuv[fv.size() - 1] - fuv[0];
            float det = dUV1.x * dUV2.y - dUV2.x * dUV1.y;
            if (std::abs(det) > 1e-10f) {
                float r = 1.0f / det;
                T_face = (dP1 * dUV2.y - dP2 * dUV1.y) * r;
                T_face = (T_face - N * N.dot(T_face)).normalized();
                float sign = (det > 0.0f) ? 1.0f : -1.0f;
                B_face = N.cross(T_face) * sign;
            }
        }

        // Fan-triangulate and rasterize all triangles with the same face tangent frame.
        for (int i = 1; i + 1 < (int)fv.size(); ++i) {
            int c0 = 0, c1 = i + 1, c2 = i;
            float u0 = fuv[c0].x * w, v0 = fuv[c0].y * h;
            float u1 = fuv[c1].x * w, v1 = fuv[c1].y * h;
            float u2 = fuv[c2].x * w, v2 = fuv[c2].y * h;

            Vector3 T = T_face, B = B_face;

            int min_x = std::max(0,     (int)std::floor(std::min({u0,u1,u2})));
            int min_y = std::max(0,     (int)std::floor(std::min({v0,v1,v2})));
            int max_x = std::min(w - 1, (int)std::ceil( std::max({u0,u1,u2})));
            int max_y = std::min(h - 1, (int)std::ceil( std::max({v0,v1,v2})));

            float area = edge_fn(u0,v0, u1,v1, u2,v2);
            if (std::abs(area) < 1e-6f) continue;
            float inv = 1.0f / area;

            for (int py = min_y; py <= max_y; ++py) {
                for (int px = min_x; px <= max_x; ++px) {
                    float sx = px + 0.5f, sy = py + 0.5f;
                    if (edge_fn(u0,v0,u1,v1,sx,sy) * inv < 0.0f) continue;
                    if (edge_fn(u1,v1,u2,v2,sx,sy) * inv < 0.0f) continue;
                    if (edge_fn(u2,v2,u0,v0,sx,sy) * inv < 0.0f) continue;
                    TexelFrame &f = frames[py * w + px];
                    f.T = T;  f.B = B;  f.N = N;  f.valid = true;
                }
            }
        }
    }

    // --- Pass 2: rasterize subdivided mesh → smooth normal per texel ---
    Ref<ArrayMesh> subdivided = subdivide_to_mesh(mesh, subdiv_levels, true);
    if (!subdivided.is_valid()) return Ref<Image>();

    Array arrays = subdivided->surface_get_arrays(0);
    PackedVector3Array s_norms  = arrays[ArrayMesh::ARRAY_NORMAL];
    PackedVector2Array s_uvs    = arrays[ArrayMesh::ARRAY_TEX_UV];
    PackedInt32Array   s_idx    = arrays[ArrayMesh::ARRAY_INDEX];

    std::vector<Vector3> texel_nsub(w * h, Vector3(0,0,0));
    std::vector<bool>    covered(w * h, false);

    int n_tris = s_idx.size() / 3;
    for (int t = 0; t < n_tris; ++t) {
        int i0 = s_idx[t*3+0], i1 = s_idx[t*3+1], i2 = s_idx[t*3+2];
        Vector3 N0 = s_norms[i0], N1 = s_norms[i1], N2 = s_norms[i2];
        Vector2 UV0 = s_uvs[i0],  UV1 = s_uvs[i1],  UV2 = s_uvs[i2];

        float u0 = UV0.x*w, v0 = UV0.y*h;
        float u1 = UV1.x*w, v1 = UV1.y*h;
        float u2 = UV2.x*w, v2 = UV2.y*h;

        int min_x = std::max(0,     (int)std::floor(std::min({u0,u1,u2})));
        int min_y = std::max(0,     (int)std::floor(std::min({v0,v1,v2})));
        int max_x = std::min(w - 1, (int)std::ceil( std::max({u0,u1,u2})));
        int max_y = std::min(h - 1, (int)std::ceil( std::max({v0,v1,v2})));

        float area = edge_fn(u0,v0,u1,v1,u2,v2);
        if (std::abs(area) < 1e-6f) continue;
        float inv = 1.0f / area;

        for (int py = min_y; py <= max_y; ++py) {
            for (int px = min_x; px <= max_x; ++px) {
                float sx = px + 0.5f, sy = py + 0.5f;
                float w0 = edge_fn(u1,v1,u2,v2,sx,sy) * inv;
                float w1 = edge_fn(u2,v2,u0,v0,sx,sy) * inv;
                float w2 = edge_fn(u0,v0,u1,v1,sx,sy) * inv;
                if (w0 < 0.0f || w1 < 0.0f || w2 < 0.0f) continue;
                int idx = py * w + px;
                texel_nsub[idx] = (N0*w0 + N1*w1 + N2*w2).normalized();
                covered[idx] = true;
            }
        }
    }

    // --- Encode: project N_sub onto base-mesh tangent frame ---
    PackedByteArray bytes;
    bytes.resize(w * h * 3);
    for (int i = 0; i < w * h; ++i) {
        if (covered[i] && frames[i].valid) {
            float nx = texel_nsub[i].dot(frames[i].T);
            float ny = texel_nsub[i].dot(frames[i].B);
            float nz = texel_nsub[i].dot(frames[i].N);
            bytes[i*3+0] = (uint8_t)std::clamp((nx * 0.5f + 0.5f) * 255.0f, 0.0f, 255.0f);
            bytes[i*3+1] = (uint8_t)std::clamp((ny * 0.5f + 0.5f) * 255.0f, 0.0f, 255.0f);
            bytes[i*3+2] = (uint8_t)std::clamp((nz * 0.5f + 0.5f) * 255.0f, 0.0f, 255.0f);
        } else {
            bytes[i*3+0] = 128;
            bytes[i*3+1] = 128;
            bytes[i*3+2] = 255;
        }
    }

    return Image::create_from_data(w, h, false, Image::FORMAT_RGB8, bytes);
}

} // namespace gomo
