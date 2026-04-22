#include "half_edge_mesh.h"

namespace gomo {

void HalfEdgeMesh::clear() {
    vertices.clear();
    half_edges.clear();
    faces.clear();
}

void HalfEdgeMesh::delete_face(int32_t face_idx) {
    if (face_idx < 0 || face_idx >= (int32_t)faces.size()) return;
    if (faces[face_idx].half_edge == -1) return;

    std::vector<int32_t> face_hes;
    int32_t he = faces[face_idx].half_edge;
    do {
        face_hes.push_back(he);
        he = half_edges[he].next;
    } while (he != faces[face_idx].half_edge);

    for (int32_t h : face_hes) {
        int32_t twin = half_edges[h].twin;
        if (twin != -1) {
            half_edges[twin].twin = -1;
            half_edges[h].twin    = -1;
        }

        int32_t vi = half_edges[h].vertex;
        if (vertices[vi].half_edge == h) {
            int32_t prev_twin = half_edges[half_edges[h].prev].twin;
            if (prev_twin != -1 && half_edges[prev_twin].face != face_idx)
                vertices[vi].half_edge = prev_twin;
            else
                vertices[vi].half_edge = -1;
        }

        half_edges[h].face = -1;
    }

    faces[face_idx].half_edge = -1;
}

} // namespace gomo
