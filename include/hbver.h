/*
 * Header file for version information
 *
 * Copyright 1999 David G. Holm <dholm@jsd-llc.com>
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

/* NOTE: This file is also used by Harbour .prg code. */

#ifndef HB_VER_H_
#define HB_VER_H_

/* Drydock product version — the version of the Drydock project itself.
 * Follows semver: 0.x.y = pre-1.0, no stability guarantees for new features.
 * Harbour compatibility is tracked separately below.
 */
#define DD_VER_MAJOR    0
#define DD_VER_MINOR    0
#define DD_VER_RELEASE  1
#define DD_VER_STATUS   "dev"    /* Build status: "dev", "alpha1", "beta1", "rc1", "" (release) */

#ifdef __DRYDOCK__
   #undef __DRYDOCK__
#endif
#define __DRYDOCK__     0x000001 /* Three bytes: Major + Minor + Release */

/* Harbour compatibility level — the upstream Harbour version this fork
 * is based on. Kept unchanged so external code checking __HARBOUR__ for
 * feature detection continues to work. Do NOT change these unless Drydock
 * merges a newer Harbour upstream.
 */
#ifdef __HARBOUR__
   #undef __HARBOUR__
#endif

#define HB_VER_MAJOR    3        /* Harbour compat major */
#define HB_VER_MINOR    2        /* Harbour compat minor */
#define HB_VER_RELEASE  0        /* Harbour compat release */
#define HB_VER_STATUS   DD_VER_STATUS  /* Alias — external code may reference this */
#define __HARBOUR__     0x030200 /* For 3rd party .c and .prg level code */

#endif /* HB_VER_H_ */
