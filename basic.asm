        ; TINY BASIC 8086 COM EDITION
        ; Original author: Oscar Toledo G.
        ; Website: http://nanochess.org/
        ;
        ; Version 2.0.0 (2026-04-08)
        ; Target is embedded 8088 Minimal systems with 2-4kbyte EPROM, 4kbyte RAM
        ;
        ; Changes since original:
        ; - COM-only target, no boot-sector mode.
        ; - Packed editable program lines (EDITLN/INSLINE/DELINE).
        ; - 4KB simulated RAM window at 0x1000..0x1FFF.
        ; - Tokenized keywords and signed 16-bit numeric literals.
        ; - FREE command and startup free-RAM sign-on.
        ; - CHR$ support in PRINT.

        cpu 8086

        org 0x0100        ; COM file testing, change later

; Adjust depending on HW implementation - 4kbyte here
RAM_START:   equ 0x1000
RAM_END:     equ 0x1fff

; simulated Embedded stack, generous 512 bytes
STACK_TOP:   equ RAM_END
PROGRAM_TOP: equ STACK_TOP-512

; Tokens for BASIC keywords
tok_new:    equ 0x80
tok_list:   equ 0x81
tok_run:    equ 0x82
tok_print:  equ 0x83
tok_input:  equ 0x84
tok_if:     equ 0x85
tok_goto:   equ 0x86
tok_system: equ 0x87
tok_rnd:    equ 0x88
tok_num:    equ 0x89
tok_free:   equ 0x8a
tok_chr:    equ 0x8b

start:
        push cs
        pop ds
        push cs
        pop es
        push cs
        pop ss
        cld             ; Clear Direction flag
        mov si,signon
        call print_z
        ;call free_bytes        ; version
        ;call output_number
        ;call new_line
        call free_statement        ; avaiable memory
        ;
        ; Main loop
        ;
main_loop:
        mov sp,STACK_TOP
        mov ax,main_loop
        push ax
        mov al,'>'      ; Show prompt
        call input_line ; Accept line
        call input_number       ; Get number
        or ax,ax        ; No number or zero?
        je statement    ; Yes, jump
        call tokenize_line
        call editln
        ret

        ;
        ; Handle 'if' statement
        ;
if_statement:
        call expr       ; Process expression
        or ax,ax        ; Is it zero?
        je f6           ; Yes, return (ignore if)
statement:
        call spaces     ; Avoid spaces
        cmp byte [si],0x0d  ; Empty line?
        je f6           ; Yes, return
        cmp byte [si],tok_new
        jb statement_text
        lodsb
        cmp al,tok_free
        je free_statement
        sub al,tok_new
        cmp al,7
        ja error
        cbw
        add ax,ax
        mov bx,ax
        call spaces
        jmp word [statement_tokens+bx]
statement_text:
        mov di,statements   ; Point to statements list
f5:     mov al,[di]     ; Read length of the string
        inc di          ; Avoid length byte
        cbw             ; Make AH zero
        dec ax          ; Is it zero?
        je f4           ; Yes, jump
        xchg ax,cx
        push si         ; Save current position
f16:    rep cmpsb       ; Compare statement
        jne f3          ; Equal? No, jump
        pop ax
        call spaces     ; Avoid spaces
        jmp word [di]   ; Jump to process statement

f3:     add di,cx       ; Advance the list pointer
        inc di          ; Avoid the address
        inc di
        pop si
        jmp f5          ; Compare another statement

f4:     call get_variable       ; Try variable
        push ax         ; Save address
        lodsb           ; Read a line letter
        cmp al,'='      ; Is it assignment '=' ?
        je assignment   ; Yes, jump to assignment.

        ;
        ; An error happened
        ;
error:
        mov si,error_message
        call print_2    ; Show error message
        jmp main_loop   ; Exit to main loop

error_message:
        db "@#!",0x0d   ; Guess the words :P

statement_tokens:
        dw start
        dw list_statement
        dw run_statement
        dw print_statement
        dw input_statement
        dw if_statement
        dw goto_statement
        dw system_statement

