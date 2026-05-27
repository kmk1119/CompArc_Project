; =============================================================================
;  Static Typing Speed and Accuracy Trainer
;  Final integrated build (Phases 1 - 4)
;
;    Phase 1 : Base text editor  - keystroke input, screen echo, backspace,
;                                  enter-to-finish.
;    Phase 2 : Timer integration - elapsed typing time via the BIOS tick clock.
;    Phase 3 : Validation logic  - byte-by-byte comparison, accuracy %, WPM.
;    Phase 4 : Result display    - binary-to-ASCII conversion and formatted
;                                  on-screen report.
;
;  Target  : Intel 8086, 16-bit real mode, assembled/run in EMU8086 (MS-DOS).
;  Rules   : 16-bit registers only. No external libraries.
;            Services used:
;              BIOS  INT 10h  - video (clear screen, set cursor)
;              BIOS  INT 16h  - keyboard (blocking read)
;              BIOS  INT 1Ah  - system timer tick counter
;              DOS   INT 21h  - character/string output, program terminate
; =============================================================================

; -----------------------------------------------------------------------------
;  STACK SEGMENT
;  Provides working space for CALL return addresses and PUSH/POP operations.
; -----------------------------------------------------------------------------
STACK_SEG SEGMENT STACK
        DW 128 DUP(0)            ; 128 words = 256 bytes of stack
STACK_SEG ENDS

; -----------------------------------------------------------------------------
;  DATA SEGMENT
; -----------------------------------------------------------------------------
DATA_SEG SEGMENT

        ; --- Named key codes (improves readability of CMP instructions) ------
        KEY_ENTER   EQU 0Dh              ; ASCII Carriage Return  -> finish
        KEY_BACKSP  EQU 08h              ; ASCII Backspace        -> delete

        ; --- Target sentence the user must reproduce -------------------------
        ; The text and a trailing '$' (the DOS INT 21h/09h string terminator)
        ; bracket the EQU below, so target_len = exact byte count of the text,
        ; WITHOUT counting the '$'.
        target_str  DB "The quick brown fox jumps over the lazy dog."
        target_len  EQU ($ - target_str) ; assembler computes the length here
                    DB '$'               ; terminator for printing (not counted)

        ; --- User input buffer ----------------------------------------------
        BUF_SIZE    EQU 200              ; maximum characters accepted
        buffer      DB BUF_SIZE DUP(0)   ; the typed text is collected here
        buf_len     DW 0                 ; number of characters actually typed

        ; --- Phase 2 : timing storage ---------------------------------------
        ; The BIOS tick counter is a 32-bit value, but we only have 16-bit
        ; registers, so every tick reading is kept as TWO 16-bit words
        ; (a low word and a high word).
        timer_on    DB 0                 ; 0 = timer not started, 1 = running
        start_lo    DW 0                 ; start tick count, low  16 bits
        start_hi    DW 0                 ; start tick count, high 16 bits
        end_lo      DW 0                 ; end   tick count, low  16 bits
        end_hi      DW 0                 ; end   tick count, high 16 bits
        elapsed_lo  DW 0                 ; (end - start) low  16 bits
        elapsed_hi  DW 0                 ; (end - start) high 16 bits
        elapsed_secs DW 0                ; elapsed time converted to whole seconds

        ; --- Phase 3 : results ----------------------------------------------
        cmp_len      DW 0                ; how many positions we compare
        correct_cnt  DW 0                ; count of matching characters
        accuracy     DW 0                ; accuracy percentage (0..100)
        wpm          DW 0                ; words-per-minute result

        ; --- Phase 4 : report message fragments (each ends with '$') --------
        msg_crlf    DB 0Dh,0Ah,'$'                 ; blank line / new line
        msg_time    DB 0Dh,0Ah,"Time: ",'$'
        msg_sec     DB " seconds",'$'
        msg_wpm     DB 0Dh,0Ah,"WPM: ",'$'
        msg_acc     DB 0Dh,0Ah,"Accuracy: ",'$'
        msg_pct     DB " %",0Dh,0Ah,'$'
DATA_SEG ENDS

; -----------------------------------------------------------------------------
;  CODE SEGMENT
; -----------------------------------------------------------------------------
CODE_SEG SEGMENT
        ASSUME CS:CODE_SEG, DS:DATA_SEG, SS:STACK_SEG

