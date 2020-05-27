;.686
;.XMM

LOGPREC EQU (8+12)

EXTERN _gi
EXTERN _gpixy
EXTERN _gixy     ;long[2]
EXTERN _gpz      ;long[2]
EXTERN _gdz      ;long[2]
EXTERN _gxmip
EXTERN _gxmax
EXTERN _gcsub    ;long[4]
EXTERN _gylookup ;long[256+4+128+4+...]
EXTERN _gmipnum
;EXTERN _cf : dd      ;{ long i0,i1,z0,z1,cx0,cy0,cx1,cy1; }[128]

EXTERN _sptr

EXTERN _skyoff   ;Memory offset to start of longitude line
EXTERN _skyxsiz  ;Size of longitude line
EXTERN _skylat   ;long[_skyxsiz] : latitude's unit dir. vector

;How to declare C-ASM shared variables in the ASM code:
;ASM:                    C:
;   PUBLIC _xr0             extern void *xr0;
;   ALIGN 16                #define lxr0 ((long *)&xr0)
;   _xr0: dd 0,0,0,0        #define fxr0 ((float *)&xr0)
;   Use: _xr0               Use: lxr0[0-3]  or:  fxr0[0-3]

;EXTERN _reax: dd
;EXTERN _rebx: dd
;EXTERN _recx: dd
;EXTERN _redx: dd
;EXTERN _resi: dd
;EXTERN _redi: dd
;EXTERN _rebp: dd
;EXTERN _resp: dd
;EXTERN _remm: dd  ;long[16]

;CODE SEGMENT PUBLIC USE32 'CODE'
;ASSUME cs:CODE,ds:CODE

;PUBLIC _v5_asm_dep_unlock ;Data Execution Prevention unlock (works under XP2 SP2)
_v5_asm_dep_unlock:
	EXTERN __imp__VirtualProtect@16
	sub esp, 4
	push esp
	push 40h ;PAGE_EXECUTE_READWRITE
	
	;push offset _dep_protect_end - offset _v5_asm_dep_unlock
	mov eax, _dep_protect_end
	sub eax, _v5_asm_dep_unlock
	push eax
	
	push _v5_asm_dep_unlock
	call __imp__VirtualProtect@16
	add esp, 4
	ret

;PUBLIC _cfasm, _skycast
ALIGN 16
_cfasm: TIMES 256*32 db 0
w8bmask0 dq 000ff00ff00ff00ffh
w8bmask1 dq 000f000f000f000f0h
w8bmask2 dq 000e000e000e000e0h
;gyadd dq ((-1) SHL (LOGPREC-16))
mmask dq 0ffff0000ffff0000h
_skycast dq 0
gylookoff dd 0
ngxmax dd 0
ce dd 0
espbak dd 0
gylut  dd _gylookup            ,_gylookup+(4*1+256)*4,_gylookup+(4*2+384)*4
		 dd _gylookup+(4*3+448)*4,_gylookup+(4*4+480)*4,_gylookup+(4*5+496)*4
		 dd _gylookup+(4*6+504)*4,_gylookup+(4*7+508)*4,_gylookup+(4*8+510)*4
gxmipk dd 7feh,3feh,1feh,0feh,7eh,3eh,1eh,0eh,6h
gymipk dd 3ff000h,0ff800h,3fc00h,0fe00h,3f00h,0f80h,3c0h,0e0h,30h
gamipk dd _sptr
		 dd _sptr+(1024*1024)*4
		 dd _sptr+(1024*1024+512*512)*4
		 dd _sptr+(1024*1024+512*512+256*256)*4
		 dd _sptr+(1024*1024+512*512+256*256+128*128)*4
		 dd _sptr+(1024*1024+512*512+256*256+128*128+64*64)*4
		 dd _sptr+(1024*1024+512*512+256*256+128*128+64*64+32*32)*4
		 dd _sptr+(1024*1024+512*512+256*256+128*128+64*64+32*32+16*16)*4
		 dd _sptr+(1024*1024+512*512+256*256+128*128+64*64+32*32+16*16+8*8)*4
gmipcnt db 0
ALIGN 16

	;THE INNER LOOP:
	;#ifdef CPU <= PENTIUM II
	;
	;   movd mm3, _gylookup[ecx*4] ;mm3: [ 0   0   0  -gy]
	;   por mm3, mm6               ;mm3: [ogx  0   gx -gy]
	;      or:
	;   paddd mm3, gyadd           ;where: gyadd: dq ((-1) SHL (LOGPREC-16))
	;
	;   ...
	;
	;   movq mm7, mm0           ;mm7: [cy0.... cx0....]
	;   psrad mm7, 16           ;mm7: [----cy0 ----cx0]
	;   packssdw mm7, mm7       ;mm7: [cy0 cx0 cy0 cx0]
	;   pmaddwd mm7, mm3           ;mm7: [ 0   0  -decide]
	;   movd eax, mm7
	;   test eax, eax
	;   j ?
	;   ...
	;   paddd mm0, _gi
	;
	;#else
	;      ;Do this only when gx/ogx changes
	;   movd mm3, ogx                   ;mm3: [ 0   0  ogx  0 ]
	;      or:
	;   pshufw mm3, mm3, 0e8h            ;mm3: [ gx ogx ogx  0 ]
	;
	;      ;Do this only when ecx/edx changes
	;   pinsrw mm3, _gylookup[ecx*2], 0 ;mm3: [ 0   0  ogx -gy]
	;      or:
	;   paddd mm3, gyadd                ;where: gyadd: dq (1 SHL LOGPREC)
	;
	;   ...
	;
	;   pshufw mm7, mm0, 0ddh      ;mm7: [cy0 cx0 cy0 cx0]
	;   pmaddwd mm7, mm3           ;mm7: [ 0   0  -decide]
	;   movd eax, mm7
	;   test eax, eax
	;   j ?
	;   ...
	;   paddd mm0, _gi
	;
	;#endif


	;   Register allocation:
	;eax: [.temp1.]     mm0: [cy0.... cx0....]
	;ebx: [.temp2.]     mm1: [cy1.... cx1....]
	;ecx: [.....z0]     mm2: [    temp!!!    ]   //gi[1].. gi[0]..]
	;edx: [.....z1]     mm3: [     temp      ]
	;esi: [..ixy..]     mm4: [??????? csub...]
	;edi: [..v[]..]     mm5: [??????? coltemp]
	;ebp: [...bakj]     mm6: [gx. 0.. ogx 0..]
	;esp: [..c->..]     mm7: [     temp      ]
