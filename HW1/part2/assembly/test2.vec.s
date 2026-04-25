	.file	"test2.c"
	.text
	.p2align 4
	.globl	test2
	.type	test2, @function
test2:
.LFB0:
	.cfi_startproc
	endbr64
	movq	%rsi, %rcx
	movl	$20000000, %esi
.L3:
	xorl	%eax, %eax
	.p2align 4,,10
	.p2align 3
.L2:
	movaps	(%rcx,%rax), %xmm0
	maxps	(%rdi,%rax), %xmm0
	movaps	%xmm0, (%rdx,%rax)
	addq	$16, %rax
	cmpq	$4096, %rax
	jne	.L2
	subl	$1, %esi
	jne	.L3
	ret
	.cfi_endproc
.LFE0:
	.size	test2, .-test2
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
