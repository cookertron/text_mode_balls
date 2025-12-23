; ====================================================================
; PROJECT: VGA TEXT MODE SPRITE ENGINE
; AUTHOR:  Antigravity (Agentic AI) & User
; DATE:    2025
; --------------------------------------------------------------------
; DESCRIPTION:
;   A high-performance animation engine running in standard VGA Text 
;   Mode (80x50). It achieves sub-pixel positioning and overlaps by:
;   1. Modifying VGA Font Memory (Plane 2) directly.
;   2. Using a pre-calculated Lookup Table (LUT) for bit-shifting.
;   3. Implementing Hardware Compositing (Write Mode 3) for zero-cost
;      merging of overlapping sprites (OR-blitting).
; ====================================================================

.MODEL SMALL
.286
.STACK 100h

; ====================================================================
; STRUCTURES
; ====================================================================
BALL STRUC 
    ; --- Physics ---
    PosX            DW ?    ; Screen X (Pixels)
    PosY            DW ?    ; Screen Y (Pixels)
    VelX            DW ?    ; Velocity X (Pixels/Frame)
    VelY            DW ?    ; Velocity Y (Pixels/Frame)
    
    ; --- Rendering ---
    ; The Starting Static Font ID (occupies 4 chars: ID, ID+1, ID+2, ID+3)
    ReservedID      DW ?    
    
    ; Pre-calculated Offset in Font Memory (ReservedID * 32)
    ; Each character is 32 bytes (16 bytes * 2 for alignment padding in VRAM? No, 8x8 font is effective 32 bytes in Plane 2 linear view?)
    ; Actually: 8 scanlines * 1 byte = 8 bytes. But in Plane 2 Linear, chars are spaced by 32 bytes.
    FontPtr         DW ?
    
    ; --- Clean-up & Collision ---
    ; Stores the 4 Screen Offsets (B800h) used in the PREVIOUS frame.
    ; Used to "Clear" the ball (draw Black Space) before drawing the new frame.
    ; FFFFh indicates the quadrant was not drawn (e.g., was composited or off-screen).
    ClearOffsets    DW 4 DUP(0FFFFh)
    
    ; Boolean: TRUE if this ball has been processed/drawn this frame.
    ; Crucial for Collision Detection to only check against ALREADY drawn balls.
    Blitted         DW ?    
ENDS

; ====================================================================
; CONSTANTS
; ====================================================================
VGA_SEQ_INDEX   EQU 03C4h
VGA_SEQ_DATA    EQU 03C5h
VGA_GC_INDEX    EQU 03CEh
VGA_GC_DATA     EQU 03CFh
VGA_CRTC_INDEX  EQU 03D4h
VGA_CRTC_DATA   EQU 03D5h
VGA_INPUT_STAT  EQU 03DAh

; ====================================================================
; DATA SEGMENT
; ====================================================================
.DATA

; Include the pre-calculated Lookup Table
INCLUDE "BALL_LUT.INC"

BALL_DATA_START = $
    ; Ball 1: ID 128, FontPtr 1000h (4096)
    Ball1   BALL <100, 50, 1, 1, 128, 1000h, , 0>
    
    ; Ball 2: ID 132, FontPtr 1080h
    Ball2   BALL <200, 100, -1, 1, 132, 1080h, , 0>
    
    ; Ball 3: ID 136, FontPtr 1100h
    Ball3   BALL <50, 150, 2, 1, 136, 1100h, , 0>
    
    ; Ball 4: ID 140, FontPtr 1180h
    Ball4   BALL <250, 60, -2, 2, 140, 1180h, , 0>
    
    ; Ball 5: ID 144, FontPtr 1200h
    Ball5   BALL <30, 300, 1, -2, 144, 1200h, , 0>
    
    ; Ball 6: ID 148, FontPtr 1280h
    Ball6   BALL <300, 200, -1, -1, 148, 1280h, , 0>
    
    ; Ball 7: ID 152, FontPtr 1300h
    Ball7   BALL <150, 350, 2, 2, 152, 1300h, , 0>
    
    ; Ball 8: ID 156, FontPtr 1380h
    Ball8   BALL <80, 80, -2, -1, 156, 1380h, , 0>
    
    ; Ball 9: ID 160, FontPtr 1400h
    Ball9   BALL <220, 20, 1, 2, 160, 1400h, , 0>
    
    ; Ball 10: ID 164, FontPtr 1480h
    Ball10  BALL <180, 180, -1, 1, 164, 1480h, , 0>
    
