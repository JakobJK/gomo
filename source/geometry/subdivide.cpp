#define _USE_MATH_DEFINES
#include "subdivide.h"

#include <opensubdiv/far/topologyDescriptor.h>
#include <opensubdiv/far/topologyRefinerFactory.h>
#include <opensubdiv/far/primvarRefiner.h>

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <vector>
#include <algorithm>

using namespace godot;
namespace Far = OpenSubdiv::Far;
namespace Sdc = OpenSubdiv::Sdc;

namespace gomo {

namespace {

struct Pos {
    float x = 0, y = 0, z = 0;
    void Clear(void * = nullptr)                        { x = y = z = 0.0f; }
    void AddWithWeight(Pos const &src, float weight)    { x += weight*src.x; y += weight*src.y; z += weight*src.z; }
};

} // anonymous namespace

Ref<ArrayMesh> subdivide_to_mesh(const HalfEdgeMesh &mesh, int levels) {
    levels = std::max(1, std::min(levels, 5));

    // --- Collect face-vertex topology from the HalfEdgeMesh ---
    std::vector<int> verts_per_face;
    std::vector<int> face_vert_indices;

    for (int32_t fi = 0; fi < mesh.face_count(); ++fi) {
        if (mesh.faces[fi].half_edge == -1) continue;
        int count = 0;
        int32_t he = mesh.faces[fi].half_edge;
        do {
            face_vert_indices.push_back((int)mesh.half_edges[he].vertex);
            ++count;
            he = mesh.half_edges[he].next;
        } while (he != mesh.faces[fi].half_edge);
        verts_per_face.push_back(count);
    }

    if (verts_per_face.empty()) return Ref<ArrayMesh>();

    // --- Build TopologyDescriptor and refiner ---
    Far::TopologyDescriptor desc;
    desc.numVertices        = mesh.vertex_count();
    desc.numFaces           = (int)verts_per_face.size();
    desc.numVertsPerFace    = verts_per_face.data();
    desc.vertIndicesPerFace = face_vert_indices.data();

    Sdc::Options sdc_opts;
    sdc_opts.SetVtxBoundaryInterpolation(Sdc::Options::VTX_BOUNDARY_EDGE_ONLY);

    using Factory = Far::TopologyRefinerFactory<Far::TopologyDescriptor>;
    Factory::Options factory_opts(Sdc::SCHEME_CATMARK, sdc_opts);

    Far::TopologyRefiner *refiner = Factory::Create(desc, factory_opts);
    if (!refiner) return Ref<ArrayMesh>();

    refiner->RefineUniform(Far::TopologyRefiner::UniformOptions(levels));

    // --- Refine vertex positions through each level ---
    std::vector<Pos> pos_buf(refiner->GetNumVerticesTotal());

    for (int i = 0; i < mesh.vertex_count(); ++i) {
        const auto &p  = mesh.vertices[i].position;
        pos_buf[i]     = {p.x, p.y, p.z};
    }

    Far::PrimvarRefiner prim_refiner(*refiner);
    Pos *src = pos_buf.data();
    for (int lvl = 1; lvl <= levels; ++lvl) {
        Pos *dst = src + refiner->GetLevel(lvl - 1).GetNumVertices();
        prim_refiner.Interpolate(lvl, src, dst);
        src = dst;
    }

    // --- Extract the finest level ---
    const Far::TopologyLevel &top = refiner->GetLevel(levels);
    int n_verts  = top.GetNumVertices();
    int n_faces  = top.GetNumFaces();
    int vert_off = (int)pos_buf.size() - n_verts;

    // Build Vector3 position array for the refined level
    std::vector<Vector3> positions(n_verts);
    for (int i = 0; i < n_verts; ++i) {
        const Pos &p  = pos_buf[vert_off + i];
        positions[i]  = {p.x, p.y, p.z};
    }

    // Compute smooth (area-weighted) per-vertex normals
    std::vector<Vector3> vnormals(n_verts, Vector3(0, 0, 0));
    for (int fi = 0; fi < n_faces; ++fi) {
        Far::ConstIndexArray fv = top.GetFaceVertices(fi);
        Vector3 p0 = positions[fv[0]];
        Vector3 p1 = positions[fv[1]];
        Vector3 p2 = positions[fv[2]];
        Vector3 n  = (p1 - p0).cross(p2 - p0); // area-weighted, no normalize
        for (int i = 0; i < fv.size(); ++i)
            vnormals[fv[i]] += n;
    }
    for (auto &n : vnormals) n = n.normalized();

    // Build indexed ArrayMesh (fan-triangulate each refined quad)
    PackedVector3Array v_arr, n_arr;
    PackedInt32Array   i_arr;
    v_arr.resize(n_verts);
    n_arr.resize(n_verts);
    for (int i = 0; i < n_verts; ++i) {
        v_arr[i] = positions[i];
        n_arr[i] = vnormals[i];
    }
    for (int fi = 0; fi < n_faces; ++fi) {
        Far::ConstIndexArray fv = top.GetFaceVertices(fi);
        for (int i = 1; i + 1 < fv.size(); ++i) {
            i_arr.push_back(fv[0]);
            i_arr.push_back(fv[i + 1]);
            i_arr.push_back(fv[i]);
        }
    }

    delete refiner;

    if (v_arr.is_empty()) return Ref<ArrayMesh>();

    Array arrays;
    arrays.resize(ArrayMesh::ARRAY_MAX);
    arrays[ArrayMesh::ARRAY_VERTEX] = v_arr;
    arrays[ArrayMesh::ARRAY_NORMAL] = n_arr;
    arrays[ArrayMesh::ARRAY_INDEX]  = i_arr;

    Ref<ArrayMesh> out;
    out.instantiate();
    out->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
    return out;
}


} // namespace gomo
