#pragma once
// The mesh separator's job (kind "mesh"): a static prop from a piece of a model in the game, given as triangles in the
// request: positions in Source units around the piece's origin, outward counter-clockwise; per material, an optional
// texture from the character cache by its content hash and an optional Source material that draws the slot instead
// (source_material). The request comes from the game module's PropFromMesh binding.
#include "core.hpp"

namespace props {
// Builds the piece's asset (no collision yet). characterTextures is the character cache's texture folder.
Asset meshAsset(const Json& request,const fs::path& characterTextures,const Limits& limits,const Progress& progress);
// The collision a piece gets when the request asks for "auto": "balanced" (CoACD) for a closed piece, 12 units across
// or more, that fills little of its outer hull (a ring, a bow), "hull" otherwise (a small piece, a compact piece, or an
// open shell CoACD cannot close).
std::string automaticCollision(const Asset& asset);
// What automaticCollision measured: the piece's open (boundary) edges and edges, its enclosed volume and its fast
// hull's volume.
struct PieceShape { size_t boundaryEdges=0,edges=0; double volume=0,hullVolume=0; };
PieceShape measurePiece(const Asset& asset);
}
