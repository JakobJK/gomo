#include "mesh_commands.h"
#include "mesh_ops.h"

namespace gomo {

// ---------------------------------------------------------------------------
// DeleteFaceCommand
// ---------------------------------------------------------------------------

DeleteFaceCommand::DeleteFaceCommand(const HalfEdgeMesh &mesh, int32_t face_index)
    : _face_index(face_index)
    , _face_half_edge(mesh.faces[face_index].half_edge)
{
    int32_t he = _face_half_edge;
    do {
        const HalfEdge &h = mesh.half_edges[he];
        _he_saves.push_back({he, h.twin, h.face});
        int32_t vi = h.vertex;
        if (mesh.vertices[vi].half_edge == he)
            _vertex_saves.push_back({vi, he});
        he = h.next;
    } while (he != _face_half_edge);
}

void DeleteFaceCommand::redo_it(HalfEdgeMesh &mesh) {
    mesh.delete_face(_face_index);
}

void DeleteFaceCommand::undo_it(HalfEdgeMesh &mesh) {
    mesh.faces[_face_index].half_edge = _face_half_edge;

    for (const auto &s : _he_saves) {
        mesh.half_edges[s.index].twin = s.twin;
        mesh.half_edges[s.index].face = s.face;
        if (s.twin != -1)
            mesh.half_edges[s.twin].twin = s.index;
    }

    for (const auto &s : _vertex_saves)
        mesh.vertices[s.vertex_index].half_edge = s.half_edge;
}

// ---------------------------------------------------------------------------
// ExtrudeEdgeCommand
// ---------------------------------------------------------------------------

ExtrudeEdgeCommand::ExtrudeEdgeCommand(int32_t half_edge_index)
    : _half_edge_index(half_edge_index)
{}

void ExtrudeEdgeCommand::do_it(HalfEdgeMesh &mesh) {
    _vertex_count_before    = mesh.vertex_count();
    _half_edge_count_before = mesh.half_edge_count();
    _face_count_before      = mesh.face_count();
    _new_vertex_indices     = extrude_edge(mesh, _half_edge_index);
}

void ExtrudeEdgeCommand::redo_it(HalfEdgeMesh &mesh) {
    extrude_edge(mesh, _half_edge_index);
}

void ExtrudeEdgeCommand::undo_it(HalfEdgeMesh &mesh) {
    mesh.half_edges[_half_edge_index].twin = -1;
    mesh.vertices.resize(_vertex_count_before);
    mesh.half_edges.resize(_half_edge_count_before);
    mesh.faces.resize(_face_count_before);
}

// ---------------------------------------------------------------------------
// ExtrudeFaceCommand
// ---------------------------------------------------------------------------

ExtrudeFaceCommand::ExtrudeFaceCommand(int32_t face_index)
    : _face_index(face_index)
{}

void ExtrudeFaceCommand::do_it(HalfEdgeMesh &mesh) {
    _vertex_count_before    = mesh.vertex_count();
    _half_edge_count_before = mesh.half_edge_count();
    _face_count_before      = mesh.face_count();

    int32_t he = mesh.faces[_face_index].half_edge;
    do {
        _face_half_edges.push_back(he);
        int32_t vi = mesh.half_edges[he].vertex;
        _face_vertices.push_back(vi);
        _original_twins.push_back(mesh.half_edges[he].twin);
        _original_vertex_he.push_back(mesh.vertices[vi].half_edge);
        he = mesh.half_edges[he].next;
    } while (he != mesh.faces[_face_index].half_edge);

    _new_vertex_indices = extrude_face(mesh, _face_index);
}

void ExtrudeFaceCommand::redo_it(HalfEdgeMesh &mesh) {
    extrude_face(mesh, _face_index);
}

void ExtrudeFaceCommand::undo_it(HalfEdgeMesh &mesh) {
    int32_t N = (int32_t)_face_half_edges.size();
    for (int32_t i = 0; i < N; ++i) {
        mesh.half_edges[_face_half_edges[i]].vertex = _face_vertices[i];
        mesh.half_edges[_face_half_edges[i]].twin   = _original_twins[i];
        if (_original_twins[i] != -1)
            mesh.half_edges[_original_twins[i]].twin = _face_half_edges[i];
        mesh.vertices[_face_vertices[i]].half_edge = _original_vertex_he[i];
    }

    mesh.vertices.resize(_vertex_count_before);
    mesh.half_edges.resize(_half_edge_count_before);
    mesh.faces.resize(_face_count_before);
}

// ---------------------------------------------------------------------------
// MoveVerticesCommand
// ---------------------------------------------------------------------------

MoveVerticesCommand::MoveVerticesCommand(std::vector<int32_t>        indices,
                                         std::vector<godot::Vector3> old_positions,
                                         std::vector<godot::Vector3> new_positions)
    : _indices(std::move(indices))
    , _old_positions(std::move(old_positions))
    , _new_positions(std::move(new_positions))
{}

void MoveVerticesCommand::redo_it(HalfEdgeMesh &mesh) {
    for (int32_t i = 0; i < (int32_t)_indices.size(); ++i)
        mesh.vertices[_indices[i]].position = _new_positions[i];
}

void MoveVerticesCommand::undo_it(HalfEdgeMesh &mesh) {
    for (int32_t i = 0; i < (int32_t)_indices.size(); ++i)
        mesh.vertices[_indices[i]].position = _old_positions[i];
}

// ---------------------------------------------------------------------------
// TiltStrokeCommand
// ---------------------------------------------------------------------------

void TiltStrokeCommand::_capture(const HalfEdgeMesh &mesh, std::vector<FaceTilt> &out) {
    out.clear();
    for (int32_t fi = 0; fi < mesh.face_count(); ++fi) {
        if (mesh.faces[fi].half_edge == -1) continue;
        out.push_back({fi, std::vector<float>(mesh.faces[fi].tilt.begin(),
                                               mesh.faces[fi].tilt.end())});
    }
}

void TiltStrokeCommand::_apply(HalfEdgeMesh &mesh, const std::vector<FaceTilt> &tilts) {
    for (const auto &ft : tilts)
        std::copy(ft.tilt.begin(), ft.tilt.end(), mesh.faces[ft.face_index].tilt.begin());
}

void TiltStrokeCommand::capture_before(const HalfEdgeMesh &mesh) { _capture(mesh, _before); }
void TiltStrokeCommand::capture_after(const HalfEdgeMesh &mesh)  { _capture(mesh, _after);  }
void TiltStrokeCommand::restore_before(HalfEdgeMesh &mesh)       { _apply(mesh, _before);   }

void TiltStrokeCommand::redo_it(HalfEdgeMesh &mesh) { _apply(mesh, _after);  }
void TiltStrokeCommand::undo_it(HalfEdgeMesh &mesh) { _apply(mesh, _before); }

} // namespace gomo
