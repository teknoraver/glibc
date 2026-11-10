/* memcpy for RISC-V, using only naturally aligned accesses
   Copyright (C) 2026 Free Software Foundation, Inc.
   This file is part of the GNU C Library.

   The GNU C Library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   The GNU C Library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with the GNU C Library.  If not, see
   <https://www.gnu.org/licenses/>.  */

#include <sysdep.h>
#include <sys/asm.h>

#if IS_IN(libc)
/* memcpy optimization for CPUs without V where misaligned accesses are
   not reported as fast (any RISCV_HWPROBE_MISALIGNED_* value other than
   FAST).

   Every load and store is naturally aligned.  Copies shorter than
   2 * SZREG are done with byte loads and stores in blocks of 8, 4, 2
   and 1 bytes, selected by the bits of LEN, without loops.  Longer
   copies first align DEST the same way, then:

   - if SRC is now aligned too, copy BLOCK_SIZE bytes per iteration with
     interleaved loads and stores, then blocks of 8, 4, 2 and 1 words
     selected by the bits of LEN, then a 4/2/1 byte tail;

   - otherwise round SRC down to a word boundary and build each output
     word from two adjacent aligned source words with shifts
     ((w0 >> shr) | (w1 << shl)), 8 words per iteration, then at most
     one block of 4 words, then single words, then copy the remaining
     bytes in blocks of 4, 2 and 1 bytes.

   Short byte loops are avoided because on the SiFive P550 their cost
   jumps by several cycles at a small iteration count: copying 2 bytes
   with a byte loop took longer than 3 bytes with the blocks above.

   The shifted copy reads the aligned word containing the last source
   byte, so it never reads past the aligned word holding SRC + LEN - 1
   and cannot cross a page boundary that the copy itself does not.

   Loop heads are aligned to 16 bytes: on the SiFive P550 a 16-byte
   loop ran about 30% slower when it straddled a 64-byte boundary,
   which otherwise depends on where the linker places this code.  */

# define BLOCK_SIZE (16 * SZREG)

ENTRY (__memcpy_shifted)
	/* a6 = DEST cursor, a0 is preserved as the return value.  */
	mv	a6, a0

	/* If LEN < 2 * SZREG copy bytes.  */
	li	a3, 2*SZREG
	bltu	a2, a3, L(byte_copy)

	/* Copy a3 = (-DEST) & (SZREG-1) bytes to align DEST, in blocks of
	   1, 2 and 4 bytes selected by the bits of a3.  */
	neg	a3, a0
	andi	a3, a3, SZREG-1
	beqz	a3, L(dst_aligned)
	sub	a2, a2, a3
	andi	a4, a3, 1
	beqz	a4, 1f
	lbu	a5, 0(a1)
	sb	a5, 0(a6)
	addi	a1, a1, 1
	addi	a6, a6, 1
1:
	andi	a4, a3, 2
	beqz	a4, 2f
	lbu	a4, 0(a1)
	lbu	a5, 1(a1)
	sb	a4, 0(a6)
	sb	a5, 1(a6)
	addi	a1, a1, 2
	addi	a6, a6, 2
2:
# if SZREG == 8
	andi	a4, a3, 4
	beqz	a4, L(dst_aligned)
	lbu	a4, 0(a1)
	lbu	a5, 1(a1)
	lbu	t0, 2(a1)
	lbu	t1, 3(a1)
	sb	a4, 0(a6)
	sb	a5, 1(a6)
	sb	t0, 2(a6)
	sb	t1, 3(a6)
	addi	a1, a1, 4
	addi	a6, a6, 4
# endif

L(dst_aligned):
	/* DEST is aligned, LEN > SZREG.  */
	andi	a3, a1, SZREG-1
	bnez	a3, L(shifted)

	/* Both aligned.  If LEN < BLOCK_SIZE jump to word copy.  */
	li	a4, BLOCK_SIZE-1
	bleu	a2, a4, L(word_copy)
	andi	a7, a2, -BLOCK_SIZE
	add	a7, a6, a7
	.p2align 4
