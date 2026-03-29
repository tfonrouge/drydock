/*
 * Benchmark: OO method dispatch
 * Measures: Method lookup, hash-based dispatch, virtual calls
 * Baseline for: InlineCaching (Phase L), LLVMBackend (Phase M)
 */

#include "hbclass.ch"

#define ITERATIONS  1000000

PROCEDURE Main()

   LOCAL nStart, nEl, i, o, n

   o := Counter():New()

   /* Simple method call */
   nStart := hb_MilliSeconds()
   FOR i := 1 TO ITERATIONS
      o:Inc()
   NEXT
   nEl := hb_MilliSeconds() - nStart

   ? "oo_method_call", nEl, "ms", hb_ntos( ITERATIONS ) + " calls"

   /* Data read */
   nStart := hb_MilliSeconds()
   FOR i := 1 TO ITERATIONS
      n := o:nCount
   NEXT
   nEl := hb_MilliSeconds() - nStart

   ? "oo_data_read", nEl, "ms", hb_ntos( ITERATIONS ) + " reads"

   /* Data write */
   nStart := hb_MilliSeconds()
   FOR i := 1 TO ITERATIONS
      o:nCount := i
   NEXT
   nEl := hb_MilliSeconds() - nStart

   ? "oo_data_write", nEl, "ms", hb_ntos( ITERATIONS ) + " writes"

   /* toString (DrydockObject universal method) */
   nStart := hb_MilliSeconds()
   FOR i := 1 TO ITERATIONS
      n := o:toString()
   NEXT
   nEl := hb_MilliSeconds() - nStart

   ? "oo_tostring", nEl, "ms", hb_ntos( ITERATIONS ) + " calls"

   /* Polymorphic dispatch — call same method name on different types */
   nStart := hb_MilliSeconds()
   FOR i := 1 TO ITERATIONS
      n := "hello":className()
      n := (42):className()
      n := .T.:className()
   NEXT
   nEl := hb_MilliSeconds() - nStart

   ? "oo_polymorphic", nEl, "ms", hb_ntos( ITERATIONS ) + " x 3 types"

   RETURN

CREATE CLASS Counter

   DATA nCount INIT 0

   METHOD New() INLINE ( ::nCount := 0, Self )
   METHOD Inc() INLINE ++::nCount
   METHOD toString() INLINE "Counter(" + hb_ntos( ::nCount ) + ")"

ENDCLASS
