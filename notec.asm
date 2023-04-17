        global notec
        extern debug

        section .bss
        align 8
; wspólna tablica wartości do wymian
        notec_values resq N
; wspólna tablica partnerów do wymian
; partnerów w tablicy numerujemy od 1 a nie od 0
; wartość 0 znaczy że nie bierze udziału w żadnej wymianie
; sama tablica indeksowana jest od 0
        notec_partners resd N
spin_lock: resd 1

        section .text
        align 8
notec:
; w rdi numer notecia, w rsi wskaźnik na napis opisujący obliczenie
; wynik umieścimy w rax
        xor r11, r11
        xor rcx, rcx
; zapisujemy rejestry, które trzeba zachować
        push rbx
        push rbp
        push r12
        push r13
        push r14
        push r15
        mov rbp, rsp                   ; zapisujemy stack pointer
notec_loop:
        movzx rax, byte [rsi]          ; wczytujemy kolejny znak obliczenia
        test rax, rax
        jz notec_done                  ; bajt zerowy, kończymy

        inc rsi                        ; przechodzimy do kolejnego znaku
        cmp rax, '0'
        jb not_number
        cmp rax, 'f'
        ja not_number
        cmp rax, '9'
        jbe number_09
        cmp rax, 'a'
        jae number_af
        cmp rax, 'A'
        jb not_number
        cmp rax, 'F'
        jbe number_AF
        jmp not_number

number_09:
        sub rax, '0'                   ; '0' -> 0, '1' -> 1, ... '9' -> 9
        jmp number_common
number_af:
        sub rax, 87                    ; 'a' -> 10, 'b' -> 11, ... 'f' -> 16
        jmp number_common
number_AF:
        sub rax, 55                    ; 'A' -> 10, 'B' -> 11, ... 'F' -> 16
number_common:
        mov r11, 1                     ; wartość bool mówiąca że jesteśmy w trybie wpisywania liczby
        shl rcx, 4                     ; przesuwamy dotychczasowe cyfry liczby w lewo
        add rcx, rax                   ; dopisujemy nową szesnastkową cyfrę
        jmp notec_loop

not_number:
        test r11, r11                  ; sprawdzamy czy byliśmy w trybie wpisywania liczby
        jz no_number_to_save
        xor r11, r11                   ; wychodzimy z trybu wpisywania liczby
        push rcx                       ; wrzucamy na stos zapisaną liczbę
        xor rcx, rcx                   ; zerujemy rejestr trzymający wczytaną liczbę
no_number_to_save:
        cmp rax, '='
        je notec_loop                  ; operacja '=' nie robi nic poza wyjściem z trybu wpisywania
        cmp rax, 'Z'
        jne not_Z
; pop_op:
        pop r8                         ; usuwamy wartość z wierzchołka stosu
        jmp notec_loop
not_Z:
        cmp rax, 'N'
        jne not_N
; push_N_op:
        push N
        jmp notec_loop
not_N:
        cmp rax, 'n'
        jne not_n
; push_id_op
        push rdi                       ; wstawiamy na stos numer instancji tego notecia
        jmp notec_loop
not_n:
        cmp rax, 'g'
        jne op_with_argument
; debug_op
; zapisujemy rejestry które debug może zmienić w tych których nie może
        mov rbx, rcx
        mov r12, rdi
        mov r13, rsi
        mov r15, r11
        
        xor r14, r14                   ; na offset jeżeli wyrównamy stos do wywowałania funkcji debug
        mov rsi, rsp
        test rsp, 1111b
        jz stack_adjusted              ; wskaźnik stosu niepodzielny przez 16, trzeba dodać 8
        sub rsp, 8
        mov r14, 8
stack_adjusted:
        call debug
        imul rax, 8
        add rsp, rax                   ; przesuwamy rsp o tyle bajtów ile powiedział nam debug
        add rsp, r14                   ; i ewentualnie cofamy nasz wyrównujący offset

; przywracamy stan rejestrów
        mov rsi, r13
        mov rdi, r12
        mov r11, r15
        mov rcx, rbx

        jmp notec_loop
op_with_argument:
        pop r8                         ; zdejmujemy argument operacji ze stosu
        cmp rax, '-'
        jne not_arithmetic_negation
;arithetic_negation_op:
        neg r8
        jmp one_arg_op_result
not_arithmetic_negation:
        cmp rax, '~'
        jne not_bitwise_negation
;bitwise_negation_op:
        not r8
        jmp one_arg_op_result
not_bitwise_negation:
        cmp rax, 'Y'
        jne not_Y
