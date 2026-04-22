#include "mesh_ops.h"

#include <unordered_map>
#include <algorithm>
#include <cmath>
#include <utility>

using namespace godot;

namespace gomo {

// --- Internal helpers ---
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

static float lerp_f(float a, float b, float t) { return a + (b - a) * t; }

static godot::Vector3 decode_normal(const gomo::FaceFrame &frame, godot::Vector3 geo_normal,
                                     float tu, float tv) {
    float tz = std::sqrt(std::max(0.0f, 1.0f - tu * tu - tv * tv));
    return (geo_normal * tz + frame.tangent * tu + frame.bitangent * tv).normalized();
}

static void encode_normal(const gomo::FaceFrame &frame, godot::Vector3 n,
                           float &tu, float &tv) {
    tu = n.dot(frame.tangent);
    tv = n.dot(frame.bitangent);
}

static Vector3 texel_world_pos(const FaceFrame &frame, int x, int y, int size) {
    float u = (float)x / (size - 1);
    float v = (float)y / (size - 1);
    return frame.origin + frame.tangent * (u * frame.width) + frame.bitangent * (v * frame.height);
}

} // anonymous namespace


// --- Construction ---

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

void build_box(HalfEdgeMesh &mesh) {
    mesh.clear();

    const Vector3 p[8] = {
        {-1,-1,-1}, { 1,-1,-1}, { 1, 1,-1}, {-1, 1,-1},
        {-1,-1, 1}, { 1,-1, 1}, { 1, 1, 1}, {-1, 1, 1},
    };
    for (auto &v : p) mesh.vertices.push_back({v, -1});

    const int32_t quads[6][4] = {
        {1, 5, 4, 0},
        {3, 7, 6, 2},
        {4, 5, 6, 7},
        {0, 3, 2, 1},
        {0, 4, 7, 3},
        {1, 2, 6, 5},
    };

    std::unordered_map<EdgeKey, int32_t, EdgeKeyHash> edge_map;

    for (int f = 0; f < 6; ++f) {
        int32_t face_index = (int32_t)mesh.faces.size();
        mesh.faces.push_back({});

        int32_t half_edge_base = (int32_t)mesh.half_edges.size();
        mesh.half_edges.resize(half_edge_base + 4);
        mesh.faces.back().half_edge = half_edge_base;

        for (int i = 0; i < 4; ++i) {
            int32_t cur          = half_edge_base + i;
            int32_t next         = half_edge_base + (i + 1) % 4;
            int32_t prev         = half_edge_base + (i + 3) % 4;
            int32_t vertex_index = quads[f][i];

            mesh.half_edges[cur].vertex = vertex_index;
            mesh.half_edges[cur].next   = next;
            mesh.half_edges[cur].prev   = prev;
            mesh.half_edges[cur].face   = face_index;
            mesh.half_edges[cur].twin   = -1;

            if (mesh.vertices[vertex_index].half_edge == -1)
                mesh.vertices[vertex_index].half_edge = cur;

            edge_map[{vertex_index, quads[f][(i + 1) % 4]}] = cur;
        }
    }

    for (auto &[key, half_edge_index] : edge_map) {
        auto it = edge_map.find({key.b, key.a});
        if (it != edge_map.end()) {
            mesh.half_edges[half_edge_index].twin = it->second;
            mesh.half_edges[it->second].twin      = half_edge_index;
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

FaceFrame compute_face_frame(const HalfEdgeMesh &mesh, int32_t face_index) {
    std::vector<Vector3> face_positions;
    int32_t half_edge = mesh.faces[face_index].half_edge;
    do {
        face_positions.push_back(mesh.vertices[mesh.half_edges[half_edge].vertex].position);
        half_edge = mesh.half_edges[half_edge].next;
    } while (half_edge != mesh.faces[face_index].half_edge);

    Vector3 tangent   = (face_positions[1] - face_positions[0]).normalized();
    Vector3 normal    = get_face_normal(mesh, face_index);
    Vector3 bitangent = normal.cross(tangent).normalized();

    float min_u =  1e38f, max_u = -1e38f;
    float min_v =  1e38f, max_v = -1e38f;
    for (auto &p : face_positions) {
        Vector3 d = p - face_positions[0];
        float u = d.dot(tangent);
        float v = d.dot(bitangent);
        min_u = std::min(min_u, u);  max_u = std::max(max_u, u);
        min_v = std::min(min_v, v);  max_v = std::max(max_v, v);
    }

    Vector3 origin = face_positions[0] + tangent * min_u + bitangent * min_v;
    return { origin, tangent, bitangent, max_u - min_u, max_v - min_v };
}

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

    return {new_vertex_a, new_vertex_b};
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



void paint_at(HalfEdgeMesh &mesh, Vector3 hit_pos, float strength, float world_radius) {
    const int size = Face::HF_SIZE;
    for (int32_t face_index = 0; face_index < (int32_t)mesh.faces.size(); ++face_index) {
        if (mesh.faces[face_index].half_edge == -1) continue;
        Vector3 geo_normal = get_face_normal(mesh, face_index);
        if (geo_normal.dot(hit_pos - get_face_center(mesh, face_index)) < 0.0f) continue;
        FaceFrame frame = compute_face_frame(mesh, face_index);
        auto &tilt = mesh.faces[face_index].tilt;
        for (int y = 0; y < size; ++y) {
            for (int x = 0; x < size; ++x) {
                Vector3 delta = texel_world_pos(frame, x, y, size) - hit_pos;
                float dist = delta.length();
                if (dist >= world_radius || dist < 1e-6f) continue;

                // Target: push outward from brush centre, clamped to upper hemisphere.
                Vector3 target = delta / dist;
                float   below  = target.dot(geo_normal);
                if (below < 0.0f) target = target - geo_normal * below;
                float tlen = target.length();
                if (tlen < 1e-6f) continue;
                target = target / tlen;

                float weight = strength * std::pow(1.0f - dist / world_radius, 2.0f);
                weight = std::min(weight, 1.0f);

                int idx = (y * size + x) * 2;
                Vector3 current = decode_normal(frame, geo_normal, tilt[idx], tilt[idx + 1]);
                Vector3 new_n   = (current + (target - current) * weight).normalized();
                encode_normal(frame, new_n, tilt[idx], tilt[idx + 1]);
            }
        }
    }
}

void flatten_at(HalfEdgeMesh &mesh, Vector3 hit_pos, float strength, float world_radius) {
    const int size = Face::HF_SIZE;

    struct FaceEntry { int32_t face_index; FaceFrame frame; Vector3 geo_normal; };
    std::vector<FaceEntry> entries;
    for (int32_t face_index = 0; face_index < (int32_t)mesh.faces.size(); ++face_index) {
        if (mesh.faces[face_index].half_edge == -1) continue;
        Vector3 geo_normal = get_face_normal(mesh, face_index);
        float   d          = geo_normal.dot(hit_pos - get_face_center(mesh, face_index));
        if (std::abs(d) >= world_radius) continue;
        entries.push_back({face_index, compute_face_frame(mesh, face_index), geo_normal});
    }
    if (entries.empty()) return;

    // First pass: uniform average of all decoded normals inside the brush (flat-top falloff).
    Vector3 avg_normal;
    int     avg_count = 0;
    for (auto &entry : entries) {
        auto &tilt = mesh.faces[entry.face_index].tilt;
        for (int y = 0; y < size; ++y) {
            for (int x = 0; x < size; ++x) {
                float dist = (texel_world_pos(entry.frame, x, y, size) - hit_pos).length();
                if (dist >= world_radius) continue;
                int idx = (y * size + x) * 2;
                avg_normal += decode_normal(entry.frame, entry.geo_normal, tilt[idx], tilt[idx + 1]);
                ++avg_count;
            }
        }
    }
    if (avg_count == 0) return;
    avg_normal = (avg_normal / (float)avg_count).normalized();

    // Second pass: snap each texel uniformly toward the average.
    for (auto &entry : entries) {
        auto &tilt = mesh.faces[entry.face_index].tilt;
        for (int y = 0; y < size; ++y) {
            for (int x = 0; x < size; ++x) {
                float dist = (texel_world_pos(entry.frame, x, y, size) - hit_pos).length();
                if (dist >= world_radius) continue;
                float weight = std::min(1.0f, strength);
                int   idx    = (y * size + x) * 2;
                Vector3 current = decode_normal(entry.frame, entry.geo_normal, tilt[idx], tilt[idx + 1]);
                Vector3 new_n   = (current + (avg_normal - current) * weight).normalized();
                encode_normal(entry.frame, new_n, tilt[idx], tilt[idx + 1]);
            }
        }
    }
}

} // namespace gomo
