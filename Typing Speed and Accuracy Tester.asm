; =============================================================================
;  Typing Speed and Accuracy Tester  (3-round, 8086, EMU8086/DOS)
;  Reports CPM, WPM, accuracy, per-round breakdown and elapsed time.
;
;  Feature set:
;    A) WPM beside CPM; red/white colour echo; 3-2-1 countdown; retry/quit
;    B) per-round results + correct/typed counts; one-decimal elapsed time
;    C) extended-key (arrow/F-key) filtering; ESC to abort; empty-Enter guard
;
;  NOTE: comments are ASCII-only (the original CP949 Korean comments showed
;  up as mojibake). Comments never affect the assembled code.
; =============================================================================
.model small
.stack 100h

.data
    ; --- Intro / prompt strings --------------------------------------------
    welcome_msg  db 'Welcome to Typing Speed Tester!!', 13, 10, '$'
    prompt_msg   db 'Press any key to start...', 13, 10, '$'
    input_prompt db 13, 10, 13, 10, 'Type here: $'

    ; --- Countdown / retry UI ----------------------------------------------
    count_msg db 'Get ready! Starting in ... $'
    start_msg db 13, 10, 13, 10, '   START!', 13, 10, '$'
    again_msg db 13, 10, 13, 10, ' Press R to retry, ESC to quit.$'

    ; --- Three target sentences --------------------------------------------
    target1 db 'Welcome to Hankuk University of Foreign Studies Computer Science!', 13, 10, '$'
    target2 db 'Understanding Big-O complexity is crucial for dynamic programming.', 13, 10, '$'
    target3 db 'Convolutional Neural Networks excel at recognizing image features.', 13, 10, '$'

    target_ptrs     dw offset target1, offset target2, offset target3
    current_round   dw 0
    selected_target dw ?

    ; --- Aggregate + per-round statistics ----------------------------------
    total_typed   dw 0
    total_correct dw 0
    round_typed   dw 3 dup(0)   ; characters typed in each round
    round_correct dw 3 dup(0)   ; correct characters in each round

    ; --- Round header UI ----------------------------------------------------
    round_msg db '=== Round $'
    round_max db ' / 3 ===', 13, 10, 13, 10, '$'

    ; --- Final result UI ----------------------------------------------------
    res_top     db 13, 10, 13, 10, '=============================', 13, 10, '    FINAL TEST RESULTS       ', 13, 10, '=============================', 13, 10, '$'
    acc_msg     db ' Accuracy     : $'
    speed_msg   db 13, 10, ' Typing Speed : $'
    wpm_msg     db 13, 10, ' Speed (WPM)  : $'
    correct_msg db 13, 10, ' Correct      : $'
    errors_msg  db 13, 10, ' Errors       : $'
    time_msg    db 13, 10, ' Total Time   : $'
    res_bot     db 13, 10, '=============================', 13, 10, '$'
    cpm_unit    db ' CPM$'
    wpm_unit    db ' WPM$'
    sec_unit    db ' sec$'

    ; --- Per-round breakdown UI --------------------------------------------
    rounds_hdr db 13, 10, ' Per-round results:', 13, 10, '$'
    rb_label   db '   Round $'
    rb_colon   db ' : $'
    rb_open    db '   ($'
    crlf_msg   db 13, 10, '$'

    ; --- Scratch for the colour-echo subroutine ----------------------------
    tmp_char db 0
    tmp_attr db 0

    ; --- Input buffer and timing -------------------------------------------
    MAX_INPUT      equ 100
    user_input     db MAX_INPUT dup('$')
    start_time     dw 0
    end_time       dw 0
    elapsed_secs   dw 0         ; whole seconds (used by CPM/WPM)
    elapsed_tenths dw 0         ; tenths of a second (used for "12.4 sec")

.code
main proc
    mov ax, @data
    mov ds, ax

    ; Force 80x25 colour text mode (mode 3) once at startup.
    mov ax, 0003h
    int 10h

    ; 1. Intro (shown once, skipped on retry).
    lea dx, welcome_msg
    mov ah, 09h
    int 21h
    lea dx, prompt_msg
    mov ah, 09h
    int 21h
    mov ah, 07h
    int 21h

