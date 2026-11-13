-- Game units, seconds, world XYZ radians/s. Pure helpers; no hooks or resources on include.
local M = {}
function M.Limit(v, maximum)
    local length = v:Length()
    return length > maximum and v * (maximum / length) or v
end
function M.Cross(a, b) return Vector(a.y*b.z-a.z*b.y, a.z*b.x-a.x*b.z, a.x*b.y-a.y*b.x) end
function M.Unit(v, fallback) return v:Length() > 0.00001 and v / v:Length() or (fallback or Vector(1,0,0)) end
function M.Segment(p,a,b)
    local delta=b-a
    local length=delta:Dot(delta)
    return length<0.000001 and a or a+delta*math.Clamp((p-a):Dot(delta)/length,0,1)
end
function M.Triangle(p, a, b, c)
    local ab, ac, ap = b-a, c-a, p-a
    local d1, d2 = ab:Dot(ap), ac:Dot(ap)
    if d1 <= 0 and d2 <= 0 then return a end
    local bp = p-b
    local d3, d4 = ab:Dot(bp), ac:Dot(bp)
    if d3 >= 0 and d4 <= d3 then return b end
    local vc = d1*d4-d3*d2
    if vc <= 0 and d1 >= 0 and d3 <= 0 then return a+ab*(d1/(d1-d3)) end
    local cp = p-c
    local d5, d6 = ab:Dot(cp), ac:Dot(cp)
    if d6 >= 0 and d5 <= d6 then return c end
    local vb = d5*d2-d1*d6
    if vb <= 0 and d2 >= 0 and d6 <= 0 then return a+ac*(d2/(d2-d6)) end
    local va = d3*d6-d5*d4
    if va <= 0 and d4-d3 >= 0 and d5-d6 >= 0 then return b+(c-b)*((d4-d3)/((d4-d3)+(d5-d6))) end
    local sum = va+vb+vc
    if math.abs(sum) < 0.000001 then return a end
    return a+ab*(vb/sum)+ac*(vc/sum)
end
function M.Throw(history, now, scale)
    local v, spin, weight = Vector(), Vector(), 0
    for i = #history, 1, -1 do
        local sample = history[i]
        local age = now-sample.time
        if age > 0.12 then break end
        if age >= 0 and sample.pose.valid then
            local w = math.max(0.05, 1-age/0.12)
            v, spin, weight = v+(sample.pose.wvel or sample.pose.vel)*w, spin+sample.pose.angvel*w, weight+w
        end
    end
    if weight == 0 then return v, spin end
    return M.Limit(v/weight, scale*25), M.Limit(spin/weight, 30)
end
-- localPos/localAng are the controller pose expressed in the physics bone's frame.
function M.HeldTransform(localPos, localAng, pos, ang)
    local inversePos, inverseAng = WorldToLocal(Vector(), Angle(), localPos, localAng)
    return LocalToWorld(inversePos, inverseAng, pos, ang)
end
function M.TwoHand(a, b, pa, pb, up)
    if (b-a):Length() < 0.5 or (pb-pa):Length() < 0.5 then return end
    local localLine,worldLine=M.Unit(b-a),M.Unit(pb-pa)
    local localUp=math.abs(localLine.z)>0.98 and Vector(0,1,0) or Vector(0,0,1)
    if math.abs(worldLine:Dot(M.Unit(up)))>0.98 then up=math.abs(worldLine.z)>0.98 and Vector(0,1,0) or Vector(0,0,1) end
    local localFrame = (b-a):AngleEx(localUp)
    local worldFrame = (pb-pa):AngleEx(up)
    local _, inverse = WorldToLocal(Vector(), Angle(), Vector(), localFrame)
    local _, rotation = LocalToWorld(Vector(), inverse, Vector(), worldFrame)
    local offset = LocalToWorld((a+b)*0.5, Angle(), Vector(), rotation)
    return (pa+pb)*0.5-offset, rotation
end
function M.Flick(start, current, velocity, body, scale)
    local toward = M.Unit(body-start)
    return velocity:Dot(toward) >= scale*0.85 and (current-start):Dot(toward) >= scale*0.075
end
function M.Arc(start, destination, seconds, gravity)
    return (destination-start)/seconds-gravity*(seconds*0.5)
end
function M.Climb(origin, feet, hands, anchors, maxDelta)
    local error, count = Vector(), 0
    for hand, anchor in pairs(anchors) do
        local pose = hands[hand]
        if pose and pose.valid then error, count = error+anchor-(origin+pose.pos-feet), count+1 end
    end
    return count > 0 and M.Limit(error/count, maxDelta) or Vector(), count
end
function M.ClimbRelative(origin, head, hands, anchors, references, maxDelta)
    local error,count=Vector(),0
    if not head or not head.valid then return error,count end
    for hand,anchor in pairs(anchors) do
        local pose=hands[hand]
        if pose and pose.valid then
            local relative=pose.pos-head.pos
            local reference=references[hand]
            if not reference or reference.anchor~=anchor then
                reference={anchor=anchor,offset=anchor-origin-relative} references[hand]=reference
            end
            error,count=error+anchor-origin-relative-reference.offset,count+1
        end
    end
    for hand in pairs(references) do if not anchors[hand] then references[hand]=nil end end
    return count>0 and M.Limit(error/count,maxDelta) or Vector(),count
end
function M.Damage(speed, scale, held)
    local metres = speed/scale
    -- The legacy two-argument API retains its original curve for weapon callers.
    -- Physical bare hands always pass false explicitly from A.Hit.
    return metres < 1.5 and 0 or math.min(held ~= false and 65 or 25, 5+(metres-1.5)*12)
end
return M
