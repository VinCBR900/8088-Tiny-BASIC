        ; uBASIC8088.asm - 2kbyte x86 Tiny BASIC for Embedded systems

        ; bootBASIC Copyright 2019 Original author: Oscar Toledo G.
        ; Website: http://nanochess.org/
        ;
        ;  Licensed under the BSD 2-Clause License. See LICENSE file.
        ;
        ; This version Copyright 2026 Vincent Crabtree
        ; https://github.com/VinCBR900/8088-Tiny-BASIC/
        ;
        ; Version 2.1.0 (2026-04-08)
        ; Target is embedded 8088 Minimal systems with 2-4kbyte EPROM, 4kbyte RAM
        ;
        ; Changes since v2.0.0:
        ; - Fix: kw_match last-char comparison masked kw_table byte, not source byte
        ;        (caused tokenizer to never match any keyword).
        ; - Fix: deleted dead 'statements' table (~60 bytes saved); all dispatch now
        ;        via token values through statement_tokens.
        ; - Fix: goto_statement AX clobbered by find_line before line-number compare.
        ; - Fix: list_kw fall-through for unknown tokens now jumps to error.
        ; - Fix: input_number cbw placed before branch, corrupted BX on non-digit.
        ; - Fix: find_program_end/find_line merged into shared walk_lines helper.
        ; - Note: pre-loaded demo program remains in RAM section for DOS/QEMU testing;
        ;         remove before targeting real EPROM.
        ;
        ; Changes since original (v1 -> v2.0.0):
        ; - COM-only target, no boot-sector mode.
        ; - Packed editable program lines (EDITLN/INSLINE/DELINE).
        ; - 4KB simulated RAM window at 0x1000..0x1FFF.
        ; - Tokenized keywords and signed 16-bit numeric literals.
        ; - FREE command and startup free-RAM sign-on.
        ; - CHR$ support in PRINT.

        ; TO-DO: All depends on Space - in order of preference
        ; PEEK/POKE, USR(addr) 
        ; Improved error numbers
        ; GOSUB/RETURN, FOR/NEXT
        ; multi-statement lines
        ; HELP (unless almost free table walk)
        ; AND/OR/XOR/NOT 
        ; ON/GOTO/GOSUB
        ; DATA/RESTORE

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
statement_text:                     ; reached only for unrecognised non-token char
        call get_variable       ; treat as variable name
        push ax                 ; save address
        lodsb                   ; read next char
        cmp al,'='              ; assignment?
        je assignment           ; yes

        ;
        ; An error happened
        ;
error:
        mov si,error_message
        call print_z    ; Show error message (null-terminated)
        jmp main_loop   ; Exit to main loop

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
        call new_line   ; was jmp new_line - too far for short jump
        ret

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
        jb output           ; Below token range: emit as raw char
        cmp al,tok_chr
        jbe list_kw_emit    ; in range - emit keyword
        jmp error           ; above range: near jump to error
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
        ;------------------------------------------------------------
        ; INPUT_NUMBER
        ; Function : Parse unsigned decimal integer from [SI].
        ; Inputs   : SI = source text.
        ; Outputs  : AX = value, SI points past last digit.
        ; Clobbers : BX,CX.
        ;------------------------------------------------------------
input_number:
        xor bx,bx           ; BX = accumulator
f11:    lodsb               ; Read character
        sub al,'0'
        cmp al,10           ; Valid digit (0-9)?
        jnc f12             ; No - stop (cbw moved after branch to avoid BX corruption)
        cbw                 ; Zero-extend digit into AX
        xchg ax,bx          ; AX = old accum, BX = new digit
        mov cx,10
        mul cx              ; AX = old accum * 10
        add bx,ax           ; BX = accum*10 + digit
        jmp f11

f12:    dec si              ; Back to first non-digit
        mov ax,bx           ; Return value in AX
        ret

        ;
        ; Handle 'system' statement
        ;
system_statement:
        int 0x20

        ;------------------------------------------------------------
        ; GOTO_STATEMENT
        ; Function : Jump execution to given line number.
        ; Inputs   : SI = tokenized source after GOTO token.
        ; Outputs  : run_next updated or direct jump.
        ; Clobbers : AX,BX,DI.
        ;------------------------------------------------------------