L(block_loop):
	REG_L	a3, 0(a1)
	REG_L	a4, SZREG(a1)
	REG_S	a3, 0(a6)
	REG_L	a5, (2*SZREG)(a1)
	REG_S	a4, SZREG(a6)
	REG_L	t0, (3*SZREG)(a1)
	REG_S	a5, (2*SZREG)(a6)
	REG_L	a3, (4*SZREG)(a1)
	REG_S	t0, (3*SZREG)(a6)
	REG_L	a4, (5*SZREG)(a1)
	REG_S	a3, (4*SZREG)(a6)
	REG_L	a5, (6*SZREG)(a1)
	REG_S	a4, (5*SZREG)(a6)
	REG_L	t0, (7*SZREG)(a1)
	REG_S	a5, (6*SZREG)(a6)
	REG_L	a3, (8*SZREG)(a1)
	REG_S	t0, (7*SZREG)(a6)
	REG_L	a4, (9*SZREG)(a1)
	REG_S	a3, (8*SZREG)(a6)
	REG_L	a5, (10*SZREG)(a1)
	REG_S	a4, (9*SZREG)(a6)
	REG_L	t0, (11*SZREG)(a1)
	REG_S	a5, (10*SZREG)(a6)
	REG_L	a3, (12*SZREG)(a1)
	REG_S	t0, (11*SZREG)(a6)
	REG_L	a4, (13*SZREG)(a1)
	REG_S	a3, (12*SZREG)(a6)
	REG_L	a5, (14*SZREG)(a1)
	REG_S	a4, (13*SZREG)(a6)
	REG_L	t0, (15*SZREG)(a1)
	REG_S	a5, (14*SZREG)(a6)
	addi	a1, a1, BLOCK_SIZE
	REG_S	t0, (15*SZREG)(a6)
	addi	a6, a6, BLOCK_SIZE
	bne	a6, a7, L(block_loop)
	andi	a2, a2, BLOCK_SIZE-1
	/* Skip the word blocks if no whole word is left.  Coming from the
	   entry LEN >= SZREG + 1 here, so the check is only needed after
	   the block loop.  */
	andi	a3, a2, -SZREG
	beqz	a3, L(aligned_tail)

	/* 0 <= LEN < BLOCK_SIZE, SRC and DEST aligned.  Copy 8, 4, 2 and 1
	   words selected by the bits of LEN, without loops.  */
L(word_copy):
	andi	a3, a2, 8*SZREG
	beqz	a3, 1f
	REG_L	a3, 0(a1)
	REG_L	a4, SZREG(a1)
	REG_L	a5, (2*SZREG)(a1)
	REG_L	t0, (3*SZREG)(a1)
	REG_S	a3, 0(a6)
	REG_S	a4, SZREG(a6)
	REG_S	a5, (2*SZREG)(a6)
	REG_S	t0, (3*SZREG)(a6)
	REG_L	a3, (4*SZREG)(a1)
	REG_L	a4, (5*SZREG)(a1)
	REG_L	a5, (6*SZREG)(a1)
	REG_L	t0, (7*SZREG)(a1)
	REG_S	a3, (4*SZREG)(a6)
	REG_S	a4, (5*SZREG)(a6)
	REG_S	a5, (6*SZREG)(a6)
	REG_S	t0, (7*SZREG)(a6)
	addi	a1, a1, 8*SZREG
	addi	a6, a6, 8*SZREG
1:
	andi	a3, a2, 4*SZREG
	beqz	a3, 2f
	REG_L	a3, 0(a1)
	REG_L	a4, SZREG(a1)
	REG_L	a5, (2*SZREG)(a1)
	REG_L	t0, (3*SZREG)(a1)
	REG_S	a3, 0(a6)
	REG_S	a4, SZREG(a6)
	REG_S	a5, (2*SZREG)(a6)
	REG_S	t0, (3*SZREG)(a6)
	addi	a1, a1, 4*SZREG
	addi	a6, a6, 4*SZREG
