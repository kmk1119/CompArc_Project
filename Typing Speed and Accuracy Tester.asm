.model small
.stack 100h

.data
    welcome_msg  db 'Welcome to Typing Speed Tester!!', 13, 10, '$'
    prompt_msg   db 'Press any key to start...', 13, 10, '$'
    input_prompt db 13, 10, 13, 10, 'Type here: $'

    count_msg db 'Get ready! Starting in ... $'
    start_msg db 13, 10, 13, 10, '   START!', 13, 10, '$'
    again_msg db 13, 10, 13, 10, ' Press R to retry, ESC to quit.$'

    target1 db 'Welcome to Hankuk University of Foreign Studies Computer Science!', 13, 10, '$'
    target2 db 'Understanding Big-O complexity is crucial for dynamic programming.', 13, 10, '$'
    target3 db 'Convolutional Neural Networks excel at recognizing image features.', 13, 10, '$'

    target_ptrs     dw offset target1, offset target2, offset target3
    current_round   dw 0
    selected_target dw ?

    total_typed   dw 0
    total_correct dw 0
    round_typed   dw 3 dup(0)
    round_correct dw 3 dup(0)

    round_msg db '=== Round $'
    round_max db ' / 3 ===', 13, 10, 13, 10, '$'

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

    rounds_hdr db 13, 10, ' Per-round results:', 13, 10, '$'
    rb_label   db '   Round $'
    rb_colon   db ' : $'
    rb_open    db '   ($'
    crlf_msg   db 13, 10, '$'

    tmp_char db 0
    tmp_attr db 0

    MAX_INPUT      equ 100
    user_input     db MAX_INPUT dup('$')
    start_time     dw 0
    end_time       dw 0
    elapsed_secs   dw 0
    elapsed_tenths dw 0

.code
main proc
    mov ax, @data
    mov ds, ax

    mov ax, 0003h
    int 10h

    lea dx, welcome_msg
    mov ah, 09h
    int 21h
    lea dx, prompt_msg
    mov ah, 09h
    int 21h
    mov ah, 07h
    int 21h

restart_point:
    mov current_round, 0
    mov total_typed, 0
    mov total_correct, 0

    call clear_screen
    lea dx, count_msg
    mov ah, 09h
    int 21h

    mov bl, '3'
countdown_loop:
    mov dl, bl
    mov ah, 02h
    int 21h
    mov cx, 18
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
    mov cx, 9
    call delay_ticks

    mov ah, 00h
    int 1Ah
    mov start_time, dx

round_start:
    call clear_screen

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

input_loop:
    mov ah, 08h
    int 21h

    cmp al, 0
    jne il_chk_esc
    mov ah, 08h
    int 21h
    jmp input_loop
il_chk_esc:
    cmp al, 27
    jne il_chk_enter
    jmp end_program
il_chk_enter:
    cmp al, 13
    jne il_chk_bs
    cmp si, 0
    je  input_loop
    jmp round_end
il_chk_bs:
    cmp al, 8
    jne il_store
    jmp handle_backspace
il_store:
    cmp si, MAX_INPUT-1
    jae input_loop

    mov user_input[si], al

    mov bx, selected_target
    add bx, si
    mov ah, [bx]
    cmp al, ah
    je  echo_white
    mov bl, 0Ch
    call putchar_attr
    mov dl, 07h
    mov ah, 02h
    int 21h
    jmp next_char
echo_white:
    mov bl, 0Fh
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
    mov ax, total_typed
    add ax, si
    mov total_typed, ax

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

    mov bx, current_round
    shl bx, 1
    mov round_typed[bx], cx
    mov round_correct[bx], di

    inc current_round
    cmp current_round, 3
    jl round_start

finish_all:
    mov ah, 00h
    int 1Ah
    mov end_time, dx

    mov ax, end_time
    sub ax, start_time
    mov cx, 100
    mul cx
    mov cx, 182
    div cx
    mov elapsed_tenths, ax
    xor dx, dx
    mov cx, 10
    div cx
    mov elapsed_secs, ax

    cmp elapsed_secs, 0
    jne calculate
    mov elapsed_secs, 1

calculate:
    cmp total_typed, 0
    je end_program

    call clear_screen

    lea dx, res_top
    mov ah, 09h
    int 21h

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

    lea dx, correct_msg
    mov ah, 09h
    int 21h
    mov ax, total_correct
    call print_number

    lea dx, errors_msg
    mov ah, 09h
    int 21h
    mov ax, total_typed
    sub ax, total_correct
    call print_number

    lea dx, time_msg
    mov ah, 09h
    int 21h
    mov ax, elapsed_tenths
    xor dx, dx
    mov cx, 10
    div cx
    push dx
    call print_number
    mov dl, '.'
    mov ah, 02h
    int 21h
    pop dx
    add dl, '0'
    mov ah, 02h
    int 21h
    lea dx, sec_unit
    mov ah, 09h
    int 21h

    lea dx, rounds_hdr
    mov ah, 09h
    int 21h
    mov si, 0
perround_loop:
    cmp si, 3
    jae perround_done

    lea dx, rb_label
    mov ah, 09h
    int 21h
    mov ax, si
    inc ax
    add al, '0'
    mov dl, al
    mov ah, 02h
    int 21h
    lea dx, rb_colon
    mov ah, 09h
    int 21h

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

putchar_attr proc
    push ax
    push bx
    push cx
    push dx
    mov tmp_char, al
    mov tmp_attr, bl

    mov ah, 03h
    mov bh, 0
    int 10h

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

clear_screen proc
    push ax
    push bx
    push cx
    push dx
    mov ax, 0600h
    mov bh, 07h
    mov cx, 0000h
    mov dx, 184Fh
    int 10h
    mov ah, 02h
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
