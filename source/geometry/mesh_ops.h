#pragma once

#include "half_edge_mesh.h"
#include <vector>

namespace gomo {

// --- Construction ---
void build_from_triangles(HalfEdgeMesh &mesh, const godot::Vector3 *positions, int32_t count);
void build_sphere(HalfEdgeMesh &mesh, int32_t lat_segments = 8, int32_t lon_segments = 16);

// --- Queries ---
FaceFrame      compute_face_frame(const HalfEdgeMesh &mesh, int32_t face_index);
godot::Vector3 get_face_normal(const HalfEdgeMesh &mesh, int32_t face_index);
godot::Vector3 get_face_center(const HalfEdgeMesh &mesh, int32_t face_index);
std::vector<int32_t> get_face_vertex_indices(const HalfEdgeMesh &mesh, int32_t face_index);
int32_t        pick_face(const HalfEdgeMesh &mesh, godot::Vector3 ray_from, godot::Vector3 ray_dir);

// --- Topology operations ---
std::vector<int32_t> extrude_edge(HalfEdgeMesh &mesh, int32_t half_edge_index);
std::vector<int32_t> extrude_face(HalfEdgeMesh &mesh, int32_t face_index);

// --- Sculpting ---
void paint_at(HalfEdgeMesh &mesh, godot::Vector3 hit_pos, float strength, float world_radius);
void flatten_at(HalfEdgeMesh &mesh, godot::Vector3 hit_pos, float strength, float world_radius);

} // namespace gomo