kw_table:
        db 'n','e','w'+0x80
        db 'l','i','s','t'+0x80
        db 'r','u','n'+0x80
        db 'p','r','i','n','t'+0x80
        db 'i','n','p','u','t'+0x80
        db 'i','f'+0x80
        db 'g','o','t','o'+0x80
        db 's','y','s','t','e','m'+0x80
        db 'r','n','d'+0x80
        db 'f','r','e','e'+0x80
        db 'c','h','r','$'+0x80

        ;
        ; Handle 'list' statement
        ;
list_statement:
        mov si,program
f29:    mov ax,[si]
        or ax,ax
        je f6
        call output_number ; Show line number
        add si,2
f32:    lodsb           ; Show line contents
        call list_output
        cmp al,0x0d
        jne f32         ; Jump if it wasn't 0x0d (CR)
        jmp f29
f6:
        ret

        ; FREE - show bytes available from end of program to RAM_END.
free_statement:
        call free_bytes
        call output_number
        jmp new_line

free_bytes:
        call find_program_end
        lea ax,[di+2]
        mov bx,PROGRAM_TOP
        sub bx,ax
        mov ax,bx
        ret

print_z:
        lodsb
        or al,al
        je f6
        call output
        jmp print_z

list_output:
        cmp al,tok_num
        jne list_kw
        lodsw
        push si
        call output_number
        pop si
        mov al,' '
        call output
        mov al,'0'
        ret
list_kw:
        cmp al,tok_new
        jb output
        cmp al,tok_chr
        jbe list_kw_emit
list_kw_emit:
        push si
        push bx
        push di
        mov bl,al
        sub bl,tok_new
        xor bh,bh
        mov di,kw_table
list_seek:
        cmp bl,0
        je list_emit
list_skip:
        mov al,[di]
        inc di
        test al,0x80
        jz list_skip
        dec bl
        jmp list_seek
list_emit:
        mov al,[di]
        inc di
        mov ah,al
        and al,0x7f
        call output
        test ah,0x80
        jz list_emit
        mov al,' '
        call output
        pop di
        pop bx
        pop si
        mov al,'0'
        ret

        ;
        ; Handle 'input' statement
        ;
input_statement:
        call get_variable   ; Get variable address
        push ax             ; Save it
        mov al,'?'          ; Prompt
        call input_line     ; Wait for line
        ;
        ; Second part of the assignment statement
        ;
assignment:
        call expr           ; Process expression
        pop di
        stosw               ; Save onto variable
        ret

        ;
        ; Handle an expression.
        ; First tier: addition & subtraction.
        ;
expr:
        call expr1          ; Call second tier
f20:    cmp byte [si],'-'   ; Subtraction operator?
        je f19              ; Yes, jump
        cmp byte [si],'+'   ; Addition operator?
        jne f6              ; No, return
        push ax
        call expr1_2        ; Call second tier
f15:    pop cx
        add ax,cx           ; Addition
        jmp f20             ; Find more operators

f19:
        push ax
        call expr1_2        ; Call second tier
        neg ax              ; Negate it (a - b converted to a + -b)
        jmp f15

        ;
        ; Handle an expression.
        ; Second tier: division & multiplication.
        ;
expr1_2:
        inc si              ; Avoid operator
expr1:
        call expr2          ; Call third tier
f21:    cmp byte [si],'/'   ; Division operator?
        je f23              ; Yes, jump
        cmp byte [si],'*'   ; Multiplication operator?
        jne f6              ; No, return

        push ax
        call expr2_2        ; Call third tier
        pop cx
        imul cx             ; Multiplication
        jmp f21             ; Find more operators

f23:
        push ax
        call expr2_2        ; Call third tier
        pop cx
        xchg ax,cx
        cwd                 ; Expand AX to DX:AX
        idiv cx             ; Signed division
        jmp f21             ; Find more operators

        ;
        ; Handle an expression.
        ; Third tier: parentheses, numbers and vars.
        ;
expr2_2:
        inc si              ; Avoid operator
expr2:
        call spaces         ; Jump spaces
        lodsb               ; Read character
        cmp al,'('          ; Open parenthesis?
        jne f24
        call expr           ; Process inner expr.
        cmp byte [si],')'   ; Closing parenthesis?
        je spaces_2         ; Yes, avoid spaces
        jmp error           ; No, jump to error

