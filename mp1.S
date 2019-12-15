
# mp1.S - life-or-death version
# Good luck, and have fun!

.data
	
    # Constants for accessing the fields of a struct keystroke_args
    # struct keystroke_args is defined in rtc.h and mp1.h

	KA_SIZE	  = 14   # 14 bytes when copying
	KA_STACK  = 16   # use 16 bytes on stack for alignment
	DIRECTION = 0
	SELECTOR  = 2
	GUESS     = 4
	HINT      = 9

    # Constants for accessing the fields of a struct game_status
    # struct game_status is defined in rtc.h and mp1.h

	GS_SIZE   = 8	# 8 bytes
	POP 	  = 0
	INF	  = 4

    # Constants for screen size

    	SCR_WIDTH  = 80
	SCR_HEIGHT = 20
	SCR_SIZE   = ((SCR_WIDTH) * (SCR_HEIGHT))

    # ASCII cell images

        CELL_LIVE = 0x78
	CELL_DEAD = 0x20


# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl rand_seed, aggression

			.align 8
rand_seed:		.quad 0x0	# Pseudo-random number seed
aggression:		.long 0x0	# Aggression level of virus


# Data private to this file

current_board:		.long 0x0	# Address of current board
next_board:		.long 0x0	# Address of next board
population:		.long 0x0	# Remaining human population
infection:		.long 0x0	# Count of live virus cells
select_image:		.string "==>"	# Picture of the selector
select_blank:		.string "   "	# Picture to overwrite selector
base_array:             .string "ACGT"  # Array of characters for bases


.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long ignore);
# Performs three tasks:
#	(1) updates the life game board and calculates infection count
#	(2) swaps the two boards
#	(3) applies population reduction based on infection count
#	(4) redraws the screen
#	(5) notifies the user code by calling mp1_notify_user
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:
		pushl %ebp   #save old stack pointer
		movl %esp, %ebp
		
		pushl %ebx	#save registers
		pushl %esi
		pushl %edi
			
		movl current_board, %eax 	#return if current board = 0
		cmpl $0, %eax
		je done
			
		xorl %eax, %eax	#clear registers
		xorl %ecx, %ecx
		xorl %esi, %esi
		
board_loop:
		movl current_board, %edx	#address of board in ebx
		addl %ecx, %edx
		
		pushl %ecx			
		pushl %edx
		#caller save
		pushl %edx #push args
		call neighbor_count
		addl $4, %esp 	
		#caller restore
		popl %edx
		popl %ecx

		movl (%edx), %ebx
		#caller save
		pushl %ecx
		pushl %edx
		pushl %eax	#push args
		pushl %ebx
		call tick_result
		addl $8, %esp
		popl %edx	#caller restore
		popl %ecx

		# store next cell value
		movl next_board, %edx
		addl %ecx, %edx
		movb %al, (%edx)
		# increment count of infected cells
		addl %eax, %esi
		
		# loop logic
		inc %ecx
		cmpl $SCR_SIZE, %ecx
		jb board_loop

		imull $10, %esi #multiply total live cells by 10
		movl %esi, infection #put that value into infection
	
		movl current_board, %edi #swap board pointers
		movl next_board, %esi
		movl %esi, current_board
		movl %edi, next_board

		
		movl infection, %edi
		movl population, %esi
		subl %edi, %esi
		movl %esi, population	#makes sure infection is not
		cmpl $0, population
		jge drawscreen		    #greater than population, 
		movl $0, population 	    #otherwise sets population to 0
drawscreen:
		
		pushl %eax
		pushl %ecx
		pushl %edx
		call draw_screen
		popl %edx
		popl %ecx
		popl %eax
		
		pushl %ecx
		pushl %edx
		call mp1_notify_user
		popl %edx
		popl %ecx
done:
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function 
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:
		movl 8(%esp), %eax	#push cmd into ecx
		cmpl $4, %eax		#if cmd >4, jump to invalid 
		jge cmd_invalid		#if cmd < 0 jump to invalid		
		cmpl $0, %eax
		jl cmd_invalid

		jmp *jump_table(,%eax,4) #jump table
		jmp ioctl_done
cmd_invalid:
		movl $-1, %eax		#return -1 if cmd value >4
ioctl_done:
		ret


# ----------------- Functions private to this file -------------------


draw_screen:	
	# For simplicity, your implementation may assume a SCR_WIDTH of 80.
		pushl %ebp		#save all registers
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi

		xorl %eax, %eax
loop_row:
		movl current_board, %edx	
		#memory address of current_board goes to ebx
		addl %eax, %edx #eax used as video offset
		
		xorl %ebx, %ebx 	
		movb (%edx), %bl	#holds current cell value
		cmpb $0, %bl	#tests cell value. outputs appropriate character
		je DEAD
		movb $CELL_LIVE, %cl
		jmp DRAW
DEAD:
		movb $CELL_DEAD, %cl
DRAW:
		shl $1, %eax		#calls mp1_poke to output appropriate character
		pushl %ebx
		pushl %ecx
		pushl %edx
		call mp1_poke
		popl %edx
		popl %ecx
		popl %ebx

		shrl $1, %eax
		incl %eax
		cmpl $SCR_SIZE, %eax
		jb loop_row

		popl %edi	#callee restore / restore ebp
		popl %esi
		popl %ebx
		leave 
		ret

