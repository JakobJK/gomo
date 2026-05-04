#pragma once

#include "half_edge_mesh.h"
#include <godot_cpp/classes/array_mesh.hpp>

namespace gomo {

godot::Ref<godot::ArrayMesh> subdivide_to_mesh(const HalfEdgeMesh &mesh, int levels);

}