;PUBLIC _grouscanasm ;Visual C entry point (passes parameters by stack)
_grouscanasm:
	mov eax, [esp+4]
	push ebx   ;Visual C's _cdecl requires EBX,ESI,EDI,EBP to be preserved
	push esi
	push edi
	push ebp
	mov [espbak], esp

	mov edi, eax

		;cfasm:   0-2047  (extra memory for stack)
		;      2048-4095  c and ce always sit in this range ((esp = c) <= ce)
		;      4096-6143  This is where memory for cfasm is actually stored!
		;      6144-8191  (memory never used - this seems unnecessary?)
	mov esp, [_cfasm + 2048]
	mov eax, [_cfasm + 4096]
	mov ecx, [eax+8]
	mov edx, [eax+12]
	movq mm0, [eax+16]
	movq mm1, [eax+24]
	mov [ce], esp

	mov [gylookoff], [_gylookup]
	mov [gmipcnt], 0

	mov ebp, _gxmax
	cmp [_gmipnum], 1
	jle short skipngxmax0
	cmp ebp, _gxmip
	jle short skipngxmax0
	mov ebp, _gxmip
skipngxmax0:
	mov ngxmax, ebp

	mov ebp, [_gpz + 4]
	sub ebp, [_gpz + 0]
	shr ebp, 31
	movd mm6, [_gpz + ebp*4]        ;update gx in mm6
	pand mm6, [mmask]
	mov eax, [_gdz + ebp*4]
	add [_gpz + ebp*4], eax

	mov esi, _gpixy
	cmp edi, [esi]
	je drawflor
	jmp drawceil

drawfwall:
	movzx eax, [edi+1]
	cmp eax, edx
	jge drawcwall
	mov ebx, [esp+4+2048]
loop0:
	neg eax
	add eax, edx
	dec edx
	punpcklbw mm5, [edi+eax*4]
	mov eax, gylookoff
	movd mm3, [eax+edx*4] ;mm3: [ 0   0   0  -gy]
	psubusb mm5, mm4
	pshufw mm2, mm5, 0ffh
	pmulhuw mm5, mm2
	psrlw mm5, 7
	packuswb mm5, mm5
	punpckldq mm5, mm6         ;Stuff ogx into hi part of color for Z buffer
	por mm3, mm6               ;mm3: [ gx  0  ogx -gy]
loop1: ;if (dmulrethigh(gylookup[edx*4],c->cx1,c->cy1,ogx) >= 0) jmp endloop1
	pshufw mm7, mm1, 0ddh      ;mm7: [cy1 cx1 cy1 cx1]
	pmaddwd mm7, mm3           ;mm7: [ 0   0  -decide]
	movd eax, mm7
	test eax, eax              ;if (cy1*ogx ? gy*cx1)
	jle endloop1
	psubd mm1, [_gi]
	movntq [ebx], mm5
	sub ebx, 8
	cmp ebx, [esp+2048]
	jnb loop1
	jmp predeletez
endloop1:
	movzx eax, [edi+1]
	cmp eax, edx
	jne loop0
	mov [esp+4+2048], ebx

drawcwall:
	cmp edi, [esi]
	mov edx, eax
	je predrawflor

	movzx eax, [edi+3]
	cmp eax, ecx
	jle predrawceil
	mov ebx, [esp+2048]
loop2:
	neg eax
	add eax, ecx
	inc ecx
	punpcklbw mm5, [edi+eax*4]
	mov eax, gylookoff
	movd mm3, [eax+ecx*4] ;mm3: [ 0   0   0  -gy]
	psubusb mm5, mm4
	pshufw mm2, mm5, 0ffh
	pmulhuw mm5, mm2
	psrlw mm5, 7
	packuswb mm5, mm5
	punpckldq mm5, mm6         ;Stuff ogx into hi part of color for Z buffer
	por mm3, mm6               ;mm3: [ gx  0  ogx -gy]
loop3: ;if (dmulrethigh(gylookup[ecx*4],c->cx0,c->cy0,ogx) < 0) jmp endloop3
	pshufw mm7, mm0, 0ddh      ;mm7: [cy0 cx0 cy0 cx0]
	pmaddwd mm7, mm3           ;mm7: [ 0   0  -decide]
	movd eax, mm7
	test eax, eax              ;if (cy0*ogx ? gy*cx0)
	jg endloop3
	paddd mm0, [_gi]
	movntq [ebx], mm5
	add ebx, 8
	cmp ebx, [esp+4+2048]
	jna loop3
	jmp predeletez
