/*
 * Drydock PersistentAST — Walker/Visitor Infrastructure
 *
 * Generic AST walker that traverses retained expression nodes.
 * Visitors are callback functions called for each node type.
 *
 * Copyright 2026 Teo Fonrouge <tfonrouge@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2, or (at your option)
 * any later version.
 */

#include "hbcomp.h"

/* Visitor callback type: called for each expression node.
 * Return HB_TRUE to continue walking children, HB_FALSE to skip.
 */
typedef HB_BOOL ( * PHB_AST_VISITOR )( PHB_EXPR pExpr, void * cargo );

/* Walk an expression tree depth-first, calling the visitor for each node.
 * The visitor is called BEFORE recursing into children (pre-order).
 * If the visitor returns HB_FALSE, children are not visited.
 */
static void hb_compExprWalkNode( PHB_EXPR pExpr, PHB_AST_VISITOR pVisitor, void * cargo )
{
   if( ! pExpr || ! pVisitor )
      return;

   /* Call visitor — if it returns FALSE, skip children */
   if( ! pVisitor( pExpr, cargo ) )
      return;

   /* Recurse into children based on expression type */
   switch( pExpr->ExprType )
   {
      /* Leaf nodes — no children */
      case HB_ET_NONE:
      case HB_ET_NIL:
      case HB_ET_NUMERIC:
      case HB_ET_DATE:
      case HB_ET_TIMESTAMP:
      case HB_ET_STRING:
      case HB_ET_LOGICAL:
      case HB_ET_SELF:
      case HB_ET_VARIABLE:
      case HB_ET_FUNNAME:
      case HB_ET_ALIAS:
      case HB_ET_FUNREF:
      case HB_ET_VARREF:
         break;

      /* Reference — single child */
      case HB_ET_REFERENCE:
         hb_compExprWalkNode( pExpr->value.asReference, pVisitor, cargo );
         break;

      /* IIF — 3 children via asList */
      case HB_ET_IIF:
      /* List/ArgList — chain of pNext-linked expressions */
      case HB_ET_LIST:
      case HB_ET_ARGLIST:
      case HB_ET_MACROARGLIST:
      case HB_ET_ARRAY:
      case HB_ET_HASH:
      {
         PHB_EXPR pChild = pExpr->value.asList.pExprList;
         while( pChild )
         {
            hb_compExprWalkNode( pChild, pVisitor, cargo );
            pChild = pChild->pNext;
         }
         if( pExpr->value.asList.pIndex )
            hb_compExprWalkNode( pExpr->value.asList.pIndex, pVisitor, cargo );
         break;
      }

      /* Array element access */
      case HB_ET_ARRAYAT:
      {
         PHB_EXPR pChild = pExpr->value.asList.pExprList;
         while( pChild )
         {
            hb_compExprWalkNode( pChild, pVisitor, cargo );
            pChild = pChild->pNext;
         }
         if( pExpr->value.asList.pIndex )
            hb_compExprWalkNode( pExpr->value.asList.pIndex, pVisitor, cargo );
         break;
      }

      /* Macro — optional expression list */
      case HB_ET_MACRO:
         if( pExpr->value.asMacro.pExprList )
            hb_compExprWalkNode( pExpr->value.asMacro.pExprList, pVisitor, cargo );
         break;

      /* Function call — function name + parameters */
      case HB_ET_FUNCALL:
         hb_compExprWalkNode( pExpr->value.asFunCall.pFunName, pVisitor, cargo );
         if( pExpr->value.asFunCall.pParms )
            hb_compExprWalkNode( pExpr->value.asFunCall.pParms, pVisitor, cargo );
         break;

      /* Message send — object + parameters + message */
      case HB_ET_SEND:
         hb_compExprWalkNode( pExpr->value.asMessage.pObject, pVisitor, cargo );
         if( pExpr->value.asMessage.pParms )
            hb_compExprWalkNode( pExpr->value.asMessage.pParms, pVisitor, cargo );
         if( pExpr->value.asMessage.pMessage )
            hb_compExprWalkNode( pExpr->value.asMessage.pMessage, pVisitor, cargo );
         break;

      /* Alias — alias + variable/expression */
      case HB_ET_ALIASVAR:
      case HB_ET_ALIASEXPR:
         if( pExpr->value.asAlias.pAlias )
            hb_compExprWalkNode( pExpr->value.asAlias.pAlias, pVisitor, cargo );
         if( pExpr->value.asAlias.pVar )
            hb_compExprWalkNode( pExpr->value.asAlias.pVar, pVisitor, cargo );
         if( pExpr->value.asAlias.pExpList )
            hb_compExprWalkNode( pExpr->value.asAlias.pExpList, pVisitor, cargo );
         break;

      /* Set/Get — variable + expression */
      case HB_ET_SETGET:
         hb_compExprWalkNode( pExpr->value.asSetGet.pVar, pVisitor, cargo );
         if( pExpr->value.asSetGet.pExpr )
            hb_compExprWalkNode( pExpr->value.asSetGet.pExpr, pVisitor, cargo );
         break;

      /* Runtime variable — optional macro */
      case HB_ET_RTVAR:
         if( pExpr->value.asRTVar.pMacro )
            hb_compExprWalkNode( pExpr->value.asRTVar.pMacro, pVisitor, cargo );
         break;

      /* Codeblock — expression list */
      case HB_ET_CODEBLOCK:
         if( pExpr->value.asCodeblock.pExprList )
            hb_compExprWalkNode( pExpr->value.asCodeblock.pExprList, pVisitor, cargo );
         break;

      /* Binary operators — left + right */
      case HB_EO_ASSIGN:
      case HB_EO_PLUSEQ:
      case HB_EO_MINUSEQ:
      case HB_EO_MULTEQ:
      case HB_EO_DIVEQ:
      case HB_EO_MODEQ:
      case HB_EO_EXPEQ:
      case HB_EO_OR:
      case HB_EO_AND:
      case HB_EO_EQUAL:
      case HB_EO_EQ:
      case HB_EO_NE:
      case HB_EO_IN:
      case HB_EO_LT:
      case HB_EO_GT:
      case HB_EO_LE:
      case HB_EO_GE:
      case HB_EO_PLUS:
      case HB_EO_MINUS:
      case HB_EO_MULT:
      case HB_EO_DIV:
      case HB_EO_MOD:
      case HB_EO_POWER:
         hb_compExprWalkNode( pExpr->value.asOperator.pLeft, pVisitor, cargo );
         if( pExpr->value.asOperator.pRight )
            hb_compExprWalkNode( pExpr->value.asOperator.pRight, pVisitor, cargo );
         break;

      /* Unary operators — left only */
      case HB_EO_NOT:
      case HB_EO_NEGATE:
      case HB_EO_PREINC:
      case HB_EO_PREDEC:
      case HB_EO_POSTINC:
      case HB_EO_POSTDEC:
         hb_compExprWalkNode( pExpr->value.asOperator.pLeft, pVisitor, cargo );
         break;

      default:
         break;
   }
}

