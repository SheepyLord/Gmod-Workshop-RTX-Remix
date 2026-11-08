; A stand-in for materialsystem.dll's call site, for the engine guard's end-to-end test (ADR 0130):
; exact bytes in the code segment (a C++ array went to .rdata), so the guard's scan of executable
; sections finds them. const char* nl_fake_initialize(void* key_values, void* material) returns what
; the call site got. Offsets: 12h the 36-byte pattern, 23h its call (its displacement at 24h is 4-byte
; aligned, as the game's is), 49h GetString, 51h "", 52h "$fallbackmaterial",
; 64h mov rax,[r14]; mov rcx,r14; call [rax] (the loop's GetName call the guard also requires).
.code
PUBLIC nl_fake_initialize
ALIGN 16
nl_fake_initialize PROC
    db 041h, 055h                                    ; 00 push r13
    db 041h, 056h                                    ; 02 push r14
    db 041h, 054h                                    ; 04 push r12
    db 057h                                          ; 06 push rdi
    db 048h, 083h, 0ECh, 048h                        ; 07 sub rsp, 48h (rsp 16-aligned at the call)
    db 049h, 089h, 0CDh                              ; 0B mov r13, rcx (the key values)
    db 049h, 089h, 0D6h                              ; 0E mov r14, rdx (the material)
    db 090h                                          ; 11 nop (aligns the call's displacement)
    db 04Ch, 08Dh, 005h, 038h, 000h, 000h, 000h      ; 12 lea r8, [rip+38h] -> 51h ""
    db 049h, 08Bh, 0CDh                              ; 19 mov rcx, r13
    db 048h, 08Dh, 015h, 02Fh, 000h, 000h, 000h      ; 1C lea rdx, [rip+2Fh] -> 52h "$fallbackmaterial"
    db 0E8h, 021h, 000h, 000h, 000h                  ; 23 call 49h (GetString)
    db 08Bh, 07Ch, 024h, 040h                        ; 28 mov edi, [rsp+40h]
    db 044h, 08Bh, 064h, 024h, 044h                  ; 2C mov r12d, [rsp+44h]
    db 080h, 038h, 000h                              ; 31 cmp byte ptr [rax], 0
    db 00Fh, 084h, 000h, 000h, 000h, 000h            ; 34 je 3Ah
    db 048h, 083h, 0C4h, 048h                        ; 3A add rsp, 48h
    db 05Fh                                          ; 3E pop rdi
    db 041h, 05Ch                                    ; 3F pop r12
    db 041h, 05Eh                                    ; 41 pop r14
    db 041h, 05Dh                                    ; 43 pop r13
    db 0C3h                                          ; 45 ret
    db 0CCh, 0CCh, 0CCh                              ; 46
    db 048h, 08Bh, 001h                              ; 49 GetString: mov rax, [rcx]
    db 0C3h                                          ; 4C ret
    db 0CCh, 0CCh, 0CCh, 0CCh                        ; 4D
    db 000h                                          ; 51 ""
    db '$fallbackmaterial', 000h                     ; 52
    db 049h, 08Bh, 006h, 049h, 08Bh, 0CEh, 0FFh, 010h ; 64 the loop's GetName call on r14 (never run here)
nl_fake_initialize ENDP
END
