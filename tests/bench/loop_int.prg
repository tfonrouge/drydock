/*
 * Benchmark: Integer arithmetic loop
 * Measures: VM dispatch overhead, integer fast path
 * Baseline for: ComputedGoto (Phase C), RegisterPcode (Phase K)
 */

#define ITERATIONS  10000000

PROCEDURE Main()

   LOCAL nStart, i, n

   n := 0
   nStart := hb_MilliSeconds()
   FOR i := 1 TO ITERATIONS
      n := n + i
   NEXT

   ? "loop_int", hb_MilliSeconds() - nStart, "ms", ;
     hb_ntos( ITERATIONS ) + " iterations"

   RETURN
