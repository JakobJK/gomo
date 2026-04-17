#pragma once

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <vector>
#include <cstdint>

namespace gomo {

struct HalfEdge;
struct Face;

struct Vertex {
    godot::Vector3 position;
    int32_t half_edge = -1; // any outgoing half-edge
};

struct HalfEdge {
    int32_t vertex   = -1; // origin vertex
    int32_t twin     = -1; // opposite half-edge
    int32_t next     = -1; // next half-edge around face (CCW)
    int32_t prev     = -1; // previous half-edge around face
    int32_t face     = -1; // owning face (-1 = boundary)
};

struct Face {
    int32_t half_edge = -1; // any half-edge of this face
};

class HalfEdgeMesh : public godot::RefCounted {
    GDCLASS(HalfEdgeMesh, godot::RefCounted)

public:
    HalfEdgeMesh() = default;
    ~HalfEdgeMesh() = default;

    // Build from a triangle soup (flat array of positions, 3 per triangle)
    void build_from_triangles(const godot::PackedVector3Array &positions);

    // Convert back to an ArrayMesh for rendering
    godot::Ref<godot::ArrayMesh> to_array_mesh() const;

    // Queries
    int32_t get_vertex_count() const { return static_cast<int32_t>(vertices.size()); }
    int32_t get_edge_count()   const { return static_cast<int32_t>(half_edges.size()); }
    int32_t get_face_count()   const { return static_cast<int32_t>(faces.size()); }

    godot::Vector3           get_vertex_position(int32_t idx) const;
    void                     set_vertex_position(int32_t idx, godot::Vector3 pos);
    godot::PackedVector3Array get_vertex_positions() const;

    void clear();

protected:
    static void _bind_methods();

private:
    std::vector<Vertex>   vertices;
    std::vector<HalfEdge> half_edges;
    std::vector<Face>     faces;
};

} // namespace gomo