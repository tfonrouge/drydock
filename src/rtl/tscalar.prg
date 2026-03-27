/*
 * Harbour implementation of Class(y) Scalar classes
 *
 * Copyright 2004 Antonio Linares <alinares@fivetechsoft.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; see the file LICENSE.txt.  If not, write to
 * the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301 USA (or visit https://www.gnu.org/licenses/).
 *
 * As a special exception, the Harbour Project gives permission for
 * additional uses of the text contained in its release of Harbour.
 *
 * The exception is that, if you link the Harbour libraries with other
 * files to produce an executable, this does not by itself cause the
 * resulting executable to be covered by the GNU General Public License.
 * Your use of that executable is in no way restricted on account of
 * linking the Harbour library code into it.
 *
 * This exception does not however invalidate any other reasons why
 * the executable file might be covered by the GNU General Public License.
 *
 * This exception applies only to the code released by the Harbour
 * Project under the name Harbour.  If you copy code from other
 * Harbour Project or Free Software Foundation releases into a copy of
 * Harbour, as the General Public License permits, the exception does
 * not apply to the code that you add in this way.  To avoid misleading
 * anyone as to the status of such modified files, you must delete
 * this exception notice from them.
 *
 * If you write modifications of your own for Harbour, it is your choice
 * whether to permit this exception to apply to your modifications.
 * If you do not wish that, delete this exception notice.
 *
 */

/* Class(y) documentation is located at:
   https://harbour.github.io/ng/classy/menu.html */

#include "hbclass.ch"

/* --- */

CREATE CLASS ScalarObject FUNCTION HBScalar

   METHOD Copy()
   METHOD IsScalar()
   METHOD AsString()
   METHOD AsExpStr()

   MESSAGE Become    METHOD BecomeErr()  /* a scalar cannot "become" another object */
   MESSAGE DeepCopy  METHOD Copy()

ENDCLASS

METHOD Copy() CLASS ScalarObject
   RETURN Self

METHOD IsScalar() CLASS ScalarObject
   RETURN .T.

METHOD AsString() CLASS ScalarObject

   SWITCH ValType( Self )
   CASE "B" ; RETURN "{ || ... }"
   CASE "M"
   CASE "C" ; RETURN Self
   CASE "D" ; RETURN DToC( Self )
   CASE "T" ; RETURN hb_TToC( Self )
   CASE "H" ; RETURN "{ ... => ... }"
   CASE "L" ; RETURN iif( Self, ".T.", ".F." )
   CASE "N" ; RETURN hb_ntos( Self )
   CASE "S" ; RETURN "@" + ::name + "()"
   CASE "P" ; RETURN "<0x...>"
   CASE "U" ; RETURN "NIL"
   ENDSWITCH

   RETURN "Error!"

METHOD AsExpStr() CLASS ScalarObject

   SWITCH ValType( Self )
   CASE "M"
   CASE "C" ; RETURN '"' + Self + '"'
   CASE "D" ; RETURN 'CToD("' + DToC( Self ) + '")'
   CASE "T" ; RETURN 'hb_CToT("' + hb_TToC( Self ) + '")'
   ENDSWITCH

   RETURN ::AsString()

METHOD PROCEDURE BecomeErr() CLASS ScalarObject

#if 0
   // Not implemented yet
   ::error( CSYERR_BECOME, "Message 'become' illegally sent to scalar", ::ClassName() )
#endif

   RETURN

/* --- */

CREATE CLASS Array INHERIT HBScalar FUNCTION __HBArray

   METHOD Init( nElements )

   METHOD AsString()
   METHOD At( n )
   METHOD AtPut( n, x )
   METHOD Add( x )
   METHOD AddAll( aOtherCollection )
   METHOD Collect( b )
   METHOD Copy()
   METHOD Do( b )
   METHOD DeleteAt( n )
   METHOD InsertAt( n, x )
   METHOD IndexOf( x )
   METHOD IsScalar()
   METHOD Remove( e )
   METHOD Scan( b )
   METHOD _Size( newSize )  // assignment method

   MESSAGE Append  METHOD Add

   /* Drydock: user-facing scalar methods */
   METHOD Len()
   METHOD Empty()
   METHOD Sort( bCompare )
   METHOD Tail()
   METHOD Each( bBlock )
   METHOD Map( bBlock )
   METHOD Filter( bBlock )

