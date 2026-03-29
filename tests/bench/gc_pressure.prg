/*
 * Benchmark: GC pressure
 * Measures: Allocation throughput, GC pause impact, memory churn
 * Baseline for: GenerationalGC (Phase D), DrydockAPI (Phase A1)
 */

#define ITERATIONS  500000

PROCEDURE Main()

   LOCAL nStart, nEl, i, a, aLongLived

   /* Rapid short-lived allocations (string) */
   nStart := hb_MilliSeconds()
   FOR i := 1 TO ITERATIONS
      a := "item_" + hb_ntos( i )
   NEXT
   nEl := hb_MilliSeconds() - nStart

   ? "gc_string_alloc", nEl, "ms", hb_ntos( ITERATIONS ) + " strings"

   /* Rapid short-lived allocations (array) */
   nStart := hb_MilliSeconds()
   FOR i := 1 TO ITERATIONS
      a := { i, i + 1, i + 2 }
   NEXT
   nEl := hb_MilliSeconds() - nStart

   ? "gc_array_alloc", nEl, "ms", hb_ntos( ITERATIONS ) + " arrays"

   /* Rapid short-lived allocations (hash) */
   nStart := hb_MilliSeconds()
   FOR i := 1 TO ITERATIONS / 5
      a := { "key" => i }
   NEXT
   nEl := hb_MilliSeconds() - nStart

   ? "gc_hash_alloc", nEl, "ms", hb_ntos( ITERATIONS / 5 ) + " hashes"

   /* Long-lived + short-lived mix (generational hypothesis test) */
   aLongLived := Array( 1000 )
   FOR i := 1 TO 1000
      aLongLived[ i ] := "permanent_" + hb_ntos( i )
   NEXT

   nStart := hb_MilliSeconds()
   FOR i := 1 TO ITERATIONS
      a := { i, "temp", aLongLived[ ( i % 1000 ) + 1 ] }
   NEXT
   nEl := hb_MilliSeconds() - nStart

   ? "gc_mixed_gen", nEl, "ms", ;
     hb_ntos( ITERATIONS ) + " temp + 1000 permanent"

   RETURN