/* Walk the entire retained AST of a function (pBodyAST linked list).
 * Each statement in the list is walked depth-first.
 */
void hb_compASTWalk( PHB_EXPR pBodyAST, PHB_AST_VISITOR pVisitor, void * cargo )
{
   PHB_EXPR pStmt = pBodyAST;
   while( pStmt )
   {
      hb_compExprWalkNode( pStmt, pVisitor, cargo );
      pStmt = pStmt->pNext;
   }
}


/* ================================================================
 * Built-in visitor: AST Printer (debug output)
 * Prints human-readable AST representation to FILE*.
 * ================================================================ */

static const char * s_exprNames[] =
{
   "NONE",          /*  0 */
   "NIL",           /*  1 */
   "NUMERIC",       /*  2 */
   "DATE",          /*  3 */
   "TIMESTAMP",     /*  4 */
   "STRING",        /*  5 */
   "CODEBLOCK",     /*  6 */
   "LOGICAL",       /*  7 */
   "SELF",          /*  8 */
   "ARRAY",         /*  9 */
   "HASH",          /* 10 */
   "FUNREF",        /* 11 */
   "VARREF",        /* 12 */
   "REFERENCE",     /* 13 */
   "IIF",           /* 14 */
   "LIST",          /* 15 */
   "ARGLIST",       /* 16 */
   "MACROARGLIST",  /* 17 */
   "ARRAYAT",       /* 18 */
   "MACRO",         /* 19 */
   "FUNCALL",       /* 20 */
   "ALIASVAR",      /* 21 */
   "ALIASEXPR",     /* 22 */
   "SETGET",        /* 23 */
   "SEND",          /* 24 */
   "FUNNAME",       /* 25 */
   "ALIAS",         /* 26 */
   "RTVAR",         /* 27 */
   "VARIABLE",      /* 28 */
   "POSTINC",       /* 29 */
   "POSTDEC",       /* 30 */
   "ASSIGN",        /* 31 */
   "PLUSEQ",        /* 32 */
   "MINUSEQ",       /* 33 */
   "MULTEQ",        /* 34 */
   "DIVEQ",         /* 35 */
   "MODEQ",         /* 36 */
   "EXPEQ",         /* 37 */
   "OR",            /* 38 */
   "AND",           /* 39 */
   "NOT",           /* 40 */
   "EQUAL",         /* 41 */
   "EQ",            /* 42 */
   "NE",            /* 43 */
   "IN",            /* 44 */
   "LT",            /* 45 */
   "GT",            /* 46 */
   "LE",            /* 47 */
   "GE",            /* 48 */
   "PLUS",          /* 49 */
   "MINUS",         /* 50 */
   "MULT",          /* 51 */
   "DIV",           /* 52 */
   "MOD",           /* 53 */
   "POWER",         /* 54 */
   "NEGATE",        /* 55 */
   "PREINC",        /* 56 */
   "PREDEC"         /* 57 */
};

