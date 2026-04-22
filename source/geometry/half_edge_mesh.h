#pragma once

#include "types.h"
#include <vector>

namespace gomo {

class HalfEdgeMesh {
public:
    std::vector<Vertex>   vertices;
    std::vector<HalfEdge> half_edges;
    std::vector<Face>     faces;

    void clear();
    void delete_face(int32_t face_idx);

    int32_t vertex_count()    const { return static_cast<int32_t>(vertices.size()); }
    int32_t half_edge_count() const { return static_cast<int32_t>(half_edges.size()); }
    int32_t face_count()      const { return static_cast<int32_t>(faces.size()); }
};

} // namespace gomo
