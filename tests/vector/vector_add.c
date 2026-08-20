/*
 * tests/vector/vector_add.c
 * Minimal RISC-V Vector (RVV) self-test using RVV intrinsics.
 * Requires -march=rv64gcv. Verifies vadd.vv on int32 vectors and
 * reports VLEN via the vlenb CSR.
 */
#include <stdio.h>
#include <stdint.h>
#include <riscv_vector.h>

#define N 32

int main(void)
{
    int32_t a[N], b[N], c[N];
    int i;
    unsigned long vlenb = 0;

    for (i = 0; i < N; i++) {
        a[i] = i;
        b[i] = 1000 + i * 7;
        c[i] = 0;
    }

    /* read VLEN (bytes) from the vlenb CSR */
    __asm__ volatile("csrr %0, vlenb" : "=r"(vlenb));
    printf("VLEN = %lu bits\n", vlenb * 8);

    /* strip-mine the array in RVV m1 registers of int32 */
    size_t vl;
    for (i = 0; i < N; i += (int)vl) {
        vl = __riscv_vsetvl_e32m1((size_t)(N - i));
        vint32m1_t va = __riscv_vle32_v_i32m1(&a[i], vl);
        vint32m1_t vb = __riscv_vle32_v_i32m1(&b[i], vl);
        vint32m1_t vc = __riscv_vadd_vv_i32m1(va, vb, vl);
        __riscv_vse32_v_i32m1(&c[i], vc, vl);
    }

    int ok = 1;
    for (i = 0; i < N; i++) {
        if (c[i] != a[i] + b[i]) {
            ok = 0;
            printf("MISMATCH at %d: got %d, want %d\n", i, c[i], a[i] + b[i]);
        }
    }

    printf("vector_add: %s\n", ok ? "PASS" : "FAIL");
    return ok ? 0 : 1;
}