2:
	andi	a3, a2, 2*SZREG
	beqz	a3, 3f
	REG_L	a3, 0(a1)
	REG_L	a4, SZREG(a1)
	REG_S	a3, 0(a6)
	REG_S	a4, SZREG(a6)
	addi	a1, a1, 2*SZREG
	addi	a6, a6, 2*SZREG
3:
	andi	a3, a2, SZREG
	beqz	a3, L(aligned_tail)
	REG_L	a3, 0(a1)
	REG_S	a3, 0(a6)
	addi	a1, a1, SZREG
	addi	a6, a6, SZREG

	/* 0 <= LEN & (SZREG-1) < SZREG, SRC and DEST aligned, so every
	   access below is naturally aligned.  */
L(aligned_tail):
# if SZREG == 8
	andi	a3, a2, 4
	beqz	a3, 1f
	lw	a4, 0(a1)
	addi	a1, a1, 4
	sw	a4, 0(a6)
	addi	a6, a6, 4
1:
# endif
	andi	a3, a2, 2
	beqz	a3, 2f
	lhu	a4, 0(a1)
	addi	a1, a1, 2
	sh	a4, 0(a6)
	addi	a6, a6, 2
2:
	andi	a3, a2, 1
	beqz	a3, L(ret)
	lbu	a4, 0(a1)
	sb	a4, 0(a6)
	ret

	/* DEST aligned, SRC not, LEN > SZREG.
	   a3 = SRC & (SZREG-1), 0 < a3 < SZREG.  */
L(shifted):
	/* t5 = right shift amount, t6 = left shift amount.  The shift
	   instructions only use the low log2(XLEN) bits of the amount, so
	   -t5 behaves as XLEN - t5.  */
	slli	t5, a3, 3
	neg	t6, t5
	/* Round SRC down to a word boundary.  */
	sub	a1, a1, a3
	/* a7 = end of the whole words in DEST, t4 = end of the 8 word blocks.  */
	andi	a7, a2, -SZREG
	add	a7, a6, a7
	andi	t4, a2, -(8*SZREG)
	add	t4, a6, t4
	/* a4 = the current aligned source word.  */
	REG_L	a4, 0(a1)
	beq	a6, t4, L(shifted_4)
	.p2align 4
L(shifted_loop8):
	REG_L	t0,     SZREG(a1)
	REG_L	t1, (2*SZREG)(a1)
	srl	a4, a4, t5
	sll	a5, t0, t6
	or	a4, a4, a5
	REG_L	t2, (3*SZREG)(a1)
	REG_S	a4,         0(a6)
	srl	t0, t0, t5
	sll	t3, t1, t6
	or	t0, t0, t3
	REG_L	a4, (4*SZREG)(a1)
	REG_S	t0,     SZREG(a6)
	srl	t1, t1, t5
	sll	a5, t2, t6
	or	t1, t1, a5
	REG_S	t1, (2*SZREG)(a6)
	srl	t2, t2, t5
	sll	t3, a4, t6
	or	t2, t2, t3
	REG_S	t2, (3*SZREG)(a6)
	REG_L	t0, (5*SZREG)(a1)
	REG_L	t1, (6*SZREG)(a1)
	srl	a4, a4, t5
	sll	a5, t0, t6
	or	a4, a4, a5
	REG_L	t2, (7*SZREG)(a1)
	REG_S	a4, (4*SZREG)(a6)
	srl	t0, t0, t5
	sll	t3, t1, t6
	or	t0, t0, t3
	REG_L	a4, (8*SZREG)(a1)
	REG_S	t0, (5*SZREG)(a6)
	srl	t1, t1, t5
	sll	a5, t2, t6
	or	t1, t1, a5
	REG_S	t1, (6*SZREG)(a6)
	srl	t2, t2, t5
	sll	t3, a4, t6
	or	t2, t2, t3
	REG_S	t2, (7*SZREG)(a6)
	addi	a1, a1, 8*SZREG
	addi	a6, a6, 8*SZREG
	bne	a6, t4, L(shifted_loop8)