start:
        ; --- Point DS at our data segment ------------------------------------
        ; On load DOS leaves DS pointing at the PSP, not our data. A segment
        ; register cannot take an immediate, so we stage the value through AX.
        MOV AX, DATA_SEG        ; AX = paragraph address of the data segment
        MOV DS, AX              ; DS now addresses every label above

        ; --- Show the target sentence the user has to copy -------------------
        ; INT 21h, AH=09h : DOS "print string". DS:DX -> text, printed until '$'.
        MOV AH, 09h
        MOV DX, OFFSET target_str
        INT 21h
        ; Drop to the next line so typed input appears below the target.
        MOV AH, 09h
        MOV DX, OFFSET msg_crlf
        INT 21h

        ; --- Flush any stray keystrokes left in the BIOS buffer --------------
        ; When DOSBox launches us from the command line, the Enter key that
        ; started the program can still be sitting in the keyboard buffer.
        ; Without this drain, the very first INT 16h read below would return
        ; that Enter (0Dh) and the program would "finish" instantly. We peek
        ; with AH=01h (non-destructive, ZF=1 means buffer empty) and discard
        ; with AH=00h until the buffer is clear.
flush_kbd:
        MOV AH, 01h             ; INT 16h, AH=01h : peek at keyboard buffer
        INT 16h                 ; ZF=1 -> no key waiting; ZF=0 -> a key waits
        JZ  flush_done          ; buffer empty -> done flushing
        MOV AH, 00h             ; INT 16h, AH=00h : remove the waiting key
        INT 16h                 ; (result discarded)
        JMP flush_kbd
flush_done:

        ; SI is the buffer write pointer / current length while typing.
        XOR SI, SI              ; SI = 0 -> first free slot in the buffer

; -----------------------------------------------------------------------------
;  MAIN INPUT LOOP (Phase 1)
; -----------------------------------------------------------------------------
input_loop:
        ; INT 16h, AH=00h : BIOS blocking keyboard read.
        ;   Returns AL = ASCII character, AH = scan code.
        MOV AH, 00h
        INT 16h                 ; wait for a key -> AL holds its ASCII value

        CMP AL, KEY_ENTER       ; was it Enter (0Dh)?
        JE  done                ; yes -> stop the test and score it

        CMP AL, KEY_BACKSP      ; was it Backspace (08h)?
        JE  handle_backspace    ; yes -> erase the last character

        JMP store_char          ; otherwise treat it as printable text

; -----------------------------------------------------------------------------
;  STORE_CHAR : start timer on first keystroke, echo char, append to buffer
;  On entry: AL = ASCII character.
; -----------------------------------------------------------------------------
store_char:
        CMP SI, BUF_SIZE        ; buffer already full?
        JAE input_loop          ; if SI >= BUF_SIZE, ignore the key

        ; --- Phase 2 : capture the START time on the very first character ----
        CMP timer_on, 1         ; has the clock already been started?
        JE  echo_char           ; yes -> skip; we only stamp the first key
        ; INT 1Ah destroys AX/CX/DX, and AL currently holds the typed char,
        ; so we preserve AX across the call.
        PUSH AX                 ; save the typed character
        MOV AH, 00h             ; INT 1Ah, AH=00h : read system tick counter
        INT 1Ah                 ; -> CX = high word, DX = low word of ticks
        MOV start_hi, CX        ; remember start time (high word)
        MOV start_lo, DX        ; remember start time (low word)
        MOV timer_on, 1         ; flag the timer as running
        POP AX                  ; restore the typed character into AL

echo_char:
        ; INT 21h, AH=02h : DOS print character in DL (cursor auto-advances).
        MOV DL, AL              ; DL = character to display
        MOV AH, 02h
        INT 21h                 ; echo it to the screen
        ; AL is preserved by this service, so it still holds our character.

        MOV buffer[SI], AL      ; store the character at buffer[SI]
        INC SI                  ; advance the write pointer
        INC buf_len             ; keep the length counter in step

        JMP input_loop          ; wait for the next key

; -----------------------------------------------------------------------------
;  HANDLE_BACKSPACE : erase the last character on screen and in the buffer
;  Screen erase = print BS, space, BS  (left, blank-over, left again).
; -----------------------------------------------------------------------------
handle_backspace:
        CMP SI, 0               ; buffer empty?
        JE  input_loop          ; nothing to delete -> ignore the key

        MOV DL, KEY_BACKSP      ; 1) BS -> cursor moves one column left
        MOV AH, 02h
        INT 21h

        MOV DL, ' '             ; 2) space -> overwrite old char, cursor right
        MOV AH, 02h
        INT 21h

        MOV DL, KEY_BACKSP      ; 3) BS -> cursor back onto the cleared cell
        MOV AH, 02h
        INT 21h

        DEC SI                  ; retract the write pointer
        DEC buf_len             ; keep the length counter in step

        JMP input_loop          ; wait for the next key

