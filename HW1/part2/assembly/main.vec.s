	.file	"main.c"
	.text
	.section	.rodata.str1.1,"aMS",@progbits,1
.LC0:
	.string	"fasttime.h"
.LC1:
	.string	"r == 0"
	.text
	.p2align 4
	.type	gettime, @function
gettime:
.LFB28:
	.cfi_startproc
	subq	$40, %rsp
	.cfi_def_cfa_offset 48
	movl	$1, %edi
	movq	%fs:40, %rax
	movq	%rax, 24(%rsp)
	xorl	%eax, %eax
	movq	%rsp, %rsi
	call	clock_gettime@PLT
	testl	%eax, %eax
	jne	.L6
	movq	(%rsp), %rax
	movq	8(%rsp), %rdx
	movq	24(%rsp), %rcx
	subq	%fs:40, %rcx
	jne	.L7
	addq	$40, %rsp
	.cfi_remember_state
	.cfi_def_cfa_offset 8
	ret
.L6:
	.cfi_restore_state
	leaq	__PRETTY_FUNCTION__.0(%rip), %rcx
	movl	$75, %edx
	leaq	.LC0(%rip), %rsi
	leaq	.LC1(%rip), %rdi
	call	__assert_fail@PLT
.L7:
	call	__stack_chk_fail@PLT
	.cfi_endproc
.LFE28:
	.size	gettime, .-gettime
	.section	.rodata.str1.1
.LC2:
	.string	"Usage: %s [options]\n"
.LC3:
	.string	"Program Options:\n"
	.section	.rodata.str1.8,"aMS",@progbits,1
	.align 8
.LC4:
	.string	"  -s  --size <N>     Use workload size N (Default = 1024)\n"
	.align 8
.LC5:
	.string	"  -t  --test <N>     Just run the testN function (Default = 1)\n"
	.align 8
.LC6:
	.string	"  -h  --help         This message\n"
	.text
	.p2align 4
	.globl	usage
	.type	usage, @function
usage:
.LFB32:
	.cfi_startproc
	endbr64
	subq	$8, %rsp
	.cfi_def_cfa_offset 16
	movq	%rdi, %rdx
	leaq	.LC2(%rip), %rsi
	xorl	%eax, %eax
	movl	$1, %edi
	call	__printf_chk@PLT
	leaq	.LC3(%rip), %rsi
	movl	$1, %edi
	xorl	%eax, %eax
	call	__printf_chk@PLT
	leaq	.LC4(%rip), %rsi
	movl	$1, %edi
	xorl	%eax, %eax
	call	__printf_chk@PLT
	leaq	.LC5(%rip), %rsi
	movl	$1, %edi
	xorl	%eax, %eax
	call	__printf_chk@PLT
	movl	$1, %edi
	xorl	%eax, %eax
	addq	$8, %rsp
	.cfi_def_cfa_offset 8
	leaq	.LC6(%rip), %rsi
	jmp	__printf_chk@PLT
	.cfi_endproc
.LFE32:
	.size	usage, .-usage
	.p2align 4
	.globl	initValue
	.type	initValue, @function
initValue:
.LFB33:
	.cfi_startproc
	endbr64
	testl	%r8d, %r8d
	je	.L18
	pushq	%r15
	.cfi_def_cfa_offset 16
	.cfi_offset 15, -16
	xorl	%r15d, %r15d
	pushq	%r14
	.cfi_def_cfa_offset 24
	.cfi_offset 14, -24
	movq	%rcx, %r14
	pushq	%r13
	.cfi_def_cfa_offset 32
	.cfi_offset 13, -32
	movq	%rdx, %r13
	pushq	%r12
	.cfi_def_cfa_offset 40
	.cfi_offset 12, -40
	movq	%rsi, %r12
	pushq	%rbp
	.cfi_def_cfa_offset 48
	.cfi_offset 6, -48
	movq	%rdi, %rbp
	pushq	%rbx
	.cfi_def_cfa_offset 56
	.cfi_offset 3, -56
	movl	%r8d, %ebx
	subq	$8, %rsp
	.cfi_def_cfa_offset 64
	.p2align 4,,10
	.p2align 3
