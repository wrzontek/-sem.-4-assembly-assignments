        SYS_READ equ 0
        SYS_WRITE equ 1
        SYS_EXIT equ 60
        STDIN equ 0
        STDOUT equ 1
        BUF_SIZE equ 1024
        MAX_LINE equ 65536             

        global _start
        
        section .bss
in_buffer: resb BUF_SIZE
; potencjalnie same znaki 2-bajtowe przechodzace w 4-bajtowe
; dlatego out_buffer dwa razy wiekszy niz in_buffer
out_buffer: resb 2 * BUF_SIZE
arg_count: resq 1
additional_byte: resq 1

        section .text
; czesc kodu wczytania argumentów zaczerpnieta ze scenariusza na moodlu
_start:
        mov rax, [rsp]                 ; [rsp] to argc
        dec rax
        test rax, rax
        jz error                       ; argc < 2 czyli nie podano a0, zwracamy blad
        mov [arg_count], rax
        lea r15, [rsp + 16]            ; adres args[1]
arg_loop:
        mov rsi, [r15]                 ; adres kolejnego argumentu
        test rsi, rsi
        jz arg_done                    ; napotkano zerowy wskaznik, nie ma wiecej argumentów
        cld                            ; zwiekszaj indeks przy przeszukiwaniu napisu
        xor al, al                     ; szukaj zera
        mov     ecx, MAX_LINE          ; ogranicz przeszukiwanie do MAX_LINE znaków
        mov rdi, rsi                   ; ustaw adres, od którego rozpoczac szukanie
        repne \
        scasb                          ; szukaj bajtu o wartosci zero

; len = rdi - rsi - 1
        mov rdx, rdi
        sub rdx, rsi
        sub rdx, 0x1
        
; w rsi pointer na string, w rdx dlugosc
        call atoi                      ; zamieniamy string na liczbe, umieszczamy w rax

        push rax                       ; wrzucamy a_i na stos by korzystac z niego pózniej

        add r15, 8                     ; przejdz do nastepnego argumentu.
        jmp arg_loop

arg_done:
; rsp zawiera wskaznik na a_n
; a_{n-i} w [rsp + 8*i] czyli np a_n-2 w [rsp + 16]
        mov r10, [arg_count]
        dec r10
        imul r10, 8
        add rsp, r10                   
; teraz rsp zawiera wskaznik na a_0
; a_{i} w [rsp - 8*i] czyli np a_2 w [rsp - 16]

        mov r13, 0
write_read_loop:
        test r13, r13
        jz nothing_to_write
; wypisujemy aktualna zawartosc bufora   
        mov rdx, r13                   ; w r13 liczba zapisanych bajtów outputu
        mov rsi, out_buffer
        mov eax, SYS_WRITE
        mov edi, STDOUT
        syscall

nothing_to_write:
        mov rax, SYS_READ
        mov rdi, STDIN
        mov rsi, in_buffer  
        mov rdx, BUF_SIZE 
        syscall

        test rax, rax                  ; w rax liczba wczytanych bitów
        jz read_done                   ; jesli 0 to koniec wejscia, konczymy wczytywanie
        
        mov r14, rax                   ; liczba wczytanych bajtów
        mov r15, 0                     ; licznik przerobionych bajtów wejscia
        mov r13, 0                     ; ustawiamy output size na 0
        mov r12, in_buffer             ; w r12 aktualne miejsce w input buforze, zaczynamy od poczatku  
            
next_character:
        cmp r15, r14
        jae write_read_loop            ; jesli przerobilismy juz caly input bufor to wypisujemy i czytamy znowu
        
        xor rdx, rdx
        mov dl, byte [r12]             ; wczytujemy bajt

        bt dx, 7                       ; sprawdzamy pierwszy z lewej bit wczytanego bajtu
        jc more_than_one_byte          ; jesli zapalony to znak wielobajtowy
        
        mov [out_buffer + r13], dl     ; znaków jednobajtowych nie zmieniemamy
        inc r13                        ; zwiekszamy output size o jeden bajt
        inc r12                        ; przechodzimy do kolejnego bajtu bufora
        inc r15                        ; zawsze przy zwiekszeniu r12 zwiekszamy r15
        jmp next_character
      
more_than_one_byte:
; sprawdzamy czy drugi bit 1 bajtu to '1' i czy 2 pierwsze 2 bajtu to '10'
        bt dx, 6
        jnc error
        
        inc r12                        ; przechodzimy do kolejnego bajtu
        inc r15
        cmp r15, r14                   ; sprawdzamy czy nie dotarlismy do konca bufora
        
        jb have_more_than_one_byte_in_buffer  
 ;znak wielobajtowy ale mamy tylko pierwszy bajt w buforze, readujemy kolejny
        mov rbx, rdx                   ; zapisujemy rdx by móc przywrócic je po syscall'u
        
        mov rax, SYS_READ
        mov rdi, STDIN
        mov rsi, additional_byte
        mov rdx, 1
        syscall
        
        test rax, rax
        jz error                       ; nie udalo sie wczytac wymaganego bajtu
        
        mov r12, additional_byte
        mov rdx, rbx