; =============================================================================
;  DONE : Enter was pressed. Stop the clock, score the attempt, show results.
; =============================================================================
done:
        ; --- Phase 2 : capture the END time ----------------------------------
        MOV AH, 00h             ; INT 1Ah, AH=00h : read system tick counter
        INT 1Ah                 ; -> CX = high word, DX = low word of ticks
        MOV end_hi, CX
        MOV end_lo, DX

        ; If no character was ever typed the timer never started; report 0 s.
        CMP timer_on, 1
        JNE no_timing

        ; --- 32-bit subtraction:  elapsed = end - start ----------------------
        ; We subtract the low words first (which may produce a borrow), then
        ; the high words using SBB so the borrow propagates correctly.
        MOV AX, end_lo
        SUB AX, start_lo        ; AX = low difference; CF = borrow flag
        MOV elapsed_lo, AX
        MOV AX, end_hi
        SBB AX, start_hi        ; high difference minus the borrow from above
        MOV elapsed_hi, AX

        ; --- Convert elapsed ticks to whole seconds --------------------------
        ; The PC's programmable interval timer runs at 1,193,182 Hz and the
        ; BIOS counter increments once every 65,536 of those pulses, giving:
        ;        1,193,182 / 65,536  =  18.2065  ticks per second.
        ; Whole seconds is therefore  ticks / 18.2065, which we approximate
        ; with the integer divisor 18 (within ~1% - adequate for this trainer).
        ;
        ; DIV with a 16-bit operand divides the 32-bit pair DX:AX by it,
        ; leaving the quotient in AX and the remainder in DX. We load our
        ; 32-bit tick difference straight into DX:AX.
        MOV DX, elapsed_hi      ; DX = high word of dividend
        MOV AX, elapsed_lo      ; AX = low  word of dividend  (DX:AX = ticks)
        MOV BX, 18              ; BX = divisor (ticks per second, rounded)
        DIV BX                  ; AX = whole seconds, DX = leftover ticks
        MOV elapsed_secs, AX
        JMP scoring

no_timing:
        MOV elapsed_secs, 0     ; user pressed Enter without typing

; -----------------------------------------------------------------------------
;  Phase 3a : COMPARE the buffer against the target, character by character
; -----------------------------------------------------------------------------
scoring:
        ; We compare over the smaller of (typed length, target length) so we
        ; never read past the end of either array. cmp_len = min(buf_len,target).
        MOV AX, buf_len
        MOV BX, target_len
        CMP AX, BX
        JBE keep_min            ; if buf_len <= target_len, AX is already min
        MOV AX, BX              ; otherwise the target length is the smaller
keep_min:
        MOV cmp_len, AX

        ; Walk both arrays with a single index in BX. buffer[BX] and
        ; target_str[BX] both resolve to (segment_base + label + BX), so one
        ; index addresses the matching byte in each array.
        MOV correct_cnt, 0      ; reset the match counter
        XOR BX, BX              ; BX = index i = 0
cmp_loop:
        CMP BX, cmp_len         ; reached the end of the compared region?
        JAE cmp_done
        MOV AL, buffer[BX]      ; AL = character the user typed at position i
        MOV AH, target_str[BX]  ; AH = expected character at position i
        CMP AL, AH              ; do they match?
        JNE cmp_next            ; no -> skip the increment
        INC correct_cnt         ; yes -> one more correct character
cmp_next:
        INC BX                  ; advance to the next position
        JMP cmp_loop
cmp_done:

; -----------------------------------------------------------------------------
;  Phase 3b : ACCURACY (%) = correct_cnt * 100 / target_len
; -----------------------------------------------------------------------------
        ; Multiply first, then divide, to preserve precision in integer math.
        ; correct_cnt <= target_len (~44) so the product fits easily in AX and
        ; the result is naturally bounded to 0..100.
        MOV AX, correct_cnt
        MOV BX, 100
        MUL BX                  ; DX:AX = correct_cnt * 100
        MOV BX, target_len
        DIV BX                  ; AX = percentage, DX = remainder (discarded)
        MOV accuracy, AX

