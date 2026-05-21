#define _USE_MATH_DEFINES
#include "cylinder.h"
#include <cmath>
#include <unordered_map>
#include <vector>

using namespace godot;

namespace gomo {

void build_cylinder(HalfEdgeMesh &mesh, int32_t sides, float radius, float height) {
    mesh.clear();
    sides = std::max(3, (int)sides);

    const float half_h = height * 0.5f;
    const float step   = 2.0f * (float)M_PI / (float)sides;

    // Vertices:
    //   bottom ring  [0 .. sides-1]
    //   top ring     [sides .. 2*sides-1]
    //   bottom center [2*sides]
    //   top center    [2*sides+1]
    for (int i = 0; i < sides; ++i) {
        float a = (float)i * step;
        mesh.vertices.push_back({{radius * std::cos(a), -half_h, radius * std::sin(a)}, -1});
    }
    for (int i = 0; i < sides; ++i) {
        float a = (float)i * step;
        mesh.vertices.push_back({{radius * std::cos(a), +half_h, radius * std::sin(a)}, -1});
    }
    const int32_t bot_center = (int32_t)mesh.vertices.size();
    mesh.vertices.push_back({{0.0f, -half_h, 0.0f}, -1});
    const int32_t top_center = (int32_t)mesh.vertices.size();
    mesh.vertices.push_back({{0.0f, +half_h, 0.0f}, -1});

    std::unordered_map<EdgeKey, int32_t, EdgeKeyHash> edge_map;

    auto add_face = [&](const std::vector<int32_t> &verts) {
        int32_t face_idx = (int32_t)mesh.faces.size();
        int32_t he_base  = (int32_t)mesh.half_edges.size();
        int32_t n        = (int32_t)verts.size();
        mesh.faces.push_back({he_base});
        mesh.half_edges.resize(he_base + n);
        for (int i = 0; i < n; ++i) {
            int32_t cur     = he_base + i;
            int32_t vi      = verts[i];
            int32_t vi_next = verts[(i + 1) % n];
            mesh.half_edges[cur] = {vi, -1, he_base + (i + 1) % n, he_base + (i + n - 1) % n, face_idx};
            if (mesh.vertices[vi].half_edge == -1)
                mesh.vertices[vi].half_edge = cur;
            edge_map[{vi, vi_next}] = cur;
        }
    };

    // Side quads: {bot[i+1], bot[i], top[i], top[i+1]} → outward normal
    for (int i = 0; i < sides; ++i) {
        int32_t b0 = i;
        int32_t b1 = (i + 1) % sides;
        int32_t t0 = sides + i;
        int32_t t1 = sides + (i + 1) % sides;
        add_face({b1, b0, t0, t1});
    }

    // Bottom cap triangles: {bot[i], bot[i+1], bot_center} → normal -Y
    for (int i = 0; i < sides; ++i)
        add_face({i, (i + 1) % sides, bot_center});

    // Top cap triangles: {top[i+1], top[i], top_center} → normal +Y
    for (int i = 0; i < sides; ++i)
        add_face({sides + (i + 1) % sides, sides + i, top_center});

    // Wire twins
    for (auto &[key, he] : edge_map) {
        auto it = edge_map.find({key.b, key.a});
        if (it != edge_map.end() && mesh.half_edges[he].twin == -1) {
            mesh.half_edges[he].twin         = it->second;
            mesh.half_edges[it->second].twin = he;
        }
    }
}

} // namespace gomo
