#include "half_edge_mesh.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/array_mesh.hpp>

#include <unordered_map>
#include <utility>

using namespace godot;

namespace gomo {

struct Vector3Hash {
    size_t operator()(const Vector3 &v) const {
        size_t h = std::hash<float>()(v.x);
        h ^= std::hash<float>()(v.y) + 0x9e3779b9 + (h << 6) + (h >> 2);
        h ^= std::hash<float>()(v.z) + 0x9e3779b9 + (h << 6) + (h >> 2);
        return h;
    }
};

// Simple edge key: ordered pair of vertex indices
struct EdgeKey {
    int32_t a, b;
    bool operator==(const EdgeKey &o) const { return a == o.a && b == o.b; }
};

struct EdgeKeyHash {
    size_t operator()(const EdgeKey &k) const {
        return std::hash<int64_t>()(((int64_t)k.a << 32) | (uint32_t)k.b);
    }
};

void HalfEdgeMesh::build_from_triangles(const PackedVector3Array &positions) {
    clear();

    int32_t tri_count = positions.size() / 3;
    if (tri_count == 0) return;

    // Deduplicate vertices
    std::unordered_map<Vector3, int32_t, Vector3Hash> vert_map;
    auto get_or_add_vertex = [&](const Vector3 &p) -> int32_t {
        auto it = vert_map.find(p);
        if (it != vert_map.end()) return it->second;
        int32_t idx = static_cast<int32_t>(vertices.size());
        vertices.push_back({p, -1});
        vert_map[p] = idx;
        return idx;
    };

    // Map from directed edge (a->b) to its half-edge index
    std::unordered_map<EdgeKey, int32_t, EdgeKeyHash> edge_map;

    for (int32_t t = 0; t < tri_count; ++t) {
        int32_t v[3];
        for (int i = 0; i < 3; ++i)
            v[i] = get_or_add_vertex(positions[t * 3 + i]);

        int32_t face_idx = static_cast<int32_t>(faces.size());
        faces.push_back({});

        int32_t he_base = static_cast<int32_t>(half_edges.size());
        half_edges.resize(he_base + 3);

        faces.back().half_edge = he_base;

        for (int i = 0; i < 3; ++i) {
            int32_t cur  = he_base + i;
            int32_t next = he_base + (i + 1) % 3;
            int32_t prev = he_base + (i + 2) % 3;

            half_edges[cur].vertex = v[i];
            half_edges[cur].next   = next;
            half_edges[cur].prev   = prev;
            half_edges[cur].face   = face_idx;
            half_edges[cur].twin   = -1;

            if (vertices[v[i]].half_edge == -1)
                vertices[v[i]].half_edge = cur;

            edge_map[{v[i], v[(i + 1) % 3]}] = cur;
        }
    }

    // Link twins
    for (auto &[key, he_idx] : edge_map) {
        auto twin_it = edge_map.find({key.b, key.a});
        if (twin_it != edge_map.end()) {
            half_edges[he_idx].twin          = twin_it->second;
            half_edges[twin_it->second].twin = he_idx;
        }
    }
}

Ref<ArrayMesh> HalfEdgeMesh::to_array_mesh() const {
    PackedVector3Array verts;
    verts.resize(static_cast<int64_t>(faces.size()) * 3);

    int32_t out = 0;
    for (const Face &f : faces) {
        int32_t he = f.half_edge;
        for (int i = 0; i < 3; ++i) {
            verts[out++] = vertices[half_edges[he].vertex].position;
            he = half_edges[he].next;
        }
    }

    Array arrays;
    arrays.resize(ArrayMesh::ARRAY_MAX);
    arrays[ArrayMesh::ARRAY_VERTEX] = verts;

    Ref<ArrayMesh> mesh;
    mesh.instantiate();
    mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
    return mesh;
}

Vector3 HalfEdgeMesh::get_vertex_position(int32_t idx) const {
    ERR_FAIL_INDEX_V(idx, static_cast<int32_t>(vertices.size()), Vector3());
    return vertices[idx].position;
}

void HalfEdgeMesh::set_vertex_position(int32_t idx, Vector3 pos) {
    ERR_FAIL_INDEX(idx, static_cast<int32_t>(vertices.size()));
    vertices[idx].position = pos;
}

PackedVector3Array HalfEdgeMesh::get_vertex_positions() const {
    PackedVector3Array out;
    out.resize(static_cast<int64_t>(vertices.size()));
    for (int32_t i = 0; i < (int32_t)vertices.size(); ++i)
        out[i] = vertices[i].position;
    return out;
}

void HalfEdgeMesh::clear() {
    vertices.clear();
    half_edges.clear();
    faces.clear();
}

void HalfEdgeMesh::_bind_methods() {
    ClassDB::bind_method(D_METHOD("build_from_triangles", "positions"), &HalfEdgeMesh::build_from_triangles);
    ClassDB::bind_method(D_METHOD("to_array_mesh"),                     &HalfEdgeMesh::to_array_mesh);
    ClassDB::bind_method(D_METHOD("get_vertex_count"),                  &HalfEdgeMesh::get_vertex_count);
    ClassDB::bind_method(D_METHOD("get_edge_count"),                    &HalfEdgeMesh::get_edge_count);
    ClassDB::bind_method(D_METHOD("get_face_count"),                    &HalfEdgeMesh::get_face_count);
    ClassDB::bind_method(D_METHOD("get_vertex_position", "idx"),        &HalfEdgeMesh::get_vertex_position);
    ClassDB::bind_method(D_METHOD("set_vertex_position", "idx", "pos"), &HalfEdgeMesh::set_vertex_position);
    ClassDB::bind_method(D_METHOD("get_vertex_positions"),              &HalfEdgeMesh::get_vertex_positions);
    ClassDB::bind_method(D_METHOD("clear"),                             &HalfEdgeMesh::clear);
}

} // namespace gomo