f24:    cmp al,0x40         ; Variable?
        jnc f25             ; Yes, jump
        dec si              ; Back one letter...
        call input_number   ; ...to read number
        jmp spaces

f25:    cmp al,tok_num
        jne f33
        lodsw
        ret
f33:    cmp al,tok_rnd
        je f34
        cmp al,0x72
        jne f22
        cmp byte [si],0x6e
        jne f22
        lodsw               ; Advance SI by 2
f34:
        in al,0x40          ; Read timer counter 0
        mov ah,0       
        ret

f22:    call get_variable_2 ; Get variable address
        xchg ax,bx
        mov ax,[bx]         ; Read
        ret                 ; Return

        ;
        ; Get variable address.
        ; Also avoid spaces.
        ;
get_variable:
        lodsb               ; Read source
get_variable_2:
        and al,0x1f         ; 0x61-0x7a -> 0x01-0x1a
        add al,al           ; x 2 (each variable = word)
        xor ah,ah
        add ax,vars         ; Setup full address
        dec si
        ;
        ; Avoid spaces after current character
        ;
spaces_2:
        inc si
        ;
        ; Avoid spaces
        ; The interpreter depends on this routine not modifying AX
        ;
spaces:
        cmp byte [si],' '   ; Space found?
        je spaces_2         ; Yes, move one character ahead.
        ret                 ; No, return.

        ;
        ; Output unsigned number 
        ; AX = value
        ;
output_number:
f26:
        xor dx,dx           ; DX:AX
        mov cx,10           ; Divisor = 10
        div cx              ; Divide
        or ax,ax            ; Nothing at left?
        push dx
        je f8               ; No, jump
        call f26            ; Yes, output left side
f8:     pop ax
        add al,'0'          ; Output remainder as...
        jmp output          ; ...ASCII digit

        ;
        ; Read number in input.
        ; AX = result
        ;
input_number:
        xor bx,bx           ; BX = 0
f11:    lodsb               ; Read source
        sub al,'0'
        cmp al,10           ; Digit valid?
        cbw
        xchg ax,bx
        jnc f12             ; No, jump
        mov cx,10           ; Multiply by 10
        mul cx
        add bx,ax           ; Add new digit
        jmp f11             ; Continue

f12:    dec si              ; SI points to first non-digit
        ret

        ;
        ; Handle 'system' statement
        ;
system_statement:
        int 0x20

        ;
        ; Handle 'goto' statement
        ;
goto_statement:
        call expr           ; Handle expression
        call find_line
        cmp word [di],ax
        jne f6
        cmp byte [running],0
        je run_from_di
        mov [run_next],di
        ret

        ;
        ; Handle 'run' statement
        ; (equivalent to 'goto 0')
        ;
run_statement:
        mov di,program
run_from_di:
        mov byte [running],1
run_loop:
        cmp word [di],0
        je run_end
        mov si,di
        call next_line_ptr
        mov [run_next],si
        mov si,di
        add si,2
        call statement
        mov di,[run_next]
        jmp run_loop
run_end:
        mov byte [running],0
        ret

        ;------------------------------------------------------------
        ; INPUT_LINE
        ; Function : Read edited input line with backspace support.
        ; Inputs   : AL = prompt character.
        ; Outputs  : LINE[] = text + CR, SI = LINE.
        ; Clobbers : AX,CX,DI.
        ;------------------------------------------------------------
input_line:
        call output
        mov si,line
        push si
        pop di          ; Target for writing line
        xor cx,cx       ; Number of chars in buffer
f1:     call input_key  ; Read keyboard
        cmp al,0x08     ; Backspace?
        jne f1_not_bs
        or cx,cx
        je f1
        dec di
        dec cx
        mov al,0x08
        call output
        mov al,' '
        call output
        mov al,0x08
        call output
        jmp f1
f1_not_bs:
        cmp al,0x0d     ; CR pressed?
        je f1_store_cr
        cmp cx,32       ; Max chars reached?
        jae f1          ; Ignore extra chars
        call output
        stosb
        inc cx
        jmp f1