BALL_DATA_END = $

; Calculate List Size and Count
; NOTE: In Ideal mode, labels in .DATA are usually offsets.
BALL_DATA_SIZE = BALL_DATA_END - BALL_DATA_START
BALL_SIZE   = SIZE BALL
NumBalls    = BALL_DATA_SIZE / BALL_SIZE

; ====================================================================
; CODE SEGMENT
; ====================================================================
.CODE

; ====================================================================
; PROCEDURES
; ====================================================================

GetLUTOffset PROC NEAR
    ; ----------------------------------------------------------------
    ; Calculates pointer to the correct sprite frame in BALL_LUT
    ; Input:  AX = PosX
    ;         BX = PosY
    ; Output: SI = Offset into BallLUT (DS:SI)
    ; ----------------------------------------------------------------
    push ax
    push bx

    ; ShiftX = PosX & 7
    and ax, 111b
    
    ; ShiftY = PosY & 7
    and bx, 111b
    
    ; Logic: Index = (ShiftY * 8) + ShiftX
    ;        Offset = Index * 32 (32 bytes per state)
    ; Optimized: Offset = (ShiftY * 256) + (ShiftX * 32)
    
    shl bx, 8       ; ShiftY * 256
    shl ax, 5       ; ShiftX * 32
    add bx, ax      ; BX = Total Offset
    
    lea si, [BallLUT + bx]
    
    pop bx
    pop ax
    ret
ENDP GetLUTOffset

GetVideoOffset PROC
    ; ----------------------------------------------------------------
    ; Calculates VRAM (B800h) Offset for a Pixel Coordinate
    ; Input:  AX = PosX
    ;         BX = PosY
    ; Output: DI = Offset into Segment B800h
    ; Note: Returns offset for the TOP-LEFT character cell of the 2x2 grid
    ; ----------------------------------------------------------------
    push ax
    push bx
    push dx
    push cx
    
    ; GridX = PosX / 8
    shr ax, 3
    
    ; GridY = PosY / 8
    shr bx, 3
    
    ; Offset = (GridY * 80 + GridX) * 2
    ; Optimization: (GridY * 160) + (GridX * 2)
    ; 160 = 128 + 32
    
    mov cx, bx      ; Copy GridY
    shl bx, 5       ; BX = GridY * 32
    shl cx, 7       ; CX = GridY * 128
    add bx, cx      ; BX = GridY * 160
    
    shl ax, 1       ; AX = GridX * 2
    
    add bx, ax
    mov di, bx
    
    pop cx
    pop dx
    pop bx
    pop ax
    ret
ENDP GetVideoOffset

SetVGA_FontMode PROC
    ; ----------------------------------------------------------------
    ; Sets VGA Registers for Font Write (Plane 2, A000h, Linear)
    ; Preserves: AX, DX
    ; ----------------------------------------------------------------
    push ax
    push dx
    
    cli
    
    mov dx, VGA_SEQ_INDEX
    mov ax, 0604h       ; Mem Mode = Odd/Even OFF (Linear)
    out dx, ax
    mov ax, 0402h       ; Map Mask = Plane 2
    out dx, ax
    
    mov dx, VGA_GC_INDEX
    mov ax, 0005h       ; Mode Register = Write 0, Read 0, Shift Linear
    out dx, ax
    mov ax, 0406h       ; Misc = Map A000h, O/E Off
    out dx, ax
    mov ax, 0001h       ; Enable Set/Reset = 0 (Disable)
    out dx, ax
    
    sti
    
    pop dx
    pop ax
    ret
