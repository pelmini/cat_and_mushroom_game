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

.define PPUCTRL      $2000
.define PPUMASK      $2001
.define PPUSTATUS    $2002
.define PPUADDR      $2006
.define PPUSCROLL    $2005
.define PPUDATA      $2007

.define NAMETABLE_0_HI $20
.define NAMETABLE_0_LO $00
.define ATTRTABLE_0_HI $23
.define ATTRTABLE_0_LO $C0
.define BGPALETTE_HI   $3F
.define BGPALETTE_LO   $00

.segment "ZEROPAGE"
nametable_ptr_lo:
.byte $00
nametable_ptr_hi:
.byte $00
frame_counter:
.byte $00

; bgpalette was moved to ZEROPAGE so we can manipulate it
; in RAM.  It was previously part of ROM and thus immutable

bgpalette:
palette0_color0:
  .byte $00
palette0_color1:
  .byte $00
palette0_color2:
  .byte $00
palette0_color3:
  .byte $00 ; palette 0
palette1_color0:
  .byte $00
palette1_color1:
  .byte $00
palette1_color2:
  .byte $00
palette1_color3:
  .byte $00
palette2_color0:
  .byte $00
palette2_color1:
  .byte $00
palette2_color2:
  .byte $00
palette2_color3:
  .byte $00
palette3_color0:
  .byte $00
palette3_color1:
  .byte $00
palette3_color2:
  .byte $00
palette3_color3:
  .byte $00


; Mandatory iNES header.
.segment "HEADER"

.byte "NES", $1A ; "NES" magic value
.byte 2          ; number of 16KB code pages (we don't need 2, but nes.cfg declares 2)
.byte 1          ; number of 8KB "char" data pages
.byte $00        ; "mapper" and bank-switching type (0 for "none")
.byte $00        ; background mirroring flats
                 ;
                 ; Note the header is 16 bytes but the nes.cfg will zero-pad for us.

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

  ; The palettes are now being stored in ZEROPAGE RAM so that
  ; they can be manipulated at runtime.  That means they need
  ; to be loaded with default values.  This loads palette 0
  ; defaults only because we don't use palette 1-3 yet.
  lda #$21
  sta palette0_color0
  lda #$1f
  sta palette0_color1
  lda #$16
  sta palette0_color2
  lda #$20
  sta palette0_color3

  ; load the background palette
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
  cpx #16
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
; infinite loop when there is nothing to compute 
; Needed for flow control, until the next nmi is ready
; will recieve signal from ppu to get out of loop 
  jmp forever

nmi:
  rti ; JUST DID TO PUT PAUSE ON ROTATE PALETTE UNTIL SHROOM HAS BEEN MADE!!!!!!!!
  ; dec - reducing the value by one 
  dec frame_counter
  ; bmi - branch if minus 
  ; if frame counter is less than zero then do rotate_palette
  bmi rotate_palette
  ; return from interrupt - end rotate code and go back to idle loop
  rti

rotate_palette:
  ; reset the frame counter
  lda #40
  sta frame_counter

  ; load palette color 1
  lda palette0_color1
  ; transfer to X
  ; X acts as a holder
  tax
  ; load palette color 2
  lda palette0_color2
  ; store palette color 2 to color 1
  sta palette0_color1
  ; load palette color 3
  lda palette0_color3
  ; store palette color 3 to color 2
  sta palette0_color2
  ; transfer X to A
  txa
  ; store in palette color 3
  sta palette0_color3

  ; Now reload the palettes

  ; load the background palette
  lda #BGPALETTE_HI
  sta PPUADDR
  lda #BGPALETTE_LO
  sta PPUADDR

  ; prep the loop
  ldx #0
rot_paletteloop:
  lda bgpalette, X ; load from the bgpalette array
  sta PPUDATA      ; store in PPUDATA, PPU will auto-increment
  inx              ; increment the X (index) register
  cpx #16
  bne rot_paletteloop  ; run the loop until X=16 (size of the palettes)


  rti ; Return from the NMI (NTSC refresh interrupt)


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
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$28,$25,$2C,$2C,$2F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$37,$2F,$32,$2C,$24,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$86,$87,$88,$89,$8A,$8B,$8C,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$96,$97,$98,$99,$9A,$9B,$9C,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; Each byte of attribute table covers four quadrants, pack four quadrants into a singe byte 
; EX. 00(bottom right) 00(bottom left) 00(top right) 00(top left)
; EX 1. 01 10 00 11 -> 0110 0011 -> $63   
attribute:
.byte $63,$63,$63,$63,$63,$63,$63
.byte $63,$63,$63,$63,$63,$63,$63
.byte $63,$63,$63,$63,$63,$63,$63
.byte $63,$63,$63,$63,$63,$63,$63
.byte $63,$63,$63,$63,$63,$63,$63
.byte $63,$63,$63,$63,$63,$63,$63
.byte $63,$63,$63,$63,$63,$63,$63
.byte $63,$63,$63,$63,$63,$63,$63
.segment "CHARS"
.incbin "cat_sheet.sav"