f1_store_cr:
        call output
        stosb
        ret             ; Yes, return
        ;------------------------------------------------------------
        ; TOKENIZE_LINE
        ; Function : Tokenize BASIC source line into LINE_TOK buffer.
        ; Inputs   : SI = source text after parsed line number.
        ; Outputs  : SI = LINE_TOK, tokenized line ends with CR.
        ; Clobbers : AX,BX,CX,DI,DL.
        ;------------------------------------------------------------
tokenize_line:
        call spaces
        mov di,line_tok
tok_scan:
        lodsb
        cmp al,0x0d
        je tok_done
        cmp al,'"'
        je tok_string
        cmp al,'-'
        jne tok_not_minus
        cmp byte [si],'0'
        jb tok_keyword
        cmp byte [si],'9'
        ja tok_keyword
        mov al,tok_num
        stosb
        call input_number
        neg ax
        stosw
        jmp tok_scan
tok_not_minus:
        cmp al,'0'
        jb tok_keyword
        cmp al,'9'
        ja tok_keyword
        dec si
        mov al,tok_num
        stosb
        call input_number
        stosw
        jmp tok_scan
tok_keyword:
        dec si
        push si
        call kw_match
        pop si
        jc tok_copy_char
        mov al,ah
        stosb
        add si,bx
        jmp tok_scan
tok_copy_char:
        lodsb
        stosb
        jmp tok_scan
tok_string:
        stosb
tok_string_loop:
        lodsb
        stosb
        cmp al,'"'
        je tok_scan
        cmp al,0x0d
        jne tok_string_loop
tok_done:
        mov al,0x0d
        stosb
        mov si,line_tok
        ret

        ; Match keyword at SI. On success: CF=0, BX=length, AH=token id.
        ; On failure: CF=1.
kw_match:
        push di
        mov di,kw_table
        mov ah,tok_new
kw_entry:
        mov bx,si
kw_cmp:
        mov al,[di]
        inc di
        mov dl,[bx]
        and dl,0x7f
        cmp dl,al
        jne kw_skip
        inc bx
        test al,0x80
        jz kw_cmp
        mov dl,[bx]
        cmp dl,'a'
        jb kw_hit
        cmp dl,'z'
        jbe kw_skip
        cmp dl,'0'
        jb kw_hit
        cmp dl,'9'
        jbe kw_skip
        cmp dl,'_'
        je kw_skip
        jmp kw_hit
kw_skip_loop:
        mov al,[di]
        inc di
kw_skip:
        test al,0x80
        jz kw_skip_loop
kw_next:
        cmp ah,tok_chr
        je kw_fail
        inc ah
        jmp kw_entry
kw_hit:
        sub bx,si
        clc
        pop di
        ret
kw_fail:
        stc
        pop di
        ret

        ;
        ; Handle "print" statement
        ;
print_statement:
        lodsb           ; Read source
        cmp al,0x0d     ; End of line?
        je new_line     ; Yes, generate new line and return
        cmp al,'"'      ; Double quotes?
        jne f7          ; No, jump
print_2:
f9:
        lodsb           ; Read string contents
        cmp al,'"'      ; Double quotes?
        je f18          ; Yes, jump
        call output     ; Output character
        cmp al,0x0d     ; 
        jne f9          ; Jump if not finished with 0x0d (CR)
        ret             ; Return

f7:     dec si
        cmp byte [si],tok_chr
        je print_chr_tok
        call expr       ; Handle expression
        call output_number      ; Output result
        jmp f18
print_chr_tok:
        inc si
        cmp byte [si],'('
        jne error
        inc si
        call expr
        cmp byte [si],')'
        jne error
        inc si
        call output
f18:    lodsb           ; Read next character
        cmp al,';'      ; Is it semicolon?
        jne new_line    ; No, jump to generate new line
        ret             ; Yes, return

        ;
        ; Read a key into al
        ; Also outputs it to screen
        ;
input_key:
        mov ah,0x00
        int 0x16
        ret
        ;
        ; Screen output of character contained in al
        ; Expands 0x0d (CR) into 0x0a 0x0d (LF CR)
        ;
output:
        cmp al,0x0d
        jne f17
        ;
        ; Go to next line (generates LF+CR)
        ;
new_line:
        mov al,0x0a
        call f17
        mov al,0x0d
