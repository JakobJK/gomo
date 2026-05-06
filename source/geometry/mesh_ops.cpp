#include "mesh_ops.h"

#include <unordered_map>
#include <unordered_set>
#include <algorithm>
#include <cmath>
#include <utility>

using namespace godot;

namespace gomo {

namespace {

struct Vector3Hash {
    size_t operator()(const Vector3 &v) const {
        size_t h = std::hash<float>()(v.x);
        h ^= std::hash<float>()(v.y) + 0x9e3779b9 + (h << 6) + (h >> 2);
        h ^= std::hash<float>()(v.z) + 0x9e3779b9 + (h << 6) + (h >> 2);
        return h;
    }
};

struct EdgeKey {
    int32_t a, b;
    bool operator==(const EdgeKey &o) const { return a == o.a && b == o.b; }
};

struct EdgeKeyHash {
    size_t operator()(const EdgeKey &k) const {
        return std::hash<int64_t>()(((int64_t)k.a << 32) | (uint32_t)k.b);
    }
};

} // anonymous namespace



void build_from_triangles(HalfEdgeMesh &mesh, const Vector3 *positions, int32_t count) {
    mesh.clear();

    int32_t tri_count = count / 3;
    if (tri_count == 0) return;

    std::unordered_map<Vector3, int32_t, Vector3Hash> vertex_map;
    auto get_or_add_vertex = [&](const Vector3 &p) -> int32_t {
        auto it = vertex_map.find(p);
        if (it != vertex_map.end()) return it->second;
        int32_t vertex_index = static_cast<int32_t>(mesh.vertices.size());
        mesh.vertices.push_back({p, -1});
        vertex_map[p] = vertex_index;
        return vertex_index;
    };

    std::unordered_map<EdgeKey, int32_t, EdgeKeyHash> edge_map;

    for (int32_t t = 0; t < tri_count; ++t) {
        int32_t v[3];
        for (int i = 0; i < 3; ++i)
            v[i] = get_or_add_vertex(positions[t * 3 + i]);

        int32_t face_index = static_cast<int32_t>(mesh.faces.size());
        mesh.faces.push_back({});

        int32_t half_edge_base = static_cast<int32_t>(mesh.half_edges.size());
        mesh.half_edges.resize(half_edge_base + 3);
        mesh.faces.back().half_edge = half_edge_base;

        for (int i = 0; i < 3; ++i) {
            int32_t cur  = half_edge_base + i;
            int32_t next = half_edge_base + (i + 1) % 3;
            int32_t prev = half_edge_base + (i + 2) % 3;

            mesh.half_edges[cur].vertex = v[i];
            mesh.half_edges[cur].next   = next;
            mesh.half_edges[cur].prev   = prev;
            mesh.half_edges[cur].face   = face_index;
            mesh.half_edges[cur].twin   = -1;

            if (mesh.vertices[v[i]].half_edge == -1)
                mesh.vertices[v[i]].half_edge = cur;

            edge_map[{v[i], v[(i + 1) % 3]}] = cur;
        }
    }

    for (auto &[key, half_edge_index] : edge_map) {
        auto twin_it = edge_map.find({key.b, key.a});
        if (twin_it != edge_map.end()) {
            mesh.half_edges[half_edge_index].twin          = twin_it->second;
            mesh.half_edges[twin_it->second].twin = half_edge_index;
        }
    }
}


void build_sphere(HalfEdgeMesh &mesh, int32_t lat_segments, int32_t lon_segments) {
    mesh.clear();

    // North pole
    int32_t north = (int32_t)mesh.vertices.size();
    mesh.vertices.push_back({{0.0f, 1.0f, 0.0f}, -1});

    // Ring vertices: lat 1..lat_segments-1
    for (int32_t lat = 1; lat < lat_segments; ++lat) {
        float phi = Math_PI * (float)lat / (float)lat_segments; // 0..PI
        float y   = std::cos(phi);
        float r   = std::sin(phi);
        for (int32_t lon = 0; lon < lon_segments; ++lon) {
            float theta = 2.0f * Math_PI * (float)lon / (float)lon_segments;
            mesh.vertices.push_back({{r * std::sin(theta), y, r * std::cos(theta)}, -1});
        }
    }

    // South pole
    int32_t south = (int32_t)mesh.vertices.size();
    mesh.vertices.push_back({{0.0f, -1.0f, 0.0f}, -1});

    auto ring_v = [&](int32_t lat_ring, int32_t lon) -> int32_t {
        // lat_ring: 0..(lat_segments-2), lon: 0..(lon_segments-1)
        return 1 + lat_ring * lon_segments + lon % lon_segments;
    };

    std::unordered_map<EdgeKey, int32_t, EdgeKeyHash> edge_map;

    auto add_face = [&](std::initializer_list<int32_t> verts) {
        int32_t face_index     = (int32_t)mesh.faces.size();
        int32_t half_edge_base = (int32_t)mesh.half_edges.size();
        int32_t n              = (int32_t)verts.size();
        mesh.faces.push_back({half_edge_base});
        mesh.half_edges.resize(half_edge_base + n);
        int32_t i = 0;
        for (int32_t vi : verts) {
            int32_t cur  = half_edge_base + i;
            int32_t nxt  = half_edge_base + (i + 1) % n;
            int32_t prv  = half_edge_base + (i + n - 1) % n;
            mesh.half_edges[cur] = {vi, -1, nxt, prv, face_index};
            if (mesh.vertices[vi].half_edge == -1)
                mesh.vertices[vi].half_edge = cur;
            int32_t v_next = *(std::data(verts) + (i + 1) % n);
            edge_map[{vi, v_next}] = cur;
            ++i;
        }
    };

    // North cap
    for (int32_t lon = 0; lon < lon_segments; ++lon)
        add_face({north, ring_v(0, lon), ring_v(0, lon + 1)});

    // Body quads
    for (int32_t lat = 0; lat < lat_segments - 2; ++lat) {
        for (int32_t lon = 0; lon < lon_segments; ++lon) {
            int32_t v0 = ring_v(lat,     lon);
            int32_t v1 = ring_v(lat,     lon + 1);
            int32_t v2 = ring_v(lat + 1, lon + 1);
            int32_t v3 = ring_v(lat + 1, lon);
            add_face({v0, v3, v2, v1});
        }
    }

    // South cap
    int32_t last_ring = lat_segments - 2;
    for (int32_t lon = 0; lon < lon_segments; ++lon)
        add_face({ring_v(last_ring, lon + 1), ring_v(last_ring, lon), south});

    // Link twins
    for (auto &[key, he] : edge_map) {
        auto it = edge_map.find({key.b, key.a});
        if (it != edge_map.end() && mesh.half_edges[he].twin == -1) {
            mesh.half_edges[he].twin        = it->second;
            mesh.half_edges[it->second].twin = he;
        }
    }
}


// --- Queries ---

Vector3 get_face_normal(const HalfEdgeMesh &mesh, int32_t face_index) {
    Vector3 normal;
    int32_t half_edge = mesh.faces[face_index].half_edge;
    do {
        Vector3 cur  = mesh.vertices[mesh.half_edges[half_edge].vertex].position;
        Vector3 next = mesh.vertices[mesh.half_edges[mesh.half_edges[half_edge].next].vertex].position;
        normal.x += (cur.y - next.y) * (cur.z + next.z);
        normal.y += (cur.z - next.z) * (cur.x + next.x);
        normal.z += (cur.x - next.x) * (cur.y + next.y);
        half_edge = mesh.half_edges[half_edge].next;
    } while (half_edge != mesh.faces[face_index].half_edge);
    return normal.normalized();
}

Vector3 get_face_center(const HalfEdgeMesh &mesh, int32_t face_index) {
    Vector3 center;
    int count = 0;
    int32_t half_edge = mesh.faces[face_index].half_edge;
    do {
        center += mesh.vertices[mesh.half_edges[half_edge].vertex].position;
        ++count;
        half_edge = mesh.half_edges[half_edge].next;
    } while (half_edge != mesh.faces[face_index].half_edge);
    return count > 0 ? center / count : center;
}

std::vector<int32_t> get_face_vertex_indices(const HalfEdgeMesh &mesh, int32_t face_index) {
    std::vector<int32_t> result;
    int32_t half_edge = mesh.faces[face_index].half_edge;
    do {
        result.push_back(mesh.half_edges[half_edge].vertex);
        half_edge = mesh.half_edges[half_edge].next;
    } while (half_edge != mesh.faces[face_index].half_edge);
    return result;
}

int32_t pick_face(const HalfEdgeMesh &mesh, Vector3 ray_from, Vector3 ray_dir) {
    float best_t = 1e38f;
    int32_t best_face = -1;

    for (int32_t face_index = 0; face_index < (int32_t)mesh.faces.size(); ++face_index) {
        if (mesh.faces[face_index].half_edge == -1) continue;

        std::vector<Vector3> face_positions;
        int32_t half_edge = mesh.faces[face_index].half_edge;
        do {
            face_positions.push_back(mesh.vertices[mesh.half_edges[half_edge].vertex].position);
            half_edge = mesh.half_edges[half_edge].next;
        } while (half_edge != mesh.faces[face_index].half_edge);
        if ((int)face_positions.size() < 3) continue;

        Vector3 n = (face_positions[1] - face_positions[0]).cross(face_positions[2] - face_positions[0]);
        float denom = n.dot(ray_dir);
        if (Math::abs(denom) < 1e-6f) continue;

        float t = n.dot(face_positions[0] - ray_from) / denom;
        if (t <= 0.0f || t >= best_t) continue;

        Vector3 p = ray_from + ray_dir * t;
        for (int i = 1; i + 1 < (int)face_positions.size(); ++i) {
            Vector3 c0 = (face_positions[i]     - face_positions[0]).cross(p - face_positions[0]);
            Vector3 c1 = (face_positions[i + 1] - face_positions[i]).cross(p - face_positions[i]);
            Vector3 c2 = (face_positions[0]     - face_positions[i + 1]).cross(p - face_positions[i + 1]);
            if (c0.dot(n) >= 0 && c1.dot(n) >= 0 && c2.dot(n) >= 0) {
                best_t    = t;
                best_face = face_index;
                break;
            }
        }
    }

    return best_face;
}


// --- Topology operations ---

std::vector<int32_t> extrude_edge(HalfEdgeMesh &mesh, int32_t half_edge_index) {
    if (half_edge_index < 0 || half_edge_index >= (int32_t)mesh.half_edges.size()) return {};
    if (mesh.half_edges[half_edge_index].twin != -1) return {};

    int32_t vertex_a = mesh.half_edges[half_edge_index].vertex;
    int32_t vertex_b = mesh.half_edges[mesh.half_edges[half_edge_index].next].vertex;

    int32_t new_vertex_a = (int32_t)mesh.vertices.size();
    mesh.vertices.push_back({mesh.vertices[vertex_a].position, -1});
    int32_t new_vertex_b = (int32_t)mesh.vertices.size();
    mesh.vertices.push_back({mesh.vertices[vertex_b].position, -1});

    int32_t face_index = (int32_t)mesh.faces.size();
    mesh.faces.push_back({});

    int32_t half_edge_base = (int32_t)mesh.half_edges.size();
    mesh.half_edges.resize(half_edge_base + 4);

    // Single quad: vertex_b → vertex_a → new_vertex_a → new_vertex_b
    int32_t q0 = half_edge_base,     q1 = half_edge_base + 1;
    int32_t q2 = half_edge_base + 2, q3 = half_edge_base + 3;
    mesh.half_edges[q0] = {vertex_b,   half_edge_index, q1, q3, face_index};
    mesh.half_edges[q1] = {vertex_a,   -1,              q2, q0, face_index};
    mesh.half_edges[q2] = {new_vertex_a, -1,            q3, q1, face_index};
    mesh.half_edges[q3] = {new_vertex_b, -1,            q0, q2, face_index};

    mesh.half_edges[half_edge_index].twin = q0;
    mesh.faces[face_index].half_edge      = q0;

    mesh.vertices[new_vertex_a].half_edge = q2;
    mesh.vertices[new_vertex_b].half_edge = q3;

    return {q2};  // new top boundary half-edge, canonical ID for the extruded edge
}

std::vector<int32_t> extrude_face(HalfEdgeMesh &mesh, int32_t face_index) {
    if (face_index < 0 || face_index >= (int32_t)mesh.faces.size()) return {};

    std::vector<int32_t> face_half_edges;
    std::vector<int32_t> face_vertices;
    int32_t half_edge = mesh.faces[face_index].half_edge;
    do {
        face_half_edges.push_back(half_edge);
        face_vertices.push_back(mesh.half_edges[half_edge].vertex);
        half_edge = mesh.half_edges[half_edge].next;
    } while (half_edge != mesh.faces[face_index].half_edge);

    int32_t N = (int32_t)face_half_edges.size();
    if (N < 3) return {};

    std::vector<int32_t> twins(N);
    for (int i = 0; i < N; ++i)
        twins[i] = mesh.half_edges[face_half_edges[i]].twin;

    std::vector<int32_t> new_vertices(N);
    for (int i = 0; i < N; ++i) {
        new_vertices[i] = (int32_t)mesh.vertices.size();
        mesh.vertices.push_back({mesh.vertices[face_vertices[i]].position, -1});
    }

    for (int i = 0; i < N; ++i)
        mesh.half_edges[face_half_edges[i]].vertex = new_vertices[i];

    int32_t half_edge_base = (int32_t)mesh.half_edges.size();
    mesh.half_edges.resize(half_edge_base + N * 4);

    std::vector<int32_t> side_faces(N);
    for (int i = 0; i < N; ++i) {
        side_faces[i] = (int32_t)mesh.faces.size();
        mesh.faces.push_back({half_edge_base + i * 4});
    }

    for (int i = 0; i < N; ++i) {
        int32_t ip1 = (i + 1) % N;
        int32_t im1 = (i + N - 1) % N;

        int32_t q0 = half_edge_base + i * 4 + 0;
        int32_t q1 = half_edge_base + i * 4 + 1;
        int32_t q2 = half_edge_base + i * 4 + 2;
        int32_t q3 = half_edge_base + i * 4 + 3;

        mesh.half_edges[q0] = {face_vertices[i],    twins[i],                        q1, q3, side_faces[i]};
        mesh.half_edges[q1] = {face_vertices[ip1],  half_edge_base + ip1 * 4 + 3,    q2, q0, side_faces[i]};
        mesh.half_edges[q2] = {new_vertices[ip1],   face_half_edges[i],              q3, q1, side_faces[i]};
        mesh.half_edges[q3] = {new_vertices[i],     half_edge_base + im1 * 4 + 1,    q0, q2, side_faces[i]};

        if (twins[i] != -1)
            mesh.half_edges[twins[i]].twin        = q0;
        mesh.half_edges[face_half_edges[i]].twin  = q2;

        mesh.vertices[face_vertices[i]].half_edge = q0;
        mesh.vertices[new_vertices[i]].half_edge  = face_half_edges[i];
    }

    return new_vertices;
}


std::vector<int32_t> extrude_edges(HalfEdgeMesh &mesh, const std::vector<int32_t> &half_edges) {
    if (half_edges.empty()) return {};

    // One new vertex per unique old vertex — shared at junctions between connected edges
    std::unordered_map<int32_t, int32_t> old_to_new;
    for (int32_t he : half_edges) {
        for (int32_t v : {mesh.half_edges[he].vertex,
                          mesh.half_edges[mesh.half_edges[he].next].vertex}) {
            if (!old_to_new.count(v)) {
                old_to_new[v] = (int32_t)mesh.vertices.size();
                mesh.vertices.push_back({mesh.vertices[v].position, -1});
            }
        }
    }

    // up_at[V]   = q1 half-edge starting at V going toward new_V   (right side of its quad)
    // down_at[V] = q3 half-edge starting at new_V going toward V   (left side of its quad)
    // At a junction vertex both will exist and must be twinned.
    std::unordered_map<int32_t, int32_t> up_at, down_at;

    std::vector<int32_t> new_top_edges;

    for (int32_t he : half_edges) {
        int32_t va     = mesh.half_edges[he].vertex;
        int32_t vb     = mesh.half_edges[mesh.half_edges[he].next].vertex;
        int32_t new_va = old_to_new[va];
        int32_t new_vb = old_to_new[vb];

        int32_t fi   = (int32_t)mesh.faces.size();
        int32_t base = (int32_t)mesh.half_edges.size();
        mesh.faces.push_back({base});
        mesh.half_edges.resize(base + 4);

        int32_t q0 = base, q1 = base+1, q2 = base+2, q3 = base+3;
        // quad ring: vb → va → new_va → new_vb (same winding as single extrude_edge)
        mesh.half_edges[q0] = {vb,     he, q1, q3, fi};
        mesh.half_edges[q1] = {va,     -1, q2, q0, fi};  // right side: va → new_va
        mesh.half_edges[q2] = {new_va, -1, q3, q1, fi};  // top (new boundary)
        mesh.half_edges[q3] = {new_vb, -1, q0, q2, fi};  // left side: new_vb → vb

        mesh.half_edges[he].twin        = q0;
        mesh.vertices[new_va].half_edge = q2;
        mesh.vertices[new_vb].half_edge = q3;

        new_top_edges.push_back(q2);

        up_at[va]   = q1;  // at vertex va, this quad's right side goes up
        down_at[vb] = q3;  // at vertex vb, this quad's left side comes down
    }

    // Twin junction side edges between adjacent quads
    for (auto &[v, q1] : up_at) {
        auto it = down_at.find(v);
        if (it != down_at.end()) {
            mesh.half_edges[q1].twin          = it->second;
            mesh.half_edges[it->second].twin  = q1;
        }
    }

    return new_top_edges;
}

std::vector<int32_t> extrude_faces(HalfEdgeMesh &mesh, const std::vector<int32_t> &face_indices) {
    if (face_indices.empty()) return {};

    std::unordered_set<int32_t> selected(face_indices.begin(), face_indices.end());

    // Collect face rings and build one new vertex per unique old vertex
    struct FaceRing { std::vector<int32_t> hes, verts, orig_twins; };
    std::vector<FaceRing> rings(face_indices.size());
    std::unordered_map<int32_t, int32_t> old_to_new;

    for (int fi = 0; fi < (int)face_indices.size(); ++fi) {
        int32_t he = mesh.faces[face_indices[fi]].half_edge;
        do {
            int32_t v = mesh.half_edges[he].vertex;
            rings[fi].hes.push_back(he);
            rings[fi].verts.push_back(v);
            rings[fi].orig_twins.push_back(mesh.half_edges[he].twin);
            if (!old_to_new.count(v)) {
                old_to_new[v] = (int32_t)mesh.vertices.size();
                mesh.vertices.push_back({mesh.vertices[v].position, -1});
            }
            he = mesh.half_edges[he].next;
        } while (he != mesh.faces[face_indices[fi]].half_edge);
    }

    // Redirect face half-edges to new vertices — original faces become the tops
    for (auto &ring : rings)
        for (int i = 0; i < (int)ring.hes.size(); ++i)
            mesh.half_edges[ring.hes[i]].vertex = old_to_new[ring.verts[i]];

    // up_at / down_at for corner twinning (same convention as extrude_edges)
    std::unordered_map<int32_t, int32_t> up_at, down_at;

    for (int fi = 0; fi < (int)face_indices.size(); ++fi) {
        auto &ring = rings[fi];
        int32_t N  = (int32_t)ring.hes.size();
        for (int i = 0; i < N; ++i) {
            int32_t he       = ring.hes[i];
            int32_t orig_twin = ring.orig_twins[i];
            int32_t va       = ring.verts[i];
            int32_t vb       = ring.verts[(i + 1) % N];
            int32_t new_va   = old_to_new[va];
            int32_t new_vb   = old_to_new[vb];

            // Skip interior edges — no side wall needed, twin relationship already intact
            if (orig_twin != -1 && selected.count(mesh.half_edges[orig_twin].face))
                continue;

            int32_t side_fi = (int32_t)mesh.faces.size();
            int32_t base    = (int32_t)mesh.half_edges.size();
            mesh.faces.push_back({base});
            mesh.half_edges.resize(base + 4);

            int32_t q0 = base, q1 = base+1, q2 = base+2, q3 = base+3;
            // q0: bottom (old edge, twins with outer mesh)
            // q1: right side — vb → new_vb
            // q2: top  — new_vb → new_va  (twins with the face's half-edge)
            // q3: left side  — new_va → va
            mesh.half_edges[q0] = {va,     orig_twin, q1, q3, side_fi};
            mesh.half_edges[q1] = {vb,     -1,        q2, q0, side_fi};
            mesh.half_edges[q2] = {new_vb, he,        q3, q1, side_fi};
            mesh.half_edges[q3] = {new_va, -1,        q0, q2, side_fi};

            if (orig_twin != -1) mesh.half_edges[orig_twin].twin = q0;
            mesh.half_edges[he].twin        = q2;
            mesh.vertices[va].half_edge     = q0;
            mesh.vertices[new_va].half_edge = ring.hes[i];

            up_at[vb]   = q1;  // right side: vb → new_vb
            down_at[va] = q3;  // left side: new_va → va
        }
    }

    // Twin corners between adjacent side walls
    for (auto &[v, q1] : up_at) {
        auto it = down_at.find(v);
        if (it != down_at.end()) {
            mesh.half_edges[q1].twin         = it->second;
            mesh.half_edges[it->second].twin = q1;
        }
    }

    return face_indices;
}

} // namespace gomo
