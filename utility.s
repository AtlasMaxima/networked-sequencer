.syntax unified
.global init_gpio, delay, play_square, change_square

.include "macros.s"

init_gpio:
  push {lr}

  @ connections
  @ E12->H0 (control)
  @ E13->H1 (clock)
  @ E14->E11 (data line 1)
  @ E15->E10 (data line 2)

  @ clock all the things
  RCC_AHB2ENR_set 4 @ GPIOE
  RCC_AHB2ENR_set 7 @ GPIOH
  RCC_APB2ENR_set 0 @ SYSCFG clock

  @ output pins @
  declare_output_pin E, 12 @ control
  declare_output_pin E, 13 @ clock
  declare_output_pin E, 14 @ data line 1
  declare_output_pin E, 15 @ data line 2

  @ input pins @
  @ control
  declare_input_pin_it H, 0
  EXTI_set_rising_edge_trigger 0
  EXTI_set_falling_edge_trigger 0
  @ clock
  declare_input_pin_it H, 1
  EXTI_set_rising_edge_trigger 1
  EXTI_set_falling_edge_trigger 1

  @ data (data line shouldn't need an interrupt)
  declare_input_pin E, 11 @ data line 1
  declare_input_pin E, 10 @ data line 2


  @ wait till things are ready
  mov r0, #5
  bl delay

  @ enable interrupts in NVIC
  NVIC_EXTI0_enable @ control receive pin H0
  NVIC_EXTI1_enable @ clock receive pin H1

  pop {lr}
  bx lr

@ --arguments--
@ r0: delay length (actual delay will be approx. 2 * r0 cycles)
delay:
  subs r0, #1
  bpl delay
  bx lr

@ --arguments--
@ r0: frequency
@ r1: amplitude
change_square:
  ldr r2, =192000 @ sample rate
  udiv r0, r2, r0
  mov r2, r1
  mov r1, #0
  ldr r3, =square_wave_data
  stmia r3, {r0,r1,r2}
  bx lr

@ takes no arguments, just keeps playing the square wave
play_square:
	push {lr}
	ldr r3, =square_wave_data
	@ r0: period
	@ r1: phase
	@ r3: semi-amplitude
	ldmia r3, {r0,r1,r2}

@ from here on, you shouldn't need to call these functions directly
@ they're just here so that play_square can do it's job

play_square_check_phase:
	@ if we're in the first half of the period, play the high value
	cmp r1, r0, asr #1
	bmi play_square_high

play_square_low:
	mov r0, #-1
	mul r0, r2 @ invert value for low half of waveform
	bl play_audio_sample
	b play_square_update_phase

play_square_high:
	mov r0, r2
	bl play_audio_sample

play_square_update_phase:
	ldr r3, =square_wave_data

	ldr r0, [r3]
	ldr r1, [r3, #4]
	add r1, #1

	cmp r1, r0
	bpl play_square_reset_phase
	b play_square_end

play_square_reset_phase:
	mov r1, #0

play_square_end:
	@ store new phase
	str r1, [r3, #4]
	pop {lr}
	bx lr

.data
square_wave_data:
.word 436     @ period (samples)
.word 0       @ phase (samples)
.word 0x7fff  @ semi-amplitude (half peak-to-peak)