f17:
        mov ah,0x0e
        mov bx,0x0007
        int 0x10
        ret

        ;------------------------------------------------------------
        ; FIND_LINE
        ; Function : Find first packed line >= AX.
        ; Inputs   : AX = line number.
        ; Outputs  : DI = line pointer or end marker.
        ; Clobbers : BX,SI.
        ;------------------------------------------------------------
find_line:
        mov di,program
find_line_1:
        mov bx,[di]
        or bx,bx
        je find_line_done
        cmp bx,ax
        jae find_line_done
        push ax
        call next_line_ptr
        mov di,si
        pop ax
        jmp find_line_1
find_line_done:
        ret

        ; Compute SI=next line pointer from DI=current line.
next_line_ptr:
        mov si,di
        add si,2
next_line_ptr_1:
        cmp byte [si],0x0d
        je next_line_ptr_2
        inc si
        jmp next_line_ptr_1
next_line_ptr_2:
        inc si
        ret

        ; Find program end marker (word zero)
find_program_end:
        mov di,program
find_program_end_1:
        mov ax,[di]
        or ax,ax
        je find_program_end_done
        call next_line_ptr
        mov di,si
        jmp find_program_end_1
find_program_end_done:
        ret

        ;------------------------------------------------------------
        ; EDITLN
        ; Function : Replace/insert/delete packed program line.
        ; Inputs   : AX = line number, SI = tokenized text + CR.
        ; Outputs  : Program image updated in RAM.
        ; Clobbers : AX,BX,CX,DX,SI,DI,BP.
        ;------------------------------------------------------------
editln:
        push ax                  ; Save line number
        call spaces
        pop dx                   ; DX = line number
        mov bx,si                ; BX = line text pointer
        mov cx,1
editln_len:
        cmp byte [si],0x0d
        je editln_len_done
        inc si
        inc cx
        jmp editln_len
editln_len_done:
        mov ax,dx
        call find_line
        cmp word [di],dx
        jne editln_no_existing
        call deline              ; delete existing line at DI
editln_no_existing:
        cmp byte [bx],0x0d
        je editln_done           ; pure line number => deletion
        mov si,bx
        mov ax,dx
        add cx,2                 ; line number + text (CR already counted)
        call insline
editln_done:
        ret

        ; Insert new line AX at DI, with text at SI and total size in CX.
insline:
        push ax
        push cx
        push si
        push di
        call find_program_end
        mov bp,di                ; BP = end marker pointer
        pop di                   ; DI = insertion pointer
        pop si                   ; SI = text pointer
        pop cx                   ; CX = new total size
        pop ax                   ; AX = line number
        mov bx,bp
        add bx,2
        add bx,cx
        cmp bx,PROGRAM_TOP
        ja insline_oom
        mov bx,bp
        add bx,2                 ; include zero marker
        sub bx,di                ; bytes to move
        mov dx,cx                ; keep new size
        std
        lea si,[di+bx-1]
        add di,bx
        add di,dx
        dec di
        mov cx,bx
        rep movsb                ; top-down move for insertion
        cld
        sub di,bx
        mov [di],ax
        add di,2
insline_copy:
        lodsb
        stosb
        cmp al,0x0d
        jne insline_copy
        ret
insline_oom:
        jmp error

deline:
        ; Delete existing line at DI
        push di
        call next_line_ptr
        mov bx,si                ; BX = source after deleted line
        call find_program_end
        mov cx,di
        add cx,2                 ; include end marker
        sub cx,bx                ; bytes to slide down
        pop di                   ; DI = destination
        mov si,bx
        rep movsb                ; forward move for deletion
        ret

        ;
        ; List of statements of bootBASIC
        ; First one byte with length of string
        ; Then string with statement
        ; Then a word with the address of the code
        ;
statements:
        db 4,"new"
        dw start

        db 5,"list"
        dw list_statement

        db 4,"run"
        dw run_statement

        db 6,"print"
        dw print_statement

        db 6,"input"
        dw input_statement

        db 3,"if"
        dw if_statement

        db 5,"goto"
        dw goto_statement

        db 7,"system"
        dw system_statement

        db 5,"free"
        dw free_statement

        db 1

