-- Independent affine matrix stand-in for C's joint-roll tests.
return function()
    local M={} M.__index=M
    function Matrix(other)
        local m=setmetatable({},M)
        for i=1,4 do m[i]={} for j=1,4 do m[i][j]=other and other[i][j] or (i==j and 1 or 0) end end
        return m
    end
    function M:SetTranslation(v) self[1][4],self[2][4],self[3][4]=v.x,v.y,v.z end
    function M:GetTranslation() return Vector(self[1][4],self[2][4],self[3][4]) end
    function M:SetAngles(a) local axes={a:Forward(),-a:Right(),a:Up()} for j,v in ipairs(axes) do self[1][j],self[2][j],self[3][j]=v.x,v.y,v.z end end
    function M:GetAngles() return Angle() end -- the authored fixture bones have identity rotation
    function M:Scale(v) for i=1,3 do self[i][1],self[i][2],self[i][3]=self[i][1]*v.x,self[i][2]*v.y,self[i][3]*v.z end end
    function M:GetInverse()
        local m=Matrix() for i=1,3 do for j=1,3 do m[i][j]=self[j][i] end end
        for i=1,3 do m[i][4]=0 for j=1,3 do m[i][4]=m[i][4]-m[i][j]*self[j][4] end end
        return m
    end
    M.__mul=function(a,b)
        if getmetatable(b)==getmetatable(Vector()) then return Vector(a[1][1]*b.x+a[1][2]*b.y+a[1][3]*b.z+a[1][4],a[2][1]*b.x+a[2][2]*b.y+a[2][3]*b.z+a[2][4],a[3][1]*b.x+a[3][2]*b.y+a[3][3]*b.z+a[3][4]) end
        local c=Matrix() for i=1,4 do for j=1,4 do c[i][j]=0 for k=1,4 do c[i][j]=c[i][j]+a[i][k]*b[k][j] end end end
        return c
    end
end
