/* SPDX-License-Identifier: GPL-2.0+ OR BSD-3-Clause */
/*
 * Copyright (c) 2019, STMicroelectronics - All Rights Reserved
 *
 */

/*****************************************************************************
 * This file is only needed for current Soc revision which has a limitation on
 * debug reset halt. This can be removed when using the Soc revision that
 * fixes the limitation. Anyway, this source code identifies the Soc revision
 * and is only executed if it corresponds, so it can be kept on other
 * revisions without any consequence.
 ****************************************************************************/

#include <linux/linkage.h>
#include <asm/macro.h>

#define BIT(nr)				(1 << (nr))

#define DBG_DSCR_ADDR			0x500D0088
#define DBG_DSCR_HDBGEN			BIT(14)

#define PWR_CR1_ADDR			0x50001000
#define PWR_CR1_DBP			BIT(8)

#define TAMP_BKP_REGISTER_20		(0x5C00A100 + (20 << 2))

#define BOOT_CONTEXT_ROM_VER_OFFSET	156
#define BOOT_CONTEXT_CUT_VER_OFFSET	4
#define BOOT_CONTEXT_CUT_VER_VALUE	0x00000200

	.globl	save_boot_params

ENTRY(save_boot_params)
	/*
	 * This function is the first call after reset.
	 * Boot rom parameters are stored in r0..r3, so we mustn't use them
	 * here. And because they are saved in r9..r12 just after the
	 * execution of this function, we should firstly use these registers.
	 * And then, if more registers needed, we have to start by using
	 * r8, and then r7 and so on. By this way, debug will be done in
	 * conditions closed to the initial context.
	 */

	/* Check Soc revision */
	mov	r12, r0
	ldr	r12, [r12, #BOOT_CONTEXT_ROM_VER_OFFSET]
	ldr	r12, [r12, #BOOT_CONTEXT_CUT_VER_OFFSET]
	teq	r12, #BOOT_CONTEXT_CUT_VER_VALUE
	bne	func_exit

	/* Disable the backup domain write protection */
	ldr	r12, =PWR_CR1_ADDR
	ldr	r11, [r12]
	orr	r11, r11, #PWR_CR1_DBP
	str	r11, [r12]
poll_dbp:
	ldr	r11, [r12]
	tst	r11, #PWR_CR1_DBP
	beq	poll_dbp

	/* Clear tamper 20 bit 16 if set */
	ldr	r12, =TAMP_BKP_REGISTER_20
	ldr	r11, [r12]
	tst	r11, #(BIT(16))
	beq	func_exit
	bic	r11, #(BIT(16))
	str	r11, [r12]

	/* Re-enable the backup domain write protection */
	ldr	r12, =PWR_CR1_ADDR
	ldr	r11, [r12]
	bic	r11, #PWR_CR1_DBP
	str	r11, [r12]
poll_dbp_2:
	ldr	r11, [r12]
	tst	r11, #PWR_CR1_DBP
	bne	poll_dbp_2

	/* Get current time + 1 second */
	/* CNTFRQ */
	mrc	p15, 0, r12, c14, c0, 0
	/* CNTPCT_64 */
	mrrc	p15, 0, r11, r10, c14
	add	r12, r12, r11

loop:
	/* Check A7 DBG_DSCR HDBGEN bit value */
	ldr	r10, =DBG_DSCR_ADDR
	ldr	r10, [r10]
	tst	r10, #DBG_DSCR_HDBGEN
	beq	loop_continue
	/* Sw break */
	bkpt	5
	/* Jump entrypoint */
	b	reset
loop_continue:
	/* Check 1 second expiration */
	mrrc	p15, 0, r10, r9, c14
	/* Check if MSB 64-bit increment needed */
	cmp	r12, r11
	bmi	msb_incr
	cmp	r12, r10
	bmi	func_exit
	b	loop
msb_incr:
	cmp	r12, r10
	bpl	loop
	cmp	r11, r10
	bmi	loop
func_exit:
	b	save_boot_params_ret
ENDPROC(save_boot_params)