have_more_than_one_byte_in_buffer:
        shl rdx, 8                     ; robimy miejsce na kolejny bajt
        mov dl, byte [r12]             ; wczytujemy bajt
        
        bt dx, 7
        jnc error
        bt dx, 6
        jc error
        
        bt dx, 13
        jc more_than_two_bytes
; mamy dwubajtowy znak
        inc r12                        ; przechodzimy do kolejnego bajtu
        inc r15
; maska 00000000 00000000 00011111 00111111
; czyli bierzemy tylko znaczace bity z wczytanych dwóch bajtów
        mov rax, 00000000000000000001111100111111b
        pext rsi, rdx, rax             ; w rsi wartosc unicode znaku
        
        cmp rsi, 0x80
        jb error                       ; mozna zapisac na mniejszej ilosci bajtów

        jmp calculate_new_value
more_than_two_bytes:
        inc r12                        ; przechodzimy do kolejnego bajtu
        inc r15
        
        cmp r15, r14
        jb have_more_than_two_bytes_in_buffer
        ;znak 3-4 bajtowy ale mamy tylko 2 bajty w buforze, readujemy kolejny
        mov rbx, rdx                   ; zapisujemy rdx by móc przywrócic je po syscall'u
        
        mov rax, SYS_READ
        mov rdi, STDIN
        mov rsi, additional_byte
        mov rdx, 1
        syscall
        
        test rax, rax
        jz error                       ; nie udalo sie wczytac wymaganego bajtu
        
        mov r12, additional_byte
        mov rdx, rbx
have_more_than_two_bytes_in_buffer:
        shl rdx, 8                     ; robimy miejsce na kolejny bajt
        mov dl, byte [r12]             ; wczytujemy bajt

; sprawdzenie poprawnosci 3 bajtu tak jak wczesniej drugiego
        bt dx, 7
        jnc error
        bt dx, 6
        jc error
        
        bt edx, 20
        jc four_bytes
; mamy trzybajtowy znak
        inc r12
        inc r15
; maska 00000000 00001111 00111111 00111111
; czyli bierzemy tylko znaczace bity z wczytanych trzech bajtów
        mov rax, 00000000000011110011111100111111b
        pext rsi, rdx, rax             ; w rsi wartosc unicode znaku

        cmp rsi, 0x800
        jb error                       ; mozna zapisac na mniejszej ilosci bajtów

        jmp calculate_new_value
four_bytes:
        inc r12                        ; przechodzimy do kolejnego bajtu
        inc r15
        
        cmp r15, r14
        jb have_more_than_three_bytes_in_buffer
; znak 4 bajtowy ale mamy tylko 3 bajty w buforze, readujemy kolejny 
        mov rbx, rdx                   ; zapisujemy rdx by móc przywrócic je po syscall'u
        
        mov rax, SYS_READ
        mov rdi, STDIN
        mov rsi, additional_byte
        mov rdx, 1
        syscall
        
        test rax, rax
        jz error                       ; nie udalo sie wczytac wymaganego bajtu
        
        mov r12, additional_byte
        mov rdx, rbx
have_more_than_three_bytes_in_buffer:
; tu mamy czterobajtowy
        shl rdx, 8                     ; robimy miejsce na kolejny bajt
        mov dl, byte [r12]             ; wczytujemy bajt
        
        inc r12                        ; przechodzimy do kolejnego bajtu
        inc r15
; sprawdzenie poprawnosci 4 bajtu tak jak wczesniej 2 i 3
        bt dx, 7
        jnc error
        bt dx, 6
        jc error

        bt edx, 27
        jc error                       ; znak 5 lub 6 bajtowy, takich nie przyjmujemy
        
; maska 00000111 00111111 00111111 00111111
; czyli bierzemy tylko znaczace bity z wczytanych czterech bajtów
        mov rax, 00000111001111110011111100111111b
        pext rsi, rdx, rax             ; w rsi wartosc unicode znaku

        cmp rsi, 0x10000
        jb error                       ; mozna zapisac na mniejszej ilosci bajtów

        cmp rsi, 0x10FFFF
        ja error                       ; wedlug polecenia wieksze to blad

calculate_new_value:
; w rsi wartosc unicode x, odejmujemy 0x80 zgodnie ze wzorem
        sub rsi, 0x80
        
; rsp zawiera wskaznik na a_0
; a_i w [rsp - 8*i] czyli np a_2 w [rsp - 16]
        mov r8, 0x10FF80               ; stala do rejestru zeby mozna bylo uzywac div   
        mov rbx, 0                     ; suma wielomianu
        mov r11, 1                     ; x^i
        mov r10, 0                     ; 'i' w a_i * x^i
