        ;
        ; bootBASIC interpreter in 512 bytes (boot sector)
        ;
        ; by Oscar Toledo G.
        ; http://nanochess.org/
        ;
        ; (c) Copyright 2019-2020 Oscar Toledo G.
        ;
        ; Creation date: Jul/19/2019. 10pm to 12am.
        ; Revision date: Jul/20/2019. 10am to 2pm.
        ;                             Added assignment statement. list now
        ;                             works. run/goto now works. Added
        ;                             system and new.
        ; Revision date: Jul/22/2019. Boot image now includes 'system'
        ;                             statement.
        ;
        ;
        ; See LICENSE
        ;
        ; This version Copyright 2026 Vincent Crabtree
        ; This modification is functionally identical to Oscar's version,
        ; but designed to run in 8bitworkshop and also includes
        ; a Mandelbrot demo pre-typed. It also adds a NEW command to erase
        ; the Demo program if desired.
        ;
        ; USER'S MANUAL:
        ;
        ; Line entry is done with keyboard, finish the line with Enter.
        ; Only 31 characters per line as maximum.
        ;
        ; Backspace can be used, don't be fooled by the fact
        ; that screen isn't deleted (it's all right in the buffer).
        ;
        ; All statements must be in lowercase.
        ;
        ; Line numbers can be 1 to 999.
        ;
        ; 26 variables are available (a-z)
        ;
        ; Numbers (0-65535) can be entered and display as unsigned.
        ;
        ; To enter new program lines:
        ;   10 print "Hello all!"
        ;
        ; To erase program lines:
        ;   10
        ;
        ; To test statements directly (interactive syntax):
        ;   print "Hello all!"
        ;
        ; To erase the current program:
        ;   new
        ;
        ; To run the current program:
        ;   run
        ;
        ; To list the current program:
        ;   list
        ;
        ; To exit to command-line:
        ;   system
        ;
        ; Statements:
        ;   var=expr        Assign expr value to var (a-z)
        ;
        ;   print expr      Print expression value, new line
        ;   print expr;     Print expression value, continue
        ;   print "hello"   Print string, new line
        ;   print "hello";  Print string, continue
        ;
        ;   input var       Input value into variable (a-z)
        ;
        ;   goto expr       Goto to indicated line in program
        ;
        ;   if expr1 goto expr2
        ;               If expr1 is non-zero then go to line,
        ;               else go to following line.
        ;
        ; Examples of if:
        ;
        ;   if c-5 goto 20  If c isn't 5, go to line 20
        ;
        ; Expressions:
        ;
        ;   The operators +, -, / and * are available with
        ;   common precedence rules and signed operation.
        ;   Integer-only arithmetic.
        ;
        ;   You can also use parentheses:
        ;
        ;      5+6*(10/2)
        ;
        ;   Variables and numbers can be used in expressions.
        ;
        ;   The rnd function (without arguments) returns a
        ;   value between 0 and 255.
        ;
        ; Sample program (counting 1 to 10):
        ;
        ; 10 a=1
        ; 20 print a
        ; 30 a=a+1
        ; 40 if a-11 goto 20
        ;
        ; Sample program (Pascal's triangle, each number is the sum
        ; of the two over it):
        ;
        ; 10 input n
        ; 20 i=1
        ; 30 c=1
        ; 40 j=0
        ; 50 t=n-i
        ; 60 if j-t goto 80
        ; 70 goto 110
        ; 80 print " ";
        ; 90 j=j+1
        ; 100 goto 50
        ; 110 k=1
        ; 120 if k-i-1 goto 140
        ; 130 goto 190
        ; 140 print c;
        ; 150 c=c*(i-k)/k
        ; 160 print " ";
        ; 170 k=k+1
        ; 180 goto 120
        ; 190 print
        ; 200 i=i+1
        ; 210 if i-n-1 goto 30
        ;
        ; Sample program of guessing the dice:
        ;
        ; 10 print "choose ";
        ; 20 print "a number ";
        ; 30 print "(1-6)"
        ; 40 input a
        ; 50 b=rnd
        ; 60 b=b-b/6*6
        ; 70 b=b+1
        ; 80 if a-b goto 110
        ; 90 print "good"
        ; 100 goto 120
        ; 110 print "miss"
        ; 120 print b
        ;

        cpu 8086
        
com_file:       equ 1


vars:       equ 0x7e00  ; Variables (multiple of 256)
line:       equ 0x7e80  ; Line input

progloc:    equ 0x8000  ; Program address
                        ; (notice optimizations dependent on this address)