.L12:
	call	rand@PLT
	pxor	%xmm0, %xmm0
	cvtsi2ssl	%eax, %xmm0
	mulss	.LC7(%rip), %xmm0
	mulss	.LC8(%rip), %xmm0
	subss	.LC9(%rip), %xmm0
	movss	%xmm0, 0(%rbp,%r15,4)
	call	rand@PLT
	pxor	%xmm0, %xmm0
	cvtsi2ssl	%eax, %xmm0
	mulss	.LC7(%rip), %xmm0
	mulss	.LC8(%rip), %xmm0
	subss	.LC9(%rip), %xmm0
	movss	%xmm0, (%r12,%r15,4)
	call	rand@PLT
	pxor	%xmm0, %xmm0
	cvtsi2sdl	%eax, %xmm0
	mulsd	.LC10(%rip), %xmm0
	divsd	.LC11(%rip), %xmm0
	subsd	.LC12(%rip), %xmm0
	movsd	%xmm0, 0(%r13,%r15,8)
	movl	$0x00000000, (%r14,%r15,4)
	addq	$1, %r15
	cmpq	%r15, %rbx
	jne	.L12
	addq	$8, %rsp
	.cfi_def_cfa_offset 56
	popq	%rbx
	.cfi_def_cfa_offset 48
	popq	%rbp
	.cfi_def_cfa_offset 40
	popq	%r12
	.cfi_def_cfa_offset 32
	popq	%r13
	.cfi_def_cfa_offset 24
	popq	%r14
	.cfi_def_cfa_offset 16
	popq	%r15
	.cfi_def_cfa_offset 8
	ret
	.p2align 4,,10
	.p2align 3
.L18:
	.cfi_restore 3
	.cfi_restore 6
	.cfi_restore 12
	.cfi_restore 13
	.cfi_restore 14
	.cfi_restore 15
	ret
	.cfi_endproc
.LFE33:
	.size	initValue, .-initValue
	.section	.rodata.str1.8
	.align 8
.LC14:
	.string	"Error: Workload size is set to %d (<0).\n"
	.align 8
.LC15:
	.string	"Error: test%d() is not available.\n"
	.section	.rodata.str1.1
.LC16:
	.string	"st:?"
.LC18:
	.string	"Running test%d()...\n"
	.section	.rodata.str1.8
	.align 8
.LC20:
	.string	"Elapsed execution time of the loop in test%d():\n"
	.section	.rodata.str1.1
.LC21:
	.string	"%lfsec (N: %d, I: %d)\n"
.LC22:
	.string	"sink=%f\n"
	.section	.text.startup,"ax",@progbits
	.p2align 4
	.globl	main
	.type	main, @function
main:
.LFB31:
	.cfi_startproc
	endbr64
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset 6, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register 6
	pushq	%r15
	.cfi_offset 15, -24
	movl	$1024, %r15d
	pushq	%r14
	.cfi_offset 14, -32
	leaq	long_options.1(%rip), %r14
	pushq	%r13
	.cfi_offset 13, -40
	leaq	.LC16(%rip), %r13
	pushq	%r12
	.cfi_offset 12, -48
	movl	%edi, %r12d
	pushq	%rbx
	.cfi_offset 3, -56
	movq	%rsi, %rbx
	subq	$56, %rsp
	movq	%fs:40, %rax
	movq	%rax, -56(%rbp)
	xorl	%eax, %eax
	movl	$1, -68(%rbp)
.L22:
	xorl	%r8d, %r8d
	movq	%r14, %rcx
	movq	%r13, %rdx
	movq	%rbx, %rsi
	movl	%r12d, %edi
	call	getopt_long@PLT
	cmpl	$-1, %eax
	je	.L64
	cmpl	$115, %eax
	je	.L23
	cmpl	$116, %eax
	je	.L24
	movq	(%rbx), %rdi
	call	usage
	movl	$1, %eax
.L27:
	movq	-56(%rbp), %rdx
	subq	%fs:40, %rdx
	jne	.L65
	leaq	-40(%rbp), %rsp
	popq	%rbx
	popq	%r12
	popq	%r13
	popq	%r14
	popq	%r15
	popq	%rbp
	.cfi_remember_state
	.cfi_def_cfa 7, 8
	ret
	.p2align 4,,10
	.p2align 3