ENDCLASS

METHOD Init( nElements ) CLASS Array

   ::size := iif( nElements == NIL, 0, nElements )

   RETURN Self

METHOD AddAll( aOtherCollection ) CLASS Array

   aOtherCollection:Do( {| e | ::Add( e ) } )

   RETURN Self

METHOD AsString() CLASS Array
   RETURN "{ ... }"

METHOD At( n ) CLASS Array
   RETURN Self[ n ]

METHOD AtPut( n, x ) CLASS Array
   RETURN Self[ n ] := x

METHOD Add( x ) CLASS Array

   AAdd( Self, x )

   RETURN .T.

METHOD Collect( b ) CLASS Array

   LOCAL elem
   LOCAL result := {}

   FOR EACH elem IN Self
      IF Eval( b, elem )
         AAdd( result, elem )
      ENDIF
   NEXT

   RETURN result

METHOD Copy() CLASS Array
   RETURN ACopy( Self, Array( Len( Self ) ) )

METHOD DeleteAt( n ) CLASS Array

   IF n >= 1 .AND. n <= Len( Self )
      hb_ADel( Self, n, .T. )
   ENDIF

   RETURN Self

METHOD InsertAt( n, x ) CLASS Array

   DO CASE
   CASE n > Len( Self )
      ASize( Self, n )
      Self[ n ] := x
   CASE n >= 1
      hb_AIns( Self, n, x, .T. )
   ENDCASE

   RETURN Self

METHOD IsScalar() CLASS Array
   RETURN .T.

METHOD Do( b ) CLASS Array

   LOCAL i

   FOR i := 1 TO Len( Self )
      b:Eval( Self[ i ], i )
   NEXT

   RETURN Self

METHOD IndexOf( x ) CLASS Array

   LOCAL elem

   FOR EACH elem IN Self
      IF elem == x
         RETURN elem:__enumIndex()
      ENDIF
   NEXT

   RETURN 0

METHOD PROCEDURE Remove( e ) CLASS Array

   ::DeleteAt( ::IndexOf( e ) )

   RETURN

METHOD Scan( b ) CLASS Array
   RETURN AScan( Self, b )

METHOD _Size( newSize ) CLASS Array

   ASize( Self, newSize )

   RETURN newSize  // so that assignment works according to standard rules

METHOD Len() CLASS Array
   RETURN Len( Self )

METHOD Empty() CLASS Array
   RETURN Empty( Self )

METHOD Sort( bCompare ) CLASS Array
   RETURN ASort( Self,,, bCompare )

METHOD Tail() CLASS Array
   RETURN ATail( Self )

METHOD Each( bBlock ) CLASS Array

   LOCAL elem

   FOR EACH elem IN Self
      Eval( bBlock, elem, elem:__enumIndex() )
   NEXT

   RETURN Self

METHOD Map( bBlock ) CLASS Array

   LOCAL elem
   LOCAL aResult := {}

   FOR EACH elem IN Self
      AAdd( aResult, Eval( bBlock, elem ) )
   NEXT

   RETURN aResult

METHOD Filter( bBlock ) CLASS Array

   LOCAL elem
   LOCAL aResult := {}

   FOR EACH elem IN Self
      IF Eval( bBlock, elem )
         AAdd( aResult, elem )
      ENDIF
   NEXT

   RETURN aResult

/* --- */

CREATE CLASS Block INHERIT HBScalar FUNCTION __HBBlock

   METHOD AsString()

ENDCLASS

METHOD AsString() CLASS Block
   RETURN "{ || ... }"

/* --- */