stack:      equ 0xff00  ; Stack address
current_line:   equ vars-2 ; Current BASIC line during RUN
max_line:   equ 1000    ; First unavailable line number
max_length: equ 20      ; Maximum length of line inc CR
max_size:   equ max_line*max_length ; Max. program size

	SECTION .text

start:
        cld             ; Clear Direction flag
        push cs         ; For boot sector
        push cs         ; it needs to setup
        push cs         ; DS, ES and SS.
        pop ds
        pop es
        pop ss		; running as EXE so tidy up segments like COM
	mov di,prog_end  ; Clear after program
f14:    mov byte [di],0x0d ; Fill with Carriage Return (CR) character
        inc di          ; Until reaching maximum 64K (DI becomes zero)
        jne f14
        ;
        ; Main loop
        ;
main_loop:
        mov sp,stack    ; Reinitialize stack pointer
        mov ax,main_loop
        push ax
        mov al,'>'      ; Show prompt
        call input_line ; Accept line
        call input_number       ; Get number
        or ax,ax        ; No number or zero?
        je statement    ; Yes, jump
        call find_line  ; Find the line
        xchg ax,di      
;       mov cx,max_length       ; CX loaded with this value in 'find_line'
        rep movsb       ; Copy entered line into program
        ret		; pops earlier main_loop

new_statement:
	mov di,program  ; Point to program space start
	jmp short f14
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
        ; BUG: Cant get current BASIC line number
        ;
error:
        call new_line
        mov al,'@'
        call output
        cmp sp,stack-2      ; Interactive mode has no current line
        je f33
        mov ax,[current_line]
        jmp f34
f33:    xor ax,ax
f34:
        call output_number
        call new_line
        jmp main_loop   ; Exit to main loop

        ;
        ; Handle 'rem' statement (comment)
        ;
rem_statement:
        ret

        ;
        ; Handle 'list' statement
        ;
list_statement:
        xor ax,ax       ; Start from line zero
f29:    push ax
        call find_line  ; Find program line
        xchg ax,si
        cmp byte [si],0x0d ; Empty line?
        je f30          ; Yes, jump
        pop ax
        push ax
        call output_number ; Show line number
f32:    lodsb           ; Show line contents
        call output
        jne f32         ; Jump if it wasn't 0x0d (CR)
f30:    pop ax
        inc ax          ; Go to next line
        cmp ax,max_line ; Finished?
        jne f29         ; No, continue
f6:
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
        jmp short spaces

f25:    cmp al,0x72
        jne f22
        cmp byte [si],0x6e
        jne f22
        lodsw               ; Advance SI by 2
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
        mov ah,vars>>8      ; Setup high-byte of address
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
        cmp byte [si],0x0d    ; Stop at end of line
        je space_ret
        cmp byte [si],' '     ; Space?
        je spaces_2           ; Yes
space_ret:
	ret

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
        db 0xb9             ; MOV CX to jump over XOR AX,AX

        ;
        ; Handle 'run' statement
        ; (equivalent to 'goto 0')
        ;
run_statement:
        xor ax,ax           
f10:
        call find_line      ; Find line in program
f27:    cmp sp,stack-2      ; In interactive mode?
        je f31              ; Yes, jump.
        mov [stack-4],ax    ; No, replace the saved address of next line
        ret
f31:
        push ax
        sub ax,program       ; Convert pointer into BASIC line number
        xor dx,dx
        mov cx,max_length
        div cx
        mov [current_line],ax
        pop ax
        push ax
        pop si
        add ax,max_length   ; Point to next line
        push ax             ; Save for next time (this goes into address stack-4)
        call statement      ; Process current statement
        pop ax              ; Restore address of next line (could have changed)
        cmp ax,program+max_size ; Reached the end?
        jne f31             ; No, continue
        ret                 ; Yes, return

        ;
        ; Input line from keyboard
        ; Entry:
        ;   al = prompt character
        ; Result:
        ;   buffer 'line' contains line, finished with CR
        ;   SI points to 'line'.
        ;
input_line:
        call output
        mov si,line
        push si
        pop di          ; Target for writing line
f1:     call input_key  ; Read keyboard
        stosb           ; Save key in buffer
        cmp al,0x08     ; Backspace?
        jne f2          ; No, jump
        dec di          ; Get back one character
        dec di
f2:     cmp al,0x0d     ; CR pressed?
        jne f1          ; No, wait another key
        ret             ; Yes, return

        ;
        ; Handle "print" statement
        ;
print_statement:
        lodsb           ; Read source
        cmp al,0x0d     ; End of line?
        je new_line     ; Yes, generate new line and return
        cmp al,0x22     ; Double quotes?
        jne f7          ; No, jump