endloop3:
	movzx eax, [edi+3]
	cmp eax, ecx
	jne loop2
	mov [esp+2048], ebx

predrawceil:
	mov ecx, eax
	pshufw mm6, mm6, 04eh       ;swap hi & lo of mm6
drawceil: ;if (dmulrethigh(gylookup[ecx*4],c->cx0,c->cy0,gx) < 0) jmp drawflor
	mov eax, gylookoff
	movd mm3, [eax+ecx*4] ;mm3: [ 0   0   0  -gy]
	por mm3, mm6               ;mm3: [ogx  0   gx -gy]
drawceilloop:
	pshufw mm7, mm0, 0ddh      ;mm7: [cy0 cx0 cy0 cx0]
	pmaddwd mm7, mm3           ;mm7: [ 0   0  -decide]
	movd eax, mm7
	test eax, eax              ;if (cy0*gx ? gy*cx0)
	jg drawflor
	paddd mm0, [_gi]
	mov eax, [esp+2048]

	punpcklbw mm5, [edi-4]
	psubusb mm5, [_gcsub + 16]
	pshufw mm2, mm5, 0ffh
	pmulhuw mm5, mm2
	psrlw mm5, 7
	packuswb mm5, mm5
	punpckldq mm5, mm6         ;Stuff gx into hi part of color for Z buffer
	movntq [eax], mm5
	add eax, 8
	mov [esp+2048], eax
	cmp eax, [esp+4+2048]
	jna drawceilloop
	jmp deletez

predrawflor:
	pshufw mm6, mm6, 04eh       ;swap hi & lo of mm6
drawflor: ;if (dmulrethigh(gylookup[edx*4],c->cx1,c->cy1,gx) >= 0) jmp enddrawflor
	mov eax, gylookoff
	movd mm3, [eax+edx*4] ;mm3: [ 0   0   0  -gy]
	por mm3, mm6               ;mm3: [ogx  0   gx -gy]
drawflorloop:
	pshufw mm7, mm1, 0ddh      ;mm7: [cy1 cx1 cy1 cx1]
	pmaddwd mm7, mm3           ;mm7: [ 0   0  -decide]
	movd eax, mm7
	test eax, eax              ;if (cy1*gx ? gy*cx1)
	jle enddrawflor
	psubd mm1, [_gi]
	mov eax, [esp+4+2048]

	punpcklbw mm5, [edi+4]
	psubusb mm5, [_gcsub + 24]
	pshufw mm2, mm5, 0ffh
	pmulhuw mm5, mm2
	psrlw mm5, 7
	packuswb mm5, mm5
	punpckldq mm5, mm6         ;Stuff gx into hi part of color for Z buffer
	movntq [eax], mm5
	sub eax, 8
	mov [esp+4+2048], eax
	cmp eax, [esp+2048]
	jnb drawflorloop
	jmp deletez

enddrawflor:
	mov ebx, esp
afterdelete:
	sub esp, 32
	cmp esp, [_cfasm + 2048]
	jae skipixy

	movq mm4, [_gcsub + ebp*8]
	add esi, [_gixy + ebp*4]
	mov ebp, [_gpz + 4]
	mov edi, [esi]
	sub ebp, [_gpz + 0]
	shr ebp, 31
	mov eax, [_gpz + ebp*4]
	movd mm7, eax
	punpckldq mm6, mm7
	pand mm6, [mmask]
	cmp eax, ngxmax
	ja remiporend
	add eax, [_gdz + ebp*4]
	mov [_gpz + ebp*4], eax
	mov esp, ce
	jmp skipixy2

skipixy:
	pshufw mm6, mm6, 04eh       ;swap hi & lo of mm6
skipixy2:
	cmp ebx, esp
	je skipixy3
	add ebx, 2048
	mov [ebx+8], ecx
	mov [ebx+12], edx
	movq [ebx+16], mm0
	movq [ebx+24], mm1
	lea ebx, [esp+2048]
	mov ecx, [ebx+8]
	mov edx, [ebx+12]
	movq mm0, [ebx+16]
	movq mm1, [ebx+24]
skipixy3:

		;Find highest intersecting vbuf slab
	cmp [edi], 0
	je drawfwall
	mov ebx, gylookoff
	jmp intoslabloop
findslabloop:
	lea edi, [edi+eax*4]
	cmp [edi], 0
	je drawfwall
intoslabloop:
	movzx eax, [edi+2]
		;if (dmulrethigh(gylookup[[edi+2]*4+4],c->cx0,c->cy0,ogx) >= 0)
		;   jmp findslabloopbreak
	movd mm3, [ebx+eax*4+4]    ;mm3: [ 0   0   0  -gy]
	por mm3, mm6               ;mm3: [ gx  0  ogx -gy]
	pshufw mm7, mm0, 0ddh      ;mm7: [cy0 cx0 cy0 cx0]
	pmaddwd mm7, mm3           ;mm7: [ 0   0  -decide]
	movd eax, mm7
	test eax, eax              ;if (cy0*ogx ? ?y*cx0)

	movzx eax, [edi]
	jg findslabloop

		;If next slab ALSO intersects, split _cfasm!
		;if (dmulrethigh(v[v[0]*4+3],c->cx1,c->cy1,ogx) >= 0) jmp drawfwall
	movzx eax, [3+edi+eax*4]
	movd mm3, [ebx+eax*4]      ;mm3: [ 0   0   0  -gy]
	por mm3, mm6               ;mm3: [ gx  0  ogx -gy]
	pshufw mm7, mm1, 0ddh      ;mm7: [cy1 cx1 cy1 cx1]
	pmaddwd mm7, mm3           ;mm7: [ 0   0  -decide]
	movd eax, mm7
	test eax, eax              ;if (cy1*ogx ? ?y*cx1)
	jle drawfwall


		;Make sure everything is in memory at this point
	lea eax, [esp+2048]
	mov [eax+8], ecx
	mov [eax+12], edx
	movq [eax+16], mm0
	movq [eax+24], mm1

		;(ecx and edx are free registers at this point)

	mov edx, [eax+4]             ;col = (long)c->i1;
	movzx eax, [edi+2]  ;dax = c->cx1; day = c->cy1;
	movd mm3, [ebx+eax*4+4]      ;mm3: [ 0   0   0  -gy]
	por mm3, mm6                 ;mm3: [ gx  0  ogx -gy]

		;WARNING: NEW CODE!!!!!!!
