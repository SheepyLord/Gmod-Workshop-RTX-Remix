#pragma once
// Cache textures (textures/<sha256>.png) as the game modules read them. The importer writes them
// with stb_image_write, so anything that is not a PNG is refused before it is decoded (the
// signature and the IHDR chunk), and the decoder is stb_image built with PNG alone
// (STBI_ONLY_PNG, cache_png.cpp) into zero-filled buffers. A script can write any bytes to such a
// file (the share protocol, file.Write of a .png): decoded as a TGA, an 18-byte header made
// "pixels" of the game's old heap (stb's short reads, CVE-2023-45663), which went into the Source
// texture made from it and back to any server's file.Read (review finding 6).
#include <memory>
#include <span>
#include <string>
namespace mmd {
// The size in a PNG's header: false unless the bytes start with the PNG signature and an IHDR
// chunk whose width and height are positive.
bool pngHeader(std::span<const unsigned char> bytes,int& width,int& height);
struct DecodedPng {std::unique_ptr<unsigned char,void(*)(void*)> pixels{nullptr,nullptr};int width=0,height=0;};
// RGBA pixels of a cached PNG, of the size its header gives; throws std::runtime_error for
// anything else (`what` names the file in the message).
DecodedPng decodeCachedPng(std::span<const unsigned char> bytes,const std::string& what);
}
