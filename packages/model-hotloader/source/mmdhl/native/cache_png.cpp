// The game modules' decoder of cache textures (cache_png.hpp): stb_image with PNG alone, static in
// this file, so the runtime's other copy (assets.cpp, every format, for the importer) is never what
// reads a cache file in the game.
#include "cache_png.hpp"
#include <climits>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#define STB_IMAGE_STATIC
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_NO_STDIO
// Zero-filled buffers: whatever a damaged image leaves undecoded reads as black, never as old heap.
#define STBI_MALLOC(size) std::calloc(1,size)
#define STBI_REALLOC(pointer,size) std::realloc(pointer,size)
#define STBI_FREE(pointer) std::free(pointer)
#include <stb_image.h>
namespace mmd {
bool pngHeader(std::span<const unsigned char> b,int& width,int& height){
 if(b.size()<24||std::memcmp(b.data(),"\x89PNG\r\n\x1a\n",8)||std::memcmp(b.data()+12,"IHDR",4))return false;
 auto be=[&](size_t at){return uint32_t(b[at])<<24|uint32_t(b[at+1])<<16|uint32_t(b[at+2])<<8|uint32_t(b[at+3]);};
 uint32_t w=be(16),h=be(20);if(!w||!h||w>INT_MAX||h>INT_MAX)return false;
 width=int(w);height=int(h);return true;
}
DecodedPng decodeCachedPng(std::span<const unsigned char> b,const std::string& what){
 int headerWidth=0,headerHeight=0;
 if(b.size()>INT_MAX||!pngHeader(b,headerWidth,headerHeight))throw std::runtime_error(what+" is not a PNG");
 DecodedPng out;int width=0,height=0,channels=0;
 out.pixels={stbi_load_from_memory(b.data(),int(b.size()),&width,&height,&channels,4),stbi_image_free};
 if(!out.pixels||width!=headerWidth||height!=headerHeight)throw std::runtime_error(what+" cannot be decoded");
 out.width=width;out.height=height;return out;
}
}