prebegsearchi16:
	movq mm7, [_gi]
	pslld mm7, 4
	movq mm5, mm1
	psubd mm5, mm7             ;mm7: [day.... dax....]
	pshufw mm7, mm5, 0ddh      ;mm7: [day dax day dax]
	pmaddwd mm7, mm3           ;mm7: [ 0   0  -decide]
	movd eax, mm7
	test eax, eax              ;if (day*ogx ? gy*dax)
	jle begsearchi
	movq mm1, mm5
	sub edx, 16 << 3
	jmp prebegsearchi16

	jmp begsearchi
		;while (dmulrethigh(gylookup[v[2]+1],dax,day,ogx) < 0)
prebegsearchi:
	sub edx, 4 << 1             ;col -= 8;
	psubd mm1, [_gi]     ;dax -= gi[0]; day -= gi[1];
begsearchi:
	pshufw mm7, mm1, 0ddh      ;mm7: [day dax day dax]
	pmaddwd mm7, mm3           ;mm7: [ 0   0  -decide]
	movd eax, mm7
	test eax, eax              ;if (day*ogx ? gy*dax)
	jg prebegsearchi

	mov eax, ce            ;ce++;
	add eax, 32

	cmp eax, [_cfasm + 4096] ;VERY BAD!!! - Interrupt would overwrite data!
	ja retsub                    ;Just in case, return early to prevent lockup.

	mov [ce], eax
	cmp eax, esp           ;for(c2=ce;c2>c;c2--)   //(c2 = eax)
	jbe skipinsertloop
beginsertloop:
	movq mm5, [eax-32+24+2048]  ;c2[0] = c2[-1];
	movq mm7, [eax-32+16+2048]
	movq [eax+24+2048], mm5
	movq [eax+16+2048], mm7
	movq mm5, [eax-32+8+2048]
	movq mm7, [eax-32+0+2048]
	movq [eax+8+2048], mm5
	movq [eax+0+2048], mm7
	sub eax, 32
	cmp eax, esp
	ja beginsertloop
skipinsertloop:

	movzx eax, [edi]
	movq mm7, mm1              ;c[1].cx1 = dax; c[1].cy1 = day;
	paddd mm7, [_gi]
	movzx eax, [3+edi+eax*4]
	mov [esp+32+4+2048], edx        ;c[1].i1 = (long *)col;
	add edx, 8                      ;c[0].i0 = (long *)(col+(4<<1));
	mov [esp+2048], edx
	mov edx, eax               ;c[1].z1 = c[0].z0 = v[(v[0]<<2)+3];
	mov [esp+8+2048], eax
	movq [esp+16+2048], mm7         ;c[0].cx0 = dax+gi[0]; c[0].cy0 = day+gi[1];
	add esp, 32                ;c++;
	jmp drawfwall

remiporend:
	mov al, gmipcnt
	inc al
	cmp al, [_gmipnum]
	jge startsky
	mov gmipcnt, al

	sub esi, _sptr

	mov eax, esi
	shl eax, 29
	xor eax, [_gixy+0]
	mov eax, [_gdz+0]
	js short skipbladd0
	add [_gpz+0], eax
skipbladd0:
	add eax, eax
	jno short skipremip0
	mov [_gpz+0], 7fffffffh
	xor eax, eax
skipremip0:
	mov [_gdz+0], eax

	mov [ebx+8+2048], ecx ;this is the official place to backup ecx

	mov eax, esi
	mov cl, [gmipcnt]
	add cl, 18
	shl eax, cl
	xor eax, [_gixy+4]
	mov eax, [_gdz+4]
	js short skipbladd1
	add [_gpz+4], eax
skipbladd1:
	add eax, eax
	jno short skipremip1
	mov [_gpz+4], 7fffffffh
	xor eax, eax
skipremip1:
	mov [_gdz+4], eax

	shr esi, 2
	mov eax, esi
	movzx ecx, [gmipcnt]
	and esi, [gxmipk+ecx*4] ;mask for x (1:1024->512, etc...)
	and eax, [gymipk+ecx*4] ;mask for y (1:1024->512, etc...)
	lea esi, [eax+esi*2]
	add esi, [gamipk+ecx*4] ;add offset (1:sptr+1024*1024*4, etc...)

	movzx eax, [gmipcnt]
	mov eax, [gylut+eax*4]
	mov gylookoff, eax

	sar [_gixy+4], 1

	mov eax, [_cfasm+2048]
