// SPDX-License-Identifier: MIT
#pragma once
#include <string>

namespace nl::vr {
// ADR 0197 read natively (review finding 8): VR starts, and drives the game window, the SteamVR keyboard, the binding
// editor and captures, only in a local single-player game as the engine itself reports it. Never from Lua: any client
// Lua, a server's included, can require this module, and a server's client scripts can replace game.SinglePlayer.
struct GameFacts {
  bool connected=false;  // IVEngineClient::IsConnected: joined to a game
  bool channel=false;    // IVEngineClient::GetNetChannelInfo returned the connection's net channel
  bool loopback=false;   // INetChannelInfo::IsLoopback: the engine's in-process loopback, to this game's own server only
  bool demo=false;       // IVEngineClient::IsPlayingDemo
  int max_clients=0;     // IVEngineClient::GetMaxClients: the server's player slots
};
// Joined through the loopback channel to the server this game runs, with one player slot and no demo playing. A remote
// server decides the slot count it reports, but cannot make the client's channel loopback.
bool local_single_player(const GameFacts& facts);
// Why a game is not a local single-player one, in English; empty when it is one.
std::string not_single_player(const GameFacts& facts);

// The engine boundary, injectable as WindowCalls is: offline tests and native hosts have no engine.
struct GameCalls {
  virtual ~GameCalls()=default;
  // What the engine reports now; false, and why, when it cannot say.
  virtual bool facts(GameFacts& out,std::string& why)=0;
};
// The engine of this process: engine.dll's CreateInterface("VEngineClient015") called through GMod x64's vtable slots,
// each read and called under SEH and only when the object's vtable lies in engine.dll and the slot's function in its
// code. Without engine.dll, or with another shape, it cannot say. Call it on the game thread (Lua's).
GameCalls& engine_game_calls();
}
