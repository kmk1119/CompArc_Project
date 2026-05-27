.model small
.stack 100h

.data
    ; 시작 및 안내 메시지
    welcome_msg db 'Welcome to Typing Speed Tester!!', 13, 10, '$'
    prompt_msg db 'Press any key to start...', 13, 10, '$'
    input_prompt db 13, 10, 13, 10, 'Type here: $'
    
    ; 3개의 긴 전공 제시문
    target1 db 'Welcome to Hankuk University of Foreign Studies Computer Science!', 13, 10, '$'
    target2 db 'Understanding Big-O complexity is crucial for dynamic programming.', 13, 10, '$'
    target3 db 'Convolutional Neural Networks excel at recognizing image features.', 13, 10, '$'
    
    ; [신규] 라운드 관리를 위한 배열 및 변수
    target_ptrs dw offset target1, offset target2, offset target3
    current_round dw 0      ; 현재 진행 중인 라운드 (0, 1, 2)
    selected_target dw ?    ; 현재 라운드의 제시문 주소
    
    ; [신규] 3라운드 전체 성적을 누적할 변수
    total_typed dw 0        ; 전체 입력한 글자 수
    total_correct dw 0      ; 전체 맞은 글자 수
    
    ; 라운드 UI 텍스트
    round_msg db '=== Round $'
    round_max db ' / 3 ===', 13, 10, 13, 10, '$'
    
    ; 결과창 UI 디자인 텍스트
    res_top db 13, 10, 13, 10, '=============================', 13, 10, '    FINAL TEST RESULTS       ', 13, 10, '=============================', 13, 10, '$'
    acc_msg db ' Accuracy     : $'
    speed_msg db 13, 10, ' Typing Speed : $'
    time_msg db 13, 10, ' Total Time   : $'
    res_bot db 13, 10, '=============================', 13, 10, '$'
    
    cpm_unit db ' CPM$'
    sec_unit db ' sec$'
    
    user_input db 100 dup('$') 
    start_time dw 0
    end_time dw 0
    elapsed_secs dw 0

.code
main proc
    mov ax, @data
    mov ds, ax

    ; 1. 시작 화면 출력
    lea dx, welcome_msg
    mov ah, 09h
    int 21h
    lea dx, prompt_msg
    mov ah, 09h
    int 21h

    ; 2. 대기 
    mov ah, 07h
    int 21h

    ; ==========================================
    ; 3. [전체 타이머 시작] 라운드 진입 직전 시계 확인
    ; ==========================================
    mov ah, 00h
    int 1Ah
    mov start_time, dx

round_start:
    ; 4. 화면 지우기 (매 라운드마다 깨끗하게 리셋)
    mov ax, 0003h
    int 10h

    ; 5. "=== Round X / 3 ===" 상단 UI 출력
    lea dx, round_msg
    mov ah, 09h
    int 21h
    
    mov ax, current_round
    inc ax             ; 0, 1, 2를 1, 2, 3으로 변환
    add al, '0'        ; 문자로 변환
    mov dl, al
    mov ah, 02h
    int 21h
    
    lea dx, round_max
    mov ah, 09h
    int 21h

    ; 6. 배열에서 현재 라운드 제시문 주소 꺼내오기
    mov bx, current_round
    shl bx, 1                   ; bx = bx * 2 (워드 단위 인덱스 계산)
    mov dx, target_ptrs[bx]
    mov selected_target, dx
    mov ah, 09h
    int 21h                     ; 제시문 화면 출력

    lea dx, input_prompt
    mov ah, 09h
    int 21h

    mov si, 0                   ; 타자 수 초기화

input_loop:
    mov ah, 01h      
    int 21h          
    
    cmp al, 13                  ; 엔터 치면 해당 라운드 종료
    je round_end    
    
    mov user_input[si], al  
    
    ; 실시간 오타 체크 (Beep)
    mov bx, selected_target
    push bx
    add bx, si       
    mov ah, [bx]     
    pop bx
    
    cmp al, ah       
    je correct_input 
    
    mov dl, 07h
    mov ah, 02h
    int 21h

correct_input:
    inc si           
    jmp input_loop   

round_end:
    ; ==========================================
    ; 7. 현재 라운드 누적 채점
    ; ==========================================
    ; (1) 이번에 친 글자 수를 전체 타수에 더함
    mov ax, total_typed
    add ax, si
    mov total_typed, ax

    ; (2) 정확도 채점 루프
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
    ; 이번에 맞춘 글자 수를 전체 정답수에 더함
    mov ax, total_correct
    add ax, di
    mov total_correct, ax

    ; 8. 다음 라운드로 이동
    inc current_round
    cmp current_round, 3
    jl round_start      ; 3라운드 미만이면 다음 라운드로 점프

finish_all:
    ; ==========================================
    ; 9. [전체 타이머 종료] 3라운드가 모두 끝나면 시간 측정
    ; ==========================================
    mov ah, 00h
    int 1Ah
    mov end_time, dx

    mov ax, end_time
    sub ax, start_time
    mov cx, 18
    mov dx, 0
    div cx
    mov elapsed_secs, ax 

    cmp elapsed_secs, 0
    jne calculate
    mov elapsed_secs, 1 

calculate:
    cmp total_typed, 0
    je end_program

    ; 10. 종합 결과창 UI 출력
    mov ax, 0003h
    int 10h           ; 마지막 결과창을 위해 화면 한 번 더 깔끔하게 지우기
    
    lea dx, res_top
    mov ah, 09h
    int 21h

    ; --- 전체 Accuracy 출력 ---
    lea dx, acc_msg
    mov ah, 09h
    int 21h
    
    mov ax, total_correct
    mov cx, 100
    mul cx        
    mov dx, 0     
    div total_typed        

    call print_number
    mov dl, '%'
    mov ah, 02h
    int 21h

    ; --- 종합 Typing Speed (CPM) 출력 ---
    lea dx, speed_msg
    mov ah, 09h
    int 21h

    mov ax, total_typed
    mov cx, 60
    mul cx          
    mov dx, 0
    mov cx, elapsed_secs
    div cx          
    
    call print_number
    lea dx, cpm_unit
    mov ah, 09h
    int 21h

    ; --- Total Time 출력 ---
    lea dx, time_msg
    mov ah, 09h
    int 21h
    
    mov ax, elapsed_secs
    call print_number
    lea dx, sec_unit
    mov ah, 09h
    int 21h

    lea dx, res_bot
    mov ah, 09h
    int 21h

end_program:
    mov ah, 4Ch
    int 21h
main endp

; =========================================
; 숫자 출력 함수 (서브루틴)
; =========================================
print_number proc
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
    ret
print_number endp

end main