startremip0:
	shr [eax+8+2048], 1
	inc [eax+12+2048]
	shr [eax+12+2048], 1
	add eax, 32
	cmp eax, ce
	jbe short startremip0

	mov eax, ngxmax
	cmp eax, _gxmax
	jae short startsky
	add eax, eax
	jo skipngxmax1 ;Make sure it doesn't overflow to negative!
	cmp eax, _gxmax
	jl short skipngxmax2
skipngxmax1:
	mov eax, _gxmax
skipngxmax2:
	mov ngxmax, eax

		;register fix-ups after here:
	mov ecx, [ebx+8+2048] ;this is the official place to restore ecx
	shr ecx, 1
	inc edx
	shr edx, 1

		;this makes grid transition clean
	mov ebp, [_gpz+4]
	sub ebp, [_gpz+0]
	shr ebp, 31
	mov eax, [_gpz+ebp*4]
	add eax, [_gdz+ebp*4]
	mov [_gpz+ebp*4], eax
	mov edi, [esi]

	mov esp, ce
	jmp skipixy2

startsky:
	mov esp, [_cfasm+2048]
	cmp esp, ce
	ja retsub
	mov esi, _skyoff
	test esi, esi
	jnz short prestartskyloop

;Sky not loaded, so fill with black ------------------------------------------
endprebegloop:
	movq mm5, _skycast
	mov eax, [esp+2048]
	mov ebx, [esp+4+2048]
	cmp eax, ebx
	ja short endnextloop
endbegloop:
	movntq [eax], mm5
	add eax, 8
	cmp eax, ebx
	jbe short endbegloop
endnextloop:
	add esp, 32
	cmp esp, ce
	jbe short endprebegloop
	jmp short retsub

;Sky loaded: do texture mapping ----------------------------------------------

prestartskyloop:
	movq [ebx+24+2048], mm1  ;Hack to make sure [cy0,cx0] is in memory for sky

	mov esi, _skyoff
	mov ecx, _skylat
	movd mm5, [_skycast+4]
	mov edi, _skyxsiz
startskyloop:
	mov eax, [esp+2048]
	mov ebx, [esp+4+2048]
	cmp eax, ebx
	ja short endskyslab
	movq mm1, [esp+24+2048]    ;mm1: [cy1.... cx1....]
preskysearch:
	psubd mm1, [_gi]
skysearch:
	pshufw mm7, mm1, 0ddh      ;mm7: [cy1 cx1 cy1 cx1]
	movd mm3, [ecx+edi*4]      ;mm3: [       xvi -yvi]
	pmaddwd mm7, mm3           ;mm7: [ 0   0  -decide]
	movd edx, mm7
	sar edx, 31
	lea edi, [edi+edx]
	jnz short skysearch        ;if (cy1*xvi ? -yvi*cx1)

	movd mm6, [esi+edi*4]
	punpckldq mm6, mm5
	movntq [ebx], mm6
	sub ebx, 8
	cmp eax, ebx
	jbe short preskysearch
endskyslab:
	add esp, 32
	cmp esp, ce
	jbe short startskyloop

;-----------------------------------------------------------------------

retsub:
	emms
	mov esp, [espbak]
	pop ebp    ;Visual C's _cdecl requires EBX,ESI,EDI,EBP to be preserved
	pop edi
	pop esi
	pop ebx
	ret

predeletez:
	pshufw mm6, mm6, 04eh       ;swap hi & lo of mm6
deletez:
	mov ebx, ce
	sub ebx, 32
	cmp ebx, [_cfasm+2048]
	jb retsub          ;nothing to fill - skip remiporend stuff!
	mov [ce], ebx

	add ebx, 32

	cmp esp, ebx       ;while (eax <= ce)
	jae afterdelete
	mov eax, esp
deleteloop:
	movq mm5, [eax+32+0+2048]
	movq mm7, [eax+32+8+2048]
	movq [eax+0+2048], mm5
	movq [eax+8+2048], mm7
	movq mm5, [eax+32+16+2048]
	movq mm7, [eax+32+24+2048]
	movq [eax+16+2048], mm5
	movq [eax+24+2048], mm7
	add eax, 32
	cmp eax, ebx
	jb deleteloop
	jmp afterdelete

;debugret:
;   mov _reax, eax
;   mov _rebx, ebx
;   mov _recx, ecx
;   mov _redx, edx
;   mov _resi, esi
;   mov _redi, edi
;   mov _rebp, ebp
;   mov _resp, esp
;   movq _remm[0], mm0
;   movq _remm[8], mm1
;   movq _remm[16], mm2
;   movq _remm[24], mm3
;   movq _remm[32], mm4
;   movq _remm[40], mm5
;   movq _remm[48], mm6
;   movq _remm[56], mm7
;   emms
;   pop ebp
;   ret

;----------------------------------------------------------------------------

MAXZSIZ EQU 1024 ;WARNING: THIS IS BAD SINCE KV6 format supports up to 65535!

EXTERN _zbufoff
EXTERN _ptfaces16

;PUBLIC _opti4asm, _caddasm, _ztabasm, _scisdist, _kv6colmul, _kv6coladd
;PUBLIC _qsum0, _qsum1, _qbplbpp, _kv6frameplace, _kv6bytesperline

ALIGN 16
_opti4asm: TIMES 5*4 dd 0        ;NOTE: this used by ?render
_caddasm: TIMES 8*4 dd 0
_ztabasm: TIMES (MAXZSIZ+3)*4 dd 0
_scisdist: dd 40800000h,0,0,0
_kv6colmul: TIMES 256 dq 0
_kv6coladd: dq 0
_qsum0: dq 0   ;[8000h-hy,8000h-hx,8000h-hy,8000h-hx]
_qsum1: dq 0   ;[8000h-fy,8000h-fx,8000h-fy,8000h-fx]
_qbplbpp: dq 0 ;[0,0,bpl,bpp]
_kv6frameplace: dd 0
_kv6bytesperline: dd 0