; -----------------------------------------------------------------------------
;  RESTART POINT - the retry option jumps back here.
; -----------------------------------------------------------------------------
restart_point:
    mov current_round, 0
    mov total_typed, 0
    mov total_correct, 0

    ; 2. Countdown "3 2 1 START" (before the timer, so setup time is free).
    call clear_screen
    lea dx, count_msg
    mov ah, 09h
    int 21h

    mov bl, '3'
countdown_loop:
    mov dl, bl
    mov ah, 02h
    int 21h
    mov cx, 18              ; ~1 second
    call delay_ticks
    mov dl, 8
    mov ah, 02h
    int 21h
    mov dl, ' '
    mov ah, 02h
    int 21h
    mov dl, 8
    mov ah, 02h
    int 21h
    dec bl
    cmp bl, '0'
    ja  countdown_loop
    lea dx, start_msg
    mov ah, 09h
    int 21h
    mov cx, 9              ; ~0.5 second on "START!"
    call delay_ticks

    ; 3. Start the overall timer.
    mov ah, 00h
    int 1Ah
    mov start_time, dx

round_start:
    ; 4. Clear screen.
    call clear_screen

    ; 5. "=== Round X / 3 ==="
    lea dx, round_msg
    mov ah, 09h
    int 21h
    mov ax, current_round
    inc ax
    add al, '0'
    mov dl, al
    mov ah, 02h
    int 21h
    lea dx, round_max
    mov ah, 09h
    int 21h

    ; 6. Pick this round's sentence.
    mov bx, current_round
    shl bx, 1
    mov dx, target_ptrs[bx]
    mov selected_target, dx
    mov ah, 09h
    int 21h
    lea dx, input_prompt
    mov ah, 09h
    int 21h

    mov si, 0

; -----------------------------------------------------------------------------
;  Input loop.  Read with NO echo (AH=08h) for full control of colour,
;  Backspace, extended keys and ESC.  Far targets are reached via JMP so the
;  conditional jumps stay inside their short-jump range.
; -----------------------------------------------------------------------------
input_loop:
    mov ah, 08h
    int 21h

    cmp al, 0               ; extended key (arrow, F-key, ...)?
    jne il_chk_esc
    mov ah, 08h             ; discard the following scan code
    int 21h
    jmp input_loop
il_chk_esc:
    cmp al, 27              ; ESC -> abort the whole program
    jne il_chk_enter
    jmp end_program
il_chk_enter:
    cmp al, 13              ; Enter -> finish round (but not if empty)
    jne il_chk_bs
    cmp si, 0
    je  input_loop          ; empty-Enter guard: must type something
    jmp round_end
il_chk_bs:
    cmp al, 8               ; Backspace
    jne il_store
    jmp handle_backspace
il_store:
    cmp si, MAX_INPUT-1     ; buffer full -> ignore
    jae input_loop

    mov user_input[si], al

    ; Choose colour by comparing with the expected character.
    mov bx, selected_target
    add bx, si
    mov ah, [bx]
    cmp al, ah
    je  echo_white
    mov bl, 0Ch             ; bright red on black
    call putchar_attr
    mov dl, 07h             ; beep on mismatch
    mov ah, 02h
    int 21h
    jmp next_char
echo_white:
    mov bl, 0Fh             ; bright white on black
    call putchar_attr
next_char:
    inc si
    jmp input_loop

handle_backspace:
    cmp si, 0
    je input_loop
    mov dl, 8
    mov ah, 02h
    int 21h
    mov dl, ' '
    mov ah, 02h
    int 21h
    mov dl, 8
    mov ah, 02h
    int 21h
    dec si
    jmp input_loop

round_end:
    ; 7a. Accumulate typed count.
    mov ax, total_typed
    add ax, si
    mov total_typed, ax

    ; 7b. Count exact matches into DI; CX keeps the typed count.
    mov bx, selected_target
    mov cx, si
    mov si, 0
    mov di, 0
compare_loop:
    cmp si, cx
    je update_correct
    mov al, user_input[si]
    push bx
    add bx, si
    mov ah, [bx]
    pop bx
    cmp al, ah
    jne skip_count
    inc di
