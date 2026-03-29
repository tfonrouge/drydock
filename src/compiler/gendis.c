/*
 * Drydock Pcode Disassembler
 *
 * Generates human-readable pcode disassembly from compiled functions.
 * Invoked via `drydock -dp source.prg`
 *
 * Copyright 2026 Teo Fonrouge <tfonrouge@gmail.com>
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
 */

#include "hbcomp.h"
#include "hbpcode.h"
#include "hbassert.h"

/* Opcode names — indexed by HB_PCODE enum value */
static const char * s_pcode_names[] =
{
   "AND",                    /*   0 */
   "ARRAYPUSH",              /*   1 */
   "ARRAYPOP",               /*   2 */
   "ARRAYDIM",               /*   3 */
   "ARRAYGEN",               /*   4 */
   "EQUAL",                  /*   5 */
   "ENDBLOCK",               /*   6 */
   "ENDPROC",                /*   7 */
   "EXACTLYEQUAL",           /*   8 */
   "FALSE",                  /*   9 */
   "FORTEST",                /*  10 */
   "FUNCTION",               /*  11 */
   "FUNCTIONSHORT",          /*  12 */
   "FRAME",                  /*  13 */
   "FUNCPTR",                /*  14 */
   "GREATER",                /*  15 */
   "GREATEREQUAL",           /*  16 */
   "DEC",                    /*  17 */
   "DIVIDE",                 /*  18 */
   "DO",                     /*  19 */
   "DOSHORT",                /*  20 */
   "DUPLICATE",              /*  21 */
   "PUSHTIMESTAMP",           /*  22 */
   "INC",                    /*  23 */
   "INSTRING",               /*  24 */
   "JUMPNEAR",               /*  25 */
   "JUMP",                   /*  26 */
   "JUMPFAR",                /*  27 */
   "JUMPFALSENEAR",          /*  28 */
   "JUMPFALSE",              /*  29 */
   "JUMPFALSEFAR",           /*  30 */
   "JUMPTRUENEAR",           /*  31 */
   "JUMPTRUE",               /*  32 */
   "JUMPTRUEFAR",            /*  33 */
   "LESSEQUAL",              /*  34 */
   "LESS",                   /*  35 */
   "LINE",                   /*  36 */
   "LOCALNAME",              /*  37 */
   "MACROPOP",               /*  38 */
   "MACROPOPALIASED",        /*  39 */
   "MACROPUSH",              /*  40 */
   "MACROARRAYGEN",          /*  41 */
   "MACROPUSHLIST",          /*  42 */
   "MACROPUSHINDEX",         /*  43 */
   "MACROPUSHPARE",          /*  44 */
   "MACROPUSHALIASED",       /*  45 */
   "MACROSYMBOL",            /*  46 */
   "MACROTEXT",              /*  47 */
   "MESSAGE",                /*  48 */
   "MINUS",                  /*  49 */
   "MODULUS",                /*  50 */
   "MODULENAME",             /*  51 */
   "MMESSAGE",               /*  52 */
   "MPOPALIASEDFIELD",       /*  53 */
   "MPOPALIASEDVAR",         /*  54 */
   "MPOPFIELD",              /*  55 */
   "MPOPMEMVAR",             /*  56 */
   "MPUSHALIASEDFIELD",      /*  57 */
   "MPUSHALIASEDVAR",        /*  58 */
   "MPUSHBLOCK",             /*  59 */
   "MPUSHFIELD",             /*  60 */
   "MPUSHMEMVAR",            /*  61 */
   "MPUSHMEMVARREF",         /*  62 */
   "MPUSHSYM",               /*  63 */
   "MPUSHVARIABLE",          /*  64 */
   "MULT",                   /*  65 */
   "NEGATE",                 /*  66 */
   "NOOP",                   /*  67 */
   "NOT",                    /*  68 */
   "NOTEQUAL",               /*  69 */
   "OR",                     /*  70 */
   "PARAMETER",              /*  71 */
   "PLUS",                   /*  72 */
   "POP",                    /*  73 */
   "POPALIAS",               /*  74 */
   "POPALIASEDFIELD",        /*  75 */
   "POPALIASEDFIELDNEAR",    /*  76 */
   "POPALIASEDVAR",          /*  77 */
   "POPFIELD",               /*  78 */
   "POPLOCAL",               /*  79 */
   "POPLOCALNEAR",           /*  80 */
   "POPMEMVAR",              /*  81 */
   "POPSTATIC",              /*  82 */
   "POPVARIABLE",            /*  83 */
   "POWER",                  /*  84 */
   "PUSHALIAS",              /*  85 */
   "PUSHALIASEDFIELD",       /*  86 */
   "PUSHALIASEDFIELDNEAR",   /*  87 */
   "PUSHALIASEDVAR",         /*  88 */
   "PUSHBLOCK",              /*  89 */
   "PUSHBLOCKSHORT",         /*  90 */
   "PUSHFIELD",              /*  91 */
   "PUSHBYTE",               /*  92 */
   "PUSHINT",                /*  93 */
   "PUSHLOCAL",              /*  94 */
   "PUSHLOCALNEAR",          /*  95 */
   "PUSHLOCALREF",           /*  96 */
   "PUSHLONG",               /*  97 */
   "PUSHMEMVAR",             /*  98 */
   "PUSHMEMVARREF",          /*  99 */
   "PUSHNIL",                /* 100 */
   "PUSHDOUBLE",             /* 101 */
   "PUSHSELF",               /* 102 */
   "PUSHSTATIC",             /* 103 */
   "PUSHSTATICREF",          /* 104 */
   "PUSHSTR",                /* 105 */
   "PUSHSTRSHORT",           /* 106 */
   "PUSHSYM",                /* 107 */
   "PUSHSYMNEAR",            /* 108 */
   "PUSHVARIABLE",           /* 109 */
   "RETVALUE",               /* 110 */
   "SEND",                   /* 111 */
   "SENDSHORT",              /* 112 */
   "SEQBEGIN",               /* 113 */
   "SEQEND",                 /* 114 */
   "SEQRECOVER",             /* 115 */
   "SFRAME",                 /* 116 */
   "STATICS",                /* 117 */
   "STATICNAME",             /* 118 */
   "SWAPALIAS",              /* 119 */
   "TRUE",                   /* 120 */
   "ZERO",                   /* 121 */
   "ONE",                    /* 122 */
   "MACROFUNC",              /* 123 */
   "MACRODO",                /* 124 */
   "MPUSHSTR",               /* 125 */
   "LOCALNEARADDINT",        /* 126 */
   "MACROPUSHREF",           /* 127 */
   "PUSHLONGLONG",           /* 128 */
   "ENUMSTART",              /* 129 */
   "ENUMNEXT",               /* 130 */
   "ENUMPREV",               /* 131 */
   "ENUMEND",                /* 132 */
   "SWITCH",                 /* 133 */
   "PUSHDATE",               /* 134 */
   "PLUSEQPOP",              /* 135 */
   "MINUSEQPOP",             /* 136 */
   "MULTEQPOP",              /* 137 */
   "DIVEQPOP",               /* 138 */
   "PLUSEQ",                 /* 139 */
   "MINUSEQ",                /* 140 */
   "MULTEQ",                 /* 141 */
   "DIVEQ",                  /* 142 */
   "WITHOBJECTSTART",        /* 143 */
   "WITHOBJECTMESSAGE",      /* 144 */
   "WITHOBJECTEND",          /* 145 */
   "MACROSEND",              /* 146 */
   "PUSHOVARREF",            /* 147 */
   "ARRAYPUSHREF",           /* 148 */
   "VFRAME",                 /* 149 */
   "LARGEFRAME",             /* 150 */
   "LARGEVFRAME",            /* 151 */
   "PUSHSTRHIDDEN",          /* 152 */
   "LOCALADDINT",            /* 153 */
   "MODEQPOP",               /* 154 */
   "EXPEQPOP",               /* 155 */
   "MODEQ",                  /* 156 */
   "EXPEQ",                  /* 157 */
   "DUPLUNREF",              /* 158 */
   "MPUSHBLOCKLARGE",        /* 159 */
   "MPUSHSTRLARGE",          /* 160 */
   "PUSHBLOCKLARGE",         /* 161 */
   "PUSHSTRLARGE",           /* 162 */
   "SWAP",                   /* 163 */
   "PUSHVPARAMS",            /* 164 */
   "PUSHUNREF",              /* 165 */
   "SEQALWAYS",              /* 166 */
   "ALWAYSBEGIN",            /* 167 */
   "ALWAYSEND",              /* 168 */
   "DECEQPOP",               /* 169 */
   "INCEQPOP",               /* 170 */
   "DECEQ",                  /* 171 */
   "INCEQ",                  /* 172 */
   "LOCALDEC",               /* 173 */
   "LOCALINC",               /* 174 */
   "LOCALINCPUSH",           /* 175 */
   "PUSHFUNCSYM",            /* 176 */
   "HASHGEN",                /* 177 */
   "SEQBLOCK",               /* 178 */
   "THREADSTATICS",          /* 179 */
   "PUSHAPARAMS"             /* 180 */
};