;PUBLIC _drawboundcubesseinit   ;Visual C entry point (pass by stack)
_drawboundcubesseinit:
	mov eax, _kv6frameplace
	mov [bcmod0-4], eax
	mov eax, _kv6bytesperline
	mov [bcmod3-4], eax
	;mov eax, _kv6bytesperline
	mov [bcmod2-4], eax
	mov eax, _zbufoff
	mov [bcmod1-4], eax
	ret       ;Visual C's _cdecl requires EBX,ESI,EDI,EBP to be preserved

ALIGN 16
;PUBLIC _drawboundcubesse       ;Visual C entry point (pass by stack)
_drawboundcubesse:
	mov eax, [esp+4]
	mov ecx, [esp+8]
	push ebx   ;Visual C's _cdecl requires EBX,ESI,EDI,EBP to be preserved
	push edi

	movzx edi, [eax+6]
	and ecx, edi
	jz retboundcube

	movaps xmm7, [_ztabasm+MAXZSIZ*16]
	movzx edi, [eax+4]
	shl edi, 4
	addps xmm7, [_ztabasm+edi]
	movhlps xmm0, xmm7
	ucomiss xmm0, _scisdist
	jc retboundcube

	lea ecx, [_ptfaces16+ecx*8]

	movzx ebx, [ecx+1] ;                           �
	movzx edi, [ecx+2] ;                           �
	movaps xmm0, [_caddasm+ebx]  ;xmm0: [ z0, z0, y0, x0]    �
	addps xmm0, xmm7            ;                           �۱
	movaps xmm1, [_caddasm+edi]  ;xmm1: [ z1, z1, y1, x1]    �
	addps xmm1, xmm7            ;                           �۱
	movaps xmm6, xmm0           ;xmm6: [ z0, z0, y0, x0]    �
	movhlps xmm0, xmm1          ;xmm0: [ z0, z0, z1, z1]    �
	movlhps xmm1, xmm6          ;xmm1: [ y0, x0, y1, x1]    �
	rcpps xmm0, xmm0            ;xmm6: [/z0,/z0,/z1,/z1]    ��
	mulps xmm0, xmm1            ;xmm0: [sy0,sx0,sy1,sx1]    �۱�

	movzx ebx, [ecx+3] ;                           �
	movzx edi, [ecx+4] ;                           �
	movaps xmm2, [_caddasm+ebx]  ;xmm2: [ z2, z2, y2, x2]    �
	addps xmm2, xmm7            ;                           �۱
	movaps xmm3, [_caddasm+edi]  ;xmm3: [ z3, z3, y3, x3]    �
	addps xmm3, xmm7            ;                           �۱
	movaps xmm6, xmm2           ;xmm6: [ z2, z2, y2, x2]    �
	movhlps xmm2, xmm3          ;xmm2: [ z2, z2, z3, z3]    �
	movlhps xmm3, xmm6          ;xmm3: [ y2, x2, y3, x3]    �
	rcpps xmm2, xmm2            ;xmm6: [/z2,/z2,/z3,/z3]    ��
	mulps xmm2, xmm3            ;xmm2: [sy2,sx2,sy3,sx3]    �۱�

	cvttps2pi mm0, xmm0         ;                           �
	movhlps xmm0, xmm0          ;                           �
	cvttps2pi mm2, xmm2         ;                           �
	cvttps2pi mm1, xmm0         ;                           �
	movhlps xmm2, xmm2          ;                           �
	packssdw mm0, mm1           ;                           �
	movq mm1, mm0               ;                           �
	cvttps2pi mm3, xmm2         ;                           �
	packssdw mm2, mm3           ;                           �
	pminsw mm0, mm2             ;                           �
	pmaxsw mm1, mm2             ;                           �

	cmp [ecx], 4
	je short bcskip6case

	movzx ebx, [ecx+5] ;                           �
	movzx edi, [ecx+6] ;                           �
	movaps xmm4, [_caddasm+ebx]  ;xmm4: [ z4, z4, y4, x4]    �
	addps xmm4, xmm7            ;                           �۱
	movaps xmm5, [_caddasm+edi]  ;xmm5: [ z5, z5, y5, x5]    �
	addps xmm5, xmm7            ;                           �۱
	movaps xmm6, xmm4           ;xmm6: [ z4, z4, y4, x4]    �
	movhlps xmm4, xmm5          ;xmm4: [ z4, z4, z5, z5]    �
	movlhps xmm5, xmm6          ;xmm5: [ y4, x4, y5, x5]    �
	rcpps xmm4, xmm4            ;xmm6: [/z4,/z4,/z5,/z5]    ��
	mulps xmm4, xmm5            ;xmm4: [sy4,sx4,sy5,sx5]    �۱�

	cvttps2pi mm4, xmm4         ;                           �
	movhlps xmm4, xmm4          ;                           �
	cvttps2pi mm5, xmm4         ;                           �
	packssdw mm4, mm5           ;                           �
	pminsw mm0, mm4             ; mm0: [my1,mx1,my0,mx0]    �
	pmaxsw mm1, mm4             ; mm1: [My1,Mx1,My0,Mx0]    �
