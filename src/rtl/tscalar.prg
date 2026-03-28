/*
 * Scalar class stubs — backward compatibility for ENABLE TYPE CLASS ALL.
 *
 * All scalar class methods are now implemented in C (src/vm/classes.c)
 * and are always available without any includes or REQUEST directives.
 * These empty class definitions exist only so that legacy code using
 * ENABLE TYPE CLASS ALL (which REQUESTs factory functions by name)
 * continues to link without error.
 *
 * Copyright 2004 Antonio Linares <alinares@fivetechsoft.com>
 * Copyright 2026 Teo Fonrouge <tfonrouge@gmail.com> (Drydock migration to C)
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

#include "hbclass.ch"

/* Stub classes — factory functions must exist for ENABLE TYPE CLASS ALL */

CREATE CLASS ScalarObject FUNCTION HBScalar
ENDCLASS

CREATE CLASS Array INHERIT HBScalar FUNCTION __HBArray
ENDCLASS

CREATE CLASS Block INHERIT HBScalar FUNCTION __HBBlock
ENDCLASS

CREATE CLASS Character INHERIT HBScalar FUNCTION __HBCharacter
ENDCLASS

CREATE CLASS Date INHERIT HBScalar FUNCTION __HBDate
ENDCLASS

CREATE CLASS TimeStamp INHERIT HBScalar FUNCTION __HBTimeStamp
ENDCLASS

CREATE CLASS Hash INHERIT HBScalar FUNCTION __HBHash
ENDCLASS

CREATE CLASS Logical INHERIT HBScalar FUNCTION __HBLogical
ENDCLASS

CREATE CLASS NIL INHERIT HBScalar FUNCTION __HBNil
ENDCLASS

CREATE CLASS Numeric INHERIT HBScalar FUNCTION __HBNumeric
ENDCLASS

CREATE CLASS Symbol INHERIT HBScalar FUNCTION __HBSymbol
ENDCLASS

CREATE CLASS Pointer INHERIT HBScalar FUNCTION __HBPointer
ENDCLASS