; -----------------------------------------------------------------------------
;  Phase 3c : WPM = (chars / 5) / minutes
; -----------------------------------------------------------------------------
        ; A "word" is conventionally 5 characters, and minutes = seconds / 60.
        ; Rearranging to avoid early rounding and stay in integers:
        ;     WPM = (chars / 5) / (secs / 60)
        ;         = (chars * 60) / (5 * secs)
        ;         = (chars * 12) / secs
        ; We guard against a divide-by-zero when the elapsed time rounds to 0 s.
        MOV BX, elapsed_secs
        CMP BX, 0
        JE  wpm_zero
        MOV AX, buf_len
        MOV CX, 12
        MUL CX                  ; DX:AX = buf_len * 12
        DIV BX                  ; AX = WPM (BX still holds elapsed_secs)
        MOV wpm, AX
        JMP wpm_done
wpm_zero:
        MOV wpm, 0
wpm_done:

; =============================================================================
;  Phase 4 : DISPLAY the results
; =============================================================================
        ; --- Clear the screen using the BIOS scroll service ------------------
        ; INT 10h, AH=06h with AL=0 blanks the whole window.
        ;   BH = attribute for the blanked cells (07h = light grey on black)
        ;   CH,CL = top-left  row,col   (0,0)
        ;   DH,DL = bottom-right row,col (24,79) -> DX = 184Fh
        MOV AX, 0600h
        MOV BH, 07h
        MOV CX, 0000h
        MOV DX, 184Fh
        INT 10h
        ; INT 10h, AH=02h : move the cursor home (page 0, row 0, col 0).
        MOV AH, 02h
        MOV BH, 00h
        MOV DX, 0000h
        INT 10h

        ; --- "Time: <secs> seconds" -----------------------------------------
        MOV AH, 09h
        MOV DX, OFFSET msg_time
        INT 21h
        MOV AX, elapsed_secs
        CALL PRINT_NUM          ; print the number in AX as decimal ASCII
        MOV AH, 09h
        MOV DX, OFFSET msg_sec
        INT 21h

        ; --- "WPM: <wpm>" ----------------------------------------------------
        MOV AH, 09h
        MOV DX, OFFSET msg_wpm
        INT 21h
        MOV AX, wpm
        CALL PRINT_NUM

        ; --- "Accuracy: <acc> %" --------------------------------------------
        MOV AH, 09h
        MOV DX, OFFSET msg_acc
        INT 21h
        MOV AX, accuracy
        CALL PRINT_NUM
        MOV AH, 09h
        MOV DX, OFFSET msg_pct
        INT 21h

        ; --- Hold the report on screen until the user presses a key ----------
        ; Without this pause the program would terminate immediately after
        ; printing, and (under DOSBox) the results would flash by before the
        ; user could read them. A blocking key read keeps the screen visible.
        MOV AH, 00h             ; INT 16h, AH=00h : wait for any keystroke
        INT 16h

        ; --- Terminate cleanly -----------------------------------------------
        ; INT 21h, AH=4Ch : return to DOS with the exit code in AL (0 = OK).
        MOV AH, 4Ch
        MOV AL, 00h
        INT 21h

; =============================================================================
;  SUBROUTINE  PRINT_NUM
;  Purpose : print the unsigned 16-bit value in AX as decimal ASCII text.
;  Method  : repeatedly divide by 10. Each division yields one decimal digit
;            as the remainder (0..9), produced least-significant-digit first.
;            We PUSH the digits onto the stack, then POP them back so they
;            print most-significant-digit first (the stack reverses the order).
;  Clobbers: none preserved -> all used registers are saved and restored.
; =============================================================================
PRINT_NUM PROC
        PUSH AX
        PUSH BX
        PUSH CX
        PUSH DX

        MOV CX, 0               ; CX = how many digits we have pushed
        MOV BX, 10              ; BX = divisor (decimal base)
pn_extract:
        XOR DX, DX              ; clear high word -> dividend is just AX
        DIV BX                  ; AX = AX/10 (quotient), DX = AX mod 10 (digit)
        PUSH DX                 ; stack the digit (0..9) for later
        INC CX                  ; one more digit recorded
        CMP AX, 0               ; any value left to break down?
        JNE pn_extract          ; if not zero, extract the next digit

pn_emit:
        POP DX                  ; retrieve digits in reverse (MSD first)
        ADD DL, '0'             ; convert numeric 0..9 to ASCII '0'..'9'
        MOV AH, 02h             ; INT 21h, AH=02h : print the character in DL
        INT 21h
        LOOP pn_emit            ; repeat for all CX digits (LOOP decrements CX)

        POP DX
        POP CX
        POP BX
        POP AX
        RET
PRINT_NUM ENDP

CODE_SEG ENDS
        END start               ; program entry point is label 'start'