;duplicate_op:
        push r8
        jmp one_arg_op_result
not_Y:
        cmp rax, 'W'
        jne op_with_2_arg
; swap_with_other_instance_op
        mov rax, notec_values
        mov r9, rdi                    ; bierzemy nasz numer notecia
        shl r9, 3                      ; r9 *= 8
        add rax, r9                    ; w rax miejsce na naszą wartość we wspólnej tablicy wartości

        mov rdx, notec_partners
        mov r9, rdi                    ; bierzemy nasz numer notecia
        shl r9, 2                      ; r9 *= 4
        add rdx, r9                    ; w rdx miejsce na numer naszego partnera we wspólnej tablicy partnerów

        inc r8                         ; podnosimy numer partnera, bo numerujemy od 1 nie od 0
        pop rcx                        ; bierzemy wartość z naszego stosu
        mov r11, spin_lock
        xor r10d, r10d                 ; zerujemy do operacji bts, btr

        jmp get_lock
open_lock:
        btr [r11], r10d
get_lock:
        lock bts [r11], r10d
        jc get_lock
; czekamy aż nie będziemy w transakcji (nasz partner będzie = 0) żeby pozwolić partnerowi odczytać wartość
        mov r12d, [rdx]
        test r12d, r12d
        jnz open_lock                  ; nasz stary partner jeszcze nie wziął naszej wartości, czekamy

        mov [rdx], r8d                 ; wpisujemy numer partnera
        mov [rax], rcx                 ; wpisujemy naszą wartość
        btr [r11], r10d                ; otwieramy lock

        dec r8                         ; zmiejszamy numer partnera, bo indeksujemy od 0 nie od 1
        mov rax, notec_values
        mov r9, r8
        shl r9, 3                      ; r9 *= 8
        add rax, r9                    ; w rax miejsce na wartość partnera we wspólnej tablicy wartości

        mov rdx, notec_partners
        shl r8, 2                      ; r8 *= 4
        add rdx, r8                    ; w rdx miejsce na numer partnera naszego partnera

        jmp get_lock_2
open_lock_2:
        btr [r11], r10d
get_lock_2:
        lock bts [r11], r10d
        jc get_lock_2
check_partner:
        mov ecx, [rdx]
        dec ecx                        ; zmiejszamy, bo wartości w tablicy o 1 większe od id noteci
        cmp ecx, edi                   ; porównujemy numer partnera naszego partnera z naszym numerem
        jne open_lock_2                ; nasz partner nie jest gotów, czekamy dalej

        mov [rdx], r10d                ; ustawiamy partnerowi partnera na 0, czyli że nie jest gotów
        mov r8, [rax]                  ; bierzemy wartość od naszego partnera

        btr [r11], r10d                ; otwieramy lock

        xor rcx, rcx
        xor r11, r11
one_arg_op_result:
        push r8                        ; wkładamy wynik operacji na stos
        jmp notec_loop

op_with_2_arg:
        pop r9                         ; zdejmujemy drugi argument operacji ze stosu
        cmp rax, '+'
        jne not_summation
; add_op
        add r8, r9
        jmp two_arg_op_result
not_summation:
        cmp rax, '*'
        jne not_multiplication
; multiply_op
        imul r8, r9
        jmp two_arg_op_result
not_multiplication:
        cmp rax, '&'
        jne not_AND
; AND_op
        and r8, r9
        jmp two_arg_op_result
not_AND:
        cmp rax, '|'
        jne not_OR
; OR_op
        or r8, r9
        jmp two_arg_op_result
not_OR:
        cmp rax, '^'
        jne not_XOR
; XOR_op
        xor r8, r9
        jmp two_arg_op_result
not_XOR:
; jedyna możliwa operacja jaka została to X (swap)
; wkładamy zdjęte argumenty na stos w odwróconej kolejności
        push r8
        push r9
        jmp notec_loop
two_arg_op_result:
        push r8                        ; wkładamy wynik operacji na stos
        jmp notec_loop

notec_done:
        test r11, r11                  ; sprawdzamy czy bylismy w trybie wpisywania liczby
        jz done_no_number_to_save
        push rcx                       ; wrzucamy na stos zapisaną liczbę
done_no_number_to_save:
        pop rax                        ; zwracamy wartość z wierzchołka stosu
        mov rsp, rbp                   ; przywracamy stan stack pointera

; przywracamy wartości rejestrów
        pop r15
        pop r14
        pop r13
        pop r12
        pop rbp
        pop rbx

        ret