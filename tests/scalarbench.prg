/*
 * Drydock Scalar Classes benchmark
 * Verifies zero performance regression on hot paths.
 */

#define ITERATIONS  1000000

PROCEDURE Main()

   LOCAL nStart, nElapsed, i, n, c

   ? "Drydock Scalar Benchmark (" + hb_ntos( ITERATIONS ) + " iterations)"
   ?

   /* Integer arithmetic (hot path — must not regress) */
   n := 0
   nStart := hb_MilliSeconds()
   FOR i := 1 TO ITERATIONS
      n := n + 1
   NEXT
   nElapsed := hb_MilliSeconds() - nStart
   ? "Int arithmetic (n+1):   " + hb_ntos( nElapsed ) + " ms"

   /* String concatenation */
   c := ""
   nStart := hb_MilliSeconds()
   FOR i := 1 TO ITERATIONS / 10
      c := "hello" + "world"
   NEXT
   nElapsed := hb_MilliSeconds() - nStart
   ? "String concat (C+C):    " + hb_ntos( nElapsed ) + " ms  (" + hb_ntos( ITERATIONS / 10 ) + " iter)"

   /* Scalar method dispatch — Upper() */
   nStart := hb_MilliSeconds()
   FOR i := 1 TO ITERATIONS
      c := "hello":Upper()
   NEXT
   nElapsed := hb_MilliSeconds() - nStart
   ? "Method dispatch (Upper): " + hb_ntos( nElapsed ) + " ms"

   /* Scalar method dispatch — Len() */
   nStart := hb_MilliSeconds()
   FOR i := 1 TO ITERATIONS
      n := "hello":Len()
   NEXT
   nElapsed := hb_MilliSeconds() - nStart
   ? "Method dispatch (Len):   " + hb_ntos( nElapsed ) + " ms"

   /* Scalar method dispatch — toString() */
   nStart := hb_MilliSeconds()
   FOR i := 1 TO ITERATIONS
      c := (42):toString()
   NEXT
   nElapsed := hb_MilliSeconds() - nStart
   ? "Method dispatch (toStr): " + hb_ntos( nElapsed ) + " ms"

   /* New operator — array concat */
   nStart := hb_MilliSeconds()
   FOR i := 1 TO ITERATIONS / 100
      c := {1,2} + {3,4}
   NEXT
   nElapsed := hb_MilliSeconds() - nStart
   ? "Array concat ({+}):     " + hb_ntos( nElapsed ) + " ms  (" + hb_ntos( ITERATIONS / 100 ) + " iter)"

   /* New operator — string repeat */
   nStart := hb_MilliSeconds()
   FOR i := 1 TO ITERATIONS / 10
      c := "abc" * 3
   NEXT
   nElapsed := hb_MilliSeconds() - nStart
   ? "String repeat (C*N):    " + hb_ntos( nElapsed ) + " ms  (" + hb_ntos( ITERATIONS / 10 ) + " iter)"

   ?
   ? "Done."

   RETURN