/* Disassemble a single function's pcode */
static void hb_compDisFunc( FILE * yyc, PHB_HFUNC pFunc, HB_COMP_DECL )
{
   HB_SIZE nPos = 0;

   fprintf( yyc, "%s:\n", pFunc->szName );

   while( nPos < pFunc->nPCodePos )
   {
      HB_BYTE bCode = pFunc->pCode[ nPos ];
      const char * szName = ( bCode < HB_P_LAST_PCODE ) ?
                            s_pcode_names[ bCode ] : "???";

      fprintf( yyc, "  %04lX  %-20s", ( unsigned long ) nPos, szName );

      /* decode common operand patterns */
      switch( bCode )
      {
         case HB_P_LINE:
            fprintf( yyc, "%u", HB_PCODE_MKUSHORT( &pFunc->pCode[ nPos + 1 ] ) );
            nPos += 3;
            break;

         case HB_P_PUSHBYTE:
            fprintf( yyc, "%d", ( signed char ) pFunc->pCode[ nPos + 1 ] );
            nPos += 2;
            break;

         case HB_P_PUSHINT:
            fprintf( yyc, "%d", HB_PCODE_MKSHORT( &pFunc->pCode[ nPos + 1 ] ) );
            nPos += 3;
            break;

         case HB_P_PUSHLONG:
            fprintf( yyc, "%ld", ( long ) HB_PCODE_MKLONG( &pFunc->pCode[ nPos + 1 ] ) );
            nPos += 5;
            break;

         case HB_P_PUSHSTRSHORT:
         {
            HB_USHORT nLen = pFunc->pCode[ nPos + 1 ];
            fprintf( yyc, "\"%.*s\"", nLen - 1, ( const char * ) &pFunc->pCode[ nPos + 2 ] );
            nPos += 2 + nLen;
            break;
         }

         case HB_P_PUSHSYM:
         case HB_P_PUSHFUNCSYM:
         case HB_P_MESSAGE:
         {
            HB_USHORT usSym = HB_PCODE_MKUSHORT( &pFunc->pCode[ nPos + 1 ] );
            PHB_HSYMBOL pSym = HB_COMP_PARAM->symbols.pFirst;
            HB_USHORT us;
            for( us = 0; us < usSym && pSym; us++ )
               pSym = pSym->pNext;
            if( pSym )
               fprintf( yyc, "%s", pSym->szName );
            else
               fprintf( yyc, "sym#%u", usSym );
            nPos += 3;
            break;
         }

         case HB_P_PUSHSYMNEAR:
         {
            HB_BYTE usSym = pFunc->pCode[ nPos + 1 ];
            PHB_HSYMBOL pSym = HB_COMP_PARAM->symbols.pFirst;
            HB_BYTE us;
            for( us = 0; us < usSym && pSym; us++ )
               pSym = pSym->pNext;
            if( pSym )
               fprintf( yyc, "%s", pSym->szName );
            else
               fprintf( yyc, "sym#%u", usSym );
            nPos += 2;
            break;
         }

         case HB_P_PUSHLOCAL:
         case HB_P_POPLOCAL:
         case HB_P_PUSHLOCALREF:
            fprintf( yyc, "%d", HB_PCODE_MKSHORT( &pFunc->pCode[ nPos + 1 ] ) );
            nPos += 3;
            break;

         case HB_P_PUSHLOCALNEAR:
         case HB_P_POPLOCALNEAR:
            fprintf( yyc, "%d", ( signed char ) pFunc->pCode[ nPos + 1 ] );
            nPos += 2;
            break;

         case HB_P_PUSHSTATIC:
         case HB_P_POPSTATIC:
         case HB_P_PUSHSTATICREF:
            fprintf( yyc, "%u", HB_PCODE_MKUSHORT( &pFunc->pCode[ nPos + 1 ] ) );
            nPos += 3;
            break;

         case HB_P_JUMPNEAR:
         case HB_P_JUMPFALSENEAR:
         case HB_P_JUMPTRUENEAR:
         {
            signed char offset = ( signed char ) pFunc->pCode[ nPos + 1 ];
            fprintf( yyc, "-> %04lX", ( unsigned long )( nPos + offset ) );
            nPos += 2;
            break;
         }

         case HB_P_JUMP:
         case HB_P_JUMPFALSE:
         case HB_P_JUMPTRUE:
         {
            HB_SHORT offset = HB_PCODE_MKSHORT( &pFunc->pCode[ nPos + 1 ] );
            fprintf( yyc, "-> %04lX", ( unsigned long )( nPos + offset ) );
            nPos += 3;
            break;
         }

         case HB_P_JUMPFAR:
         case HB_P_JUMPFALSEFAR:
         case HB_P_JUMPTRUEFAR:
         case HB_P_SEQBEGIN:
         case HB_P_SEQEND:
         case HB_P_SEQALWAYS:
         case HB_P_ALWAYSBEGIN:
         {
            HB_LONG offset = HB_PCODE_MKINT24( &pFunc->pCode[ nPos + 1 ] );
            fprintf( yyc, "-> %04lX", ( unsigned long )( nPos + offset ) );
            nPos += 4;
            break;
         }

         case HB_P_FRAME:
            fprintf( yyc, "locals=%u params=%u",
                     pFunc->pCode[ nPos + 1 ], pFunc->pCode[ nPos + 2 ] );
            nPos += 3;
            break;

         case HB_P_VFRAME:
            fprintf( yyc, "locals=%u params=%u (varargs)",
                     pFunc->pCode[ nPos + 1 ], pFunc->pCode[ nPos + 2 ] );
            nPos += 3;
            break;

         case HB_P_LARGEFRAME:
            fprintf( yyc, "locals=%u params=%u",
                     HB_PCODE_MKUSHORT( &pFunc->pCode[ nPos + 1 ] ),
                     pFunc->pCode[ nPos + 3 ] );
            nPos += 4;
            break;

         case HB_P_FUNCTION:
         case HB_P_DO:
         case HB_P_SEND:
            fprintf( yyc, "%u", HB_PCODE_MKUSHORT( &pFunc->pCode[ nPos + 1 ] ) );
            nPos += 3;
            break;

         case HB_P_FUNCTIONSHORT:
         case HB_P_DOSHORT:
         case HB_P_SENDSHORT:
            fprintf( yyc, "%u", pFunc->pCode[ nPos + 1 ] );
            nPos += 2;
            break;

         case HB_P_LOCALNEARADDINT:
            fprintf( yyc, "local=%d int=%d",
                     ( signed char ) pFunc->pCode[ nPos + 1 ],
                     HB_PCODE_MKSHORT( &pFunc->pCode[ nPos + 2 ] ) );
            nPos += 4;
            break;

         case HB_P_LOCALADDINT:
            fprintf( yyc, "local=%d int=%d",
                     HB_PCODE_MKSHORT( &pFunc->pCode[ nPos + 1 ] ),
                     HB_PCODE_MKSHORT( &pFunc->pCode[ nPos + 3 ] ) );
            nPos += 5;
            break;

         case HB_P_LOCALNAME:
         case HB_P_STATICNAME:
         case HB_P_MODULENAME:
         {
            const char * sz = ( const char * ) &pFunc->pCode[ nPos + 1 ];
            fprintf( yyc, "\"%s\"", sz );
            nPos += 2 + strlen( sz );
            break;
         }

         case HB_P_ARRAYDIM:
         case HB_P_ARRAYGEN:
         case HB_P_HASHGEN:
            fprintf( yyc, "%u", HB_PCODE_MKUSHORT( &pFunc->pCode[ nPos + 1 ] ) );
            nPos += 3;
            break;

         default:
         {
            /* Use the pcode length table for opcodes we don't decode specially */
            extern const HB_BYTE hb_comp_pcode_len[];
            HB_BYTE nLen = hb_comp_pcode_len[ bCode ];
            if( nLen > 1 )
            {
               HB_SIZE i;
               for( i = 1; i < nLen; i++ )
                  fprintf( yyc, "%02X ", pFunc->pCode[ nPos + i ] );
            }
            nPos += nLen ? nLen : 1;
            break;
         }
      }

      fprintf( yyc, "\n" );
   }
   fprintf( yyc, "\n" );
}


void hb_compGenDis( HB_COMP_DECL )
{
   PHB_HFUNC pFunc;

   fprintf( stdout, "; Drydock pcode disassembly: %s\n\n",
            HB_COMP_PARAM->szFile ? HB_COMP_PARAM->szFile : "(unknown)" );

   pFunc = HB_COMP_PARAM->functions.pFirst;
   while( pFunc )
   {
      if( ( pFunc->funFlags & HB_FUNF_FILE_DECL ) == 0 )
         hb_compDisFunc( stdout, pFunc, HB_COMP_PARAM );
      pFunc = pFunc->pNext;
   }
}
