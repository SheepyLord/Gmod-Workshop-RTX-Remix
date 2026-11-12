; A stand-in for shaderapidx9.dll's Color3f, Color3fv, Color4f and Color4fv, for the colour cap's end-to-end test
; (ADR 0190). Each has the shape the colour cap looks for, as the game's have: 255.0 loaded rip-relative, each
; component converted with cvttss2si and its low byte kept (so 1.5 gives 7Eh), packed as D3DCOLOR (A, R, G, B),
; then IDirect3DDevice9::SetRenderState(D3DRS_TEXTUREFACTOR = 3Ch, colour) through the device's vtable (+1C8h).
; The 3-component ones set alpha to FFh themselves; the vector ones read through rdx; Color4f takes alpha from
; the stack. Each ends with ret and int3 padding. rcx is the API object (unused here); nl_fake_device is the device.
EXTERN nl_fake_device:QWORD

.const
ALIGN 4
scale255 REAL4 255.0

.code

; Low byte of cvttss2si(xmm * 255) into ebx's low byte, after shifting ebx left by 8.
PUBLIC nl_fake_colour3f
PUBLIC nl_fake_colour3fv
PUBLIC nl_fake_colour4f
PUBLIC nl_fake_colour4fv

ALIGN 16
nl_fake_colour3f PROC                  ; (this, r = xmm1, g = xmm2, b = xmm3)
    push rbx
    sub rsp, 20h
    movss xmm0, dword ptr [scale255]
    mulss xmm1, xmm0
    mulss xmm2, xmm0
    mulss xmm3, xmm0
    cvttss2si eax, xmm1
    movzx ebx, al
    shl ebx, 8
    cvttss2si eax, xmm2
    movzx eax, al
    or ebx, eax
    shl ebx, 8
    cvttss2si eax, xmm3
    movzx eax, al
    or ebx, eax
    or ebx, 0FF000000h
    mov rcx, qword ptr [nl_fake_device]
    mov r8d, ebx
    mov edx, 3Ch
    mov rax, qword ptr [rcx]
    call qword ptr [rax+1C8h]
    add rsp, 20h
    pop rbx
    ret
    int 3
    int 3
nl_fake_colour3f ENDP

ALIGN 16
nl_fake_colour3fv PROC                 ; (this, const float* rgb = rdx)
    push rbx
    sub rsp, 20h
    movss xmm3, dword ptr [scale255]
    movss xmm0, dword ptr [rdx]
    mulss xmm0, xmm3
    cvttss2si eax, xmm0
    movzx ebx, al
    shl ebx, 8
    movss xmm0, dword ptr [rdx+4]
    mulss xmm0, xmm3
    cvttss2si eax, xmm0
    movzx eax, al
    or ebx, eax
    shl ebx, 8
    movss xmm0, dword ptr [rdx+8]
    mulss xmm0, xmm3
    cvttss2si eax, xmm0
    movzx eax, al
    or ebx, eax
    or ebx, 0FF000000h
    mov rcx, qword ptr [nl_fake_device]
    mov r8d, ebx
    mov edx, 3Ch
    mov rax, qword ptr [rcx]
    call qword ptr [rax+1C8h]
    add rsp, 20h
    pop rbx
    ret
    int 3
    int 3
nl_fake_colour3fv ENDP

ALIGN 16
nl_fake_colour4f PROC                  ; (this, r = xmm1, g = xmm2, b = xmm3, a = [rsp+28h] at entry)
    push rbx
    sub rsp, 20h
    movss xmm4, dword ptr [scale255]
    movss xmm0, dword ptr [rsp+50h]
    mulss xmm0, xmm4
    cvttss2si eax, xmm0
    movzx ebx, al
    shl ebx, 8
    mulss xmm1, xmm4
    cvttss2si eax, xmm1
    movzx eax, al
    or ebx, eax
    shl ebx, 8
    mulss xmm2, xmm4
    cvttss2si eax, xmm2
    movzx eax, al
    or ebx, eax
    shl ebx, 8
    mulss xmm3, xmm4
    cvttss2si eax, xmm3
    movzx eax, al
    or ebx, eax
    mov rcx, qword ptr [nl_fake_device]
    mov r8d, ebx
    mov edx, 3Ch
    mov rax, qword ptr [rcx]
    call qword ptr [rax+1C8h]
    add rsp, 20h
    pop rbx
    ret
    int 3
    int 3
nl_fake_colour4f ENDP

ALIGN 16
nl_fake_colour4fv PROC                 ; (this, const float* rgba = rdx)
    push rbx
    sub rsp, 20h
    movss xmm3, dword ptr [scale255]
    movss xmm0, dword ptr [rdx+0Ch]
    mulss xmm0, xmm3
    cvttss2si eax, xmm0
    movzx ebx, al
    shl ebx, 8
    movss xmm0, dword ptr [rdx]
    mulss xmm0, xmm3
    cvttss2si eax, xmm0
    movzx eax, al
    or ebx, eax
    shl ebx, 8
    movss xmm0, dword ptr [rdx+4]
    mulss xmm0, xmm3
    cvttss2si eax, xmm0
    movzx eax, al
    or ebx, eax
    shl ebx, 8
    movss xmm0, dword ptr [rdx+8]
    mulss xmm0, xmm3
    cvttss2si eax, xmm0
    movzx eax, al
    or ebx, eax
    mov rcx, qword ptr [nl_fake_device]
    mov r8d, ebx
    mov edx, 3Ch
    mov rax, qword ptr [rcx]
    call qword ptr [rax+1C8h]
    add rsp, 20h
    pop rbx
    ret
    int 3
    int 3
nl_fake_colour4fv ENDP
END