.L23:
	.cfi_restore_state
	movq	optarg(%rip), %rdi
	movl	$10, %edx
	xorl	%esi, %esi
	call	strtol@PLT
	movl	%eax, %r15d
	testl	%eax, %eax
	jg	.L22
	movl	%eax, %edx
	leaq	.LC14(%rip), %rsi
	movl	$1, %edi
	xorl	%eax, %eax
	call	__printf_chk@PLT
	orl	$-1, %eax
	jmp	.L27
	.p2align 4,,10
	.p2align 3
.L24:
	movq	optarg(%rip), %rdi
	movl	$10, %edx
	xorl	%esi, %esi
	call	strtol@PLT
	movl	%eax, -68(%rbp)
	subl	$1, %eax
	cmpl	$2, %eax
	jbe	.L22
	movl	-68(%rbp), %edx
	leaq	.LC15(%rip), %rsi
	movl	$1, %edi
	xorl	%eax, %eax
	call	__printf_chk@PLT
	orl	$-1, %eax
	jmp	.L27
.L64:
	movslq	%r15d, %rcx
	movq	%rsp, %rsi
	leaq	15(,%rcx,4), %rax
	movq	%rax, %rdi
	movq	%rax, %rdx
	andq	$-4096, %rdi
	andq	$-16, %rdx
	subq	%rdi, %rsi
.L29:
	cmpq	%rsi, %rsp
	je	.L30
	subq	$4096, %rsp
	orq	$0, 4088(%rsp)
	jmp	.L29
.L30:
	andl	$4095, %edx
	subq	%rdx, %rsp
	testq	%rdx, %rdx
	je	.L31
	orq	$0, -8(%rsp,%rdx)
.L31:
	movq	%rax, %rdi
	movq	%rax, %rdx
	movq	%rsp, %rsi
	movq	%rsp, %r14
	andq	$-4096, %rdi
	andq	$-16, %rdx
	subq	%rdi, %rsi
.L32:
	cmpq	%rsi, %rsp
	je	.L33
	subq	$4096, %rsp
	orq	$0, 4088(%rsp)
	jmp	.L32
.L33:
	andl	$4095, %edx
	subq	%rdx, %rsp
	testq	%rdx, %rdx
	je	.L34
	orq	$0, -8(%rsp,%rdx)
.L34:
	leaq	15(,%rcx,8), %rdx
	movq	%rsp, %rsi
	movq	%rsp, %r9
	movq	%rdx, %rcx
	andq	$-4096, %rdx
	andq	$-16, %rcx
	subq	%rdx, %rsi
.L35:
	cmpq	%rsi, %rsp
	je	.L36
	subq	$4096, %rsp
	orq	$0, 4088(%rsp)
	jmp	.L35
.L36:
	andl	$4095, %ecx
	subq	%rcx, %rsp
	testq	%rcx, %rcx
	je	.L37
	orq	$0, -8(%rsp,%rcx)
.L37:
	movq	%rax, %rdx
	movq	%rsp, %rcx
	andq	$-4096, %rax
	movq	%rsp, %r10
	andq	$-16, %rdx
	subq	%rax, %rcx
.L38:
	cmpq	%rcx, %rsp
	je	.L39
	subq	$4096, %rsp
	orq	$0, 4088(%rsp)
	jmp	.L38
.L39:
	movq	%rdx, %rax
	andl	$4095, %eax
	subq	%rax, %rsp
	testq	%rax, %rax
	je	.L40
	orq	$0, -8(%rsp,%rax)
.L40:
	movq	%rsp, %r13
	movq	%r9, %rsi
	movq	%r10, %rdx
	movl	%r15d, %r8d
	movq	%r13, %rcx
	movq	%r14, %rdi
	movq	%r9, -88(%rbp)
	movq	%r10, -80(%rbp)
	call	initValue
	movl	-68(%rbp), %edx
	movl	$1, %edi
	xorl	%eax, %eax
	leaq	.LC18(%rip), %rsi
	movq	$0x000000000, -64(%rbp)
	call	__printf_chk@PLT
	call	gettime
	movq	-88(%rbp), %r9
	movq	%rax, %rbx
	movl	-68(%rbp), %eax
	movq	%rdx, %r12
	cmpl	$2, %eax
	je	.L41
	cmpl	$3, %eax
	movq	-80(%rbp), %r10
	je	.L42
	subl	$1, %eax
	je	.L66