poly_loop:
        cmp r10, [arg_count]
        je poly_done                   ; argumentów jest n+1, a a_{n+1} juz nie ma, konczymy

        mov rdi, r10
        imul rdi, 8                    ; w rdi offset opisany wyzej jako '8*i'
        mov rax, rsp
        sub rax, rdi
        mov rax, [rax]                 ; pobieramy a_i
   
        xor rdx, rdx
        div r8
        mov eax, edx                   ; a_i mod 0x10FF80
        
        ; liczymy a_i * x^i 
        ; x^i w r11, a_i w rax
        imul rax, r11                  ; x^i * a_i
        xor rdx, rdx
        div r8                         ; dzielimy przez 0x10FF80, reszta w rdx
        mov eax, edx                   ; x^i * a_i mod 0x10FF80
        
        add rax, rbx                   ; sumujemy nowy wyraz i dotychczasowa sume
        xor rdx, rdx
        div r8                         ; dzielimy przez 0x10FF80, reszta w rdx
        mov ebx, edx                   ; mamy nowa sume mod 0x10FF80

        imul r11, rsi                  ; x^i * x = x^{i+1}
        mov rax, r11
        xor rdx, rdx
        div r8
        mov r11d, edx                  ; x^{i+1} mod 0x10ff80
        
        inc r10
        jmp poly_loop

poly_done:
        add rbx, 0x80                  ; dodajemy 0x80 wedle wzoru
; wynikowy znak zajmuje co najmniej dwa bajty bo >= 0x80
        cmp rbx, 0x7FF
        ja result_more_than_two_bytes

; tu wynik dwubajtowy
; maska 00000000 00000000 00011111 00111111
; czyli bity unicode na odpowiednie bity w utf-8
        mov eax, 00000000000000000001111100111111b
        pdep esi, ebx, eax

; or    00000000 00000000 11000000 10000000
; czyli uzupelniamy wiodace bity utf-8 dla dwubajtowego znaku
        or esi, 00000000000000001100000010000000b
        mov rdx, rsi
       
; wpisujemy otrzymany znak do output buffera
        inc r13
        mov [out_buffer + r13], dl
        dec r13
        shr rdx, 8
        mov [out_buffer + r13], dl
        add r13, 2
        
        jmp next_character
        
result_more_than_two_bytes:
        cmp rbx, 0xFFFF
        ja result_four_bytes

; tu wynik trzybajtowy
; maska 00000000 00001111 00111111 00111111
; czyli bity unicode na odpowiednie bity w utf-8
        mov eax, 00000000000011110011111100111111b
        pdep esi, ebx, eax

; or    00000000 11100000 10000000 10000000
; czyli uzupelniamy wiodace bity utf-8 dla trzybajtowego znaku
        or esi, 00000000111000001000000010000000b
        mov rdx, rsi
        
; wpisujemy otrzymany znak do output buffera
        add r13, 2
        mov [out_buffer + r13], dl
        dec r13
        shr rdx, 8
        mov [out_buffer + r13], dl
        dec r13
        shr rdx, 8
        mov [out_buffer + r13], dl  
        add r13, 3

        jmp next_character

result_four_bytes:
; tu wynik trzybajtowy
; maska 00000111 00111111 00111111 00111111
; czyli bity unicode na odpowiednie bity w utf-8
        mov eax, 00000111001111110011111100111111b
        pdep esi, ebx, eax

; or    11110000 10000000 10000000 10000000
; czyli uzupelniamy wiodace bity utf-8 dla czterobajtowego znaku
        or esi, 11110000100000001000000010000000b
        mov rdx, rsi
        
; wpisujemy otrzymany znak do output buffera
        add r13, 3
        mov [out_buffer + r13], dl
        dec r13
        shr rdx, 8
        mov [out_buffer + r13], dl
        dec r13
        shr rdx, 8
        mov [out_buffer + r13], dl
        dec r13
        shr rdx, 8
        mov [out_buffer + r13], dl     
        add r13, 4

        jmp next_character

read_done:
        mov eax, SYS_EXIT
        mov edi, 0                     ; kod powrotu 0
        syscall

error:
; wypisz aktualna zawartosc bufora
        mov rdx, r13
        mov rsi, out_buffer
        mov eax, SYS_WRITE
        mov edi, STDOUT
        syscall

        mov eax, SYS_EXIT
        mov edi, 1                     ; kod powrotu 1
        syscall

; zmodyfikowane https://gist.github.com/tnewman/63b64284196301c4569f750a08ef52b2
; w rdi pointer na string, w rdx dlugosc
; zmienia rax, rdx, rdi, rsi
; wynik umieszcza w rax
atoi:
        mov rax, 0                     ; inicjalizacja sumy na 0

convert_loop:
        test rdx, rdx
        jz atoi_done                   ; jesli pozostala dlugosc to 0 to konczymy
        movzx rdi, byte [rsi]          ; wczytujemy kolejny znak

; znaki < '0' lub > '9' sa niepoprawne poniewaz nie sa cyframi
        cmp rdi, '0'
        jl error

        cmp rdi, '9'
        jg error

        sub rdi, '0'                   ; zmieniamy ascii na cyfre
        imul rax, 10                   ; mnozymy dotychczasowa sume przez 10
        add rax, rdi                   ; dodajemy nowa cyfreedo sumy

        inc rsi                        ; przechodzimy do adresu kolejnej cyfry
        dec rdx                        ; zmiejszamy pozostala do wczytania dlugosc
        jmp convert_loop

atoi_done:
        ret                            