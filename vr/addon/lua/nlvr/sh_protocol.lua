-- One type byte in one channel. Float angles intentionally avoid net.WriteAngle quantisation.
local P = {NAME = "nlvr", START = 1, STOP = 2, SYNC = 3, SYNC_BITS = 1467,
    MIN_SCALE = 10, MAX_SCALE = 100, REACH = 2.5, HISTORY_SECONDS = 1,
    Modules = {hands = {16, 23}, move = {24, 31}, ui = {32, 39}, interact = {40, 63},
        weapons = {64, 79}, reload = {80, 95}, tools = {96, 111}},
    Buttons = {grip = 1, trigger = 2, stick_click = 4, a = 8, b = 16}}
function P.Finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
function P.Scale(n) return P.Finite(n) and n >= P.MIN_SCALE and n <= P.MAX_SCALE end
function P.ModuleType(n) return type(n) == "number" and n % 1 == 0 and n >= 16 and n <= 127 end
local function vector(io, value)
    io.WriteFloat(value.x) io.WriteFloat(value.y) io.WriteFloat(value.z)
end
local function angle(io, value)
    io.WriteFloat(value.p) io.WriteFloat(value.y) io.WriteFloat(value.r)
end
local function read_vector(io) return Vector(io.ReadFloat(), io.ReadFloat(), io.ReadFloat()) end
local function read_angle(io) return Angle(io.ReadFloat(), io.ReadFloat(), io.ReadFloat()) end
function P.WriteSync(io, sample)
    io.WriteUInt(sample.seq, 32)
    io.WriteBool(sample.head.valid) vector(io, sample.head.pos) angle(io, sample.head.ang)
    for _, hand in ipairs({"left", "right"}) do
        local h = sample.hands[hand]
        io.WriteBool(h.valid) vector(io, h.pos) angle(io, h.ang) vector(io, h.vel) vector(io, h.angvel)
        io.WriteFloat(h.grip_force) io.WriteFloat(h.trigger_value)
        for i = 1, 5 do io.WriteFloat(h.curls[i]) end
        io.WriteUInt(h.buttons, 8)
    end
end
function P.ReadSync(io)
    local sample = {seq = io.ReadUInt(32), hands = {}}
    sample.head = {valid = io.ReadBool(), pos = read_vector(io), ang = read_angle(io)}
    for _, hand in ipairs({"left", "right"}) do
        local h = {valid = io.ReadBool(), pos = read_vector(io), ang = read_angle(io), vel = read_vector(io), angvel = read_vector(io),
            grip_force = io.ReadFloat(), trigger_value = io.ReadFloat(), curls = {}}
        for i = 1, 5 do h.curls[i] = io.ReadFloat() end
        h.buttons = io.ReadUInt(8) sample.hands[hand] = h
    end
    return sample
end
local function finite_vector(v) return v and P.Finite(v.x) and P.Finite(v.y) and P.Finite(v.z) end
local function finite_angle(a) return a and P.Finite(a.p) and P.Finite(a.y) and P.Finite(a.r) end
function P.ValidateSync(sample, state, eyes, reach)
    if not sample or not P.Finite(sample.seq) or sample.seq % 1 ~= 0 or sample.seq < 0 or sample.seq >= 4294967296 then return false, "sequence" end
    if state.seq ~= nil then
        local delta = (sample.seq - state.seq) % 4294967296
        if delta == 0 or delta >= 2147483648 then return false, "sequence" end
    end
    local head = sample.head
    if not head or type(head.valid) ~= "boolean" or not finite_vector(head.pos) or not finite_angle(head.ang) then return false, "finite" end
    if head.pos:DistToSqr(eyes) > reach * reach then return false, "reach" end
    for _, hand in ipairs({"left", "right"}) do
        local h = sample.hands and sample.hands[hand]
        if not h or type(h.valid) ~= "boolean" or not finite_vector(h.pos) or not finite_angle(h.ang) or
            not finite_vector(h.vel) or not finite_vector(h.angvel) then return false, "finite" end
        if h.pos:DistToSqr(eyes) > reach * reach then return false, "reach" end
        for _, value in ipairs({h.grip_force, h.trigger_value}) do
            if not P.Finite(value) or value < 0 or value > 1 then return false, "axis" end
        end
        if not P.Finite(h.grip_force) or not P.Finite(h.trigger_value) then return false, "axis" end
        for i = 1, 5 do
            local v = h.curls and h.curls[i]
            if not P.Finite(v) or v < 0 or v > 1 then return false, "curls" end
        end
        if not P.Finite(h.buttons) or h.buttons % 1 ~= 0 or h.buttons < 0 or h.buttons > 31 then return false, "buttons" end
    end
    return true
end
-- A writer receives this net-shaped buffer. It snapshots values now; the server may send it next tick.
-- Comparing the recorded payload avoids sending unchanged physics and never replaces global net functions.
function P.Packet(writer)
    local ops, signature, bytes = {}, {}, 0
    local io = {}
    local function add(name, args, text, size)
        bytes = bytes + size assert(bytes <= 4096, "VR module payload exceeds 4096 bytes")
        ops[#ops + 1] = {name, args} signature[#signature + 1] = name .. ":" .. text
    end
    for _, name in ipairs({"WriteFloat", "WriteDouble", "WriteUInt", "WriteInt"}) do
        local method = name
        io[method] = function(n, bits)
            assert(P.Finite(n), "Non-finite module payload")
            if method == "WriteUInt" or method == "WriteInt" then
                assert(P.Finite(bits) and bits % 1 == 0 and bits >= 1 and bits <= 32, "Invalid integer width")
                local low = method == "WriteUInt" and 0 or -(2 ^ (bits - 1))
                local high = method == "WriteUInt" and 2 ^ bits - 1 or 2 ^ (bits - 1) - 1
                assert(n % 1 == 0 and n >= low and n <= high, "Integer payload out of range")
            end
            add(method, {n, bits}, string.format("%.17g/%s", n, tostring(bits)), 8)
        end
    end
    function io.WriteBool(b) assert(type(b) == "boolean") add("WriteBool", {b}, tostring(b), 1) end
    function io.WriteString(s) assert(type(s) == "string" and not s:find("\0", 1, true)) add("WriteString", {s}, #s .. ":" .. s, #s + 1) end
    function io.WriteVector(v)
        assert(finite_vector(v))
        add("WriteVector", {Vector(v.x, v.y, v.z)}, string.format("%.17g,%.17g,%.17g", v.x, v.y, v.z), 12)
    end
    function io.WriteAngle(a)
        assert(finite_angle(a))
        add("WriteAngle", {Angle(a.p, a.y, a.r)}, string.format("%.17g,%.17g,%.17g", a.p, a.y, a.r), 12)
    end
    function io.WriteEntity(e)
        local index = IsValid(e) and e:EntIndex() or 0
        add("WriteEntity", {e}, tostring(index), 2)
    end
    if writer then writer(io) end
    return {signature = table.concat(signature, "|"), Write = function(destination)
        for _, op in ipairs(ops) do destination[op[1]](unpack(op[2])) end
    end}
end
return P
