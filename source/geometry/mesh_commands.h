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
// ExtrudeEdgeCommand
// do_it()   captures pre-op mesh sizes and runs the extrude.
// redo_it() re-runs the extrude (mesh is back to pre-op state after undo_it).
// undo_it() pops the appended elements and clears the boundary twin.
// ---------------------------------------------------------------------------

class ExtrudeEdgeCommand : public Command {
public:
    explicit ExtrudeEdgeCommand(int32_t half_edge_index);
    void do_it(HalfEdgeMesh &mesh)   override;
    void redo_it(HalfEdgeMesh &mesh) override;
    void undo_it(HalfEdgeMesh &mesh) override;

    const std::vector<int32_t> &new_vertex_indices() const { return _new_vertex_indices; }

private:
    int32_t _half_edge_index;
    int32_t _vertex_count_before    = 0;
    int32_t _half_edge_count_before = 0;
    int32_t _face_count_before      = 0;
    std::vector<int32_t> _new_vertex_indices;
};

// ---------------------------------------------------------------------------
// ExtrudeFaceCommand
// do_it()   captures face ring state and runs the extrude.
// redo_it() re-runs the extrude (mesh is back to pre-op state after undo_it).
// undo_it() restores face ring connectivity then pops appended elements.
// ---------------------------------------------------------------------------

class ExtrudeFaceCommand : public Command {
public:
    explicit ExtrudeFaceCommand(int32_t face_index);
    void do_it(HalfEdgeMesh &mesh)   override;
    void redo_it(HalfEdgeMesh &mesh) override;
    void undo_it(HalfEdgeMesh &mesh) override;

    const std::vector<int32_t> &new_vertex_indices() const { return _new_vertex_indices; }

private:
    int32_t _face_index;
    int32_t _vertex_count_before    = 0;
    int32_t _half_edge_count_before = 0;
    int32_t _face_count_before      = 0;

    std::vector<int32_t> _face_half_edges;
    std::vector<int32_t> _face_vertices;
    std::vector<int32_t> _original_twins;
    std::vector<int32_t> _original_vertex_he;

    std::vector<int32_t> _new_vertex_indices;
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

// ---------------------------------------------------------------------------
// TiltStrokeCommand
// Used by sculpt and flatten tools. Call capture_before() at stroke start and
// capture_after() at stroke end. redo_it() restores the exact after-snapshot.
// ---------------------------------------------------------------------------

class TiltStrokeCommand : public Command {
public:
    void capture_before(const HalfEdgeMesh &mesh);
    void capture_after(const HalfEdgeMesh &mesh);
    void restore_before(HalfEdgeMesh &mesh);
    void do_it(HalfEdgeMesh &mesh)   override { redo_it(mesh); }
    void redo_it(HalfEdgeMesh &mesh) override;
    void undo_it(HalfEdgeMesh &mesh) override;

private:
    struct FaceTilt { int32_t face_index; std::vector<float> tilt; };

    std::vector<FaceTilt> _before;
    std::vector<FaceTilt> _after;

    static void _capture(const HalfEdgeMesh &mesh, std::vector<FaceTilt> &out);
    static void _apply(HalfEdgeMesh &mesh, const std::vector<FaceTilt> &tilts);
};

} // namespace gomo
