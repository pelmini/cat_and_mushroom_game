; Nametables and attribute tables Demo for NES
; Following on from the background palette program, this program looks at how
; to load a pattern table, which contains the actual graphic tiles, a nametable,
; which contains the layout of graphic tiles for the background, and the
; attribute table, which specifies what palette to paint everything with.
;
; I am not an artist, and even then, converting bitmaps to pattern tables can be
; a chore.  So, I used the "Generitiles" from the NESDev wiki
; (https://wiki.nesdev.com/w/index.php/Placeholder_graphics).  I then ran these
; through a Python script supplied by Damian Yerrick 
; (https://github.com/pinobatch/nesbgeditor) which converts a 2-bit PNG into
; pattern tables pretty darn effectively.  Thanks, Damian!
; 
; So, we're now *finally* using the CHARS section, which gets directly mapped
; into the PPU's memory at power on.  This section really should more
; be named "CHR-ROM", as this is the more common name for it.  You'll notice
; that I can directly include the file produced by Damian's tools, which keeps
; the code tidy.
;
; With the patterns directly mapped in, the next step is to load up some data
; in the name table.  Since we're not doing anything fancy, I've restricted
; things to the first of the two name tables.  Much like we did for loading the
; palette colors, we load this through the use of PPUADDR and PPUDATA.
;
; Finally, we load the attribute table, which says which palette to use for
; each 32x32 pixel region on the screen.  In a more advanced demo, this would
; raise the number of effective colors I was using on the screen.  For now,
; though, I just want to keep things simple and easy-to-explain.
;
; Note that the annyoing "hello world" sound is now gone.  The graphics show
; that everything is working.

.define SPRITE_PAGE  $0200

.define PPUCTRL      $2000
.define PPUMASK      $2001
.define PPUSTATUS    $2002
.define PPUADDR      $2006
.define PPUSCROLL    $2005
.define PPUDATA      $2007

.define OAM_DMA      $4014

.define OAM_PAGE     2

.define NAMETABLE_0_HI $20
.define NAMETABLE_0_LO $00
.define ATTRTABLE_0_HI $23
.define ATTRTABLE_0_LO $C0
.define BGPALETTE_HI   $3F
.define BGPALETTE_LO   $00

; On write: DMC enable, length counter enable
; On read: DMC interrupt, frame interrupt, length counter status
.define DMC_LEN_CNT_CTRL_STA $4015

; Frame counter mode (4 or 5 frame), frame counter interrupt enable/disable
.define FRAME_CNT_MODE_INT $4017

; Controller 1
.define CONTROLLER_1_PORT $4016
.define CONTROLLER_2_PORT $4017
.define CONTROLLER_STROBE $01
.define CONTROLLER_LATCH  $00
.define CONTROLLER_D0_BIT $01

.segment "HEADER"

.byte "NES", $1A ; "NES" magic value
.byte 2          ; number of 16KB code pages (we don't need 2, but nes.cfg declares 2)
.byte 1          ; number of 8KB "char" data pages
.byte $00        ; "mapper" and bank-switching type (0 for "none")
.byte $00        ; background mirroring flats
                 ;
                 ; Note the header is 16 bytes but the nes.cfg will zero-pad for us.

.segment "ZEROPAGE"
nametable_ptr_lo:
.byte $00
nametable_ptr_hi:
.byte $00
frame_counter:
.byte $00
current_frame:
.byte 0
sprite_x:
.byte $7F
sprite_y:
.byte$7F
run:
.byte 0
; code ROM segment
; all code and on-ROM program data goes here

.segment "STARTUP"

; reset vector
reset:
  bit PPUSTATUS  ; clear the VBL flag if it was set at reset time
vwait1:
  bit PPUSTATUS
  bpl vwait1     ; at this point, about 27384 cycles have passed
vwait2:
  bit PPUSTATUS
  bpl vwait2     ; at this point, about 57165 cycles have passed

  ; Interesting little fact I learned along the way.  Because it takes two
  ; stores on PPUADDR to move its pointer, it's good practice to start all of
  ; your PPUADDR use with a peek at PPUSTATUS since this resets its "latch"
  ; and ensures you're addressing the address you expect.
  ; Technically, we don't need this because we did it in the reset code, but
  ; it's a neat little thing to mention here

  bit PPUSTATUS

  ; load all the palettes
  lda #BGPALETTE_HI
  sta PPUADDR
  lda #BGPALETTE_LO
  sta PPUADDR

  ; prep the loop
  ldx #0

paletteloop:
  lda bgpalette, X ; load from the bgpalette array
  sta PPUDATA      ; store in PPUDATA, PPU will auto-increment
  inx              ; increment the X (index) register
  cpx #32
  bne paletteloop  ; run the loop until X=16 (size of the palettes)

; move PPUADDR over to nametable 0. 
  lda #NAMETABLE_0_HI
  sta PPUADDR
  lda #NAMETABLE_0_LO
  sta PPUADDR

; This loop iterates over the pattern table, outputting it in lines of 16
; The other 16 are just padded out with a pattern that's blank.  This lets
; me easily show you some simple graphics that are made up of multiple
; stacked tiles without getting too fancy.  In reality, you'd probably have
; complete nametables that you'd load in from files and simply run in a loop.

; prep the loop
  ldx #4
  ldy #0

  lda #.LOBYTE(background)
  sta nametable_ptr_lo
  lda #.HIBYTE(background)
  sta nametable_ptr_hi

nametableloop:
  lda (nametable_ptr_lo), y ; load from the nametable
  sta PPUDATA         ; store the PPUDATA, PPU will auto-increment
  iny                 ; increment Y as the offset into the pointer
  bne nametableloop   ; this will continue to loop until Y rolls over to 0
  dex                 ; Y rolled over, decrement x
  beq nt_finished     ; When X decrements to 0, break to done
  inc nametable_ptr_hi ; next block of 256 reads
jmp nametableloop

nt_finished:

; set up Palette 0 for everything
  bit PPUSTATUS
  lda #ATTRTABLE_0_HI
  sta PPUADDR
  lda #ATTRTABLE_0_LO
  sta PPUADDR
  ldx #0 ; 64 tiles in the attribute table

attrloop:
  lda attribute, X ; loads attribute[x] into accumulator 
  sta PPUDATA
  inx ; incremnet x (by one)
  cpx #64 ; comparing x to 64
  bne attrloop

; zero out the OAM DMA shadow page
  ldx #$FF
  lda $0
zero_oam:
  sta SPRITE_PAGE, X
  dex
  bne zero_oam

; refresh our index register...we're going to make heavy use of it
; now...
  ldx #0
  sta current_frame
  lda #0
  sta frame_counter
; Load the sprite
  jsr load_sprite

; Enable background and sprite rendering.  This is suuuuuper important to
; remember.  I didn't remember to put this in and probably blew a whole day
; trying to figure out why my emulator hated me.
  lda #$1e
  sta PPUMASK


; generate NMI - Non-maskable interrupt
; Set at 80 to generate NMI
; 7th bit is flipped, which is technically 8 in hex (1000 0000)
; http://wiki.nesdev.com/w/index.php/PPU_registers#PPUCTRL  
  lda #$80
  sta PPUCTRL

forever:
; read the controller state
  lda #CONTROLLER_STROBE
  sta CONTROLLER_1_PORT
  lda #CONTROLLER_LATCH
  sta CONTROLLER_1_PORT
; The controller state is latched, the bits will report in in this
; order on subsequent reads: A, B, Select, Start, U, D, L, R
;
; We only care about the 0 bit because that's where D0, the standard
; controller, reports in
  lda CONTROLLER_1_PORT ; A
  lda CONTROLLER_1_PORT ; B
  lda CONTROLLER_1_PORT ; Select
  lda CONTROLLER_1_PORT ; Start
  lda CONTROLLER_1_PORT ; U
  lda CONTROLLER_1_PORT ; D
  lda CONTROLLER_1_PORT ; L
  lda CONTROLLER_1_PORT ; R
  and #CONTROLLER_D0_BIT
; A value of 0 means the button is pressed
  sta run
  jmp forever

nmi:
  lda #OAM_PAGE
  sta OAM_DMA
 
  inc frame_counter
  lda frame_counter
  cmp #3
  bne done
  lda #0
  sta frame_counter

  lda current_frame
  clc
  adc #0
  ;adc #6 Commneted out because it takes 6 frames for a perosn to walk, each 
  cmp #24
  bne dont_cycle_anim
  lda #0 
dont_cycle_anim:
    sta current_frame

  lda sprite_x
  clc
  adc #1
  sta sprite_x
dont_reset_x:
  sta sprite_x
done:
  jsr load_sprite
  rti

  lda run
  cmp #0
  beq done

; load_sprite consults current_frame to determine the offset into anim
; and then draws the data in that row of anim into a 2x2 square
.proc load_sprite
  ldx #0
  ldy current_frame
  lda #$7F
  sta sprite_y
load_loop:
; First of two cells
  lda sprite_y
  sta SPRITE_PAGE, X
  inx
  lda anim, Y
  iny
  sta SPRITE_PAGE, X
  inx
  lda #$00
  sta SPRITE_PAGE, X
  inx
  lda sprite_x
  sta SPRITE_PAGE, X
  clc
  adc #8             ; move to right cell
  sta sprite_x
  inx
; Second of two cells
  lda sprite_y
  sta SPRITE_PAGE, X
  clc
  adc #8 ; change y coordinates of sprite
  sta sprite_y 
  inx
  lda anim, Y
  iny
  sta SPRITE_PAGE, X
  inx
  lda #$00
  sta SPRITE_PAGE, X
  inx
  lda sprite_x
  sta SPRITE_PAGE, X
  sec
  sbc #8              ; return to the left cell
  sta sprite_x
  inx
;; Loop if we haven't loaded the full sprite
  cpx #16
  bne load_loop
  rts
.endproc
  rti ; JUST DID TO PUT PAUSE ON ROTATE PALETTE UNTIL SHROOM HAS BEEN MADE!!!!!!!!
  ; dec - reducing the value by one 
  dec frame_counter
  ; bmi - branch if minus 
  ; if frame counter is less than zero then do rotate_palette
  bmi rotate_palette
  ; return from interrupt - end rotate code and go back to idle loop
  rti

rotate_palette:
  rti ; Return from the NMI (NTSC refresh interrupt)

bgpalette:
  .byte $1f, $00, $00, $00 ; palette 0, first byte is universal background
  .byte $1f, $20, $1f, $19 ; palette 1, first byte is not used
  .byte $1f, $38, $00, $1a ; palette 2, first byte is not used
  .byte $1f, $20, $1f, $16 ; palette 3, first byte is not used
  
spritepalette:
  .byte $1F, $20, $1f, $16 ; palette 0, first byte is not used
  .byte $1F, $07, $19, $20 ; palette 1, first byte is not used
  .byte $1F, $07, $19, $20 ; palette 2, first byte is not used
  .byte $1F, $07, $19, $20 ; palette 3, first byte is not used

anim:
  .byte $86, $87, $96, $97  ; Cat
;  .byte $96, $97  ;  
;  .byte $A4, $A5, $B4, $B5, $C4, $C5 ; frame 3
;  .byte $A6, $A7, $B6, $B7, $C6, $C7 ; frame 4

; vectors declaration
.segment "VECTORS"
.word nmi
.word reset
.word 0

; As mentioned above, this is the place where you put your pattern table data
; so that it can automatically be mapped into the PPU's memory at $0000-$1FFF.
; Note the use of .incbin so I can just import a binary file.  Neato!
.segment "RODATA"
background:
.byte $8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$68,$A1,$A0,$69,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D
.byte $9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$78,$B0,$B1,$79,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D
.byte $8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$68,$A1,$A0,$69,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D
.byte $9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$78,$B0,$B1,$79,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D 
.byte $8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$68,$A1,$A0,$69,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D
.byte $9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$78,$B0,$B1,$79,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D
.byte $8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$68,$A1,$A0,$69,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D
.byte $9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$78,$B0,$B1,$79,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D 
.byte $8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$68,$A1,$A0,$69,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D
.byte $9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$78,$B0,$B1,$79,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D
.byte $8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$68,$66,$67,$66,$67,$66,$A1,$A0,$67,$66,$67,$66,$67,$66,$67,$66,$67,$66,$67,$66,$67
.byte $9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$78,$76,$77,$76,$77,$76,$B0,$B1,$77,$76,$77,$76,$77,$76,$77,$76,$77,$76,$77,$76,$77 
.byte $8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$68,$A0,$A1,$A0,$A1,$A0,$A1,$A0,$A1,$A0,$A1,$A0,$A1,$A0,$A1,$A0,$A1,$A0,$A1,$A0,$A1
.byte $9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$78,$B0,$B1,$B0,$B1,$B0,$B1,$B0,$B1,$B0,$B1,$B0,$B1,$B0,$B1,$B0,$B1,$B0,$B1,$B0,$B1
.byte $8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$68,$A0,$A1,$6A,$6B,$6A,$6B,$6A,$6B,$6A,$6B,$A0,$A1,$6A,$6B,$6A,$6B,$6A,$6B,$6A,$6B
.byte $9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$78,$B0,$B1,$7A,$7B,$7A,$7B,$7A,$7B,$7A,$7B,$B0,$B1,$7A,$7B,$7A,$7B,$7A,$7B,$7A,$7B 
.byte $8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$68,$A0,$A1,$69,$8C,$8D,$8C,$8D,$8C,$8D,$68,$A0,$A1,$69,$8C,$8D,$8C,$8D,$8C,$8D,$8C
.byte $9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$78,$B0,$B1,$79,$9C,$9D,$9C,$9D,$9C,$9D,$78,$B0,$B1,$79,$9C,$9D,$9C,$9D,$9C,$9D,$9C
.byte $8C,$8D,$8C,$8D,$8C,$68,$66,$67,$66,$67,$66,$67,$A0,$A1,$69,$8C,$8D,$8C,$8D,$8C,$8D,$68,$A0,$A1,$69,$8C,$8D,$8C,$8D,$8C,$8D,$8C
.byte $9C,$9D,$9C,$9D,$9C,$78,$76,$77,$76,$77,$76,$77,$B0,$B1,$79,$9C,$9D,$9C,$9D,$9C,$9D,$78,$B0,$B1,$79,$9C,$9D,$9C,$9D,$9C,$9D,$9C 
.byte $8C,$8D,$8C,$8D,$8C,$68,$A0,$A1,$A0,$A1,$A0,$A1,$A0,$A1,$69,$8C,$8D,$8C,$8D,$8C,$8D,$68,$A0,$A1,$69,$8C,$8D,$8C,$8D,$8C,$8D,$8C
.byte $9C,$9D,$9C,$9D,$9C,$78,$B0,$B1,$B0,$B1,$B0,$B1,$B0,$B1,$79,$9C,$9D,$9C,$9D,$9C,$9D,$78,$B0,$B1,$79,$9C,$9D,$9C,$9D,$9C,$9D,$9C
.byte $8C,$8D,$8C,$8D,$8C,$68,$A0,$A1,$6A,$6B,$6A,$6B,$6A,$6B,$69,$8C,$8D,$8C,$8D,$8C,$8D,$68,$A0,$A1,$69,$8C,$8D,$8C,$8D,$8C,$8D,$8C
.byte $9C,$9D,$9C,$9D,$9C,$78,$B0,$B1,$7A,$7B,$7A,$7B,$7A,$7B,$79,$9C,$9D,$9C,$9D,$9C,$9D,$78,$B0,$B1,$79,$9C,$9D,$9C,$9D,$9C,$9D,$9C
.byte $8C,$8D,$8C,$8D,$8C,$68,$A0,$A1,$69,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$68,$A0,$A1,$69,$8C,$8D,$8C,$8D,$8C,$8D,$8C
.byte $9C,$9D,$9C,$9D,$9C,$78,$B0,$B1,$79,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$78,$B0,$B1,$79,$9C,$9D,$9C,$9D,$9C,$9D,$9C
.byte $66,$67,$66,$67,$66,$67,$A0,$A1,$69,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$68,$A0,$A1,$69,$8C,$8D,$8C,$8D,$8C,$8D,$8C
.byte $76,$77,$76,$77,$76,$77,$B0,$B1,$79,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$78,$B0,$B1,$79,$9C,$9D,$9C,$9D,$9C,$9D,$9C 
.byte $A0,$A1,$A0,$A1,$A0,$A1,$A0,$A1,$69,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$68,$A0,$A1,$69,$8C,$8D,$8C,$8D,$8C,$8D,$8C
.byte $B0,$B1,$B0,$B1,$B0,$B1,$B0,$B1,$79,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$78,$B0,$B1,$79,$9C,$9D,$9C,$9D,$9C,$9D,$9C
.byte $6A,$6B,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$8C,$8D,$68,$A0,$A1,$69,$8C,$8D,$8C,$8D,$8C,$8D,$8C
.byte $7A,$7B,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$9C,$9D,$78,$B0,$B1,$79,$9C,$9D,$9C,$9D,$9C,$9D,$9C 
; Each byte of attribute table covers four quadrants, pack four quadrants into a singe byte 
; EX. 00(bottom right) 00(bottom left) 00(top right) 00(top left)
; EX 1. 01 10 00 11 -> 0110 0011 -> $63 
; 10100110 -> A6
; palette 0 (00), palette 1 (01), palette 2 (10), or palette 3 (11) 
attribute:
.byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
.byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
.byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
.byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
.byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
.byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
.byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
.byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
.segment "CHARS"
.incbin "cat_and_mushroom.sav"
