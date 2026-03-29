/*
 * Benchmark: String operations
 * Measures: String allocation, concatenation, RTL function overhead
 * Baseline for: EncodingStrings, ScalarClasses method dispatch
 */

#define ITERATIONS  1000000

PROCEDURE Main()

   LOCAL nStart, nEl, i, c

   /* Concatenation */
   nStart := hb_MilliSeconds()
   FOR i := 1 TO ITERATIONS
      c := "hello" + " " + "world"
   NEXT
   nEl := hb_MilliSeconds() - nStart

   ? "string_concat", nEl, "ms", hb_ntos( ITERATIONS ) + " iterations"

   /* Upper (function call) */
   nStart := hb_MilliSeconds()
   FOR i := 1 TO ITERATIONS
      c := Upper( "hello world" )
   NEXT
   nEl := hb_MilliSeconds() - nStart

   ? "string_upper_func", nEl, "ms", hb_ntos( ITERATIONS ) + " iterations"

   /* Upper (method dispatch) */
   nStart := hb_MilliSeconds()
   FOR i := 1 TO ITERATIONS
      c := "hello world":Upper()
   NEXT
   nEl := hb_MilliSeconds() - nStart

   ? "string_upper_method", nEl, "ms", hb_ntos( ITERATIONS ) + " iterations"

   /* SubStr */
   nStart := hb_MilliSeconds()
   FOR i := 1 TO ITERATIONS
      c := SubStr( "hello world", 3, 5 )
   NEXT
   nEl := hb_MilliSeconds() - nStart

   ? "string_substr", nEl, "ms", hb_ntos( ITERATIONS ) + " iterations"

   RETURN
