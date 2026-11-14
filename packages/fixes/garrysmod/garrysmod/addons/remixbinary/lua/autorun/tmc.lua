-- Native loader (ADR 0206): only in this machine's RTX starts, as the companion's first autorun says, or under the
-- verified multiplayer initializer; an off switch, a removed loader or files a loader left behind run none of this.
if not (NATIVELOADER_VERIFIED_MULTIPLAYER or NativeLoaderRTXStart and NativeLoaderRTXStart()) then return end
if SERVER then
    AddCSLuaFile("tmc/init.lua")
else
    include("tmc/init.lua")
end