goto_statement:
        call expr           ; AX = target line number
        push ax             ; Save - find_line clobbers AX
        call find_line      ; DI = pointer to line >= original AX
        pop bx              ; BX = target line number
        cmp word [di],bx    ; Exact match?
        jne f6              ; No, return (line not found)
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

        ;------------------------------------------------------------
        ; KW_MATCH
        ; Function : Try to match a keyword at [SI] against kw_table.
        ;            Keyword must not be followed by a-z, 0-9 or _.
        ; Inputs   : SI = source text pointer.
        ; Outputs  : CF=0 -> BX=keyword length, AH=token id.
        ;            CF=1 -> no match.
        ; Clobbers : AX,BX,DL,DI (DI saved/restored internally).
        ; Note     : Token counter kept on stack to avoid AH clobber during
        ;            character comparison loop.
        ;------------------------------------------------------------
kw_match:
        push di
        push cx             ; CX = token id counter
        mov di,kw_table
        mov cx,tok_new
kw_entry:
        mov bx,si           ; BX walks source, DI walks kw_table
kw_cmp:
        mov al,[di]         ; kw_table byte (may have bit7 terminator set)
        inc di
        mov ah,al           ; preserve for terminator test (saves mov dl,[di-1])
        and al,0x7f         ; mask for char comparison
        cmp [bx],al         ; compare source byte against masked kw byte
        jne kw_skip         ; mismatch - skip to next keyword
        inc bx
        test ah,0x80        ; was this the terminator byte?
        jz kw_cmp           ; no - keep comparing
        ; All chars matched - check source char after keyword is not alnum/_
        mov al,[bx]         ; check char following keyword in source
        cmp al,'a'
        jb kw_hit
        cmp al,'z'
        jbe kw_skip
        cmp al,'0'
        jb kw_hit
        cmp al,'9'
        jbe kw_skip
        cmp al,'_'
        je kw_skip
        jmp kw_hit
kw_skip_loop:
        mov al,[di]
        inc di
kw_skip:
        test al,0x80        ; scan forward to end of this kw_table entry
        jz kw_skip_loop
kw_next:
        cmp cx,tok_chr      ; exhausted all keywords?
        je kw_fail
        inc cx
        jmp kw_entry
kw_hit:
        sub bx,si           ; BX = keyword length
        mov ah,cl           ; AH = token id
        clc
        pop cx
        pop di
        ret
kw_fail:
        stc
        pop cx
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
        je pct_ok1
        jmp error
pct_ok1:
        inc si
        call expr
        cmp byte [si],')'
        je pct_ok2
        jmp error
pct_ok2:
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
        ; WALK_LINES (shared helper - saves ~15 bytes vs two separate routines)
        ; Function : Walk program lines from start. Stops when line number
        ;            in [DI] is zero (end marker) OR >= AX (if AX != 0xFFFF).
        ;            Pass AX=0xFFFF to walk to end unconditionally.
        ; Inputs   : AX = stop-threshold line number (0xFFFF = walk to end).
        ; Outputs  : DI = pointer to matching or end-marker line.
        ; Clobbers : BX,SI.
        ;------------------------------------------------------------
walk_lines:
        mov di,program
walk_lines_1:
        mov bx,[di]         ; BX = current line number (0 = end marker)
        or bx,bx
        je walk_lines_done  ; end marker - stop
        cmp bx,ax           ; line >= threshold?
        jae walk_lines_done ; yes - stop (for find_line semantics)
        call next_line_ptr
        mov di,si
        jmp walk_lines_1
walk_lines_done:
        ret

        ;------------------------------------------------------------
        ; FIND_LINE
        ; Function : Find first packed line >= AX.
        ; Inputs   : AX = line number.
        ; Outputs  : DI = line pointer or end marker.
        ; Clobbers : BX,SI.
        ;------------------------------------------------------------
find_line:
        jmp walk_lines      ; AX = threshold, walk_lines stops at >= AX

        ;------------------------------------------------------------
        ; FIND_PROGRAM_END
        ; Function : Walk to end-of-program marker (word zero).
        ; Inputs   : none.
        ; Outputs  : DI = pointer to zero end marker.
        ; Clobbers : AX,BX,SI.
        ;------------------------------------------------------------
find_program_end:
        mov ax,0xffff       ; threshold > any valid line number -> walk to end
        jmp walk_lines

        ; Compute SI=next line pointer from DI=current line.
        ; Inputs  : DI = pointer to current line (word linenum + bytes + CR).
        ; Outputs : SI = pointer to next line.
        ; Clobbers: SI.
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

; String tables

signon: db "TINY BASIC V2.1.0 FREE=",0

error_message:
        db "@#!",0x0d,0 ; error: CR then null terminator for print_z

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
        ; NOTE: 'statements' text table removed (v2.1.0).
        ; All dispatch is via token values through statement_tokens + kw_table.
        ; The statement_text path (f5/f16) in 'statement' is now dead code
        ; since tokenize_line is always called before statement dispatch.
        ; TODO: remove statement_text path to reclaim ~30 more bytes.

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