mp1_ioctl_startgame:
		pushl %ebp		#update base pointer
		movl %esp, %ebp
		pushl %ebx		#callee save
		pushl %esi
		pushl %edi

		pushl %ecx		#caller save
		pushl %edx
		
		movl 4(%ebp), %ebx 	#ebp + 8 contains seed
		pushl %ebx
		call seed_generator
		addl $4, %esp
		#caller restore
		popl %edx
		popl %ecx
		#caller save	
		pushl %ecx
		pushl %edx
		#allocate memory for boards
		movl $SCR_SIZE, %ebx
		pushl %ebx
		call mp1_malloc
		addl $4, %esp
		#caller restore
		popl %edx
		popl %ecx
		#tests to see if allocation failed
		movl %eax, current_board
		cmpl $0, current_board
		je allocation_failed
		#caller save
		pushl %ecx
		pushl %edx
		#allocate memory for boards
		movl $SCR_SIZE, %ebx
		pushl %ebx
		call mp1_malloc
		addl $4, %esp
		#caller restore
		popl %edx
		popl %ecx
		#test to see if allocation failed
		movl %eax, next_board
		cmpl $0, next_board
		je allocation2_failed
		
		xorl %ecx, %ecx
		
fill_with_zeros:
		movl current_board, %edx 	#loop through board and fill 
		addl %ecx, %edx				#with zeros
		movb $0, (%edx)
		
		movl next_board, %edx
		addl %ecx, %edx
		movb $0, (%edx)
		
		inc %ecx
		cmpl $SCR_SIZE - 1, %ecx
		jb fill_with_zeros 
		
		pushl %ecx	#caller save
		pushl %edx
		movl (current_board), %edx	#push arguments and initiate virus
		pushl %edx
		call init_virus
		addl $4, %esp
		popl %edx	#caller restore
		popl %ecx
		
		movl %eax, infection		#update variables
		movl $80, aggression
		movl $8000000, population
		movl $0, %eax
		
startgame_done:
		popl %edi	#callee / base pointer restore
		popl %esi
		popl %ebx
		leave
		ret
allocation2_failed:
	movl $0, current_board	#failed allocation cases
allocation_failed:
	movl -1, %eax
	jmp startgame_done

mp1_ioctl_endgame:
		pushl %ebp		#callee / base pointer save
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		#caller save
		pushl %ecx
		pushl %edx
		#free memory
		movl (current_board), %ebx
		pushl %ebx
		call mp1_free
		addl $4, %esp
		#caller restore
		popl %edx
		popl %ecx
		#caller save
		pushl %ecx
		pushl %edx
		#free memory
		movl (next_board), %ebx
		push %ebx
		call mp1_free
		addl $4, %esp
		#caller restore
		popl %edx
		popl %ecx
		#set values to 0
		movl $0, current_board
		movl $0, next_board
		#set return value to 0
		movl $0,%eax
		#callee / base pointer restore
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

mp1_ioctl_keystroke:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		
		#check for invalid characters
		movl 8(%ebp), %esi
		cmp $0, %esi
		je invalid_key
		
		addl $-KA_STACK, %esp #allocate space for kernel stack
		movl %esp, %ebx
		
		#copy keys to kernel memory
		pushl %ecx	#caller save
		pushl %edx 
		pushl $KA_SIZE	#push args
		pushl 8(%ebp)
		pushl %ebx
		call mp1_copy_to_user
		addl $12, %esp
		popl %edx	#caller restore
		popl %ecx
		#return value in eax
		#account for failed copy
		cmp $0, %eax
		je failed_copy
		
		movl $0, %eax
		movw (%ebx), %ax
		
		# copy struct back into user space
		
		pushl %ecx #caller save`
		pushl %edx
		pushl $KA_SIZE #push args
		pushl %ebx
		pushl 8(%ebp)
		call mp1_copy_from_user
		addl $12, %esp
		popl %edx
		popl %ecx	
		cmp $0, %eax
		jne failed_copy
		
		addl $KA_STACK, %esp #deallocate space off the stack
		#callee restore
		popl %edi
		popl %esi
		popl %ebx
		movl $0, %eax
		leave
		ret
failed_copy:
		addl $KA_STACK, %esp # pop kernel stack off
invalid_key:
		popl %edi
		popl %esi
		popl %ebx
		movl $-1, %eax
		leave
		ret


mp1_ioctl_getstatus:
		pushl %ebp		#callee save
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi

		movl 8(%ebp), %esi #put argument into esi
		cmp $0, %esi
		je error
		
		addl $-GS_SIZE, %esp	#allocate space on kernel stack
		push %ebx
		movl population, %eax #push population and infection onto stack
		movl %ebx, 4(%esp)
		movl infection, %ebx
		movl %ebx, 8(%esp)
		pop %ebx
		movl %esp, %ebx	#move stack ptr into ebx
		
		pushl %ecx	#caller save
		pushl %edx
		
		push $GS_SIZE	#push arguments and copy to user
		push %ebx
		pushl %esi
		call mp1_copy_to_user
		addl $12, %esp

		popl %edx	#caller restore
		popl %ecx

		addl $GS_SIZE, %esp #free space on kernel stack
		cmpl $0, %eax
		je getstatus_done

error:
		movl $-1, %eax

getstatus_done:		
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret
		
mp1_ioctl_vaccinate: 
		ret
	
jump_table:
.long mp1_ioctl_startgame, mp1_ioctl_endgame, mp1_ioctl_keystroke, mp1_ioctl_getstatus, mp1_ioctl_vaccinate
