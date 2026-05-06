#pragma once

#include "half_edge_mesh.h"
#include <godot_cpp/classes/image.hpp>

namespace gomo {

godot::Ref<godot::Image> bake_normal_map(const HalfEdgeMesh &mesh, int subdiv_levels, int resolution);

}
