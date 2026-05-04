#pragma once

#include "half_edge_mesh.h"

namespace gomo {

// Run LSCM UV unwrapping. Islands are separated by seam edges and boundaries.
// Results are stored in HalfEdge::uv for every half-edge in the mesh.
void unwrap_uvs(HalfEdgeMesh &mesh);

// Toggle the seam flag on a half-edge and its twin.
void toggle_seam(HalfEdgeMesh &mesh, int32_t half_edge_index);

} // namespace gomo
