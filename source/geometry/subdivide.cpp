#define _USE_MATH_DEFINES
#include "subdivide.h"

#include <opensubdiv/far/topologyDescriptor.h>
#include <opensubdiv/far/topologyRefinerFactory.h>
#include <opensubdiv/far/primvarRefiner.h>

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <vector>
#include <algorithm>
#include <unordered_map>

using namespace godot;
namespace Far = OpenSubdiv::Far;
namespace Sdc = OpenSubdiv::Sdc;

namespace gomo {

namespace {

struct Pos {
    float x = 0, y = 0, z = 0;
    void Clear(void * = nullptr)                     { x = y = z = 0.0f; }
    void AddWithWeight(Pos const &src, float weight) { x += weight*src.x; y += weight*src.y; z += weight*src.z; }
};

struct UV {
    float u = 0, v = 0;
    void Clear(void * = nullptr)                    { u = v = 0.0f; }
    void AddWithWeight(UV const &src, float weight) { u += weight*src.u; v += weight*src.v; }
};

} // anonymous namespace

Ref<ArrayMesh> subdivide_to_mesh(const HalfEdgeMesh &mesh, int levels, bool bilinear_uvs) {
    levels = std::max(1, std::min(levels, 5));

    // --- Collect face-vertex topology and face-varying UVs in one pass ---
    std::vector<int> verts_per_face;
    std::vector<int> face_vert_indices;
    std::vector<UV>  fv_values;   // flat array of unique UV values
    std::vector<int> fv_indices;  // per face-corner: index into fv_values
    std::unordered_map<int32_t, int> he_to_fv; // half-edge index -> fv value index

    for (int32_t fi = 0; fi < mesh.face_count(); ++fi) {
        if (mesh.faces[fi].half_edge == -1) continue;
        int count = 0;
        int32_t he = mesh.faces[fi].half_edge;
        do {
            face_vert_indices.push_back((int)mesh.half_edges[he].vertex);

            // Share UV index with the same vertex in an adjacent face.
            // he.vertex = V (source). Partner at V via outgoing edge = twin.next.
            // Partner at V via incoming edge = prev.twin.
            int fv_idx = -1;

            int32_t twin = mesh.half_edges[he].twin;
            if (!mesh.half_edges[he].seam && twin >= 0) {
                int32_t partner = mesh.half_edges[twin].next;
                auto it = he_to_fv.find(partner);
                if (it != he_to_fv.end()) fv_idx = it->second;
            }

            if (fv_idx < 0) {
                int32_t prev_he   = mesh.half_edges[he].prev;
                int32_t prev_twin = mesh.half_edges[prev_he].twin;
                if (!mesh.half_edges[prev_he].seam && prev_twin >= 0) {
                    auto it = he_to_fv.find(prev_twin);
                    if (it != he_to_fv.end()) fv_idx = it->second;
                }
            }

            if (fv_idx < 0) {
                fv_idx = (int)fv_values.size();
                fv_values.push_back({mesh.half_edges[he].uv.x, mesh.half_edges[he].uv.y});
            }

            he_to_fv[he] = fv_idx;
            fv_indices.push_back(fv_idx);

            ++count;
            he = mesh.half_edges[he].next;
        } while (he != mesh.faces[fi].half_edge);
        verts_per_face.push_back(count);
    }

    if (verts_per_face.empty()) return Ref<ArrayMesh>();

    // --- Build TopologyDescriptor with UV face-varying channel ---
    Far::TopologyDescriptor::FVarChannel fv_channel;
    fv_channel.numValues    = (int)fv_values.size();
    fv_channel.valueIndices = fv_indices.data();

    Far::TopologyDescriptor desc;
    desc.numVertices        = mesh.vertex_count();
    desc.numFaces           = (int)verts_per_face.size();
    desc.numVertsPerFace    = verts_per_face.data();
    desc.vertIndicesPerFace = face_vert_indices.data();
    desc.numFVarChannels    = 1;
    desc.fvarChannels       = &fv_channel;

    Sdc::Options sdc_opts;
    sdc_opts.SetVtxBoundaryInterpolation(Sdc::Options::VTX_BOUNDARY_EDGE_ONLY);
    sdc_opts.SetFVarLinearInterpolation(bilinear_uvs ? Sdc::Options::FVAR_LINEAR_ALL
                                                     : Sdc::Options::FVAR_LINEAR_BOUNDARIES);

    using Factory = Far::TopologyRefinerFactory<Far::TopologyDescriptor>;
    Factory::Options factory_opts(Sdc::SCHEME_CATMARK, sdc_opts);

    Far::TopologyRefiner *refiner = Factory::Create(desc, factory_opts);
    if (!refiner) return Ref<ArrayMesh>();

    refiner->RefineUniform(Far::TopologyRefiner::UniformOptions(levels));

    // --- Refine vertex positions ---
    std::vector<Pos> pos_buf(refiner->GetNumVerticesTotal());
    for (int i = 0; i < mesh.vertex_count(); ++i) {
        const auto &p = mesh.vertices[i].position;
        pos_buf[i]    = {p.x, p.y, p.z};
    }

    // --- Refine UVs as face-varying data ---
    std::vector<UV> uv_buf(refiner->GetNumFVarValuesTotal(0));
    for (int i = 0; i < (int)fv_values.size(); ++i)
        uv_buf[i] = fv_values[i];

    Far::PrimvarRefiner prim_refiner(*refiner);
    Pos *pos_src = pos_buf.data();
    UV  *uv_src  = uv_buf.data();
    for (int lvl = 1; lvl <= levels; ++lvl) {
        Pos *pos_dst = pos_src + refiner->GetLevel(lvl - 1).GetNumVertices();
        UV  *uv_dst  = uv_src  + refiner->GetLevel(lvl - 1).GetNumFVarValues(0);
        prim_refiner.Interpolate(lvl, pos_src, pos_dst);
        prim_refiner.InterpolateFaceVarying(lvl, uv_src, uv_dst, 0);
        pos_src = pos_dst;
        uv_src  = uv_dst;
    }

    // --- Extract finest level ---
    const Far::TopologyLevel &top = refiner->GetLevel(levels);
    int n_verts = top.GetNumVertices();
    int n_faces = top.GetNumFaces();
    int pos_off = (int)pos_buf.size() - n_verts;
    int uv_off  = (int)uv_buf.size()  - top.GetNumFVarValues(0);

    std::vector<Vector3> positions(n_verts);
    for (int i = 0; i < n_verts; ++i) {
        const Pos &p = pos_buf[pos_off + i];
        positions[i] = {p.x, p.y, p.z};
    }

    // Compute smooth (area-weighted) per-vertex normals
    std::vector<Vector3> vnormals(n_verts, Vector3(0, 0, 0));
    for (int fi = 0; fi < n_faces; ++fi) {
        Far::ConstIndexArray fv = top.GetFaceVertices(fi);
        Vector3 p0 = positions[fv[0]];
        Vector3 p1 = positions[fv[1]];
        Vector3 p2 = positions[fv[2]];
        Vector3 n  = (p1 - p0).cross(p2 - p0);
        for (int i = 0; i < fv.size(); ++i)
            vnormals[fv[i]] += n;
    }
    for (auto &n : vnormals) n = n.normalized();

    // --- Build indexed output, splitting vertices at UV seams ---
    struct VertKey {
        int vert, fv;
        bool operator==(const VertKey &o) const { return vert == o.vert && fv == o.fv; }
    };
    struct VertKeyHash {
        size_t operator()(const VertKey &k) const {
            return std::hash<int>()(k.vert) ^ (std::hash<int>()(k.fv) << 16);
        }
    };

    std::unordered_map<VertKey, int, VertKeyHash> split_map;
    PackedVector3Array v_arr, n_arr;
    PackedVector2Array uv_arr;
    PackedInt32Array   i_arr;

    for (int fi = 0; fi < n_faces; ++fi) {
        Far::ConstIndexArray fv  = top.GetFaceVertices(fi);
        Far::ConstIndexArray fuv = top.GetFaceFVarValues(fi, 0);

        for (int i = 1; i + 1 < fv.size(); ++i) {
            int corners[3] = {0, i + 1, i};
            for (int c : corners) {
                VertKey key{fv[c], fuv[c]};
                auto it = split_map.find(key);
                int out_idx;
                if (it == split_map.end()) {
                    out_idx        = v_arr.size();
                    split_map[key] = out_idx;
                    v_arr.push_back(positions[fv[c]]);
                    n_arr.push_back(vnormals[fv[c]]);
                    const UV &u = uv_buf[uv_off + fuv[c]];
                    uv_arr.push_back(Vector2(u.u, u.v));
                } else {
                    out_idx = it->second;
                }
                i_arr.push_back(out_idx);
            }
        }
    }

    delete refiner;

    if (v_arr.is_empty()) return Ref<ArrayMesh>();

    Array arrays;
    arrays.resize(ArrayMesh::ARRAY_MAX);
    arrays[ArrayMesh::ARRAY_VERTEX] = v_arr;
    arrays[ArrayMesh::ARRAY_NORMAL] = n_arr;
    arrays[ArrayMesh::ARRAY_TEX_UV] = uv_arr;
    arrays[ArrayMesh::ARRAY_INDEX]  = i_arr;

    Ref<ArrayMesh> out;
    out.instantiate();
    out->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
    return out;
}

} // namespace gomo