ENDP SetVGA_FontMode

SetVGA_ScreenMode PROC
    ; ----------------------------------------------------------------
    ; Sets VGA Registers for Screen Write (Plane 0+1, B800h, Odd/Even)
    ; Preserves: AX, DX
    ; ----------------------------------------------------------------
    push ax
    push dx
    
    cli
    
    mov dx, VGA_SEQ_INDEX
    mov ax, 0204h       ; Mem Mode = Odd/Even ON
    out dx, ax
    mov ax, 0302h       ; Map Mask = Planes 0+1
    out dx, ax
    
    mov dx, VGA_GC_INDEX
    mov ax, 1005h       ; Mode Register = Write 0, Read 0, Shift O/E
    out dx, ax
    mov ax, 0E06h       ; Misc = Map B800h, O/E On
    out dx, ax
    mov ax, 0001h       ; Enable Set/Reset = 0 (Disable)
    out dx, ax
    
    sti
    
    pop dx
    pop ax
    ret
ENDP SetVGA_ScreenMode

WaitForVBlank PROC
    ; ----------------------------------------------------------------
    ; Waits for the start of the Vertical Retrace
    ; ----------------------------------------------------------------
    push dx
    push ax
    
    mov dx, 03DAh   ; Input Status Register 1
    
WaitNotVBlank:
    in al, dx
    test al, 08h    ; Bit 3 = Vertical Retrace
    jnz WaitNotVBlank
    
WaitVBlank:
    in al, dx
    test al, 08h
    jz WaitVBlank
    
    pop ax
    pop dx
    ret
ENDP WaitForVBlank

ClearBall PROC
    ; ----------------------------------------------------------------
    ; Clears the ball from its previous position to prevention trails
    ; Input: SI = Pointer to BALL
    ; ----------------------------------------------------------------
    push es
    push di
    push cx
    push ax
    
    mov ax, 0B800h
    mov es, ax
    
    ; We have 4 offsets to clear
    ; Valid offsets are != FFFFh
    
    ; Loop 4 times? Unrolled is faster/cleaner
    
    ; Q0
    mov di, [si+BALL.ClearOffsets]
    cmp di, 0FFFFh
    je SkipQ0
    mov word ptr es:[di], 0000h ; Black char, Black attr
    mov [si+BALL.ClearOffsets], 0FFFFh ; Mark as cleared/invalid
SkipQ0:

    ; Q1
    mov di, [si+BALL.ClearOffsets+2]
    cmp di, 0FFFFh
    je SkipQ1
    mov word ptr es:[di], 0000h
    mov [si+BALL.ClearOffsets+2], 0FFFFh
SkipQ1:

    ; Q2
    mov di, [si+BALL.ClearOffsets+4]
    cmp di, 0FFFFh
    je SkipQ2
    mov word ptr es:[di], 0000h
    mov [si+BALL.ClearOffsets+4], 0FFFFh
SkipQ2:

    ; Q3
    mov di, [si+BALL.ClearOffsets+6]
    cmp di, 0FFFFh
    je SkipQ3
    mov word ptr es:[di], 0000h
    mov [si+BALL.ClearOffsets+6], 0FFFFh
SkipQ3:

    ; Reset Blitted Flag for new frame
    mov word ptr [si+BALL.Blitted], 0

    pop ax
    pop cx
    pop di
    pop es
    ret
ENDP ClearBall

UpdateBall PROC
    ; ----------------------------------------------------------------
    ; Updates ball position based on velocity and bounds
    ; Input: SI = Pointer to BALL
    ; ----------------------------------------------------------------
    push ax
    push bx
    push dx
    
    ; --- X AXIS ---
    mov ax, [si+BALL.PosX]
    add ax, [si+BALL.VelX]
    mov [si+BALL.PosX], ax
    
    ; Bounds Check X (0 to 624)
    cmp ax, 0
    jl BounceX
    cmp ax, 624
    jg BounceX
    jmp CheckY