skip_count:
    inc si
    jmp compare_loop
update_correct:
    mov ax, total_correct
    add ax, di
    mov total_correct, ax

    ; Store this round's stats into the per-round arrays.
    mov bx, current_round
    shl bx, 1
    mov round_typed[bx], cx
    mov round_correct[bx], di

    inc current_round
    cmp current_round, 3
    jl round_start

finish_all:
    ; 9. Stop timer; convert ticks to tenths-of-seconds and whole seconds.
    mov ah, 00h
    int 1Ah
    mov end_time, dx

    mov ax, end_time
    sub ax, start_time      ; AX = elapsed ticks
    mov cx, 100
    mul cx                  ; DX:AX = ticks * 100
    mov cx, 182
    div cx                  ; AX = tenths of seconds (18.2065 ticks/sec)
    mov elapsed_tenths, ax
    xor dx, dx
    mov cx, 10
    div cx                  ; AX = whole seconds, DX = .x digit (unused here)
    mov elapsed_secs, ax

    cmp elapsed_secs, 0     ; guard the CPM/WPM divisions
    jne calculate
    mov elapsed_secs, 1

calculate:
    cmp total_typed, 0
    je end_program

    call clear_screen

    lea dx, res_top
    mov ah, 09h
    int 21h

    ; --- Overall accuracy (%) ---------------------------------------------
    lea dx, acc_msg
    mov ah, 09h
    int 21h
    mov ax, total_correct
    mov cx, 100
    mul cx
    div total_typed
    call print_number
    mov dl, '%'
    mov ah, 02h
    int 21h

    ; --- CPM ---------------------------------------------------------------
    lea dx, speed_msg
    mov ah, 09h
    int 21h
    mov ax, total_typed
    mov cx, 60
    mul cx
    mov cx, elapsed_secs
    div cx
    call print_number
    lea dx, cpm_unit
    mov ah, 09h
    int 21h

    ; --- WPM ---------------------------------------------------------------
    lea dx, wpm_msg
    mov ah, 09h
    int 21h
    mov ax, total_typed
    mov cx, 12
    mul cx
    mov cx, elapsed_secs
    div cx
    call print_number
    lea dx, wpm_unit
    mov ah, 09h
    int 21h

    ; --- Correct / Errors counts ------------------------------------------
    lea dx, correct_msg
    mov ah, 09h
    int 21h
    mov ax, total_correct
    call print_number

    lea dx, errors_msg
    mov ah, 09h
    int 21h
    mov ax, total_typed
    sub ax, total_correct   ; errors = typed - correct
    call print_number

    ; --- Total time with one decimal place ("12.4 sec") -------------------
    lea dx, time_msg
    mov ah, 09h
    int 21h
    mov ax, elapsed_tenths
    xor dx, dx
    mov cx, 10
    div cx                  ; AX = whole seconds, DX = fractional tenth
    push dx                 ; save the fractional digit across the call
    call print_number       ; print the integer part
    mov dl, '.'
    mov ah, 02h
    int 21h
    pop dx                  ; recover the fractional digit
    add dl, '0'
    mov ah, 02h
    int 21h
    lea dx, sec_unit
    mov ah, 09h
    int 21h

    ; --- Per-round breakdown:  "Round n : XX%   (correct/typed)" ----------
    lea dx, rounds_hdr
    mov ah, 09h
    int 21h
    mov si, 0               ; SI = round index 0..2
perround_loop:
    cmp si, 3
    jae perround_done

    lea dx, rb_label
    mov ah, 09h
    int 21h
    mov ax, si              ; round number = index + 1
    inc ax
    add al, '0'
    mov dl, al
    mov ah, 02h
    int 21h
    lea dx, rb_colon
    mov ah, 09h
    int 21h

    ; accuracy = round_correct * 100 / round_typed (guard typed = 0)
    mov bx, si
    shl bx, 1
    mov ax, round_typed[bx]
    cmp ax, 0
    je  pr_zero
    mov ax, round_correct[bx]
    mov cx, 100
    mul cx
    mov cx, round_typed[bx]
    div cx
    jmp pr_show