CREATE CLASS Character INHERIT HBScalar FUNCTION __HBCharacter

   METHOD AsString()
   METHOD AsExpStr()

   /* Drydock: user-facing scalar methods */
   METHOD Upper()
   METHOD Lower()
   METHOD Trim()
   METHOD LTrim()
   METHOD RTrim()
   METHOD Left( n )
   METHOD Right( n )
   METHOD SubStr( nStart, nLen )
   METHOD At( cSearch )
   METHOD Len()
   METHOD Empty()
   METHOD Replicate( nTimes )
   METHOD Split( cDelim )
   METHOD Reverse()

ENDCLASS

METHOD AsString() CLASS Character
   RETURN Self

METHOD AsExpStr() CLASS Character
   RETURN '"' + Self + '"'

METHOD Upper() CLASS Character
   RETURN Upper( Self )

METHOD Lower() CLASS Character
   RETURN Lower( Self )

METHOD Trim() CLASS Character
   RETURN AllTrim( Self )

METHOD LTrim() CLASS Character
   RETURN LTrim( Self )

METHOD RTrim() CLASS Character
   RETURN RTrim( Self )

METHOD Left( n ) CLASS Character
   RETURN Left( Self, n )

METHOD Right( n ) CLASS Character
   RETURN Right( Self, n )

METHOD SubStr( nStart, nLen ) CLASS Character
   IF nLen == NIL
      RETURN SubStr( Self, nStart )
   ENDIF
   RETURN SubStr( Self, nStart, nLen )

METHOD At( cSearch ) CLASS Character
   RETURN At( cSearch, Self )

METHOD Len() CLASS Character
   RETURN Len( Self )

METHOD Empty() CLASS Character
   RETURN Empty( Self )

METHOD Replicate( nTimes ) CLASS Character
   RETURN Replicate( Self, nTimes )

METHOD Split( cDelim ) CLASS Character
   RETURN hb_ATokens( Self, hb_defaultValue( cDelim, " " ) )

METHOD Reverse() CLASS Character

   LOCAL cResult := "", i

   FOR i := Len( Self ) TO 1 STEP -1
      cResult += SubStr( Self, i, 1 )
   NEXT

   RETURN cResult

/* --- */

CREATE CLASS Date INHERIT HBScalar FUNCTION __HBDate

   METHOD Year()
   METHOD Month()
   METHOD Day()
   METHOD AsString()
   METHOD AsExpStr()

   /* Drydock: user-facing scalar methods */
   METHOD AddDays( nDays )
   METHOD DiffDays( dOther )
   METHOD DOW()
   METHOD Empty()

ENDCLASS

METHOD AsString() CLASS Date
   RETURN DToC( Self )

METHOD AsExpStr() CLASS Date
   RETURN 'CToD("' + ::AsString() + '")'

METHOD Year() CLASS Date
   RETURN Year( Self )

METHOD Month() CLASS Date
   RETURN Month( Self )

METHOD Day() CLASS Date
   RETURN Day( Self )

METHOD AddDays( nDays ) CLASS Date
   RETURN Self + nDays

METHOD DiffDays( dOther ) CLASS Date
   RETURN Self - dOther

METHOD DOW() CLASS Date
   RETURN DOW( Self )

METHOD Empty() CLASS Date
   RETURN Empty( Self )

/* --- */

CREATE CLASS TimeStamp INHERIT HBScalar FUNCTION __HBTimeStamp

   METHOD Date()
   METHOD Time()
   METHOD Year()
   METHOD Month()
   METHOD Day()
   METHOD Hour()
   METHOD Minute()
   METHOD Sec()

   METHOD AsString()
   METHOD AsExpStr()

ENDCLASS

METHOD AsString() CLASS TimeStamp
   RETURN hb_TToS( Self )

METHOD AsExpStr() CLASS TimeStamp
   RETURN 'hb_SToT("' + ::AsString() + '")'

METHOD Date() CLASS TimeStamp
   RETURN hb_TToC( Self,, "" )

METHOD Time() CLASS TimeStamp
   RETURN hb_TToC( Self, "", "hh:mm:ss" )

METHOD Year() CLASS TimeStamp
   RETURN Year( Self )