bcskip6case:

	pshufw mm2, mm0, 0eh        ; mm2: [   ,   ,my1,mx1]    �
	pshufw mm3, mm1, 0eh        ; mm3: [   ,   ,My1,Mx1]    �
	pminsw mm0, mm2             ; mm0: [  ?,  ?, my, mx]    �
	pmaxsw mm1, mm3             ; mm1: [  ?,  ?, My, Mx]    �
	punpckldq mm0, mm1          ; mm0: [ My, Mx, my, mx]    �

		;See SCRCLP2D.BAS for a derivation of these 4 lines:
	paddsw mm0, mm6 ;_qsum0     ; mm0: ["+?,"+?,"+?,"+?]    �
	pmaxsw mm0, mm7 ;_qsum1     ; mm0: [sy1,sx1,sy0,sx0]    �
	pshufw mm1, mm0, 0eeh       ; mm1: [sy1,sx1,sy1,sx1]    �
	psubusw mm1, mm0            ; mm1: [  0,  0, dy, dx]    �
		;kv6frameplace -= ((32767-yres)*bpl + (32767-xres)*4);

	movd edx, mm1               ; edx: [ dy, dx]            �
	pmaddwd mm0, _qbplbpp       ; mm0: [      ?,   offs]    ۱� (=y*bpl+x*bpp)
	movd ebx, mm1               ; ebx: [ dy, dx]            �
	and edx, 0ffffh             ; ebx: [  0, dx]            �
	jz short retboundcube       ;                           �
	sub ebx, 65536              ;                           �
	jc short retboundcube       ;                           �

	movzx edi, [eax+7]
	punpcklbw mm5, [eax]
	pmulhuw mm5, [_kv6colmul+edi*8]
	paddw mm5, _kv6coladd
	packuswb mm5, mm5
	movd edi, mm0               ; edi: offs

	lea edi, [edi+edx*4+88888888h] ;_kv6frameplace
bcmod0:
	neg edx
	movhlps xmm0, xmm7
	lea eax, [edi+88888888h] ;_zbufoff
bcmod1:
boundcubenextline:
	mov ecx, edx
begstosb:
	ucomiss xmm0, [eax+ecx*4]
	jnc short skipdrawpix
	movss [eax+ecx*4], xmm0
	movd [edi+ecx*4], mm5
skipdrawpix:
	inc ecx
	jnz begstosb
	add eax, 88888888h; _kv6bytesperline
bcmod2:
	add edi, 88888888h ;_kv6bytesperline
bcmod3:

	sub ebx, 65536
	jnc short boundcubenextline

retboundcube:
	pop edi    ;Visual C's _cdecl requires EBX,ESI,EDI,EBP to be preserved
	pop ebx
	ret

;PUBLIC _drawboundcube3dninit   ;Visual C entry point (pass by stack)
_drawboundcube3dninit:
	mov eax, _kv6frameplace
	mov [bcmod0_3dn-4], eax
	mov eax, _kv6bytesperline
	mov [bcmod3_3dn-4], eax
	;mov eax, _kv6bytesperline
	mov [bcmod2_3dn-4], eax
	mov eax, _zbufoff
	mov [bcmod1_3dn-4], eax
	ret       ;Visual C's _cdecl requires EBX,ESI,EDI,EBP to be preserved

