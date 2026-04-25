	.file	"test1.c"
	.text
	.p2align 4
	.globl	test1
	.type	test1, @function
test1:
.LFB0:
	.cfi_startproc
	endbr64
	movq	%rsi, %rcx
	xorl	%eax, %eax
.L2:
	movss	(%rdi,%rax), %xmm0
	addss	(%rcx,%rax), %xmm0
	addq	$4, %rax
	addq	$4, %rdx
	movss	%xmm0, -4(%rdx)
	cmpq	$4096, %rax
	jne	.L2
	ret
	.cfi_endproc
.LFE0:
	.size	test1, .-test1
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
