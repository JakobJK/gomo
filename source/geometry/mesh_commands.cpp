#include "mesh_commands.h"
#include "mesh_ops.h"

#include <unordered_set>

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
// ExtrudeEdgesCommand
// ---------------------------------------------------------------------------

ExtrudeEdgesCommand::ExtrudeEdgesCommand(std::vector<int32_t> half_edges)
    : _half_edges(std::move(half_edges))
{}

void ExtrudeEdgesCommand::do_it(HalfEdgeMesh &mesh) {
    _vertex_count_before    = mesh.vertex_count();
    _half_edge_count_before = mesh.half_edge_count();
    _face_count_before      = mesh.face_count();
    _new_edge_indices = extrude_edges(mesh, _half_edges);
}

void ExtrudeEdgesCommand::redo_it(HalfEdgeMesh &mesh) {
    extrude_edges(mesh, _half_edges);
}

void ExtrudeEdgesCommand::undo_it(HalfEdgeMesh &mesh) {
    for (int32_t he : _half_edges)
        mesh.half_edges[he].twin = -1;
    mesh.vertices.resize(_vertex_count_before);
    mesh.half_edges.resize(_half_edge_count_before);
    mesh.faces.resize(_face_count_before);
}

// ---------------------------------------------------------------------------
// ExtrudeFacesCommand
// ---------------------------------------------------------------------------

ExtrudeFacesCommand::ExtrudeFacesCommand(std::vector<int32_t> face_indices)
    : _face_indices(std::move(face_indices))
{}

void ExtrudeFacesCommand::do_it(HalfEdgeMesh &mesh) {
    _vertex_count_before    = mesh.vertex_count();
    _half_edge_count_before = mesh.half_edge_count();
    _face_count_before      = mesh.face_count();

    std::unordered_set<int32_t> selected(_face_indices.begin(), _face_indices.end());

    _face_undos.resize(_face_indices.size());
    for (int fi = 0; fi < (int)_face_indices.size(); ++fi) {
        auto &u    = _face_undos[fi];
        int32_t he = mesh.faces[_face_indices[fi]].half_edge;
        do {
            int32_t v    = mesh.half_edges[he].vertex;
            int32_t twin = mesh.half_edges[he].twin;
            u.half_edges.push_back(he);
            u.orig_vertices.push_back(v);
            u.orig_twins.push_back(twin);
            u.orig_vertex_he.push_back(mesh.vertices[v].half_edge);
            u.orig_outer_twins.push_back(
                (twin != -1 && !selected.count(mesh.half_edges[twin].face)) ? twin : -1
            );
            he = mesh.half_edges[he].next;
        } while (he != mesh.faces[_face_indices[fi]].half_edge);
    }

    extrude_faces(mesh, _face_indices);
}

void ExtrudeFacesCommand::redo_it(HalfEdgeMesh &mesh) {
    extrude_faces(mesh, _face_indices);
}

void ExtrudeFacesCommand::undo_it(HalfEdgeMesh &mesh) {
    for (auto &u : _face_undos) {
        for (int i = 0; i < (int)u.half_edges.size(); ++i) {
            int32_t he     = u.half_edges[i];
            int32_t orig_v = u.orig_vertices[i];
            mesh.half_edges[he].vertex      = orig_v;
            mesh.half_edges[he].twin        = u.orig_twins[i];
            mesh.vertices[orig_v].half_edge = u.orig_vertex_he[i];
            if (u.orig_outer_twins[i] != -1)
                mesh.half_edges[u.orig_outer_twins[i]].twin = he;
        }
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

} // namespace gomo