BounceX:
    neg [si+BALL.VelX]
    ; Clamp to screen
    cmp ax, 0
    jge ClampMaxX
    mov [si+BALL.PosX], 0
    jmp CheckY
ClampMaxX:
    mov [si+BALL.PosX], 624
    
    ; --- Y AXIS ---
CheckY:
    mov ax, [si+BALL.PosY]
    add ax, [si+BALL.VelY]
    mov [si+BALL.PosY], ax
    
    ; Bounds Check Y (0 to 384)
    cmp ax, 0
    jl BounceY
    cmp ax, 384
    jg BounceY
    jmp DoneUpdate

BounceY:
    neg [si+BALL.VelY]
    ; Clamp to screen
    cmp ax, 0
    jge ClampMaxY
    mov [si+BALL.PosY], 0
    jmp DoneUpdate
ClampMaxY:
    mov [si+BALL.PosY], 384

DoneUpdate:
    pop dx
    pop bx
    pop ax
    ret
ENDP UpdateBall

CheckCollision PROC
    ; ----------------------------------------------------------------
    ; Checks if the current screen position (DI) is occupied
    ; Input:  DI = Screen Offset (B800h)
    ;         SI = Pointer to Current Ball (to avoid self-collision)
    ; Output: CF = 1 if Hit, 0 if Miss
    ;         BX = Pointer to Collided Ball (if Hit)
    ;         AX = Collided Quadrant Index (0-3) (if Hit)
    ; ----------------------------------------------------------------
    push cx
    
    mov cx, NumBalls
    mov bx, OFFSET BALL_DATA_START
    
CheckLoop:
    ; Don't check against self
    cmp bx, si
    je NextBall
    
    ; Don't check if not blitted yet
    cmp word ptr [bx+BALL.Blitted], 1
    jne NextBall
    
    ; Check all 4 quadrants of candidate
    ; Q0 (TL)
    cmp di, [bx+BALL.ClearOffsets]
    je HitQ0
    ; Q1 (TR)
    cmp di, [bx+BALL.ClearOffsets+2]
    je HitQ1
    ; Q2 (BL)
    cmp di, [bx+BALL.ClearOffsets+4]
    je HitQ2
    ; Q3 (BR)
    cmp di, [bx+BALL.ClearOffsets+6]
    je HitQ3
    
NextBall:
    add bx, SIZE BALL
    loop CheckLoop
    
    ; No Hit
    pop cx
    clc
    ret

HitQ0:
    mov ax, 0
    jmp HitFound
HitQ1:
    mov ax, 1
    jmp HitFound
HitQ2:
    mov ax, 2
    jmp HitFound
HitQ3:
    mov ax, 3
HitFound:
    pop cx
    stc
    ret
ENDP CheckCollision

