.syntax unified
.global main, TIM7_IRQHandler, EXTI1_IRQHandler, EXTI0_IRQHandler
.type TIM7_IRQHandler, %function // inserts the function to the vector table
.type EXTI1_IRQHandler, %function //clock line
.type EXTI0_IRQHandler, %function
.include "macros.s"
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@						utility.s have been modified							@
@						Added extra pin and wire 								@
@					 		PARARELL PROTOCOL 									@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ uid: u6071322
@ Author: Lin Peng
@ clock cycle rate is 80mHz

main:
  @initialize the audio
  bl init_audio

  @initialize the pins
  bl init_gpio

  @duration for 0.50 Break
  ldr r8 , =96000

  @duration for 0.25s Note
  ldr r9 , =48000
  ldr r11, =#4800

@@@ credit: piazza 664 @@@
  @ unmask interrupt 55 (TIM7) in NVIC
  ldr r0, =#(0xe000e100 + 4)
  mov r1, #(1 << (55 - 32))
  str r1, [r0]
  @ RCC
  ldr r0, =#0x40021000
  @ RCC_APB1ENR10.1ms * 2500
  ldr r1, [r0, #0x58]
  @ clock TIM7
  orr r1, #(1 << 5)
  str r1, [r0, #0x58]

  @ required-delay paranoia
  nop
  nop

  @ DBGMCU_APB1FZR1
  ldr r0, =#0xe0042008
  ldr r1, [r0]
  @ set DBG_TIM7_STOP
  orr r1, #(1 << 5)
  str r1, [r0]

@ (SENDER!!?!?!!!)

  @ TIM7
  ldr r0, =#0x40001400
  @ TIMx_DIER
  ldr r1, [r0, #0x0c]
  @ set UIE
  orr r1, #1
  str r1, [r0, #0x0c]
  @TIMx_PSC := 7999 + 1 = 8,000 (8,000/80,000,000Hz = 0.1ms)
  ldr r1, =#7999
  str r1, [r0, #0x28]
  @ TIMx_ARR := 2500 (2500*0.1ms = 0.25s)
  ldr r1, =#10
  strh r1, [r0, #0x2c]
  @ TIMx_CR1
  ldr r1, [r0]
  @ set CE enables the clock
  orr r1, #0b1001
  @ store it back
  str r1, [r0]

  @ NVIC_IPRn
  ldr r0, =#0xe000e400
  ldr r1, [r0, #((55/4) * 4)] @ TIM7
  bic r1, #(15 << (8 * (55 % 4) + 4))
  orr r1, #(2 << (8 * (55 % 4) + 4)) @ priority := 2
  str r1, [r0, #((55/4) * 4)]

  ldr r1, [r0, #((6/4) * 4)] @ EXTI0 Control Line
  bic r1, #(15 << (8 * (6 % 4) + 4))
  orr r1, #(0 << (8 * (6 % 4) + 4)) @ priority := 0
  str r1, [r0, #((6/4) * 4)]

  ldr r1, [r0, #((7/4) * 4)] @ EXTI1 Clock Line
  bic r1, #(15 << (8 * (7 % 4) + 4))
  orr r1, #(1 << (8 * (7 % 4) + 4)) @ priority := 1
  str r1, [r0, #((7/4) * 4)]

@ play square repeatedly
play_square_repeated:
	bl play_square
	b play_square_repeated

@ --arguments--
@ r0: message
send_a_message:
	push {r4, r5, lr}
	mov r4, r0
	@1) enable the control line from 0 to 1
	GPIOx_ODR_set E, 12

	ldr r0, =#3000
	bl delay

	@ add a counter to count down from 16 to 0 to terminate the loop
	mov r5, #16

	@2) grab the first bit
	grab_each_bit:
		@ data line 1
		tst r4, #(1 <<31) @ sets the zero flag. 1 = unset, 0 set and store the flag value into r5
		lsl r4, #1 @ left shift everything by 1
		beq bit_zero_E14
		GPIOx_ODR_set E, 14 @set up 14 for the data line 1
		b data_line_2

		bit_zero_E14:
			GPIOx_ODR_clear E 14 //data line 1

		data_line_2:
		@ data line 2
		tst r4, #(1 <<31) @ sets the zero flag. 1 = unset, 0 set and store the flag value into r5
		lsl r4, #1 @ left shift everything by 1
		beq bit_zero_E15
		GPIOx_ODR_set E, 15 @set up 15 for the data line 2
		b bit_one

		bit_zero_E15:
			GPIOx_ODR_clear E 15 //data line 2

	bit_one: @ send bit
		@ toggle the clock because the bit is one
		GPIOx_ODR_toggle E, 13

		@ --arguments--
		@ r0: delay length (actual delay will be approx. 2 * r0 cycles) 100*20 (20 cycle is one microsecond because it is 80mHz)
		ldr r0, =#3000
		bl delay

		@ terminate this loop...
		add r5, #1
		cmp r5, #32
		beq send_a_message_return
		b grab_each_bit


send_a_message_return:
	@ Clear out the controller line so receiver can play the note
	GPIOx_ODR_clear E, 12
	pop {r4, r5, lr}
	bx lr @ branch back to whoever called you

@ TRANSMITTER!!!!!?!?!!!!111
@ interrupt function that will move the note(s)
TIM7_IRQHandler:
	push {r4, r5, lr}

	@ clear UIF
	ldr r0, =#0x40001400
	ldr r1, [r0, #0x10]
	bic r1, #1
	str r1, [r0, #0x10]

	@ load the storage address
	ldr r0, =storage

	@ load the index
	ldr r1, =index

	@ load the boolean
	ldr r3, =boolean

	@ load the boolean value
	ldr r4, [r3]

	@ r2 has the index value
	ldr r2, [r1]

	add r0, r2

	@ if the index value is zero, do the rest
	@cbz r2, rest

	cbz r4, note

	rest:
	@ increment by 12 bytes to get the next freq
	add r2, #12

	str r2, [r1]

	@ change boolean from 1 to 0
	mov r4, #0

	@ load the freqnecy value to r2
	ldr r2, [r0]
	@ assign amp
	mov r5, #0
	@ write duration delay
	ldr r6, [r0,#8]

	b end_note

	note:
		@ change boolean from 0 to 1
		mov r4, #1
		@ load the freqnecy value to r2
		ldr r2, [r0]
		@ assign amp
		ldr r5, =#0x7FFF
		@ write duration
		ldr r6, [r0,#4]

	end_note:
		str r4, [r3]

	cbz r2, exit_handler

	@ construct put message together
	lsl r0, r2, #16
	orr r0, r5

	bl send_a_message

	@ reenable the timer with ARR
  	ldr r0, =#0x40001400
  	@ TIMx_ARR := 2500 (2500*0.1ms = 0.25s)
  	strh r6, [r0, #0x2c]
  	@ TIMx_CR1
  	ldr r1, [r0]
  	@ set CE enables the clock
  	orr r1, #1
  	@ store it back
  	str r1, [r0]

	exit_handler:
	@go to the following instructions pop and bx lr
	pop {r4, r5, lr}
	bx lr

@ (RECEIVER!!!?!?!!!)
@ interrupt for the control line
EXTI0_IRQHandler:
	push {r11,lr}
	EXTI_PR_clear_pending 0

    GPIOx_IDR_read H, 0 @ control line of the receiver side
    beq falling
    bne rising

    falling:
    	@r0 = freq
    	@r1 = amplitude

    	ldr r3, =counter
    	ldr r11, [r3]

    	ldr r12, =message
    	ldr r2, [r12]

    	@store the freq value
    	lsr r0, r2, #16

    	@shift left then shift right then back to get the 16bit
    	lsl r2, #16

    	lsr r2, #16

    	@put r2 into r1
    	mov r1, r2

		cmp r11, #16
		bne rising
    	bl change_square

    rising:
		ldr r3, =counter
		mov r0, #0
		str r0, [r3]

		ldr r3, =message
		mov r0, #0
		str r0, [r3]

	pop {r11, lr}
	bx lr

@ (RECEIVER!!!?!?!!!)
@ interrupt for the clock line
  @ E14->E11 (data line 1)
  @ E15->E10 (data line 2)
EXTI1_IRQHandler:
	push {lr}
	EXTI_PR_clear_pending 1

	GPIOx_IDR_read E, 11 @ read the data line 1
	mov r11, r0 @ save the bit we've just read from GPIO 11

	GPIOx_IDR_read E, 10 @ read the data line 2 @ the value from this is already in r0

	ldr r2, =counter @ load the counter data structure
	ldr r3, [r2] @ store the value into r3 as a 'counter'

	ldr r12, =message @ load the message data structure
	ldr r1, [r12] @ load the value into r1 as the value of the 'message'

	orr r1, r11  @ orr the bit value read from the sender with the value from the storage 'message'
	lsl r1, #1 @ left shift the value that has been or-ed by 1
	orr r1, r0

	add r3, #1 @ increment the counter
	cmp r3, #16 @ compare when the counter up to 16
	beq finish @ if it equals to 16, then store the message into r1
	lsl r1, #1 @ left shift the value that has been or-ed by 1

	finish:
	str r1, [r12]
	str r3, [r2]

	pop {lr}
	bx lr

@safety net
end:
	nop
	b end

@storage of the notes
.data
@ SENDER!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
storage:
	@ the first column is the frequency calculated by the sampled rate of 192kHz
	.word 308, 2500, 1 @ hard code this in to play first while receiver is playing this at first
	@ the unit of the time is 1/10 ms due to the PSC config. (e.g. 2500 * 0.1ms = .25s)
	.word 259, 2500, 1
	.word 206, 2500, 1
	.word 259, 2500, 1
	.word 308, 2500, 1
	.word 259, 2500, 1
	.word 1, 1, 5000
	.word 345, 2500, 1
	.word 275, 2500, 1
	.word 345, 2500, 1
	.word 231, 2500, 1
	.word 259, 2500, 1
	.word 275, 2500, 1
	.word 259, 2500, 1
	.word 1, 1, 5000
	.word 366, 2500, 1
	.word 308, 2500, 1
	.word 366, 2500, 1
	.word 231, 2500, 1
	.word 259, 2500, 1
	.word 308, 2500, 1
	.word 366, 2500, 1
	.word 1, 1, 5000
	.word 390, 2500, 1
	.word 388, 2500, 1
	.word 390, 2500, 1
	.word 206, 2500, 1
	.word 412, 2500, 1
	.word 206, 2500, 1
	.word 0, 0, 0

@ SENDER!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
index:
	.word 0 @int i = 0 like in Java
@ SENDER!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
boolean: @ let me know if we're sending a rest(1) or a note (0)
	.word 0

@ RECEIVER!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
message:
	.word 0
counter:
	.word 0

