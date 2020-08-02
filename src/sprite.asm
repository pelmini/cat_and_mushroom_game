; NES Controller Basics
;
; This lab introduces some incredibly basic code for reading the controller
; state.  This will work in the most basic scenario, which is for reading a
; standard NES dpad controller, which most emulators will support out of the
; box.
;
; The controller interface works as follows:
; * Writing to the controller register with the strobe bit active causes the
;   controller's latches to run in "parallel" mode.  Any reads from the
;   register at this time will give real-time updates on the state of the first
;   button of the controller (for a dpad, that's A).
; * A subsequent write to the register with the strobe bit inactive latches in
;   the last state of the buttons and a shift register will let you read them
;   out, one button per read.  Different controllers will report on different
;   bits in the read, but the standard dpad will always report on bit 0.
;
; Want to know more about controller reading?  See here:
;
; * http://wiki.nesdev.com/w/index.php/Standard_controller
; * http://wiki.nesdev.com/w/index.php/Controller_reading
; * http://wiki.nesdev.com/w/index.php/Controller_reading_code
;
; Really, that's it.  Just for this lab, the R button now controls the walk
; animation, so the little man now runs only when you tell him to.  To achieve
; this, I simply inhibit the walk cycle animation unless the button has been
; pressed.  I sample constantly in the main loop and set a flag, which the
; NMI vector checks before performing any animations.
;
; Believe it or not, at this point, we know enough to make bigger and better
; applications.  But this code here is horribly structured for doing so.  So,
; in my next lab, I'm going to clean this up, reorganize it, and try to make
; a more workable "engine" on which to put advanced topics.
;
; Tiny note: I changed the ZEROPAGE to DATA here merely for correctness' sake.
; The ZEROPAGE should always contain unitialized data, but some of the data
; was initialized and this gives a linker warning.
;
; Thanks again for reading this far and taking this NES 6502 journey with me!

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

; APU REGISTERS

; Pulse/square generator 1
.define PULSE_1_DUTY_VOL  $4000
.define PULSE_1_SWEEP     $4001
.define PULSE_1_PERIOD_LO $4002
.define PULSE_1_PERIOD_HI $4003

; Pulse/square generator 2
.define PULSE_2_DUTY_VOL  $4004
.define PULSE_2_SWEEP     $4005
.define PULSE_2_PERIOD_LO $4006
.define PULSE_2_PERIOD_HI $4007

; Triangle wave generator
.define TRI_LINEAR_COUNTER $4008
.define TRI_UNUSED         $4009
.define TRI_TIMER_LO       $400A
.define TRI_COUNT_TIMER_HI $400B

; Noise generator
.define NOISE_ENV_LEN_VOL    $400C
.define NOISE_UNUSED         $400D
.define NOISE_MODE_PERIOD    $400E
.define NOISE_LENGTH_COUNTER $400F

; Delta modulation (sample) player
.define DMC_FLAGS_RATE      $4010
.define DMC_VOL_DIRECT_LOAD $4011
.define DMC_SAMPLE_ADDRESS  $4012
.define DMC_SAMPLE_LENGTH   $4013

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

; Mandatory iNES header.
.segment "HEADER"

.byte "NES", $1A ; "NES" magic value
.byte 2          ; number of 16KB code pages (we don't need 2, but nes.cfg declares 2)
.byte 1          ; number of 8KB "char" data pages
.byte $00        ; "mapper" and bank-switching type (0 for "none")
.byte $00        ; background mirroring flats
                 ;
                 ; Note the header is 16 bytes but the nes.cfg will zero-pad for us.

; "zero page" RAM
; This is where we're storing our mutable state.
.segment "DATA"
current_frame:
  .byte 0
sprite_x:
  .byte $7F
sprite_y:
  .byte $7F
frame_count:
  .byte 0
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

; load the palettes
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
  bne paletteloop  ; run the loop until X=32 (size of the palettes)

; move PPUADDR over to nametable 0. 
  lda #NAMETABLE_0_HI
  sta PPUADDR
  lda #NAMETABLE_0_LO
  sta PPUADDR

; set up Palette 0 for everything
  bit PPUSTATUS
  lda #ATTRTABLE_0_HI
  sta PPUADDR
 lda #ATTRTABLE_0_LO
  sta PPUADDR
  ldx #64 ; 64 tiles in the attribute table
  lda #0

attrloop:
  sta PPUDATA
  dex
  bne attrloop

; zero out the OAM DMA shadow page
  ldx #$FF
  lda $0
zero_oam:
  sta SPRITE_PAGE, X
  dex
  bne zero_oam

; Set up the sprite's base x and y coordinates
; and frame index (i.e. where in the animation we are)
; and then call load_sprite to do the hard work

  lda #0
  sta current_frame
  lda #0
  sta frame_count
; Load the sprite
  jsr load_sprite

; Enable background and sprite rendering.
  lda #$1e
  sta PPUMASK

; Initialize the APU.
  jsr init_apu

; Since we're going to use only one sound in this demo, let's go ahead and
; configure it.

; Enable noise tone mode, lowest tone supported (deep rumble)
  lda #$8F
  sta NOISE_MODE_PERIOD

; generate NMI
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
; OAM DMA must always be a transfer from address XX00-XXFF, so we write
; the value of XX (in this case, 2) to OAM_DMA ($4014) to trigger the
; transfer

  lda #OAM_PAGE
  sta OAM_DMA 

; Here we keep a count of the NMIs as they come in.  Until we count 15
; of them, which is roughly a quarter second, just keep holding on the
; existing sprite.
  inc frame_count
  lda frame_count
  cmp #5
  bne done
  lda #0
  sta frame_count

; If run is 0, don't do anything
  lda run
  cmp #0
  beq done

; We counted 15 NMIs, so let's update the animation frame and
; make the little character walk
  lda current_frame
  clc                   ; NEVER forget to clear the carry flag before adding
  adc #6                ; Each frame is an offset of a multiple of 6
  cmp #24               ; After 4 frames, wrap around (4*6 = 24)
  bne dont_cycle_anim
; Make a little sound on every cycle through the animation

; Load up 2 cycles of the length counter
  lda #$10
  sta NOISE_LENGTH_COUNTER

; Full volume, run the length counter
  lda #$1F
  sta NOISE_ENV_LEN_VOL

; Reset the animation cycle
  lda #0

dont_cycle_anim:
  sta current_frame


  lda sprite_x
  clc
  adc #2
  sta sprite_x
dont_reset_x:
  sta sprite_x


done:
  jsr load_sprite
  rti                   ; Return from the NMI (NTSC refresh interrupt)

; load_sprite consults current_frame to determine the offset into anim
; and then draws the data in that row of anim into a 2x3 rectangle
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
  adc #7               ; move to right cell
  sta sprite_x
  inx
; Second of two cells
  lda sprite_y
  sta SPRITE_PAGE, X
  clc
  adc #7
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
  sbc #7              ; return to the left cell
  sta sprite_x
  inx
;; Loop if we haven't loaded the full sprite
  cpx #24
  bne load_loop
  lda sprite_y
  sec
  sbc #14
  sta sprite_y
  rts
.endproc

; Initialize the Audio Processing Unit (APU)
; This will load the APU with default values guaranteed
; to not make sound.
;
; It's more effective to do this as a table of bytes and
; load the registers with a loop, but tis will give us a
; chance to discuss what they do.
; 
; For more details, see the following pages:
; http://wiki.nesdev.com/w/index.php/APU_basics
; http://wiki.nesdev.com/w/index.php/APU_registers
; http://wiki.nesdev.com/w/index.php/APU_DMC

.proc init_apu
; Note there are 2 pulse (square) wave units, and both are initialized
; to the same values.

; Duty cycle 0, length counter halted (1), constant volume (1), vol 0
  lda #$30
  sta PULSE_1_DUTY_VOL
  sta PULSE_2_DUTY_VOL

; Sweep not enabled, no period, sweep upward (1), pitch shift step 0
  lda #$08
  sta PULSE_1_SWEEP
  sta PULSE_2_SWEEP

; Period 0 (no waveform)
  lda #$00
  sta PULSE_1_PERIOD_LO
  sta PULSE_1_PERIOD_HI
  sta PULSE_2_PERIOD_LO
  sta PULSE_2_PERIOD_HI

; Halt tri linear counter, load 0 into counter
  lda #$80
  sta TRI_LINEAR_COUNTER

; Unusued register, 0 out
  lda #$00
  sta TRI_UNUSED

; Set frequency timer (frequency control) to 0
  sta TRI_TIMER_LO
  sta TRI_COUNT_TIMER_HI

; Length counter halt(1), constant volume(1), envelope period 0
  lda #$30
  sta NOISE_ENV_LEN_VOL

; Not used, zero out
  lda #$00
  sta NOISE_UNUSED

; Set period and length to 0
  sta NOISE_MODE_PERIOD
  sta NOISE_LENGTH_COUNTER

; DMC (sample playback) control
; No IRQ generation, no loop, frequency 0
  sta DMC_FLAGS_RATE

; No sample loaded directly to DMC
  sta DMC_VOL_DIRECT_LOAD

; No sample indirectly in memory, so 0 address and 0 length
  sta DMC_SAMPLE_ADDRESS
  sta DMC_SAMPLE_LENGTH

; Disable DMC length counter, enable all 4 synths
  lda #$0F
  sta DMC_LEN_CNT_CTRL_STA

; 4x frame (i.e. 240Hz) counter, disable frame counter interrupt
  lda #$40
  sta FRAME_CNT_MODE_INT

rts
.endproc

; The background colors are, in order:
; $0F: black
; $15: red
; $22: blue
; $20: white

bgpalette:
  .byte $0F, $15, $22, $20 ; palette 0
  .byte $0F, $15, $22, $20 ; palette 1
  .byte $0F, $15, $22, $20 ; palette 2
  .byte $0F, $15, $22, $20 ; palette 3

; The foreground/sprite colors are:
; $0F: black
; $07: dark brown
; $19: drab green
; $20: white

spritepalette:
  .byte $0F, $07, $19, $20 ; palette 0
  .byte $0F, $07, $19, $20 ; palette 1
  .byte $0F, $07, $19, $20 ; palette 2
  .byte $0F, $07, $19, $20 ; palette 3

; This describes each "frame" or "cell" of the walk animation.  I decided to
; write out an animation table rather than alter the pattern table.  This
; means that load_sprite is a little less efficient than it probably ought be,
; but makes the pattern table easier to visually think about in a debugger
; like fceux.  Each byte here is an address in the pattern table; you'll
; recognize them from the previous lab.

anim:
  .byte $A0, $A1, $B0, $B1, $C0, $C1 ; frame 1
  .byte $A2, $A3, $B2, $B3, $C2, $C3 ; frame 2
  .byte $A4, $A5, $B4, $B5, $C4, $C5 ; frame 3
  .byte $A6, $A7, $B6, $B7, $C6, $C7 ; frame 4

; vectors declaration
.segment "VECTORS"
.word nmi
.word reset
.word 0

; As mentioned above, this is the place where you put your pattern table data
; so that it can automatically be mapped into the PPU's memory at $0000-$1FFF.
; Note the use of .incbin so I can just import a binary file.  Neato!

.segment "CHARS"
.incbin "generitiles.pat"
