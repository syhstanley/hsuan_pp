	.file	"test3.c"
	.text
	.p2align 4
	.globl	test3
	.type	test3, @function
test3:
.LFB0:
	.cfi_startproc
	endbr64
	movq	%rdi, %rsi
	movl	$20000000, %ecx
	pxor	%xmm0, %xmm0
	leaq	8192(%rdi), %rdx
.L2:
	movq	%rsi, %rax
	.p2align 4,,10
	.p2align 3
.L3:
	movsd	(%rax), %xmm1
	addq	$16, %rax
	addsd	%xmm1, %xmm0
	movsd	-8(%rax), %xmm1
	addsd	%xmm1, %xmm0
	cmpq	%rax, %rdx
	jne	.L3
	subl	$1, %ecx
	jne	.L2
	ret
	.cfi_endproc
.LFE0:
	.size	test3, .-test3
	.ident	"GCC: (Ubuntu 11.4.0-1ubuntu1~22.04.3) 11.4.0"
	.section	.note.GNU-stack,"",@progbits
	.section	.note.gnu.property,"a"
	.align 8
	.long	1f - 0f
	.long	4f - 1f
	.long	5
0:
	.string	"GNU"
1:
	.align 8
	.long	0xc0000002
	.long	3f - 2f
2:
	.long	0x3
3:
	.align 8
4:
