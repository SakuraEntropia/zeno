#include "Cloth.cuh"
#include "zensim/geometry/Distance.hpp"

namespace zeno {

ClothSystem::PrimitiveHandle::PrimitiveHandle(std::shared_ptr<tiles_t> elesPtr_, ZenoParticles::category_e category)
    : zsprimPtr{}, modelsPtr{}, vertsPtr{}, elesPtr{elesPtr_},
      etemp{elesPtr_->get_allocator(), {{"He", 6 * 6}}, elesPtr_->size()}, surfTrisPtr{}, surfEdgesPtr{},
      surfVertsPtr{}, svtemp{}, vOffset{0}, sfOffset{0}, seOffset{0}, svOffset{0}, category{category} {
    ;
}
ClothSystem::PrimitiveHandle::PrimitiveHandle(ZenoParticles &zsprim, Ti &vOffset, Ti &sfOffset, Ti &seOffset,
                                              Ti &svOffset, zs::wrapv<2>)
    : zsprimPtr{&zsprim, [](void *) {}}, modelsPtr{&zsprim.getModel(), [](void *) {}}, vertsPtr{&zsprim.getParticles(),
                                                                                                [](void *) {}},
      elesPtr{&zsprim.getQuadraturePoints(), [](void *) {}}, etemp{zsprim.getQuadraturePoints().get_allocator(),
                                                                   {{"He", 6 * 6}},
                                                                   zsprim.numElements()},
      surfTrisPtr{&zsprim.getQuadraturePoints(), [](void *) {}},  // this is fake!
      surfEdgesPtr{&zsprim.getQuadraturePoints(), [](void *) {}}, // all elements are surface edges
      surfVertsPtr{&zsprim[ZenoParticles::s_surfVertTag], [](void *) {}}, vOffset{vOffset},
      svtemp{zsprim.getQuadraturePoints().get_allocator(),
             {{"H", 3 * 3}, {"fn", 1}},
             zsprim[ZenoParticles::s_surfVertTag].size()},
      sfOffset{sfOffset}, seOffset{seOffset}, svOffset{svOffset}, category{zsprim.category} {
    if (category != ZenoParticles::curve)
        throw std::runtime_error("dimension of 2 but is not curve");
    vOffset += getVerts().size();
    // sfOffset += 0; // no surface triangles
    seOffset += getSurfEdges().size();
    svOffset += getSurfVerts().size();
}
ClothSystem::PrimitiveHandle::PrimitiveHandle(ZenoParticles &zsprim, Ti &vOffset, Ti &sfOffset, Ti &seOffset,
                                              Ti &svOffset, zs::wrapv<3>)
    : zsprimPtr{&zsprim, [](void *) {}}, modelsPtr{&zsprim.getModel(), [](void *) {}}, vertsPtr{&zsprim.getParticles(),
                                                                                                [](void *) {}},
      elesPtr{&zsprim.getQuadraturePoints(), [](void *) {}}, etemp{zsprim.getQuadraturePoints().get_allocator(),
                                                                   {{"He", 9 * 9}},
                                                                   zsprim.numElements()},
      surfTrisPtr{&zsprim.getQuadraturePoints(), [](void *) {}}, surfEdgesPtr{&zsprim[ZenoParticles::s_surfEdgeTag],
                                                                              [](void *) {}},
      surfVertsPtr{&zsprim[ZenoParticles::s_surfVertTag], [](void *) {}}, vOffset{vOffset},
      svtemp{zsprim.getQuadraturePoints().get_allocator(),
             {{"H", 3 * 3}, {"fn", 1}},
             zsprim[ZenoParticles::s_surfVertTag].size()},
      sfOffset{sfOffset}, seOffset{seOffset}, svOffset{svOffset}, category{zsprim.category} {
    if (category != ZenoParticles::surface)
        throw std::runtime_error("dimension of 3 but is not surface");
    vOffset += getVerts().size();
    sfOffset += getSurfTris().size();
    seOffset += getSurfEdges().size();
    svOffset += getSurfVerts().size();
}
ClothSystem::PrimitiveHandle::PrimitiveHandle(ZenoParticles &zsprim, Ti &vOffset, Ti &sfOffset, Ti &seOffset,
                                              Ti &svOffset, zs::wrapv<4>)
    : zsprimPtr{&zsprim, [](void *) {}}, modelsPtr{&zsprim.getModel(), [](void *) {}}, vertsPtr{&zsprim.getParticles(),
                                                                                                [](void *) {}},
      elesPtr{&zsprim.getQuadraturePoints(), [](void *) {}}, etemp{zsprim.getQuadraturePoints().get_allocator(),
                                                                   {{"He", 12 * 12}},
                                                                   zsprim.numElements()},
      surfTrisPtr{&zsprim[ZenoParticles::s_surfTriTag], [](void *) {}},
      surfEdgesPtr{&zsprim[ZenoParticles::s_surfEdgeTag], [](void *) {}},
      surfVertsPtr{&zsprim[ZenoParticles::s_surfVertTag], [](void *) {}}, vOffset{vOffset},
      svtemp{zsprim.getQuadraturePoints().get_allocator(),
             {{"H", 3 * 3}, {"fn", 1}},
             zsprim[ZenoParticles::s_surfVertTag].size()},
      sfOffset{sfOffset}, seOffset{seOffset}, svOffset{svOffset}, category{zsprim.category} {
    if (category != ZenoParticles::tet)
        throw std::runtime_error("dimension of 4 but is not tetrahedra");
    vOffset += getVerts().size();
    sfOffset += getSurfTris().size();
    seOffset += getSurfEdges().size();
    svOffset += getSurfVerts().size();
}
typename ClothSystem::T ClothSystem::PrimitiveHandle::averageNodalMass(zs::CudaExecutionPolicy &pol) const {
    using namespace zs;
    constexpr auto space = execspace_e::cuda;
    if (zsprimPtr->hasMeta(s_meanMassTag))
        return zsprimPtr->readMeta(s_meanMassTag, zs::wrapt<T>{});
    auto &verts = getVerts();
    Vector<T> masses{verts.get_allocator(), verts.size()};
    pol(Collapse{verts.size()}, [verts = proxy<space>({}, verts), masses = proxy<space>(masses)] ZS_LAMBDA(
                                    int vi) mutable { masses[vi] = verts("m", vi); });
    auto tmp = reduce(pol, masses) / masses.size();
    zsprimPtr->setMeta(s_meanMassTag, tmp);
    return tmp;
}

/// ClothSystem
typename ClothSystem::T ClothSystem::averageNodalMass(zs::CudaExecutionPolicy &pol) {
    using T = typename ClothSystem::T;
    T sumNodalMass = 0;
    int sumNodes = 0;
    for (auto &&primHandle : prims) {
        if (primHandle.isBoundary())
            continue;
        auto numNodes = primHandle.getVerts().size();
        sumNodes += numNodes;
        sumNodalMass += primHandle.averageNodalMass(pol) * numNodes;
    }
    if (sumNodes)
        return sumNodalMass / sumNodes;
    else
        return 0;
}
void ClothSystem::updateWholeBoundingBoxSize(zs::CudaExecutionPolicy &pol) {
    using namespace zs;
    bv_t bv = seBvh.getTotalBox(pol);
    if (coVerts)
        if (coVerts->size()) {
            auto bouBv = bouSeBvh.getTotalBox(pol);
            merge(bv, bouBv._min);
            merge(bv, bouBv._max);
        }
    boxDiagSize2 = (bv._max - bv._min).l2NormSqr();
}

void ClothSystem::markSelfIntersectionPrimitives(zs::CudaExecutionPolicy &pol) {
    //exclSes, exclSts, stInds, seInds, seBvh
    using namespace zs;
    constexpr auto space = execspace_e::cuda;
    exclSes.reset(0);
    exclSts.reset(0);
    exclBouSes.reset(0);
    exclBouSts.reset(0);

    Vector<int> cnt{vtemp.get_allocator(), 1};
    cnt.setVal(0);

    auto edgeBvs = retrieve_bounding_volumes(pol, vtemp, "xn", seInds, wrapv<2>{}, 0);
    seBvh.refit(pol, edgeBvs);
    pol(range(stInds.size()), [vtemp = proxy<space>({}, vtemp), stInds = proxy<space>({}, stInds),
                               seInds = proxy<space>({}, seInds), exclSes = proxy<space>(exclSes),
                               exclSts = proxy<space>(exclSts), bvh = proxy<space>(seBvh), cnt = proxy<space>(cnt),
                               dHat = dHat] __device__(int sti) mutable {
        auto tri = stInds.pack(dim_c<3>, "inds", sti).reinterpret_bits(int_c);
        auto t0 = vtemp.pack(dim_c<3>, "xn", tri[0]);
        auto t1 = vtemp.pack(dim_c<3>, "xn", tri[1]);
        auto t2 = vtemp.pack(dim_c<3>, "xn", tri[2]);
        auto bv = bv_t{get_bounding_box(t0, t1)};
        merge(bv, t2);
        bool triIntersected = false;
        bvh.iter_neighbors(bv, [&](int sei) {
            auto line = seInds.pack(dim_c<2>, "inds", sei).reinterpret_bits(int_c);
            if (tri[0] == line[0] || tri[0] == line[1] || tri[1] == line[0] || tri[1] == line[1] || tri[2] == line[0] ||
                tri[2] == line[1])
                return;
            if (et_intersected(vtemp.pack(dim_c<3>, "xn", line[0]), vtemp.pack(dim_c<3>, "xn", line[1]), t0, t1, t2)) {
                triIntersected = true;
                exclSes[sei] = 1;

                atomic_add(exec_cuda, &cnt[0], 1);
            }
        });
        if (triIntersected)
            exclSts[sti] = 1;
    });
    zeno::log_info("{} self et intersections\n", cnt.getVal());

    if (coEdges) {
        cnt.setVal(0);
        edgeBvs = retrieve_bounding_volumes(pol, vtemp, "xn", *coEdges, zs::wrapv<2>{}, coOffset);
        bouSeBvh.refit(pol, edgeBvs);
        pol(range(stInds.size()),
            [vtemp = proxy<space>({}, vtemp), stInds = proxy<space>({}, stInds), seInds = proxy<space>({}, *coEdges),
             exclBouSes = proxy<space>(exclBouSes), exclSts = proxy<space>(exclSts), bvh = proxy<space>(bouSeBvh),
             cnt = proxy<space>(cnt), dHat = dHat, voffset = coOffset] __device__(int sti) mutable {
                auto tri = stInds.pack(dim_c<3>, "inds", sti).reinterpret_bits(int_c);
                auto t0 = vtemp.pack(dim_c<3>, "xn", tri[0]);
                auto t1 = vtemp.pack(dim_c<3>, "xn", tri[1]);
                auto t2 = vtemp.pack(dim_c<3>, "xn", tri[2]);
                auto bv = bv_t{get_bounding_box(t0, t1)};
                merge(bv, t2);
                bool triIntersected = false;
                bvh.iter_neighbors(bv, [&](int sei) {
                    auto line = seInds.pack(dim_c<2>, "inds", sei).reinterpret_bits(int_c) + voffset;
                    // no need to check common vertices here
                    if (et_intersected(vtemp.pack(dim_c<3>, "xn", line[0]), vtemp.pack(dim_c<3>, "xn", line[1]), t0, t1,
                                       t2)) {
                        triIntersected = true;
                        exclBouSes[sei] = 1;

                        atomic_add(exec_cuda, &cnt[0], 1);
                    }
                });
                if (triIntersected)
                    exclSts[sti] = 1;
            });

        auto triBvs = retrieve_bounding_volumes(pol, vtemp, "xn", *coEles, zs::wrapv<3>{}, coOffset);
        bouStBvh.refit(pol, triBvs);
        pol(range(seInds.size()),
            [vtemp = proxy<space>({}, vtemp), seInds = proxy<space>({}, seInds), coTris = proxy<space>({}, *coEles),
             exclBouSts = proxy<space>(exclBouSts), exclSes = proxy<space>(exclSes), bvh = proxy<space>(bouStBvh),
             cnt = proxy<space>(cnt), dHat = dHat, voffset = coOffset] __device__(int sei) mutable {
                auto line = seInds.pack(dim_c<2>, "inds", sei).reinterpret_bits(int_c);
                auto e0 = vtemp.pack(dim_c<3>, "xn", line[0]);
                auto e1 = vtemp.pack(dim_c<3>, "xn", line[1]);
                auto bv = bv_t{get_bounding_box(e0, e1)};
                bool edgeIntersected = false;
                bvh.iter_neighbors(bv, [&](int sti) {
                    auto tri = coTris.pack(dim_c<3>, "inds", sti).reinterpret_bits(int_c) + voffset;
                    // no need to check common vertices here
                    if (et_intersected(e0, e1, vtemp.pack(dim_c<3>, "xn", tri[0]), vtemp.pack(dim_c<3>, "xn", tri[1]),
                                       vtemp.pack(dim_c<3>, "xn", tri[2]))) {
                        edgeIntersected = true;
                        exclBouSts[sti] = 1;

                        atomic_add(exec_cuda, &cnt[0], 1);
                    }
                });
                if (edgeIntersected)
                    exclSes[sei] = 1;
            });
        zeno::log_info("{} boundary et intersections\n", cnt.getVal());
    }
    return;
}

void ClothSystem::initialize(zs::CudaExecutionPolicy &pol) {
    using namespace zs;
    constexpr auto space = execspace_e::cuda;
    stInds = tiles_t{vtemp.get_allocator(), {{"inds", 3}}, (std::size_t)sfOffset};
    seInds = tiles_t{vtemp.get_allocator(), {{"inds", 2}}, (std::size_t)seOffset};
    svInds = tiles_t{vtemp.get_allocator(), {{"inds", 1}}, (std::size_t)svOffset};
    exclSes = Vector<u8>{vtemp.get_allocator(), (std::size_t)seOffset};
    exclSts = Vector<u8>{vtemp.get_allocator(), (std::size_t)sfOffset};
    std::size_t nBouSes = 0, nBouSts = 0;
    if (coEdges) {
        nBouSes = coEdges->size();
        nBouSts = coEles->size();
    }
    exclBouSes = Vector<u8>{vtemp.get_allocator(), nBouSes};
    exclBouSts = Vector<u8>{vtemp.get_allocator(), nBouSts};

    auto deduce_node_cnt = [](std::size_t numLeaves) {
        if (numLeaves <= 2)
            return numLeaves;
        return numLeaves * 2 - 1;
    };
    selfStFront = bvfront_t{(int)deduce_node_cnt(stInds.size()), (int)estNumCps, zs::memsrc_e::um, vtemp.devid()};
    selfSeFront = bvfront_t{(int)deduce_node_cnt(seInds.size()), (int)estNumCps, zs::memsrc_e::um, vtemp.devid()};
    if (coVerts) {
        boundaryStFront =
            bvfront_t{(int)deduce_node_cnt(coEles->size()), (int)estNumCps, zs::memsrc_e::um, vtemp.devid()};
        boundarySeFront =
            bvfront_t{(int)deduce_node_cnt(coEdges->size()), (int)estNumCps, zs::memsrc_e::um, vtemp.devid()};
    }

    avgNodeMass = averageNodalMass(pol);

    for (auto &primHandle : prims) {
        if (primHandle.isAuxiliary())
            continue;
        const auto &verts = primHandle.getVerts();
        // record surface (tri) indices
        if (primHandle.category != ZenoParticles::category_e::curve) {
            auto &tris = primHandle.getSurfTris();
            pol(Collapse(tris.size()), [stInds = proxy<space>({}, stInds), tris = proxy<space>({}, tris),
                                        voffset = primHandle.vOffset,
                                        sfoffset = primHandle.sfOffset] __device__(int i) mutable {
                stInds.tuple(dim_c<3>, "inds", sfoffset + i) =
                    (tris.pack(dim_c<3>, "inds", i).reinterpret_bits(int_c) + (int)voffset).reinterpret_bits(float_c);
            });
        }
        const auto &edges = primHandle.getSurfEdges();
        pol(Collapse(edges.size()),
            [seInds = proxy<space>({}, seInds), edges = proxy<space>({}, edges), voffset = primHandle.vOffset,
             seoffset = primHandle.seOffset] __device__(int i) mutable {
                seInds.tuple(dim_c<2>, "inds", seoffset + i) =
                    (edges.pack(dim_c<2>, "inds", i).reinterpret_bits(int_c) + (int)voffset).reinterpret_bits(float_c);
            });
        const auto &points = primHandle.getSurfVerts();
        pol(Collapse(points.size()),
            [svInds = proxy<space>({}, svInds), points = proxy<space>({}, points), voffset = primHandle.vOffset,
             svoffset = primHandle.svOffset] __device__(int i) mutable {
                svInds("inds", svoffset + i) =
                    reinterpret_bits<float>(reinterpret_bits<int>(points("inds", i)) + (int)voffset);
            });
    }
    // initialize vtemp & spatial accel
    reinitialize(pol, dt);
}

void ClothSystem::reinitialize(zs::CudaExecutionPolicy &pol, T framedt) {
    using namespace zs;
    constexpr auto space = execspace_e::cuda;

    dt = framedt;
    this->framedt = framedt;
    curRatio = 0;

    substep = -1;
    projectDBC = false;

    if (enableContact) {
        nPP.setVal(0);
        nPE.setVal(0);
        nPT.setVal(0);
        nEE.setVal(0);

        ncsPT.setVal(0);
        ncsEE.setVal(0);
    }

    for (auto &primHandle : prims) {
        if (primHandle.isAuxiliary())
            continue;
        auto &verts = primHandle.getVerts();
        // initialize BC info
        // predict pos, initialize augmented lagrangian, constrain weights
        pol(Collapse(verts.size()),
            [vtemp = proxy<space>({}, vtemp), verts = proxy<space>({}, verts), voffset = primHandle.vOffset, dt = dt,
             avgNodeMass = avgNodeMass, augLagCoeff = augLagCoeff] __device__(int i) mutable {
                auto x = verts.pack<3>("x", i);
                auto v = verts.pack<3>("v", i);

                vtemp("ws", voffset + i) = verts("m", i);
                vtemp.tuple<3>("xtilde", voffset + i) = x + v * dt;
                vtemp.tuple<3>("xn", voffset + i) = x;
                vtemp.tuple<3>("vn", voffset + i) = v;
                vtemp.tuple<3>("xhat", voffset + i) = x;
            });
    }
    if (coVerts)
        if (auto coSize = coVerts->size(); coSize) {
            pol(Collapse(coSize),
                [vtemp = proxy<space>({}, vtemp), coverts = proxy<space>({}, *coVerts), coOffset = coOffset, dt = dt,
                 augLagCoeff = augLagCoeff, avgNodeMass = avgNodeMass] __device__(int i) mutable {
                    auto x = coverts.pack<3>("x", i);
                    auto v = coverts.pack<3>("v", i);
                    auto newX = x + v * dt;

                    vtemp("ws", coOffset + i) = avgNodeMass * augLagCoeff;
                    vtemp.tuple<3>("xtilde", coOffset + i) = newX;
                    vtemp.tuple<3>("xn", coOffset + i) = x;
                    // vtemp.tuple<3>("vn", coOffset + i) = v;
                    // vtemp.tuple<3>("xhat", coOffset + i) = x;
                });
        }

    // spatial accel structs
    frontManageRequired = true;
#define init_front(sInds, front)                                                                                 \
    {                                                                                                            \
        auto numNodes = front.numNodes();                                                                        \
        if (numNodes <= 2) {                                                                                     \
            front.reserve(sInds.size() * numNodes);                                                              \
            front.setCounter(sInds.size() * numNodes);                                                           \
            pol(Collapse{sInds.size()}, [front = proxy<space>(selfStFront), numNodes] ZS_LAMBDA(int i) mutable { \
                for (int j = 0; j != numNodes; ++j)                                                              \
                    front.assign(i *numNodes + j, i, j);                                                         \
            });                                                                                                  \
        } else {                                                                                                 \
            front.reserve(sInds.size());                                                                         \
            front.setCounter(sInds.size());                                                                      \
            pol(Collapse{sInds.size()},                                                                          \
                [front = proxy<space>(front)] ZS_LAMBDA(int i) mutable { front.assign(i, i, 0); });              \
        }                                                                                                        \
    }
    {
        auto triBvs = retrieve_bounding_volumes(pol, vtemp, "xn", stInds, zs::wrapv<3>{}, 0);
        stBvh.build(pol, triBvs);
        init_front(svInds, selfStFront);

        auto edgeBvs = retrieve_bounding_volumes(pol, vtemp, "xn", seInds, zs::wrapv<2>{}, 0);
        seBvh.build(pol, edgeBvs);
        init_front(seInds, selfSeFront);
    }
    if (coVerts)
        if (coVerts->size()) {
            auto triBvs = retrieve_bounding_volumes(pol, vtemp, "xn", *coEles, zs::wrapv<3>{}, coOffset);
            bouStBvh.build(pol, triBvs);
            init_front(svInds, boundaryStFront);

            auto edgeBvs = retrieve_bounding_volumes(pol, vtemp, "xn", *coEdges, zs::wrapv<2>{}, coOffset);
            bouSeBvh.build(pol, edgeBvs);
            init_front(seInds, boundarySeFront);
        }

    updateWholeBoundingBoxSize(pol);
    /// update grad pn residual tolerance
    targetGRes = pnRel * std::sqrt(boxDiagSize2);
}

ClothSystem::ClothSystem(std::vector<ZenoParticles *> zsprims, const tiles_t *coVerts, const tiles_t *coEdges,
                         const tiles_t *coEles, T dt, std::size_t estNumCps, bool withContact, T augLagCoeff, T pnRel,
                         T cgRel, int PNCap, int CGCap, T dHat_, T gravity)
    : coVerts{coVerts}, coEdges{coEdges}, coEles{coEles}, PP{estNumCps, zs::memsrc_e::um, 0},
      nPP{zsprims[0]->getParticles().get_allocator(), 1}, tempPP{{{"H", 36}}, estNumCps, zs::memsrc_e::um, 0},
      PE{estNumCps, zs::memsrc_e::um, 0}, nPE{zsprims[0]->getParticles().get_allocator(), 1},
      tempPE{{{"H", 81}}, estNumCps, zs::memsrc_e::um, 0}, PT{estNumCps, zs::memsrc_e::um, 0},
      nPT{zsprims[0]->getParticles().get_allocator(), 1}, tempPT{{{"H", 144}}, estNumCps, zs::memsrc_e::um, 0},
      EE{estNumCps, zs::memsrc_e::um, 0}, nEE{zsprims[0]->getParticles().get_allocator(), 1}, tempEE{{{"H", 144}},
                                                                                                     estNumCps,
                                                                                                     zs::memsrc_e::um,
                                                                                                     0},
      //
      temp{estNumCps, zs::memsrc_e::um, zsprims[0]->getParticles().devid()}, csPT{estNumCps, zs::memsrc_e::um, 0},
      csEE{estNumCps, zs::memsrc_e::um, 0}, ncsPT{zsprims[0]->getParticles().get_allocator(), 1},
      ncsEE{zsprims[0]->getParticles().get_allocator(), 1},
      //
      dt{dt}, framedt{dt}, curRatio{0}, estNumCps{estNumCps}, enableContact{withContact}, augLagCoeff{augLagCoeff},
      pnRel{pnRel}, cgRel{cgRel}, PNCap{PNCap}, CGCap{CGCap}, dHat{dHat_}, extAccel{0, gravity, 0} {
    coOffset = sfOffset = seOffset = svOffset = 0;
    for (auto primPtr : zsprims) {
        if (primPtr->category == ZenoParticles::category_e::curve) {
            prims.emplace_back(*primPtr, coOffset, sfOffset, seOffset, svOffset, zs::wrapv<2>{});
        } else if (primPtr->category == ZenoParticles::category_e::surface)
            prims.emplace_back(*primPtr, coOffset, sfOffset, seOffset, svOffset, zs::wrapv<3>{});
        else if (primPtr->category == ZenoParticles::category_e::tet)
            prims.emplace_back(*primPtr, coOffset, sfOffset, seOffset, svOffset, zs::wrapv<4>{});
    }
    numDofs = coOffset;
    if (coVerts)
        numDofs += coVerts->size();
    numBouDofs = numDofs - coOffset;

    fmt::print("num total obj <verts, bouVerts, surfV, surfE, surfT>: {}, {}, {}, {}, {}\n", coOffset, numBouDofs,
               svOffset, seOffset, sfOffset);

    vtemp = tiles_t{zsprims[0]->getParticles().get_allocator(),
                    {{"grad", 3},
                     {"P", 9},
                     {"ws", 1}, // also as constraint jacobian
                     {"cons", 3},

                     {"dir", 3},
                     {"xn", 3},
                     {"vn", 3},
                     {"xn0", 3},
                     {"xtilde", 3},
                     {"xhat", 3}, // initial positions at the current substep (constraint,
                                  // extAccel)
                     {"temp", 3},
                     {"r", 3},
                     {"p", 3},
                     {"q", 3}},
                    (std::size_t)numDofs};

    auto cudaPol = zs::cuda_exec();
    // average edge length (for CCD filtering)
    initialize(cudaPol); // update vtemp, bvh, boxsize, targetGRes
                         // adaptive dhat, targetGRes, kappa
    // dHat (static)
    this->dHat = dHat_ * std::sqrt(boxDiagSize2);

    // check initial self intersections
    // including proximity pairs
    // do once
    markSelfIntersectionPrimitives(cudaPol);
}

} // namespace zeno