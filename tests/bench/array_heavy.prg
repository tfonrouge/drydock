/*
 * Benchmark: Array operations
 * Measures: Array allocation, element access, iteration, GC pressure
 * Baseline for: GenerationalGC (Phase D), InlineCaching (Phase L)
 */

#define ITERATIONS  100000
#define ARRAY_SIZE  100

PROCEDURE Main()

   LOCAL nStart, nEl, i, j, a, n

   /* Array creation + fill */
   nStart := hb_MilliSeconds()
   FOR i := 1 TO ITERATIONS
      a := Array( ARRAY_SIZE )
      FOR j := 1 TO ARRAY_SIZE
         a[ j ] := j
      NEXT
   NEXT
   nEl := hb_MilliSeconds() - nStart

   ? "array_create_fill", nEl, "ms", ;
     hb_ntos( ITERATIONS ) + " arrays of " + hb_ntos( ARRAY_SIZE )

   /* Array element read */
   a := Array( ARRAY_SIZE )
   FOR j := 1 TO ARRAY_SIZE
      a[ j ] := j
   NEXT
   nStart := hb_MilliSeconds()
   n := 0
   FOR i := 1 TO ITERATIONS * 10
      n += a[ ( i % ARRAY_SIZE ) + 1 ]
   NEXT
   nEl := hb_MilliSeconds() - nStart

   ? "array_read", nEl, "ms", hb_ntos( ITERATIONS * 10 ) + " reads"

   /* Array :Map() method */
   a := Array( ARRAY_SIZE )
   FOR j := 1 TO ARRAY_SIZE
      a[ j ] := j
   NEXT
   nStart := hb_MilliSeconds()
   FOR i := 1 TO ITERATIONS / 10
      a := a:Map( {| x | x * 2 } )
   NEXT
   nEl := hb_MilliSeconds() - nStart

   ? "array_map", nEl, "ms", ;
     hb_ntos( ITERATIONS / 10 ) + " maps of " + hb_ntos( ARRAY_SIZE )

   RETURN