CompositeOverlay PROC
    ; ----------------------------------------------------------------
    ; HARDWARE COMPOSITING ROUTINE
    ; ----------------------------------------------------------------
    ; Uses VGA Write Mode 3 to merge the Current Ball (Source) onto
    ; an existing Collided Ball (Destination) without destroying it.
    ; This effectively performs a logical OR operation:
    ;   Dest = Dest OR Source
    ;
    ; INPUTS:
    ;   SI = Pointer to Current Ball Struct
    ;   BX = Pointer to Collided Ball Struct
    ;   CX = Current Quadrant Index (0-3)
    ;   AX = Collided Quadrant Index (0-3)
    ; ----------------------------------------------------------------
    push es
    push ds
    push di
    push si
    push dx
    push cx
    push bx ; Save Collided Ball Ptr (Crucial, as GetLUTOffset clobbers BX)
    push ax ; Save Collided Quad (AX)
    
    ; 1. PREPARE SOURCE PIXELS (LUT)
    ; ------------------------------
    mov ax, [si+BALL.PosX]
    mov bx, [si+BALL.PosY]
    call GetLUTOffset     ; Returns SI = LUT Base Ptr containing the sprite data
    
    ; 2. OFFSET SOURCE BY CURRENT QUADRANT
    ; ------------------------------------
    ; Convert Quad Index (0-3) to Byte Offset (0, 8, 16, 24)
    mov dx, cx  
    shl dx, 3   ; * 8 bytes per quadrant
    add si, dx  ; SI = Precise Source Pixels for this corner
    
    ; 3. PREPARE DESTINATION FONT POINTER
    ; -----------------------------------
    pop ax      ; Restore Collided Quad (AX)
    pop bx      ; Restore Collided Ball Ptr (BX)
    
    mov di, [bx+BALL.FontPtr] ; Base Font Address of obstacle
    
    ; 4. OFFSET DEST BY COLLIDED QUADRANT
    ; -----------------------------------
    ; Convert Quad Index to Font Memory Offset (0, 32, 64, 96)
    ; Recall: In Plane 2 Linear, each char is 32 bytes apart.
    mov dx, ax  
    shl dx, 5   ; * 32 bytes (Size of one full character slot)
    add di, dx  ; DI = Precise Destination Font Address
    
    ; 5. SETUP VGA FOR HARDWARE COMPOSITING (Write Mode 3)
    ; ----------------------------------------------------
    ; Switch to Font Plane (Plane 2, A000h)
    call SetVGA_FontMode
    
    mov dx, VGA_GC_INDEX
    
    ; Mode Register (Index 05h) = 03h (Write Mode 3)
    ; In Mode 3, the CPU Data acts as the Bit Mask.
    mov ax, 0305h 
    out dx, ax
    
    ; Set/Reset (Index 00h) = FFh (Paint Color = All 1s / White)
    mov ax, 0FF00h
    out dx, ax
    
    ; Enable Set/Reset (Index 01h) = FFh (Enable S/R for all planes)
    mov ax, 0FF01h
    out dx, ax
    
    ; Data Rotate / Function (Index 03h) = 00h (Replace/Copy)
    ; Logic: 
    ;   If Mask Bit = 1: Write Set/Reset Color (White)
    ;   If Mask Bit = 0: Write Latched Data (Background/Old Ball)
    ; Result: Merges the new white pixels onto the old pixels.
    mov ax, 0003h 
    out dx, ax
    
    ; Bit Mask (Index 08h) = FFh (Use CPU Data as the Bit Mask)
    ; This ensures the byte we write (mov es:[di], al) is fully interpreted as the mask.
    mov ax, 0FF08h
    out dx, ax
    
    ; 6. PERFORM THE MERGE LOOP
    ; -------------------------
    ; Setup ES=A000h (Sequencer is already pointed to Plane 2)
    mov ax, 0A000h
    mov es, ax
    
    mov cx, 8 ; 8 Lines per character