L(shifted_4):
	/* At most one 4 word block is left.  */
	andi	t4, a2, 4*SZREG
	beqz	t4, L(shifted_word)
	REG_L	t0,     SZREG(a1)
	REG_L	t1, (2*SZREG)(a1)
	srl	a4, a4, t5
	sll	a5, t0, t6
	or	a4, a4, a5
	REG_L	t2, (3*SZREG)(a1)
	REG_S	a4,         0(a6)
	srl	t0, t0, t5
	sll	t3, t1, t6
	or	t0, t0, t3
	REG_L	a4, (4*SZREG)(a1)
	REG_S	t0,     SZREG(a6)
	srl	t1, t1, t5
	sll	a5, t2, t6
	or	t1, t1, a5
	REG_S	t1, (2*SZREG)(a6)
	srl	t2, t2, t5
	sll	t3, a4, t6
	or	t2, t2, t3
	REG_S	t2, (3*SZREG)(a6)
	addi	a1, a1, 4*SZREG
	addi	a6, a6, 4*SZREG
L(shifted_word):
	beq	a6, a7, L(shifted_tail)
	.p2align 4
L(shifted_loop1):
	REG_L	t0, SZREG(a1)
	srl	a4, a4, t5
	sll	a5, t0, t6
	or	a4, a4, a5
	REG_S	a4, 0(a6)
	mv	a4, t0
	addi	a1, a1, SZREG
	addi	a6, a6, SZREG
	bne	a6, a7, L(shifted_loop1)
L(shifted_tail):
	/* Point SRC back at the next unaligned byte.  */
	add	a1, a1, a3
	andi	a2, a2, SZREG-1

	/* Copy the remaining 0 <= LEN < 2 * SZREG bytes in blocks of 8, 4,
	   2 and 1 bytes selected by the bits of LEN.  */
L(byte_copy):
# if SZREG == 8
	andi	a3, a2, 8
	beqz	a3, 1f
	lbu	a3, 0(a1)
	lbu	a4, 1(a1)
	lbu	a5, 2(a1)
	lbu	a7, 3(a1)
	sb	a3, 0(a6)
	sb	a4, 1(a6)
	sb	a5, 2(a6)
	sb	a7, 3(a6)
	lbu	a3, 4(a1)
	lbu	a4, 5(a1)
	lbu	a5, 6(a1)
	lbu	a7, 7(a1)
	sb	a3, 4(a6)
	sb	a4, 5(a6)
	sb	a5, 6(a6)
	sb	a7, 7(a6)
	addi	a1, a1, 8
	addi	a6, a6, 8
1:
# endif
	andi	a3, a2, 4
	beqz	a3, 2f
	lbu	a3, 0(a1)
	lbu	a4, 1(a1)
	lbu	a5, 2(a1)
	lbu	a7, 3(a1)
	sb	a3, 0(a6)
	sb	a4, 1(a6)
	sb	a5, 2(a6)
	sb	a7, 3(a6)
	addi	a1, a1, 4
	addi	a6, a6, 4
2:
	andi	a3, a2, 2
	beqz	a3, 3f
	lbu	a3, 0(a1)
	lbu	a4, 1(a1)
	sb	a3, 0(a6)
	sb	a4, 1(a6)
	addi	a1, a1, 2
	addi	a6, a6, 2
3:
	andi	a3, a2, 1
	beqz	a3, L(ret)
	lbu	a3, 0(a1)
	sb	a3, 0(a6)
L(ret):
	ret
END (__memcpy_shifted)

#endif
