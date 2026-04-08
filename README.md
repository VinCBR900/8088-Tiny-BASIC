# 8088-Tiny-BASIC

Intel 8088  Tiny BASIC **WORK IN PRGRESS**, do not use.

##  Notes

First attempt at writing a Intel 8088 Tiny BASIC Interpreter in Claude with help from CODEX.  Target is <2kbyte for a 2716 EPROM.

Dev platform is FreeDOs but eventuially we will run on an standalone embedded system via serial comms. 

To assemble run makefile or use this command line:

  nasm -f bin basic.asm -Dcom_file=1 -o basic.com

# Credits
Derived from **bootBASIC interpreter in 512 bytes (boot sector or COM file)**
by Oscar Toledo G. Jul/22/2019

http://nanochess.org

See

https://github.com/nanochess/bootBASIC
