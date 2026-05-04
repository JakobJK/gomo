#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include "../geometry/half_edge_mesh.h"
#include "../geometry/mesh_commands.h"
#include "../commands/command.h"
#include <memory>

class HalfEdgeMesh : public godot::RefCounted {
    GDCLASS(HalfEdgeMesh, godot::RefCounted)

public:
    // Construction
    void build_from_triangles(const godot::PackedVector3Array &positions);
    void build_box(float width = 2.0f, float height = 2.0f, float depth = 2.0f,
                   int32_t width_segments = 1, int32_t height_segments = 1, int32_t depth_segments = 1);
    void build_sphere(int32_t lat_segments = 8, int32_t lon_segments = 16);

    // Conversion
    godot::Ref<godot::ArrayMesh> to_array_mesh() const;

    // Counts
    int32_t get_vertex_count() const;
    int32_t get_edge_count()   const;
    int32_t get_face_count()   const;

    // Vertex accessors
    godot::Vector3            get_vertex_position(int32_t idx) const;
    void                      set_vertex_position(int32_t idx, godot::Vector3 pos);
    godot::PackedVector3Array get_vertex_positions() const;

    // Half-edge accessors
    int32_t get_half_edge_vertex(int32_t half_edge_index) const;
    int32_t get_half_edge_next(int32_t half_edge_index)   const;
    int32_t get_half_edge_twin(int32_t half_edge_index)   const;
    int32_t get_half_edge_face(int32_t half_edge_index)   const;

    // Face accessors
    bool                    is_face_valid(int32_t face_idx)            const;
    godot::Vector3          get_face_center(int32_t face_idx)         const;
    godot::Vector3          get_face_normal(int32_t face_idx)         const;
    godot::PackedInt32Array get_face_vertex_indices(int32_t face_idx)  const;
    int32_t                 pick_face(godot::Vector3 ray_from, godot::Vector3 ray_dir) const;

    // Topology operations (all recorded to undo history)
    godot::PackedInt32Array extrude_edge(int32_t half_edge_index);
    godot::PackedInt32Array extrude_face(int32_t face_idx);
    void                    delete_face(int32_t face_idx);

    // Vertex move (record after drag ends — vertices already at new positions)
    void record_move_vertices(godot::PackedInt32Array indices,
                              godot::PackedVector3Array old_positions);

    // Sculpting (paint_at / flatten_at are recorded via begin/end_tilt_stroke)
    void                     paint_at(godot::Vector3 hit_pos, float strength, float world_radius);
    void                     flatten_at(godot::Vector3 hit_pos, float strength, float world_radius);
    void                     begin_tilt_stroke();
    void                     end_tilt_stroke();
    void                     restore_tilt_to_stroke_base();
    godot::Ref<godot::Image> get_face_normal_map(int32_t face_idx) const;

    // Subdivision preview
    godot::Ref<godot::ArrayMesh> subdivide_to_mesh(int32_t levels = 2) const;

    // UV unwrapping
    void                      unwrap_uvs();
    void                      set_seam(int32_t half_edge_index, bool is_seam);
    bool                      get_seam(int32_t half_edge_index) const;
    godot::PackedVector2Array get_uv_edges() const;
    void                      translate_uvs(godot::PackedVector2Array positions, godot::Vector2 delta, float epsilon);

    // Undo / redo
    bool undo();
    bool redo();
    bool can_undo() const;
    bool can_redo() const;

    void clear();

protected:
    static void _bind_methods();

private:
    gomo::HalfEdgeMesh                        _mesh;
    gomo::CommandHistory                      _history;
    std::unique_ptr<gomo::TiltStrokeCommand>  _pending_tilt_stroke;
    bool                                      _uvs_valid = false;
};