MergeLoop:
    ; A. Dummy Read (Load Latches from Background)
    ; This reads the existing data (e.g., the collided ball's pixels) into the VGA Latches.
    mov al, es:[di]
    
    ; B. Load Mask (Source Pixel from LUT)
    lodsb      ; AL = [DS:SI], SI++
    
    ; C. Hardware Write
    ; The CPU writes AL. In Mode 3, AL becomes the BIT MASK.
    ;   - Where AL=1 (New Ball Pixel), VGA writes White (S/R Reg).
    ;   - Where AL=0 (Transparent), VGA writes Latch (Old Ball Pixel).
    mov es:[di], al
    
    inc di
    loop MergeLoop
    
    ; 7. CLEANUP
    ; ----------
    call SetVGA_ScreenMode
    
    pop cx
    pop dx
    pop si
    pop di
    pop ds
    pop es
    ret
ENDP CompositeOverlay

DrawBall PROC
    ; ----------------------------------------------------------------
    ; Renders a ball to the screen
    ; Input:  SI = Pointer to BALL struct
    ; ----------------------------------------------------------------
    push es
    push ds
    push di
    push cx
    
    ; Note: We need to preserve SI (Ball Ptr)
    
    ; 1. GET SOURCE (LUT PIXELS) -> DS:SI
    ; -----------------------------------
    mov ax, [si+BALL.PosX]
    mov bx, [si+BALL.PosY]
    
    push si         ; Save Ball Ptr
    call GetLUTOffset   ; Returns SI = Source Data Ptr
    
    ; Save LUT Ptr in DX temporarily so we can restore Ball Ptr
    mov dx, si
    
    pop si          ; Restore Ball Ptr to get FontPtr
    
    ; 2. GET FONT DESTINATION (A000h) -> ES:DI
    ; ----------------------------------------
    mov ax, 0A000h
    mov es, ax
    mov di, [si+BALL.FontPtr]
    
    push si         ; Save Ball Ptr AGAIN for Step 4
    
    ; 3. TRANSFER PIXELS (LUT -> FONT RAM)
    ; ------------------------------------
    ; Source: DS:DX (LUT) -> Move to SI
    ; Dest:   ES:DI (Font RAM)
    
    ; SETUP VGA FOR FONT WRITE (Plane 2, Linear, A000h)
    call SetVGA_FontMode
    
    mov si, dx      ; SI = LUT Source
    
    ; Loop 4 times (4 tiles)
    mov cx, 4
CopyTileLoop:
    ; Copy 8 bytes (4 words)
    movsw
    movsw
    movsw
    movsw
    
    ; Skip 24 bytes in Dest (advance to next char slot)
    add di, 24
    
    loop CopyTileLoop
    
    ; 4. UPDATE SCREEN RAM (B800h)
    ; ----------------------------
    pop si          ; Restore Ball Ptr
    
    ; SETUP VGA FOR SCREEN WRITE (Plane 0+1, Odd/Even, B800h)
    call SetVGA_ScreenMode
    
    mov ax, [si+BALL.PosX]
    mov bx, [si+BALL.PosY]
    
    push si         ; Save Ball Ptr one last time (needed for ID)
    call GetVideoOffset ; Returns DI = Screen Offset
    pop si          ; Restore Ball Ptr
    
    mov ax, 0B800h
    mov es, ax
    
    ; Get Base Character ID
    mov ax, [si+BALL.ReservedID]
    mov ah, 0Fh
    cld
    
    ; --- Q0: Top-Left ---
    ; Check Collision
    push ax ; Save Char/Attr
    call CheckCollision ; In: DI, SI. Out: CF, BX, AX(Quad)
    jc CollideQ0
    
    ; No Collision
    ; Store Offset ONLY if we own the cell
    mov [si+BALL.ClearOffsets], di
    pop ax
    stosw
    jmp DoneQ0

CollideQ0:
    ; Collision! (AX=CollidedQuad, BX=CollidedObj)
    ; CompositeQ0(Src=SI, Dst=BX, CurQuad=0, ColQuad=AX)
    mov cx, 0 ; Current Quad 0
    call CompositeOverlay
    
    pop ax ; Restore AX (Char ID) to inc it
    add di, 2 ; Skip screen write, just advance DI
    
DoneQ0:
    inc al ; Next Char ID
    
    ; --- Q1: Top-Right ---
    push ax
    call CheckCollision
    jc CollideQ1
    
    mov [si+BALL.ClearOffsets+2], di
    pop ax
    stosw
    jmp DoneQ1
    
CollideQ1:
    mov cx, 1 ; Current Quad 1
    call CompositeOverlay
    pop ax
    add di, 2
    
DoneQ1:

    add di, 156
    inc al
    
    ; --- Q2: Bottom-Left ---
    push ax
    call CheckCollision
    jc CollideQ2
    
    mov [si+BALL.ClearOffsets+4], di
    pop ax
    stosw
    jmp DoneQ2
    
CollideQ2:
    mov cx, 2
    call CompositeOverlay
    pop ax
    add di, 2
    
DoneQ2:
    inc al
    
    ; --- Q3: Bottom-Right ---
    push ax
    call CheckCollision
    jc CollideQ3
    
    mov [si+BALL.ClearOffsets+6], di
    pop ax
    stosw
    jmp DoneQ3
    
CollideQ3:
    mov cx, 3
    call CompositeOverlay
    pop ax
    add di, 2
    
DoneQ3:

    ; Mark as Blitted

    ; Mark as Blitted
    mov [si+BALL.Blitted], 1
    
    pop cx
    pop di
    pop ds
    pop es
    ret
ENDP DrawBall

; ====================================================================
; MAIN PROGRAM
; ====================================================================
start:
    ; Initialize DS
    mov ax, @data
    mov ds, ax

    ; ------------------------------------------------------------
    ; 1. SETUP VIDEO MODE
    ; ------------------------------------------------------------
    ; Reset Video Mode to 80x25 (Standard Text)
    mov ax, 0003h
    int 10h

    ; Switch to 80x50 Mode (Load 8x8 Font)
    mov ax, 1112h
    xor bl, bl
    int 10h

    ; Hide Cursor
    mov ah, 01h
    mov cx, 2000h
    int 10h

    ; ------------------------------------------------------------
    ; 2. CONFIGURE VGA REGISTERS (Unlock Plane 2 / 8-Dot Mode)
    ; ------------------------------------------------------------
    cli
    
    ; Sequencer Operations
    mov dx, VGA_SEQ_INDEX
    
    ; Sync Reset
    mov ax, 0100h   
    out dx, ax
    
    ; 8-Dot Mode (Index 01h = 09h) - Fixes 9th column gap
    mov ax, 0901h   
    out dx, ax
    
    ; Plane Select / Disable Chain-4 (Index 02h = 04h) - Write only to Plane 2
    mov ax, 0402h   
    out dx, ax

    mov ax, 0604h   ; Memory Mode
    out dx, ax
    
    mov ax, 0402h   ; Plane Select (Redundant but safe)
    out dx, ax
    
    ; End Reset
    mov ax, 0300h   
    out dx, ax
    
    ; Graphics Controller Operations
    mov dx, VGA_GC_INDEX
    ; Graphics Mode (Map A000)
    mov ax, 0406h
    out dx, ax
    
    sti

    ; Point ES to Video Memory (A000h for Font Data in Plane 2)
    ; (Handled inside DrawBall now, but explicit set here doesn't hurt, though we overwrite ES later)
    
    ; ------------------------------------------------------------
    ; 3. MAIN LOOP
    ; ------------------------------------------------------------
MainLoop:
    ; A. Sync to VBlank
    call WaitForVBlank
    
    ; B. Clear Previous Balls
    mov cx, NumBalls
    mov si, OFFSET BALL_DATA_START
ClearLoop:
    call ClearBall
    add si, BALL_SIZE
    loop ClearLoop

    ; C. Update Physics
    mov cx, NumBalls
    mov si, OFFSET BALL_DATA_START
UpdateLoop:
    call UpdateBall
    add si, BALL_SIZE
    loop UpdateLoop

    ; D. Render All Balls
    ; --------------------------------------
    mov cx, NumBalls
    mov si, OFFSET BALL_DATA_START
    
RenderLoop:
    call DrawBall
    
    ; Next Ball
    add si, SIZE BALL
    loop RenderLoop

    ; C. Check Input
    ; --------------------------------------
    in al, 60h
    cmp al, 1       ; ESC Scan Code
    je ExitApp
    
    jmp MainLoop

    ; ------------------------------------------------------------
    ; 4. EXIT & CLEANUP
    ; ------------------------------------------------------------
ExitApp:
    ; Restore standard text mode
    mov ax, 0003h
    int 10h
    
    ; Exit to DOS
    mov ah, 4ch
    mov al, 0
    int 21h

END start