ALIGN 16
;PUBLIC _drawboundcube3dn       ;Visual C entry point (pass by stack)
_drawboundcube3dn:
	mov eax, [esp+4]
	mov ecx, [esp+8]
	push ebx   ;Visual C's _cdecl requires EBX,ESI,EDI,EBP to be preserved
	push edi

	movzx edi, [eax+6]
	and ecx, edi
	jz retboundcube_3dn

	movq mm6, [_ztabasm+MAXZSIZ*16]
	movq mm7, [_ztabasm+MAXZSIZ*16+8]
	movzx edi, [eax+4]
	shl edi, 4
	pfadd mm6, [_ztabasm+edi]
	pfadd mm7, [_ztabasm+edi+8]
	movq mm0, mm7
	pcmpgtd mm0, [_scisdist]
	movd edx, mm0
	test edx, edx
	jz retboundcube_3dn

	lea ecx, [_ptfaces16+ecx*8]

	movzx ebx, [ecx+1]
	movzx edi, [ecx+2]
	movq mm0, [_caddasm+ebx]
	movq mm1, [_caddasm+edi]
	pfadd mm0, mm6              ;mm0: [   y0    x0]
	pfadd mm1, mm6              ;mm1: [   y1    x1]
	movd mm5, [_caddasm+ebx+8]
	punpckldq mm5, [_caddasm+edi+8]
	pfadd mm5, mm7              ;mm5: [   z1    z0]
	pfrcp mm4, mm5              ;mm4: [ 1/z0  1/z0]
	punpckhdq mm5, mm5          ;mm5: [   z1    z1]
	pfrcp mm5, mm5              ;mm5: [ 1/z1  1/z1]
	pfmul mm0, mm4              ;mm0: [y0/z0 x0/z0]
	pfmul mm1, mm5              ;mm1: [y1/z1 x1/z1]
	pf2id mm0, mm0              ;mm0: [  sy0   sx0]
	pf2id mm1, mm1              ;mm1: [  sy1   sx1]
	packssdw mm0, mm1           ;mm0: [sy1 sx1 sy0 sx0]

	movzx ebx, [ecx+3]
	movzx edi, [ecx+4]
	movq mm2, [_caddasm+ebx]
	movq mm3, [_caddasm+edi]
	pfadd mm2, mm6              ;mm2: [   y2    x2]
	pfadd mm3, mm6              ;mm3: [   y3    x3]
	movd mm5, [_caddasm+ebx+8]
	punpckldq mm5, [_caddasm+edi+8]
	pfadd mm5, mm7              ;mm5: [   z3    z2]
	pfrcp mm4, mm5              ;mm4: [ 1/z2  1/z2]
	punpckhdq mm5, mm5          ;mm5: [   z3    z3]
	pfrcp mm5, mm5              ;mm5: [ 1/z3  1/z3]
	pfmul mm2, mm4              ;mm2: [y2/z2 x2/z2]
	pfmul mm3, mm5              ;mm3: [y3/z3 x3/z3]
	pf2id mm2, mm2              ;mm2: [  sy2   sx2]
	pf2id mm3, mm3              ;mm3: [  sy3   sx3]
	packssdw mm2, mm3           ;mm2: [sy3 sx3 sy2 sx2]

	movq mm1, mm0
	pminsw mm0, mm2             ;mm0: [sy1 sx1 sy0 sx0] <-min
	pmaxsw mm1, mm2             ;mm1: [sy1 sx1 sy0 sx0] <-max

	cmp [ecx], 4
	je short bcskip6case_3dn

	movzx ebx, [ecx+5]
	movzx edi, [ecx+6]
	movq mm2, [_caddasm+ebx]
	movq mm3, [_caddasm+edi]
	pfadd mm2, mm6              ;mm2: [   y4    x4]
	pfadd mm3, mm6              ;mm3: [   y5    x5]
	movd mm5, [_caddasm+ebx+8]
	punpckldq mm5, [_caddasm+edi+8]
	pfadd mm5, mm7              ;mm5: [   z5    z4]
	pfrcp mm4, mm5              ;mm4: [ 1/z4  1/z4]
	punpckhdq mm5, mm5          ;mm5: [   z5    z5]
	pfrcp mm5, mm5              ;mm5: [ 1/z5  1/z5]
	pfmul mm2, mm4              ;mm2: [y4/z4 x4/z4]
	pfmul mm3, mm5              ;mm3: [y5/z5 x5/z5]
	pf2id mm2, mm2              ;mm2: [  sy4   sx4]
	pf2id mm3, mm3              ;mm3: [  sy5   sx5]
	packssdw mm2, mm3           ;mm2: [sy5 sx5 sy4 sx4]

	pminsw mm0, mm2             ; mm0: [my1,mx1,my0,mx0]
	pmaxsw mm1, mm2             ; mm1: [My1,Mx1,My0,Mx0]
bcskip6case_3dn:

	pshufw mm2, mm0, 0eh        ; mm2: [my0,mx0,my1,mx1]
	pshufw mm3, mm1, 0eh        ; mm3: [My0,Mx0,My1,Mx1]
	pminsw mm0, mm2             ; mm0: [  ?,  ?, my, mx]
	pmaxsw mm1, mm3             ; mm1: [  ?,  ?, My, Mx]
	punpckldq mm0, mm1          ; mm0: [ My, Mx, my, mx]

		;See SCRCLP2D.BAS for a derivation of these 4 lines:
	paddsw mm0, _qsum0          ; mm0: ["+?,"+?,"+?,"+?]    �
	pmaxsw mm0, _qsum1          ; mm0: [sy1,sx1,sy0,sx0]    �
	pshufw mm1, mm0, 0eeh       ; mm1: [sy1,sx1,sy1,sx1]    �
	psubusw mm1, mm0            ; mm1: [  0,  0, dy, dx]    �
		;kv6frameplace -= ((32767-yres)*bpl + (32767-xres)*4);

	movd edx, mm1               ; edx: [ dy, dx]            �
	pmaddwd mm0, _qbplbpp       ; mm0: [      ?,   offs]    ۱� (=y*bpl+x*bpp)
	movd ebx, mm1               ; ebx: [ dy, dx]            �
	and edx, 0ffffh             ; ebx: [  0, dx]            �
	jz short retboundcube_3dn   ;                           �
	sub ebx, 65536              ;                           �
	jc short retboundcube_3dn   ;                           �

	movzx edi, [eax+7]
	punpcklbw mm5, [eax]
	pmulhuw mm5, [_kv6colmul+edi*8]
	paddw mm5, _kv6coladd
	packuswb mm5, mm5
	movd edi, mm0               ; edi: offs

	lea edi, [edi+edx*4+88888888h] ;_kv6frameplace
bcmod0_3dn:
	neg edx
	movd mm1, edx
	lea eax, [edi+88888888h] ;_zbufoff
bcmod1_3dn:
boundcubenextline_3dn:
	movd ecx, mm1
begstosb_3dn:
	movq mm0, mm7
	pcmpgtd mm0, [eax+ecx*4]
	movd edx, mm0
	test edx, edx
	jnz short skipdrawpix_3dn
	movd [eax+ecx*4], mm7
	movd [edi+ecx*4], mm5
skipdrawpix_3dn:
	inc ecx
	jnz begstosb_3dn
	add eax, 88888888h; _kv6bytesperline
bcmod2_3dn:
	add edi, 88888888h ;_kv6bytesperline
bcmod3_3dn:

	sub ebx, 65536
	jnc short boundcubenextline_3dn

retboundcube_3dn:
	pop edi    ;Visual C's _cdecl requires EBX,ESI,EDI,EBP to be preserved
	pop ebx
	ret

_dep_protect_end:
;CODE ENDS
;END