signon: db "TINY BASIC V2.1.0 FREE=",0

ROM_END:

;        TIMES 0x1000-($-$$) DB 0

        ORG RAM_START

vars:       DW 26 DUP (0)
running:    DW 0
run_next:   DW 0
line:       DW 17 DUP (0)      ; 34 bytes, max 32 chars + CR
line_tok:   DW 17 DUP (0)

program:
        ; 10 PRINT "MANDELBROT 16BIT"
        dw 10
        db 0x83,0x20,0x22,"MANDELBROT 16BIT",0x22,0x0d
        ; 20 Y=-12
        dw 20
        db 0x79,0x3d,0x89,0xf4,0xff,0x0d
        ; 30 IF Y-12 GOTO 50
        dw 30
        db 0x85,0x20,0x79,0x89,0xf4,0xff,0x20,0x86,0x20,0x89,0x32,0x00,0x0d
        ; 40 GOTO 999
        dw 40
        db 0x86,0x20,0x89,0xe7,0x03,0x0d
        ; 50 X=-39
        dw 50
        db 0x78,0x3d,0x89,0xd9,0xff,0x0d
        ; 60 IF X-39 GOTO 80
        dw 60
        db 0x85,0x20,0x78,0x89,0xd9,0xff,0x20,0x86,0x20,0x89,0x50,0x00,0x0d
        ; 70 GOTO 900
        dw 70
        db 0x86,0x20,0x89,0x84,0x03,0x0d
        ; 80 A=0
        dw 80
        db 0x61,0x3d,0x89,0x00,0x00,0x0d
        ; 90 B=0
        dw 90
        db 0x62,0x3d,0x89,0x00,0x00,0x0d
        ; 100 I=0
        dw 100
        db 0x69,0x3d,0x89,0x00,0x00,0x0d
        ; 110 T=A*A/16-B*B/16+X
        dw 110
        db 0x74,0x3d,0x61,0x2a,0x61,0x2f,0x89,0x10,0x00,0x2d,0x62,0x2a,0x62,0x2f,0x89,0x10,0x00,0x2b,0x78,0x0d
        ; 120 B=A*B/8+Y
        dw 120
        db 0x62,0x3d,0x61,0x2a,0x62,0x2f,0x89,0x08,0x00,0x2b,0x79,0x0d
        ; 130 A=T
        dw 130
        db 0x61,0x3d,0x74,0x0d
        ; 140 I=I+1
        dw 140
        db 0x69,0x3d,0x69,0x2b,0x89,0x01,0x00,0x0d
        ; 150 IF I-16 GOTO 170
        dw 150
        db 0x85,0x20,0x69,0x89,0xf0,0xff,0x20,0x86,0x20,0x89,0xaa,0x00,0x0d
        ; 160 GOTO 200
        dw 160
        db 0x86,0x20,0x89,0xc8,0x00,0x0d
        ; 170 IF A*A/16+B*B/16-64 GOTO 110
        dw 170
        db 0x85,0x20,0x61,0x2a,0x61,0x2f,0x89,0x10,0x00,0x2b,0x62,0x2a,0x62,0x2f,0x89,0x10,0x00,0x89,0xc0,0xff,0x20,0x86,0x20,0x89,0x6e,0x00,0x0d
        ; 200 PRINT CHR$(42);
        dw 200
        db 0x83,0x20,0x8b,0x28,0x89,0x2a,0x00,0x29,0x3b,0x0d
        ; 210 X=X+1
        dw 210
        db 0x78,0x3d,0x78,0x2b,0x89,0x01,0x00,0x0d
        ; 220 GOTO 60
        dw 220
        db 0x86,0x20,0x89,0x3c,0x00,0x0d
        ; 900 PRINT
        dw 900
        db 0x83,0x0d
        ; 910 Y=Y+1
        dw 910
        db 0x79,0x3d,0x79,0x2b,0x89,0x01,0x00,0x0d
        ; 920 GOTO 30
        dw 920
        db 0x86,0x20,0x89,0x1e,0x00,0x0d
        ; 999 PRINT "DONE"
        dw 999
        db 0x83,0x20,0x22,"DONE",0x22,0x0d
        dw 0

        ;
        ; End of COM image
        ;