METHOD Month() CLASS TimeStamp
   RETURN Month( Self )

METHOD Day() CLASS TimeStamp
   RETURN Day( Self )

METHOD Hour() CLASS TimeStamp
   RETURN hb_Hour( Self )

METHOD Minute() CLASS TimeStamp
   RETURN hb_Minute( Self )

METHOD Sec() CLASS TimeStamp
   RETURN hb_Sec( Self )

/* --- */

CREATE CLASS Hash INHERIT HBScalar FUNCTION __HBHash

   METHOD AsString()

   /* Drydock: user-facing scalar methods */
   METHOD Keys()
   METHOD Values()
   METHOD Len()
   METHOD Empty()
   METHOD HasKey( xKey )
   METHOD Del( xKey )

ENDCLASS

METHOD AsString() CLASS Hash
   RETURN "{ ... => ... }"

METHOD Keys() CLASS Hash
   RETURN hb_HKeys( Self )

METHOD Values() CLASS Hash
   RETURN hb_HValues( Self )

METHOD Len() CLASS Hash
   RETURN Len( Self )

METHOD Empty() CLASS Hash
   RETURN Empty( Self )

METHOD HasKey( xKey ) CLASS Hash
   RETURN hb_HHasKey( Self, xKey )

METHOD Del( xKey ) CLASS Hash
   RETURN hb_HDel( Self, xKey )

/* --- */

CREATE CLASS Logical INHERIT HBScalar FUNCTION __HBLogical

   METHOD AsString()

   /* Drydock: user-facing scalar methods */
   METHOD IsTrue()
   METHOD Toggle()

ENDCLASS

METHOD AsString() CLASS Logical
   RETURN iif( Self, ".T.", ".F." )

METHOD IsTrue() CLASS Logical
   RETURN Self

METHOD Toggle() CLASS Logical
   RETURN ! Self

/* --- */

CREATE CLASS NIL INHERIT HBScalar FUNCTION __HBNil

   METHOD AsString()

ENDCLASS

METHOD AsString() CLASS NIL
   RETURN "NIL"

/* --- */

CREATE CLASS Numeric INHERIT HBScalar FUNCTION __HBNumeric

   METHOD AsString()

   /* Drydock: user-facing scalar methods */
   METHOD Abs()
   METHOD Int()
   METHOD Round( nDec )
   METHOD Str( nLen, nDec )
   METHOD Min( nOther )
   METHOD Max( nOther )
   METHOD Empty()
   METHOD Between( nLow, nHigh )

ENDCLASS

METHOD AsString() CLASS Numeric
   RETURN hb_ntos( Self )

METHOD Abs() CLASS Numeric
   RETURN Abs( Self )

METHOD Int() CLASS Numeric
   RETURN Int( Self )

METHOD Round( nDec ) CLASS Numeric
   RETURN Round( Self, hb_defaultValue( nDec, 0 ) )

METHOD Str( nLen, nDec ) CLASS Numeric
   IF nLen == NIL
      RETURN hb_ntos( Self )
   ENDIF
   IF nDec == NIL
      RETURN Str( Self, nLen )
   ENDIF
   RETURN Str( Self, nLen, nDec )

METHOD Min( nOther ) CLASS Numeric
   RETURN Min( Self, nOther )

METHOD Max( nOther ) CLASS Numeric
   RETURN Max( Self, nOther )

METHOD Empty() CLASS Numeric
   RETURN Empty( Self )

METHOD Between( nLow, nHigh ) CLASS Numeric
   RETURN Self >= nLow .AND. Self <= nHigh

/* --- */

CREATE CLASS Symbol INHERIT HBScalar FUNCTION __HBSymbol

   METHOD AsString()

ENDCLASS

METHOD AsString() CLASS Symbol
   RETURN "@" + ::name + "()"

/* --- */

CREATE CLASS Pointer INHERIT HBScalar FUNCTION __HBPointer

   METHOD AsString()

ENDCLASS

METHOD AsString() CLASS Pointer
   RETURN "<0x...>"