typedef struct
{
   FILE * yyc;
   int    iIndent;
} HB_AST_PRINT_CARGO;

static HB_BOOL hb_compASTPrintVisitor( PHB_EXPR pExpr, void * cargo )
{
   HB_AST_PRINT_CARGO * pCargo = ( HB_AST_PRINT_CARGO * ) cargo;
   const char * szType;
   int i;

   if( pExpr->ExprType < HB_EXPR_COUNT )
      szType = s_exprNames[ pExpr->ExprType ];
   else
      szType = "???";

   for( i = 0; i < pCargo->iIndent; i++ )
      fprintf( pCargo->yyc, "  " );

   fprintf( pCargo->yyc, "%s", szType );

   /* Print extra info for leaf types */
   switch( pExpr->ExprType )
   {
      case HB_ET_NUMERIC:
         if( pExpr->value.asNum.NumType == 1 )
            fprintf( pCargo->yyc, " %ld", ( long ) pExpr->value.asNum.val.l );
         else
            fprintf( pCargo->yyc, " %g", pExpr->value.asNum.val.d );
         break;
      case HB_ET_STRING:
         fprintf( pCargo->yyc, " \"%s\"", pExpr->value.asString.string ?
                  pExpr->value.asString.string : "" );
         break;
      case HB_ET_LOGICAL:
         fprintf( pCargo->yyc, " %s", pExpr->value.asLogical ? ".T." : ".F." );
         break;
      case HB_ET_VARIABLE:
         fprintf( pCargo->yyc, " %s", pExpr->value.asSymbol.name ?
                  pExpr->value.asSymbol.name : "?" );
         if( pExpr->pSymbol )
            fprintf( pCargo->yyc, " [resolved→%s]", pExpr->pSymbol->szName );
         break;
      case HB_ET_FUNNAME:
         fprintf( pCargo->yyc, " %s", pExpr->value.asSymbol.name ?
                  pExpr->value.asSymbol.name : "?" );
         break;
      case HB_ET_FUNCALL:
         /* Function name printed by child visitor */
         break;
      case HB_ET_SEND:
         if( pExpr->value.asMessage.szMessage )
            fprintf( pCargo->yyc, " :%s", pExpr->value.asMessage.szMessage );
         break;
      default:
         break;
   }

   fprintf( pCargo->yyc, "\n" );
   pCargo->iIndent++;

   return HB_TRUE; /* continue into children */
}

/* Post-visit callback to decrease indent (called manually after children) */
/* For simplicity, we handle indent in the visitor itself — the walker
 * doesn't support post-visit callbacks. We'll use a depth counter instead.
 * TODO: add post-visit support to walker for proper indentation.
 */

/* Print the retained AST of a function */
void hb_compASTPrint( PHB_HFUNC pFunc, FILE * yyc )
{
   HB_AST_PRINT_CARGO cargo;
   cargo.yyc = yyc;
   cargo.iIndent = 1;

   fprintf( yyc, "%s:\n", pFunc->szName );

   if( pFunc->pBodyAST )
   {
      PHB_EXPR pStmt = pFunc->pBodyAST;
      while( pStmt )
      {
         cargo.iIndent = 1;
         hb_compExprWalkNode( pStmt, ( PHB_AST_VISITOR ) hb_compASTPrintVisitor, &cargo );
         pStmt = pStmt->pNext;
      }
   }
   else
      fprintf( yyc, "  (no AST retained)\n" );

   fprintf( yyc, "\n" );
}


