// SPDX-License-Identifier: MIT
// The game an offline test session runs in (review finding 8). The module asks the engine whether the game is a local
// single-player one before VR starts and before it drives the game window, the keyboard, the binding editor or a
// capture; offline tests have no engine, so FakeGame answers instead.
#pragma once
#include "single_player.h"
#include <string>

struct FakeGame final:nl::vr::GameCalls {
  // A local single-player game: joined through the loopback channel to this process's own server, one player slot.
  nl::vr::GameFacts game{true,true,true,false,1};
  bool readable=true;  // false: the engine cannot say
  unsigned asked=0;
  bool facts(nl::vr::GameFacts& out,std::string& why) override {
    ++asked;
    if(!readable) { why="the test's engine cannot say";return false; }
    out=game;return true;
  }
};
// Every test session that is not about the gate runs in a local single-player game. Never change this one.
inline FakeGame& single_player() { static FakeGame game;return game; }
