-- Built animations follow a Model Hotloader character across its carriers (ADR 0259).
--
-- A built animation is the motion solved against one skeleton: every frame holds each bone's
-- manipulation from the model's own Reference pose, by bone and flex index (cl_menu.lua,
-- fast_compile_solver). Its file is named after the model path (sh_core.lua, BuiltTail). An
-- imported character's model is a carrier, models/mmd/<16 hex>/<name>.mdl, whose 16 hex are the
-- start of a hash of the carrier's whole fit (the Model Hotloader's rig.cpp, identify): its size,
-- its asset (a new one at every import), its materials, attachments and physics. Any of them gives
-- the character a new path, and every motion built for it was missing again: in the user's game
-- 102 carriers changed since 2026-11-01, sixty of them for a new size alone (the report).
--
-- Here two carriers share their builds when a build solved on either would be the same: the same
-- role and animation profile, bones (names, parents, fitted rotations, offsets from the parent
-- divided by the carrier's size) and morphs (names and indices: the flex ids a build drives), and
-- the same Reference pose (each bone's reference rotation; its offset as it is or divided by the
-- size). Numbers are compared within Tolerance: scale variants of one fit differ by at most 1.8e-6
-- (rotations) and 3.6e-6 (offsets) in the user's 668 rigs, while different skeletons differ by far
-- more. The first carrier of a skeleton that gets a build (or an expression mapping) becomes its
-- build model: the name later carriers of that skeleton build and look for their files under.
-- A resized character reuses its builds as they are: rotations do not change with the size, and
-- motion offsets are in the motion's units for every model; only the pelvis/spine correction is
-- the size of the carrier the build was made on (0.16 units at most at a 20 % size change in the
-- user's carriers, whose spine sits 2.1 units from the pelvis at most).
--
-- The skeletons live in built/_skeletons.dat ("Skeletons" below): each build model's numbers, so
-- carriers still match after the Hotloader deleted the build model's own rig. Builds and
-- expression mappings made before this change are adopted once (Migration): carriers with the
-- same skeleton are joined under the one with the most builds, their files renamed to its name.
-- Models that are not Model Hotloader carriers keep their own path, as before.

MMDVMDNPC = MMDVMDNPC or {}
MMDVMDNPC.Skeletons = MMDVMDNPC.Skeletons or {}
local S = MMDVMDNPC.Skeletons

S.Format = 1
S.IndexPath = (MMDVMDNPC.BuiltRoot or "mmd_vmd_npc/built") .. "/_skeletons.dat"
S.RigRoot = "mmd_hotloader/rigs"
S.Tolerance = 1e-4
-- Per model path (lower case): what BuildModelKey answered. A final answer (a build model, an
-- alias, a match) holds for the session: a carrier's rig never changes under its path (the path is
-- the rig's hash). A provisional one (no match yet) holds until a new build model is added.
S.Memo = {}
S.Revision = S.Revision or 0

local MIGRATION_TIMER = "MMDVMDNPCSkeletonMigration"
local SAVE_TIMER = "MMDVMDNPCSkeletonIndexSave"
local OVERRIDE_FIELDS = { "by_mmd", "by_source", "by_mmd_norm", "by_source_norm" }
-- The options part of a build file name in the current format (sh_core.lua, BuiltTail). Files of the
-- format before it (no "_fm2") are not read by this add-on at all: the migration leaves them as they are.
local BUILT_OPTIONS = "^tw%d_ht%d_eye%d_sp%d_fm2"

function S.LowerPath(path)
    return string.lower(string.gsub(tostring(path or ""), "\\", "/"))
end

-- The carrier's 16 hex digits, or nil for any other model.
function S.CarrierKey16(path)
    local key16 = string.match(S.LowerPath(path), "^models/mmd/(%x+)/[^/]+%.mdl$")
    if key16 and #key16 == 16 then return key16 end
    return nil
end

local function read_rig(path)
    local raw = file.Read(path, "DATA")
    local rig = raw and util.JSONToTable(raw) or nil
    return istable(rig) and rig or nil
end

-- The Hotloader's rig manifest of a carrier: the one it holds for this session, else its rig.json.
function S.RigForModel(modelPath)
    local wanted = S.LowerPath(modelPath)
    local key16 = S.CarrierKey16(wanted)
    if not key16 then return nil end
    local byModel = istable(mmdhl) and istable(mmdhl.rigsByModel) and mmdhl.rigsByModel or nil
    if byModel then
        local rig = byModel[tostring(modelPath or "")] or byModel[wanted]
        if istable(rig) then return rig end
    end
    local _, dirs = file.Find(S.RigRoot .. "/" .. key16 .. "*", "DATA")
    for _, dir in ipairs(dirs or {}) do
        if string.match(dir, "^%x+$") then
            local rig = read_rig(S.RigRoot .. "/" .. dir .. "/rig.json")
            if rig and S.LowerPath(rig.model) == wanted then return rig end
        end
    end
    return nil
end

local function number(value)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function fixed(value)
    return string.format("%.4f", number(value) or 0)
end

-- v rotated by the inverse of the unit quaternion q = {x, y, z, w}.
local function rotate_inverse(q, x, y, z)
    local qx, qy, qz, qw = -q[1], -q[2], -q[3], q[4]
    local tx = 2 * (qy * z - qz * y)
    local ty = 2 * (qz * x - qx * z)
    local tz = 2 * (qx * y - qy * x)
    return x + qw * tx + (qy * tz - qz * ty),
        y + qw * ty + (qz * tx - qx * tz),
        z + qw * tz + (qx * ty - qy * tx)
end

local function quaternion(value)
    if not istable(value) then return nil end
    local x, y, z, w = number(value[1]), number(value[2]), number(value[3]), number(value[4])
    if not (x and y and z and w) then return nil end
    return { x, y, z, w }
end

local function position(value)
    if not istable(value) then return nil end
    local x, y, z = number(value[1]), number(value[2]), number(value[3])
    if not (x and y and z) then return nil end
    return x, y, z
end

local function hash(text)
    if util.SHA256 then return util.SHA256(text) end
    return util.CRC(text) .. ":" .. #text
end

-- What decides a build, from a rig manifest: {family, bones, refs, scale, values, refValues}, or nil
-- when the manifest is not one this reads. family hashes everything compared exactly; values hold
-- per bone its rotation (4) and offset from its parent divided by the size (3), refValues per
-- Reference bone its rotation (4) and its offset as written (3).
function S.Signature(rig)
    if not istable(rig) or not istable(rig.bones) or #rig.bones == 0 then return nil end
    local scale = number(rig.scale)
    if not scale or scale <= 0 then return nil end
    local anim = istable(rig.animation) and rig.animation or {}
    local parts = {
        "carrier-identity-1", tostring(rig.version), tostring(rig.role or ""), tostring(anim.profile or ""),
        tostring(rig.meshYaw), tostring(rig.referenceYaw), tostring(rig.jointFrameConvention or ""),
        tostring(rig.nativeFlexCount),
    }
    for _, include in ipairs(istable(anim.includes) and anim.includes or {}) do parts[#parts + 1] = "inc:" .. tostring(include) end
    for _, chain in ipairs(istable(anim.ikChains) and anim.ikChains or {}) do
        if istable(chain) then
            parts[#parts + 1] = "ik:" .. tostring(chain.name) .. ":" .. tostring(chain.type)
            for _, link in ipairs(istable(chain.links) and chain.links or {}) do
                local knee = istable(link) and istable(link.knee) and link.knee or {}
                parts[#parts + 1] = "l:" .. tostring(istable(link) and link.bone) .. ":" .. fixed(knee[1]) .. "," .. fixed(knee[2]) .. "," .. fixed(knee[3])
            end
        end
    end
    for _, lock in ipairs(istable(anim.ikLocks) and anim.ikLocks or {}) do parts[#parts + 1] = "lock:" .. tostring(lock) end
    for _, pose in ipairs(istable(anim.poseParameters) and anim.poseParameters or {}) do
        if istable(pose) then
            parts[#parts + 1] = "pose:" .. tostring(pose.name) .. ":" .. tostring(pose.flags) .. ":" .. fixed(pose.start) .. ":" .. fixed(pose["end"]) .. ":" .. fixed(pose.loop)
        end
    end
    for _, morph in ipairs(istable(rig.morphs) and rig.morphs or {}) do
        if istable(morph) then
            parts[#parts + 1] = "m:" .. tostring(morph.name) .. ":" .. tostring(morph.original) .. ":" .. tostring(morph.mmd) .. ":" .. tostring(morph.native)
        end
    end

    local bones, values = rig.bones, {}
    local origin = number(rig.actorOrigin) or 0
    for _, bone in ipairs(bones) do
        if not istable(bone) then return nil end
        local q = quaternion(bone.rotation)
        local x, y, z = position(bone.position)
        local parent = number(bone.parent)
        if not q or not x or not parent then return nil end
        parts[#parts + 1] = "b:" .. tostring(bone.name) .. ":" .. tostring(parent)
        local lx, ly, lz
        if parent < 0 then
            -- An actor's carrier stands on actorOrigin, a fixed height: only the rest scales.
            lx, ly, lz = x, y, z - origin
        else
            local up = bones[parent + 1]
            local pq = istable(up) and quaternion(up.rotation) or nil
            local px, py, pz
            if istable(up) then px, py, pz = position(up.position) end
            if not pq or not px then return nil end
            lx, ly, lz = rotate_inverse(pq, x - px, y - py, z - pz)
        end
        local n = #values
        values[n + 1], values[n + 2], values[n + 3], values[n + 4] = q[1], q[2], q[3], q[4]
        values[n + 5], values[n + 6], values[n + 7] = lx / scale, ly / scale, lz / scale
    end

    local refValues = {}
    local reference = istable(anim.reference) and anim.reference or {}
    for _, ref in ipairs(reference) do
        local q = istable(ref) and quaternion(ref.rotation) or nil
        local x, y, z
        if istable(ref) then x, y, z = position(ref.position) end
        if not q or not x then return nil end
        local n = #refValues
        refValues[n + 1], refValues[n + 2], refValues[n + 3], refValues[n + 4] = q[1], q[2], q[3], q[4]
        refValues[n + 5], refValues[n + 6], refValues[n + 7] = x, y, z
    end
    parts[#parts + 1] = "refs:" .. #reference

    return {
        family = hash(table.concat(parts, "\n")),
        bones = #bones,
        refs = #reference,
        scale = scale,
        values = values,
        refValues = refValues,
    }
end

local function quaternion_matches(a, b, o, tolerance)
    local dot = a[o + 1] * b[o + 1] + a[o + 2] * b[o + 2] + a[o + 3] * b[o + 3] + a[o + 4] * b[o + 4]
    local sign = dot < 0 and -1 or 1
    for k = 1, 4 do
        if math.abs(a[o + k] - sign * b[o + k]) > tolerance then return false end
    end
    return true
end

-- Whether a build solved on one of two signatures fits the other.
function S.Matches(a, b, tolerance)
    tolerance = tolerance or S.Tolerance
    if not istable(a) or not istable(b) then return false end
    if a.family ~= b.family or a.bones ~= b.bones or a.refs ~= b.refs then return false end
    local av, bv = a.values, b.values
    if #av ~= a.bones * 7 or #bv ~= b.bones * 7 then return false end
    for i = 0, a.bones - 1 do
        local o = i * 7
        if not quaternion_matches(av, bv, o, tolerance) then return false end
        for k = 5, 7 do
            if math.abs(av[o + k] - bv[o + k]) > tolerance then return false end
        end
    end
    local ar, br = a.refValues, b.refValues
    if #ar ~= a.refs * 7 or #br ~= b.refs * 7 then return false end
    for i = 0, a.refs - 1 do
        local o = i * 7
        if not quaternion_matches(ar, br, o, tolerance) then return false end
        -- A bone the profile's skeleton has keeps that skeleton's offset whatever the size;
        -- any other bone keeps the fitted one, which scales.
        local raw, scaled = true, true
        for k = 5, 7 do
            if math.abs(ar[o + k] - br[o + k]) > tolerance then raw = false end
            if math.abs(ar[o + k] / a.scale - br[o + k] / b.scale) > tolerance then scaled = false end
        end
        if not raw and not scaled then return false end
    end
    return true
end

-- Skeletons -----------------------------------------------------------------------------------

local function encode_numbers(list)
    local out = {}
    for i, value in ipairs(list) do out[i] = string.format("%.6f", value) end
    return table.concat(out, ",")
end

local function decode_numbers(text, count)
    local out = {}
    for part in string.gmatch(tostring(text or ""), "[^,]+") do
        local value = number(part)
        if not value then return nil end
        out[#out + 1] = value
    end
    if #out ~= count then return nil end
    return out
end

local function decode_entry(raw)
    if not istable(raw) or not isstring(raw.model) or not S.CarrierKey16(raw.model) or not isstring(raw.family) then return nil end
    local bones, refs, scale = number(raw.bones), number(raw.refs), number(raw.scale)
    if not bones or not refs or not scale or scale <= 0 or bones < 1 or refs < 0 then return nil end
    local values = decode_numbers(raw.values, bones * 7)
    local refValues = refs > 0 and decode_numbers(raw.refValues, refs * 7) or {}
    if not values or not refValues then return nil end
    return {
        model = raw.model, family = raw.family, bones = bones, refs = refs, scale = scale,
        values = values, refValues = refValues, name = isstring(raw.name) and raw.name or nil,
    }
end

local function add_to_family(entry)
    S.ByFamily[entry.family] = S.ByFamily[entry.family] or {}
    table.insert(S.ByFamily[entry.family], entry)
end

function S.Index()
    if S.Data then return S.Data end
    local data = { migrated = false, entries = {}, aliases = {} }
    local raw = file.Read(S.IndexPath, "DATA")
    local parsed = raw and util.JSONToTable(raw) or nil
    if istable(parsed) and number(parsed.format) == S.Format then
        data.migrated = parsed.migrated == true
        local list = istable(parsed.skeletons) and parsed.skeletons or {}
        for _, rawEntry in ipairs(list) do
            local entry = decode_entry(rawEntry)
            if entry then data.entries[S.LowerPath(entry.model)] = entry end
        end
        for from, to in pairs(istable(parsed.aliases) and parsed.aliases or {}) do
            if isstring(from) and isstring(to) and S.CarrierKey16(from) and S.CarrierKey16(to) then
                data.aliases[S.LowerPath(from)] = to
            end
        end
    end
    S.Data = data
    S.ByFamily = {}
    local ordered = {}
    for _, entry in pairs(data.entries) do ordered[#ordered + 1] = entry end
    table.sort(ordered, function(a, b) return S.LowerPath(a.model) < S.LowerPath(b.model) end)
    for _, entry in ipairs(ordered) do add_to_family(entry) end
    return data
end

function S.Save()
    S.Dirty = false
    timer.Remove(SAVE_TIMER)
    local data = S.Index()
    local list = {}
    for _, entry in pairs(data.entries) do
        list[#list + 1] = {
            model = entry.model, family = entry.family, bones = entry.bones, refs = entry.refs, scale = entry.scale,
            values = encode_numbers(entry.values), refValues = encode_numbers(entry.refValues), name = entry.name,
        }
    end
    table.sort(list, function(a, b) return S.LowerPath(a.model) < S.LowerPath(b.model) end)
    file.CreateDir(MMDVMDNPC.DataRoot or "mmd_vmd_npc")
    file.CreateDir(MMDVMDNPC.BuiltRoot or "mmd_vmd_npc/built")
    file.Write(S.IndexPath, util.TableToJSON({ format = S.Format, migrated = data.migrated == true, skeletons = list, aliases = data.aliases }))
end

function S.SaveSoon()
    S.Dirty = true
    timer.Create(SAVE_TIMER, 1, 1, function() S.Save() end)
end

-- A new build model: carriers that found none so far look again.
function S.AddEntry(model, sig, name)
    local entry = {
        model = model, family = sig.family, bones = sig.bones, refs = sig.refs, scale = sig.scale,
        values = sig.values, refValues = sig.refValues, name = isstring(name) and name or nil,
    }
    S.Index().entries[S.LowerPath(model)] = entry
    add_to_family(entry)
    S.Revision = S.Revision + 1
    S.SaveSoon()
    return entry
end

local function remember(modelPath, key, final, sig)
    S.Memo[S.LowerPath(modelPath)] = { model = modelPath, key = key, final = final, sig = sig, revision = S.Revision }
end

function S.MatchEntry(sig)
    if not sig then return nil end
    for _, entry in ipairs(S.ByFamily[sig.family] or {}) do
        if S.Matches(sig, entry) then return entry end
    end
    return nil
end

-- The model whose name a model's builds take: for a Model Hotloader carrier, the build model of its
-- skeleton when one exists; for anything else, the model itself.
function MMDVMDNPC.BuildModelKey(modelPath)
    modelPath = tostring(modelPath or "")
    if not S.CarrierKey16(modelPath) then return modelPath end
    local lower = S.LowerPath(modelPath)
    local memo = S.Memo[lower]
    if memo and (memo.final or memo.revision == S.Revision) then return memo.key end
    S.FinishMigration()
    local data = S.Index()
    local alias = data.aliases[lower]
    if alias then
        remember(modelPath, alias, true)
        return alias
    end
    local entry = data.entries[lower]
    if entry then
        remember(modelPath, entry.model, true)
        return entry.model
    end
    local sig = memo and memo.sig or nil
    if not sig then
        local rig = S.RigForModel(modelPath)
        sig = rig and S.Signature(rig) or nil
    end
    local match = S.MatchEntry(sig)
    if match then
        remember(modelPath, match.model, true)
        return match.model
    end
    remember(modelPath, modelPath, false, sig)
    return modelPath
end

function MMDVMDNPC.SameBuildModel(a, b)
    return S.LowerPath(MMDVMDNPC.BuildModelKey(a)) == S.LowerPath(MMDVMDNPC.BuildModelKey(b))
end

-- Every model this session found under a build model (and the build model itself): the client
-- replicas of builds made on any of them go when that build model's builds do.
function MMDVMDNPC.BuildModelMembers(key)
    key = tostring(key or "")
    local wanted = S.LowerPath(key)
    local out, seen = { key }, { [wanted] = true }
    for lower, memo in pairs(S.Memo) do
        if not seen[lower] and S.LowerPath(memo.key) == wanted then
            seen[lower] = true
            out[#out + 1] = memo.model
        end
    end
    table.sort(out, function(x, y)
        if x == key then return true end
        if y == key then return false end
        return S.LowerPath(x) < S.LowerPath(y)
    end)
    return out
end

-- After a build or an expression mapping was saved for a model: its build model is kept, so that
-- other carriers of its skeleton find what was saved.
function MMDVMDNPC.NoteBuildModel(modelPath)
    local key = MMDVMDNPC.BuildModelKey(modelPath)
    if not S.CarrierKey16(key) then return false end
    local data = S.Index()
    if data.entries[S.LowerPath(key)] or data.aliases[S.LowerPath(key)] then return false end
    local memo = S.Memo[S.LowerPath(modelPath)]
    local sig = memo and memo.sig or nil
    local rig
    if not sig then
        rig = S.RigForModel(key)
        sig = rig and S.Signature(rig) or nil
    end
    if not sig then return false end
    rig = rig or S.RigForModel(key)
    S.AddEntry(key, sig, rig and rig.name or nil)
    remember(key, key, true)
    return true
end

-- Migration ---------------------------------------------------------------------------------

-- What follows the motion id in a build file's name for a model, up to its options (BuiltTail of
-- the model itself, without the build model).
function S.RawTailPrefix(modelPath)
    return "_" .. MMDVMDNPC.SafeModelName(modelPath) .. "_" .. util.CRC(string.lower(string.Trim(tostring(modelPath or "")))) .. "_"
end

local function find_last(text, part)
    local last, from = nil, 1
    while true do
        local at = string.find(text, part, from, true)
        if not at then return last end
        last, from = at, at + 1
    end
end

local function merge_overrides(into, from)
    for _, field in ipairs(OVERRIDE_FIELDS) do
        if istable(from[field]) then
            into[field] = istable(into[field]) and into[field] or {}
            for name, value in pairs(from[field]) do
                if into[field][name] == nil then into[field][name] = value end
            end
        end
    end
end

-- The carriers named by build files and expression mappings: their rigs are read one at a time.
function S.StartMigration()
    if S.MigrationState or S.Index().migrated then return end
    local state = { queue = {}, queued = {}, candidates = {}, files = {} }
    local function queue(key16)
        if key16 and not state.queued[key16] then
            state.queued[key16] = true
            state.queue[#state.queue + 1] = key16
        end
    end
    local extension = MMDVMDNPC.CacheExtension or ".json"
    local names = file.Find((MMDVMDNPC.BuiltRoot or "mmd_vmd_npc/built") .. "/*" .. extension, "DATA") or {}
    for _, name in ipairs(names) do
        if string.sub(name, -(#extension + 4)) == "_fm2" .. extension then
            state.files[#state.files + 1] = name
            for key16 in string.gmatch(string.lower(name), "_mmd_(%x+)_") do
                if #key16 == 16 then queue(key16) end
            end
        end
    end
    local overrides = MMDVMDNPC.LoadFlexOverrides and MMDVMDNPC.LoadFlexOverrides() or {}
    for model in pairs(overrides) do queue(S.CarrierKey16(model)) end
    table.sort(state.queue)
    S.MigrationState = state
end

-- Reads rigs for about budget seconds (at least one); true when the migration is complete.
function S.StepMigration(budget)
    local state = S.MigrationState
    if not state then return S.Index().migrated == true end
    local deadline = SysTime() + (budget or 0.004)
    repeat
        local key16 = table.remove(state.queue)
        if not key16 then break end
        local _, dirs = file.Find(S.RigRoot .. "/" .. key16 .. "*", "DATA")
        for _, dir in ipairs(dirs or {}) do
            local rig = string.match(dir, "^%x+$") and read_rig(S.RigRoot .. "/" .. dir .. "/rig.json") or nil
            if rig and isstring(rig.model) and S.CarrierKey16(rig.model) == key16 then
                local sig = S.Signature(rig)
                if sig then
                    state.candidates[S.LowerPath(rig.model)] = { model = rig.model, sig = sig, name = isstring(rig.name) and rig.name or nil }
                end
            end
        end
    until SysTime() >= deadline
    if #state.queue > 0 then return false end
    S.CompleteMigration(state)
    return true
end

-- Joins carriers of one skeleton under the one with the most builds; each other one's files take
-- its name (a file that name already has stays as it was) and its expression mappings join its.
function S.CompleteMigration(state)
    local root = MMDVMDNPC.BuiltRoot or "mmd_vmd_npc/built"
    local extension = MMDVMDNPC.CacheExtension or ".json"
    local order = {}
    for _, candidate in pairs(state.candidates) do
        candidate.prefix = S.RawTailPrefix(candidate.model)
        candidate.files = {}
        for _, name in ipairs(state.files) do
            local at = find_last(name, candidate.prefix)
            local options = at and string.sub(name, at + #candidate.prefix) or nil
            if options and string.match(options, BUILT_OPTIONS) and string.sub(options, -#extension) == extension
                and #options == #string.match(options, BUILT_OPTIONS) + #extension then
                candidate.files[#candidate.files + 1] = name
            end
        end
        order[#order + 1] = candidate
    end
    table.sort(order, function(a, b)
        if #a.files ~= #b.files then return #a.files > #b.files end
        return S.LowerPath(a.model) < S.LowerPath(b.model)
    end)

    local data = S.Index()
    local overrides = MMDVMDNPC.LoadFlexOverrides and MMDVMDNPC.LoadFlexOverrides() or {}
    local overridesChanged = false
    local models, joined, renamed, kept = 0, 0, 0, 0
    for _, candidate in ipairs(order) do
        local lower = S.LowerPath(candidate.model)
        local mapping = overrides[lower]
        if #candidate.files > 0 or istable(mapping) then
            local entry = data.entries[lower]
            if not entry and not data.aliases[lower] then entry = S.MatchEntry(candidate.sig) end
            if not entry and not data.aliases[lower] then
                S.AddEntry(candidate.model, candidate.sig, candidate.name)
                models = models + 1
            elseif entry and S.LowerPath(entry.model) ~= lower then
                data.aliases[lower] = entry.model
                joined = joined + 1
                local prefix = S.RawTailPrefix(entry.model)
                for _, name in ipairs(candidate.files) do
                    local at = find_last(name, candidate.prefix)
                    local target = string.sub(name, 1, at - 1) .. prefix .. string.sub(name, at + #candidate.prefix)
                    local from, to = root .. "/" .. name, root .. "/" .. target
                    if not file.Exists(to, "DATA") and file.Rename(from, to) then
                        renamed = renamed + 1
                        if MMDVMDNPC.ForgetBuiltHeader then MMDVMDNPC.ForgetBuiltHeader(from) end
                    else
                        kept = kept + 1
                    end
                end
                if istable(mapping) then
                    local into = S.LowerPath(entry.model)
                    overrides[into] = istable(overrides[into]) and overrides[into] or {}
                    merge_overrides(overrides[into], mapping)
                    overrides[lower] = nil
                    overridesChanged = true
                end
            end
        end
    end
    if overridesChanged and MMDVMDNPC.SaveFlexOverrides then MMDVMDNPC.SaveFlexOverrides() end
    data.migrated = true
    S.MigrationState = nil
    timer.Remove(MIGRATION_TIMER)
    S.Revision = S.Revision + 1
    S.Save()
    if models + joined > 0 then
        print(string.format("[MMD VMD] Built animations of imported characters: %d skeleton(s) kept, %d other carrier(s) joined, %d build(s) renamed to them, %d left as they were.",
            models, joined, renamed, kept))
    end
end

-- Completes the migration now (a lookup needs it); it normally runs in steps after the map starts.
function S.FinishMigration()
    if S.Migrating or S.Index().migrated then return end
    S.Migrating = true
    local ok, err = pcall(function()
        S.StartMigration()
        while not S.StepMigration(math.huge) do end
    end)
    S.Migrating = false
    if not ok then
        -- Never again this session: lookups fall back to each carrier's own name.
        S.Index().migrated = true
        S.MigrationState = nil
        ErrorNoHalt("[MMD VMD] adopting earlier builds failed: " .. tostring(err) .. "\n")
    end
end

hook.Add("InitPostEntity", "MMDVMDNPCSkeletonMigration", function()
    timer.Simple(3, function()
        if S.Index().migrated or S.Migrating then return end
        S.StartMigration()
        timer.Create(MIGRATION_TIMER, 0, 0, function()
            if S.Migrating then return end
            S.Migrating = true
            local ok, done = pcall(S.StepMigration, 0.003)
            S.Migrating = false
            if not ok then
                S.Index().migrated = true
                S.MigrationState = nil
                timer.Remove(MIGRATION_TIMER)
                ErrorNoHalt("[MMD VMD] adopting earlier builds failed: " .. tostring(done) .. "\n")
            elseif done then
                timer.Remove(MIGRATION_TIMER)
            end
        end)
    end)
end)

hook.Add("ShutDown", "MMDVMDNPCSkeletonIndex", function()
    if S.Dirty then S.Save() end
end)