/* ================================================================
 * Symbol Resolution Walker (Phase E.2)
 *
 * Resolves HB_ET_VARIABLE nodes to their HB_HVAR declarations by
 * searching the function's local/static/field/memvar lists.
 * ================================================================ */

/* Search a variable list for a name */
static PHB_HVAR hb_compASTFindVar( PHB_HVAR pVarList, const char * szName )
{
   while( pVarList )
   {
      if( pVarList->szName && strcmp( pVarList->szName, szName ) == 0 )
         return pVarList;
      pVarList = pVarList->pNext;
   }
   return NULL;
}

typedef struct
{
   PHB_HFUNC  pFunc;      /* current function being resolved */
   HB_SIZE    nResolved;  /* count of resolved variables */
} HB_AST_RESOLVE_CARGO;

static HB_BOOL hb_compASTResolveVisitor( PHB_EXPR pExpr, void * cargo )
{
   HB_AST_RESOLVE_CARGO * pCargo = ( HB_AST_RESOLVE_CARGO * ) cargo;

   if( pExpr->ExprType == HB_ET_VARIABLE && pExpr->value.asSymbol.name )
   {
      PHB_HVAR pVar;

      /* Search in order: locals → statics → fields → memvars → detached */
      pVar = hb_compASTFindVar( pCargo->pFunc->pLocals, pExpr->value.asSymbol.name );
      if( ! pVar )
         pVar = hb_compASTFindVar( pCargo->pFunc->pStatics, pExpr->value.asSymbol.name );
      if( ! pVar )
         pVar = hb_compASTFindVar( pCargo->pFunc->pFields, pExpr->value.asSymbol.name );
      if( ! pVar )
         pVar = hb_compASTFindVar( pCargo->pFunc->pMemvars, pExpr->value.asSymbol.name );
      if( ! pVar )
         pVar = hb_compASTFindVar( pCargo->pFunc->pDetached, pExpr->value.asSymbol.name );

      if( pVar )
      {
         pExpr->pSymbol = pVar;
         pCargo->nResolved++;
      }
   }

   return HB_TRUE; /* always continue into children */
}

/* Resolve all variable references in a function's retained AST.
 * Returns the number of variables resolved.
 */
HB_SIZE hb_compASTResolveSymbols( PHB_HFUNC pFunc )
{
   HB_AST_RESOLVE_CARGO cargo;

   if( ! pFunc->pBodyAST )
      return 0;

   cargo.pFunc = pFunc;
   cargo.nResolved = 0;

   {
      PHB_EXPR pStmt = pFunc->pBodyAST;
      while( pStmt )
      {
         hb_compExprWalkNode( pStmt,
                              ( PHB_AST_VISITOR ) hb_compASTResolveVisitor,
                              &cargo );
         pStmt = pStmt->pNext;
      }
   }

   return cargo.nResolved;
}


/* ================================================================
 * Type Checking Walker (GradualTyping Phase F.1)
 *
 * Checks assignments to typed variables for type compatibility.
 * Emits WARNINGS (not errors) — code still compiles.
 * ================================================================ */

/* Map HB_EXPR type to cType character */
static char hb_compASTExprTypeChar( PHB_EXPR pExpr )
{
   switch( pExpr->ExprType )
   {
      case HB_ET_STRING:    return 'C';
      case HB_ET_NUMERIC:   return 'N';
      case HB_ET_DATE:      return 'D';
      case HB_ET_TIMESTAMP: return 'T';
      case HB_ET_LOGICAL:   return 'L';
      case HB_ET_ARRAY:     return 'A';
      case HB_ET_HASH:      return 'H';
      case HB_ET_CODEBLOCK: return 'B';
      case HB_ET_NIL:       return 'U';
      case HB_ET_SELF:      return 'O';
      default:              return 0; /* unknown/complex — can't check */
   }
}

/* Type name for diagnostics */
static const char * hb_compASTTypeName( char cType )
{
   switch( cType )
   {
      case 'C': return "String";
      case 'N': return "Numeric";
      case 'D': return "Date";
      case 'T': return "Timestamp";
      case 'L': return "Logical";
      case 'A': return "Array";
      case 'H': return "Hash";
      case 'B': return "Block";
      case 'O': return "Object";
      case 'U': return "NIL";
      default:  return "Unknown";
   }
}

