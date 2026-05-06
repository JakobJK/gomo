#pragma once

#include "half_edge_mesh.h"
#include "../commands/command.h"
#include <vector>

namespace gomo {

// ---------------------------------------------------------------------------
// DeleteFaceCommand
// State is captured in the constructor. do_it / redo_it both call delete_face.
// ---------------------------------------------------------------------------

class DeleteFaceCommand : public Command {
public:
    DeleteFaceCommand(const HalfEdgeMesh &mesh, int32_t face_index);
    void do_it(HalfEdgeMesh &mesh)   override { redo_it(mesh); }
    void redo_it(HalfEdgeMesh &mesh) override;
    void undo_it(HalfEdgeMesh &mesh) override;

private:
    struct HalfEdgeSave { int32_t index, twin, face; };
    struct VertexSave   { int32_t vertex_index, half_edge; };

    int32_t _face_index;
    int32_t _face_half_edge;
    std::vector<HalfEdgeSave> _he_saves;
    std::vector<VertexSave>   _vertex_saves;
};

// ---------------------------------------------------------------------------
// ExtrudeEdgesCommand  (handles one or many boundary half-edges as one undo step)
// ---------------------------------------------------------------------------

class ExtrudeEdgesCommand : public Command {
public:
    explicit ExtrudeEdgesCommand(std::vector<int32_t> half_edges);
    void do_it(HalfEdgeMesh &mesh)   override;
    void redo_it(HalfEdgeMesh &mesh) override;
    void undo_it(HalfEdgeMesh &mesh) override;

    const std::vector<int32_t> &new_edge_indices() const { return _new_edge_indices; }

private:
    std::vector<int32_t> _half_edges;
    int32_t _vertex_count_before    = 0;
    int32_t _half_edge_count_before = 0;
    int32_t _face_count_before      = 0;
    std::vector<int32_t> _new_edge_indices;
};

// ---------------------------------------------------------------------------
// ExtrudeFacesCommand  (handles one or many faces as one undo step)
// ---------------------------------------------------------------------------

class ExtrudeFacesCommand : public Command {
public:
    explicit ExtrudeFacesCommand(std::vector<int32_t> face_indices);
    void do_it(HalfEdgeMesh &mesh)   override;
    void redo_it(HalfEdgeMesh &mesh) override;
    void undo_it(HalfEdgeMesh &mesh) override;

    const std::vector<int32_t> &result_face_indices() const { return _face_indices; }

private:
    std::vector<int32_t> _face_indices;
    int32_t _vertex_count_before    = 0;
    int32_t _half_edge_count_before = 0;
    int32_t _face_count_before      = 0;

    // Per-face ring data needed for undo
    struct FaceUndo {
        std::vector<int32_t> half_edges;
        std::vector<int32_t> orig_vertices;
        std::vector<int32_t> orig_twins;
        std::vector<int32_t> orig_outer_twins; // outer mesh he whose twin we overwrote
        std::vector<int32_t> orig_vertex_he;   // vertex.half_edge before extrude
    };
    std::vector<FaceUndo> _face_undos;
};

// ---------------------------------------------------------------------------
// MoveVerticesCommand
// ---------------------------------------------------------------------------

class MoveVerticesCommand : public Command {
public:
    MoveVerticesCommand(std::vector<int32_t>        indices,
                        std::vector<godot::Vector3> old_positions,
                        std::vector<godot::Vector3> new_positions);
    void do_it(HalfEdgeMesh &mesh)   override { redo_it(mesh); }
    void redo_it(HalfEdgeMesh &mesh) override;
    void undo_it(HalfEdgeMesh &mesh) override;

private:
    std::vector<int32_t>        _indices;
    std::vector<godot::Vector3> _old_positions;
    std::vector<godot::Vector3> _new_positions;
};

} // namespace gomo
