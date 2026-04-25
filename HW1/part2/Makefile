TARGET := test_auto_vectorize

OBJS := main.o test1.o test2.o test3.o

CC ?= gcc

CFLAGS := -O3 -std=c11 -Wall -D_POSIX_C_SOURCE=200809L

ifeq ($(ASSEMBLE),1)
	CFLAGS += -S
endif
ifeq ($(VECTORIZE),1)
	CFLAGS += -ftree-vectorize -fopt-info-vec-optimized -fopt-info-vec-missed
	SUFFIX := .vec
else
	CFLAGS += -fno-tree-vectorize
	SUFFIX := .novec
endif
ifeq ($(RESTRICT),1)
	SUFFIX := $(SUFFIX).restr
endif
ifeq ($(ALIGN),1)
	SUFFIX := $(SUFFIX).align
endif
ifeq ($(AVX2),1)
	CFLAGS += -mavx2
	SUFFIX := $(SUFFIX).avx2
endif
ifeq ($(FASTMATH),1)
	CFLAGS += -ffast-math
  	SUFFIX := $(SUFFIX).fmath
endif

all: $(TARGET)

%.o: %.c test.h
ifeq ($(ASSEMBLE),1)
	mkdir -p "./assembly"
	$(CC) $(CFLAGS) -c $< -o assembly/$(basename $<)$(SUFFIX).s
else
	$(CC) $(CFLAGS) -c $<
endif

$(TARGET): $(OBJS)
ifneq ($(ASSEMBLE),1)
	$(CC) $(CFLAGS) $(OBJS) -o $@
endif

clean:
	$(RM) *.o *.s $(TARGET) *~

cleanall:
	$(RM) -r *.o *.s $(TARGET) *~ assembly