.L43:
	call	gettime
	pxor	%xmm0, %xmm0
	pxor	%xmm1, %xmm1
	leaq	.LC20(%rip), %rsi
	subq	%r12, %rdx
	subq	%rbx, %rax
	movl	$1, %edi
	cvtsi2sdq	%rdx, %xmm0
	mulsd	.LC19(%rip), %xmm0
	movl	-68(%rbp), %edx
	cvtsi2sdq	%rax, %xmm1
	xorl	%eax, %eax
	addsd	%xmm1, %xmm0
	movsd	%xmm0, -80(%rbp)
	call	__printf_chk@PLT
	movsd	-80(%rbp), %xmm0
	movl	%r15d, %edx
	movl	$20000000, %ecx
	leaq	.LC21(%rip), %rsi
	movl	$1, %edi
	movl	$1, %eax
	call	__printf_chk@PLT
	movsd	-64(%rbp), %xmm0
	movl	$1, %edi
	leaq	.LC22(%rip), %rsi
	movl	$1, %eax
	call	__printf_chk@PLT
	xorl	%eax, %eax
	jmp	.L27
.L41:
	movl	%r15d, %ecx
	movq	%r13, %rdx
	movq	%r9, %rsi
	movq	%r14, %rdi
	call	test2@PLT
	xorl	%eax, %eax
.L45:
	movsd	-64(%rbp), %xmm1
	pxor	%xmm0, %xmm0
	cvtss2sd	0(%r13,%rax,4), %xmm0
	addq	$64, %rax
	addsd	%xmm1, %xmm0
	movsd	%xmm0, -64(%rbp)
	cmpl	%eax, %r15d
	jg	.L45
	jmp	.L43
.L66:
	movl	%r15d, %ecx
	movq	%r13, %rdx
	movq	%r9, %rsi
	movq	%r14, %rdi
	call	test1@PLT
	xorl	%eax, %eax
.L44:
	movsd	-64(%rbp), %xmm1
	pxor	%xmm0, %xmm0
	cvtss2sd	0(%r13,%rax,4), %xmm0
	addq	$64, %rax
	addsd	%xmm1, %xmm0
	movsd	%xmm0, -64(%rbp)
	cmpl	%eax, %r15d
	jg	.L44
	jmp	.L43
.L42:
	movl	%r15d, %esi
	movq	%r10, %rdi
	call	test3@PLT
	movapd	%xmm0, %xmm1
	movsd	-64(%rbp), %xmm0
	addsd	%xmm1, %xmm0
	movsd	%xmm0, -64(%rbp)
	jmp	.L43
.L65:
	call	__stack_chk_fail@PLT
	.cfi_endproc
.LFE31:
	.size	main, .-main
	.section	.rodata
	.align 8
	.type	__PRETTY_FUNCTION__.0, @object
	.size	__PRETTY_FUNCTION__.0, 8
__PRETTY_FUNCTION__.0:
	.string	"gettime"
	.section	.rodata.str1.1
.LC23:
	.string	"size"
.LC24:
	.string	"test"
.LC25:
	.string	"help"
	.section	.data.rel.local,"aw"
	.align 32
	.type	long_options.1, @object
	.size	long_options.1, 128
long_options.1:
	.quad	.LC23
	.long	1
	.zero	4
	.quad	0
	.long	115
	.zero	4
	.quad	.LC24
	.long	1
	.zero	4
	.quad	0
	.long	116
	.zero	4
	.quad	.LC25
	.long	0
	.zero	4
	.quad	0
	.long	63
	.zero	4
	.quad	0
	.long	0
	.zero	4
	.quad	0
	.long	0
	.zero	4
	.section	.rodata.cst4,"aM",@progbits,4
	.align 4
.LC7:
	.long	1082130432
	.align 4
.LC8:
	.long	805306368
	.align 4
.LC9:
	.long	1065353216
	.section	.rodata.cst8,"aM",@progbits,8
	.align 8
.LC10:
	.long	0
	.long	1074790400
	.align 8
.LC11:
	.long	-4194304
	.long	1105199103
	.align 8
.LC12:
	.long	0
	.long	1072693248
	.align 8
.LC19:
	.long	-400107883
	.long	1041313291
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