pr_zero:
    mov ax, 0
pr_show:
    call print_number
    mov dl, '%'
    mov ah, 02h
    int 21h

    ; "   (correct/typed)"
    lea dx, rb_open
    mov ah, 09h
    int 21h
    mov bx, si
    shl bx, 1
    mov ax, round_correct[bx]
    call print_number
    mov dl, '/'
    mov ah, 02h
    int 21h
    mov bx, si
    shl bx, 1
    mov ax, round_typed[bx]
    call print_number
    mov dl, ')'
    mov ah, 02h
    int 21h
    lea dx, crlf_msg
    mov ah, 09h
    int 21h

    inc si
    jmp perround_loop
perround_done:

    lea dx, res_bot
    mov ah, 09h
    int 21h

    ; 11. Retry / quit prompt.
    lea dx, again_msg
    mov ah, 09h
    int 21h
ask_again:
    mov ah, 07h
    int 21h
    cmp al, 27
    je  end_program
    cmp al, 'r'
    je  restart_point
    cmp al, 'R'
    je  restart_point
    jmp ask_again

end_program:
    mov ah, 4Ch
    int 21h
main endp

; =============================================================================
;  print_number : print unsigned AX as decimal ASCII. All registers preserved.
; =============================================================================
print_number proc
    push ax
    push bx
    push cx
    push dx
    mov cx, 0
    mov bx, 10
divide_loop:
    mov dx, 0
    div bx
    push dx
    inc cx
    cmp ax, 0
    jne divide_loop
print_digits:
    pop dx
    add dl, '0'
    mov ah, 02h
    int 21h
    loop print_digits
    pop dx
    pop cx
    pop bx
    pop ax
    ret
print_number endp

; =============================================================================
;  delay_ticks : busy-wait for CX BIOS timer ticks (~CX/18.2 s). Regs preserved.
; =============================================================================
delay_ticks proc
    push ax
    push bx
    push dx
    mov ah, 00h
    int 1Ah
    mov bx, dx
dt_wait:
    mov ah, 00h
    int 1Ah
    sub dx, bx
    cmp dx, cx
    jb  dt_wait
    pop dx
    pop bx
    pop ax
    ret
delay_ticks endp

; =============================================================================
;  putchar_attr : write AL with attribute BL at the cursor and advance it.
;  INT 10h/03h (read cursor) -> INT 10h/09h (write char+attr, no move) ->
;  INT 10h/02h (move cursor, with line wrap). All registers preserved.
; =============================================================================
putchar_attr proc
    push ax
    push bx
    push cx
    push dx
    mov tmp_char, al
    mov tmp_attr, bl

    mov ah, 03h
    mov bh, 0
    int 10h                 ; DH=row, DL=col

    mov al, tmp_char
    mov bl, tmp_attr
    mov bh, 0
    mov cx, 1
    mov ah, 09h
    int 10h

    inc dl
    cmp dl, 80
    jb  set_cur
    mov dl, 0
    inc dh
set_cur:
    mov ah, 02h
    mov bh, 0
    int 10h

    pop dx
    pop cx
    pop bx
    pop ax
    ret
putchar_attr endp

; =============================================================================
;  clear_screen : blank the whole 80x25 window to attribute 07h and home the
;  cursor.  Uses INT 10h/06h (scroll up, AL=0 = clear) which RESETS the colour
;  attribute of every cell - unlike a same-mode set, which can leave stale
;  attributes behind and make later teletype text inherit old colours.
;  All registers preserved.
; =============================================================================
clear_screen proc
    push ax
    push bx
    push cx
    push dx
    mov ax, 0600h           ; AH=06 scroll up, AL=00 -> clear entire window
    mov bh, 07h             ; blanked cells get attribute 07h (grey on black)
    mov cx, 0000h           ; top-left  = (row 0, col 0)
    mov dx, 184Fh           ; bottom-right = (row 24, col 79)
    int 10h
    mov ah, 02h             ; move cursor home
    mov bh, 00h
    mov dx, 0000h
    int 10h
    pop dx
    pop cx
    pop bx
    pop ax
    ret
clear_screen endp

end main
