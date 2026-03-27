/*
 * Drydock Scalar Classes test
 * Tests user-facing methods added to scalar types.
 */

#include "hbclass.ch"

ENABLE TYPE CLASS ALL

STATIC s_nPass := 0, s_nFail := 0

PROCEDURE MAIN()

   /* Character methods */
   TEST( "Upper",     "hello":Upper(),        "HELLO" )
   TEST( "Lower",     "HELLO":Lower(),        "hello" )
   TEST( "Trim",      "  hi  ":Trim(),        "hi" )
   TEST( "LTrim",     "  hi":LTrim(),         "hi" )
   TEST( "RTrim",     "hi  ":RTrim(),         "hi" )
   TEST( "Left",      "hello":Left( 3 ),      "hel" )
   TEST( "Right",     "hello":Right( 3 ),     "llo" )
   TEST( "SubStr",    "hello":SubStr( 2, 3 ), "ell" )
   TEST( "Len",       "hello":Len(),          5 )
   TEST( "Empty F",   "hello":Empty(),        .F. )
   TEST( "Empty T",   "":Empty(),             .T. )
   TEST( "At",        "hello":At( "ll" ),     3 )
   TEST( "Replicate", "ha":Replicate( 3 ),    "hahaha" )
   TEST( "Reverse",   "abc":Reverse(),        "cba" )
   TEST( "AsString",  "hello":AsString(),     "hello" )
   TEST( "IsScalar",  "hello":IsScalar(),     .T. )
   TEST( "ClassName", "hello":ClassName(),    "CHARACTER" )

   /* Numeric methods */
   TEST( "Abs",       ( -5 ):Abs(),            5 )
   TEST( "Int",       ( 3.7 ):Int(),           3 )
   TEST( "Round",     ( 3.14159 ):Round( 2 ),  3.14 )
   TEST( "Str",       ( 42 ):Str(),            "42" )
   TEST( "Min",       ( 5 ):Min( 3 ),          3 )
   TEST( "Max",       ( 5 ):Max( 10 ),         10 )
   TEST( "Empty F",   ( 1 ):Empty(),           .F. )
   TEST( "Empty T",   ( 0 ):Empty(),           .T. )
   TEST( "Between T", ( 5 ):Between( 1, 10 ),  .T. )
   TEST( "Between F", ( 15 ):Between( 1, 10 ), .F. )
   TEST( "N AsStr",   ( 42 ):AsString(),       "42" )
   TEST( "N Class",   ( 42 ):ClassName(),      "NUMERIC" )

   /* Logical methods */
   TEST( "IsTrue T",  .T.:IsTrue(),           .T. )
   TEST( "IsTrue F",  .F.:IsTrue(),           .F. )
   TEST( "Toggle T",  .T.:Toggle(),           .F. )
   TEST( "Toggle F",  .F.:Toggle(),           .T. )
   TEST( "L AsStr",   .T.:AsString(),         ".T." )
   TEST( "L Class",   .T.:ClassName(),        "LOGICAL" )

   /* Date methods */
   TEST( "D Year",    Date():Year(),          Year( Date() ) )
   TEST( "D Month",   Date():Month(),         Month( Date() ) )
   TEST( "D Day",     Date():Day(),           Day( Date() ) )
   TEST( "D DOW",     Date():DOW(),           DOW( Date() ) )
   TEST( "D Empty",   Date():Empty(),         .F. )
   TEST( "D Class",   Date():ClassName(),     "DATE" )

   /* Array methods */
   TEST( "A Len",     { 1, 2, 3 }:Len(),            3 )
   TEST( "A Empty F", { 1 }:Empty(),                 .F. )
   TEST( "A Empty T", {}:Empty(),                     .T. )
   TEST( "A Tail",    { 1, 2, 3 }:Tail(),            3 )
   TEST( "A Map",     { 1, 2, 3 }:Map( {| x | x * 2 } ), { 2, 4, 6 } )
   TEST( "A Filter",  { 1, 2, 3, 4, 5 }:Filter( {| x | x > 3 } ), { 4, 5 } )
   TEST( "A Class",   {}:ClassName(),                 "ARRAY" )

   /* Hash methods */
   TEST( "H Len",     { "a" => 1, "b" => 2 }:Len(),        2 )
   TEST( "H Empty",   { => }:Empty(),                        .T. )
   TEST( "H HasKey",  { "a" => 1 }:HasKey( "a" ),           .T. )
   TEST( "H Keys",    { "a" => 1, "b" => 2 }:Keys(),       { "a", "b" } )
   TEST( "H Values",  { "a" => 1, "b" => 2 }:Values(),     { 1, 2 } )
   TEST( "H Class",   { => }:ClassName(),                    "HASH" )

   /* Split test */
   TEST( "Split",     "a,b,c":Split( "," ),  { "a", "b", "c" } )

   ?
   ? "Passed:", s_nPass, "  Failed:", s_nFail, "  Total:", s_nPass + s_nFail

   RETURN

STATIC FUNCTION TEST( cName, xResult, xExpected )

   LOCAL lPass, i

   IF ValType( xResult ) == "A" .AND. ValType( xExpected ) == "A"
      lPass := ( Len( xResult ) == Len( xExpected ) )
      IF lPass
         FOR i := 1 TO Len( xResult )
            IF !( xResult[ i ] == xExpected[ i ] )
               lPass := .F.
               EXIT
            ENDIF
         NEXT
      ENDIF
   ELSE
      lPass := ( xResult == xExpected )
   ENDIF

   IF lPass
      s_nPass++
      ?? "."
   ELSE
      s_nFail++
      ?
      ? "FAIL:", cName, "got:", xResult, "expected:", xExpected
   ENDIF

   RETURN lPass