print_2:
f9:
        lodsb           ; Read string contents
        cmp al,0x22     ; Double quotes?
        je f18          ; Yes, jump
        call output     ; Output character
        cmp al,0x0d     ; 
        jne f9          ; Jump if not finished with 0x0d (CR)
        ret             ; Return

f7:     dec si
        call expr       ; Handle expression
        call output_number      ; Output result
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

        ;
        ; Find line in program
        ; Entry:
        ;   ax = line number
        ; Result:
        ;   ax = pointer to program.
        ;   cx = max. length allowed for line.
find_line:
        mov cx,max_length
        mul cx
        add ax,program
        ret

        ;
        ; List of statements of bootBASIC
        ; First one byte with length of string
        ; Then string with statement
        ; Then a word with the address of the code
        ;
statements:
        db 4,"new"
        dw new_statement

        db 5,"list"
        dw list_statement

        db 4,"rem"
        dw rem_statement

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


        db 1

error_message:
        db "@#!",0x0d   ; Guess the words :P

        
	; Cant use two ORGS so pad to Progloc
        TIMES progloc-($-$$) DB 0x0d

; Each line is given a max_length byte slot inc 0x0d sentinel

program:	; start of program?
        TIMES (progloc + 10*max_length)-($-$$) DB 0x0d
        db " rem 16-bit fixedpt",0x0d      
        TIMES (progloc + 20*max_length)-($-$$) DB 0x0d
	db " rem mandelbrot",0x0d      
        TIMES (progloc + 30*max_length)-($-$$) DB 0x0d
        db " y=-307",0x0d      
        TIMES (progloc + 40*max_length)-($-$$) DB 0x0d
        db " l=307",0x0d   
        TIMES (progloc + 50*max_length)-($-$$) DB 0x0d
        db " s=-512",0x0d   
        TIMES (progloc + 60*max_length)-($-$$) DB 0x0d
        db " e=256",0x0d   
        TIMES (progloc + 70*max_length)-($-$$) DB 0x0d
        db " t=24",0x0d   
        TIMES (progloc + 80*max_length)-($-$$) DB 0x0d
        db " p=12",0x0d   
        TIMES (progloc + 90*max_length)-($-$$) DB 0x0d
        db " x=s",0x0d   
        TIMES (progloc + 100*max_length)-($-$$) DB 0x0d
        db " a=x",0x0d   
        TIMES (progloc + 110*max_length)-($-$$) DB 0x0d
        db " b=y",0x0d   
        TIMES (progloc + 120*max_length)-($-$$) DB 0x0d
        db " c=0",0x0d   
        TIMES (progloc + 130*max_length)-($-$$) DB 0x0d
        db " d=0",0x0d   
        TIMES (progloc + 140*max_length)-($-$$) DB 0x0d
        db " i=0",0x0d   
        TIMES (progloc + 150*max_length)-($-$$) DB 0x0d
        db " f=(c*c)/256",0x0d   
        TIMES (progloc + 160*max_length)-($-$$) DB 0x0d
        db " g=(d*d)/256",0x0d   
        TIMES (progloc + 170*max_length)-($-$$) DB 0x0d
        db " m=(f+g)/1024",0x0d
        TIMES (progloc + 171*max_length)-($-$$) DB 0x0d
        db " if m goto 220",0x0d
        TIMES (progloc + 180*max_length)-($-$$) DB 0x0d
        db " d=(c*d)/128+b",0x0d   
        TIMES (progloc + 190*max_length)-($-$$) DB 0x0d
        db " c=f-g+a",0x0d   
        TIMES (progloc + 200*max_length)-($-$$) DB 0x0d
        db " i=i+1",0x0d   
        TIMES (progloc + 210*max_length)-($-$$) DB 0x0d
        db " if i-16 goto 150",0x0d   
        TIMES (progloc + 220*max_length)-($-$$) DB 0x0d
        db " if i-8 goto 223",0x0d
        TIMES (progloc + 221*max_length)-($-$$) DB 0x0d
        db " goto 290",0x0d
        TIMES (progloc + 223*max_length)-($-$$) DB 0x0d
        db " if i-9 goto 225",0x0d
        TIMES (progloc + 224*max_length)-($-$$) DB 0x0d
        db " goto 290",0x0d
        TIMES (progloc + 225*max_length)-($-$$) DB 0x0d
        db " if i-10 goto 227",0x0d
        TIMES (progloc + 226*max_length)-($-$$) DB 0x0d
        db " goto 290",0x0d
        TIMES (progloc + 227*max_length)-($-$$) DB 0x0d
        db " if i-11 goto 230",0x0d
        TIMES (progloc + 228*max_length)-($-$$) DB 0x0d
        db " goto 290",0x0d
        TIMES (progloc + 230*max_length)-($-$$) DB 0x0d
        db " if i-12 goto 233",0x0d
        TIMES (progloc + 231*max_length)-($-$$) DB 0x0d
        db " goto 300",0x0d
        TIMES (progloc + 233*max_length)-($-$$) DB 0x0d
        db " if i-13 goto 235",0x0d
        TIMES (progloc + 234*max_length)-($-$$) DB 0x0d
        db " goto 300",0x0d
        TIMES (progloc + 235*max_length)-($-$$) DB 0x0d
        db " if i-14 goto 237",0x0d
        TIMES (progloc + 236*max_length)-($-$$) DB 0x0d
        db " goto 300",0x0d
        TIMES (progloc + 237*max_length)-($-$$) DB 0x0d
        db " if i-15 goto 239",0x0d
        TIMES (progloc + 238*max_length)-($-$$) DB 0x0d
        db " goto 300",0x0d
        TIMES (progloc + 239*max_length)-($-$$) DB 0x0d
        db " if i-16 goto 242",0x0d
        TIMES (progloc + 240*max_length)-($-$$) DB 0x0d
        db " goto 300",0x0d
        TIMES (progloc + 242*max_length)-($-$$) DB 0x0d
        db " if i-4 goto 245",0x0d
        TIMES (progloc + 243*max_length)-($-$$) DB 0x0d
        db " goto 270",0x0d
        TIMES (progloc + 245*max_length)-($-$$) DB 0x0d
        db " if i-5 goto 248",0x0d
        TIMES (progloc + 246*max_length)-($-$$) DB 0x0d
        db " goto 270",0x0d
        TIMES (progloc + 248*max_length)-($-$$) DB 0x0d
        db " if i-6 goto 251",0x0d
        TIMES (progloc + 249*max_length)-($-$$) DB 0x0d
        db " goto 280",0x0d
        TIMES (progloc + 250*max_length)-($-$$) DB 0x0d
        db " print ",0x22," ",0x22,";",0x0d   
        TIMES (progloc + 251*max_length)-($-$$) DB 0x0d
        db " if i-7 goto 254",0x0d
        TIMES (progloc + 252*max_length)-($-$$) DB 0x0d
        db " goto 280",0x0d
        TIMES (progloc + 254*max_length)-($-$$) DB 0x0d
        db " if i-2 goto 257",0x0d
        TIMES (progloc + 255*max_length)-($-$$) DB 0x0d
        db " goto 260",0x0d
        TIMES (progloc + 257*max_length)-($-$$) DB 0x0d
        db " if i-3 goto 250",0x0d
        TIMES (progloc + 258*max_length)-($-$$) DB 0x0d
        db " goto 260",0x0d
        TIMES (progloc + 260*max_length)-($-$$) DB 0x0d
        db " print ",0x22,".",0x22,";",0x0d
        TIMES (progloc + 261*max_length)-($-$$) DB 0x0d
        db " goto 310",0x0d   
        TIMES (progloc + 270*max_length)-($-$$) DB 0x0d
        db " print ",0x22,"-",0x22,";",0x0d   
        TIMES (progloc + 271*max_length)-($-$$) DB 0x0d
        db " goto 310",0x0d   
        TIMES (progloc + 280*max_length)-($-$$) DB 0x0d
        db " print ",0x22,"+",0x22,";",0x0d   
        TIMES (progloc + 281*max_length)-($-$$) DB 0x0d
        db " goto 310",0x0d   
        TIMES (progloc + 290*max_length)-($-$$) DB 0x0d
        db " print ",0x22,"*",0x22,";",0x0d   
        TIMES (progloc + 291*max_length)-($-$$) DB 0x0d
        db " goto 310",0x0d   
        TIMES (progloc + 300*max_length)-($-$$) DB 0x0d
        db " print ",0x22,"#",0x22,";",0x0d   
        TIMES (progloc + 301*max_length)-($-$$) DB 0x0d
        db " goto 310",0x0d   
        TIMES (progloc + 310*max_length)-($-$$) DB 0x0d
        db " x=x+p",0x0d   
        TIMES (progloc + 320*max_length)-($-$$) DB 0x0d
        db " if x-256 goto 100",0x0d
        TIMES (progloc + 330*max_length)-($-$$) DB 0x0d
        db " print",0x0d   
        TIMES (progloc + 340*max_length)-($-$$) DB 0x0d
        db " y=y+t",0x0d   
        TIMES (progloc + 350*max_length)-($-$$) DB 0x0d
        db " if y-317 goto 90",0x0d
prog_end:  
        end