typedef struct
{
   HB_COMP_DECL;
   PHB_HFUNC  pFunc;
   HB_SIZE    nWarnings;
} HB_AST_TYPECHECK_CARGO;

static HB_BOOL hb_compASTTypeCheckVisitor( PHB_EXPR pExpr, void * cargo )
{
   HB_AST_TYPECHECK_CARGO * pCargo = ( HB_AST_TYPECHECK_CARGO * ) cargo;

   /* F.1a: Check assignments to typed variables */
   if( pExpr->ExprType == HB_EO_ASSIGN )
   {
      PHB_EXPR pLeft = pExpr->value.asOperator.pLeft;
      PHB_EXPR pRight = pExpr->value.asOperator.pRight;

      if( pLeft && pLeft->ExprType == HB_ET_VARIABLE &&
          pLeft->pSymbol && pLeft->pSymbol->cType != 0 && pRight )
      {
         char cRhsType = hb_compASTExprTypeChar( pRight );

         /* Only warn when RHS type is known AND different from declared */
         if( cRhsType != 0 && cRhsType != pLeft->pSymbol->cType )
         {
            /* NIL is always allowed for nullable types */
            if( cRhsType != 'U' )
            {
               char szMsg[ 128 ];
               hb_snprintf( szMsg, sizeof( szMsg ),
                  "Type mismatch: '%s' declared AS %s, assigned %s",
                  pLeft->pSymbol->szName,
                  hb_compASTTypeName( pLeft->pSymbol->cType ),
                  hb_compASTTypeName( cRhsType ) );
               hb_compGenWarning( pCargo->HB_COMP_PARAM, hb_comp_szWarnings,
                                  'W', HB_COMP_WARN_ASSIGN_TYPE, szMsg, NULL );
               pCargo->nWarnings++;
            }
         }
      }
   }

   /* F.1d: Check binary operator type compatibility */
   if( pExpr->ExprType >= HB_EO_PLUS && pExpr->ExprType <= HB_EO_POWER )
   {
      PHB_EXPR pLeft = pExpr->value.asOperator.pLeft;
      PHB_EXPR pRight = pExpr->value.asOperator.pRight;

      if( pLeft && pRight )
      {
         char cLeft = hb_compASTExprTypeChar( pLeft );
         char cRight = hb_compASTExprTypeChar( pRight );

         /* Only check when both types are known */
         if( cLeft != 0 && cRight != 0 && cLeft != cRight )
         {
            /* Some cross-type operations are valid: date+numeric, numeric+date */
            HB_BOOL fValid = HB_FALSE;

            if( ( cLeft == 'D' || cLeft == 'T' ) && cRight == 'N' )
               fValid = HB_TRUE; /* date/timestamp +/- numeric */
            else if( cLeft == 'N' && ( cRight == 'D' || cRight == 'T' ) )
               fValid = HB_TRUE; /* numeric + date/timestamp */

            if( ! fValid )
            {
               /* Warning template: "Incompatible operand types '%s' and '%s'" */
               hb_compGenWarning( pCargo->HB_COMP_PARAM, hb_comp_szWarnings,
                                  'W', HB_COMP_WARN_OPERANDS_INCOMPATIBLE,
                                  hb_compASTTypeName( cLeft ),
                                  hb_compASTTypeName( cRight ) );
               pCargo->nWarnings++;
            }
         }
      }
   }

   return HB_TRUE; /* continue into children */
}

/* Run type checking on a function's retained AST.
 * Returns the number of warnings emitted.
 */
HB_SIZE hb_compASTTypeCheck( HB_COMP_DECL, PHB_HFUNC pFunc )
{
   HB_AST_TYPECHECK_CARGO cargo;

   if( ! pFunc->pBodyAST )
      return 0;

   cargo.HB_COMP_PARAM = HB_COMP_PARAM;
   cargo.pFunc = pFunc;
   cargo.nWarnings = 0;

   {
      PHB_EXPR pStmt = pFunc->pBodyAST;
      while( pStmt )
      {
         hb_compExprWalkNode( pStmt,
                              ( PHB_AST_VISITOR ) hb_compASTTypeCheckVisitor,
                              &cargo );
         pStmt = pStmt->pNext;
      }
   }

   return cargo.nWarnings;
}
