# DESIGN -- DrydockObject (SUBSYSTEM)

## 1. Current State

### Class System Initialization (`hb_clsInit`, classes.c:1102-1150)

The current init sequence:
1. Register 30 operator symbol dynsyms
2. Register special message dynsyms (CLASSNAME, CLASSH, etc.)
3. Allocate class pool (`s_pClasses` array)
4. Set `s_pClasses[0] = NULL` (handle 0 = invalid)

After this, `hb_clsDoInit()` (called later from hvm.c:1146) searches for
PRG factory functions by name and calls them. If the functions aren't linked,
scalar classes remain uninitialized (`s_uiCharacterClass == 0`).

### Built-In Default Messages (classes.c:2165-2224)

Messages like `CLASSNAME`, `CLASSH`, `CLASSSEL` are handled in
`hb_objGetMethod()` AFTER class method lookup fails:

```c
/* Default messages here */
if( pMsg == s___msgClassName.pDynSym )
   return &s___msgClassName;
else if( pMsg == s___msgClassH.pDynSym )
   return &s___msgClassH;
```

Each is a static `HB_SYMB` with a C function pointer:
```c
static HB_SYMB s___msgClassName = {
   "CLASSNAME", {HB_FS_MESSAGE}, {HB_FUNCNAME( msgClassName )}, NULL
};
```

The C function uses `hb_stackSelfItem()` to get the receiver and
returns a value via `hb_retc()` / `hb_retni()`.

### Public C API for Class Creation (classes.c:5584-5620)

```c
HB_USHORT hb_clsCreate( HB_USHORT usSize, const char * szClassName );
void hb_clsAdd( HB_USHORT usClassH, const char * szMethodName, PHB_FUNC pFuncPtr );
void hb_clsAssociate( HB_USHORT usClassH );
```

- `hb_clsCreate(0, "NAME")` — creates class with 0 instance data
- `hb_clsAdd(handle, "METHOD", func)` — adds C function as exported method
- These are the building blocks for creating classes entirely in C

### Inheritance via `hb_clsNew` (classes.c:3386-3584)

```c
static HB_USHORT hb_clsNew( const char * szClassName, HB_USHORT uiDatas,
                            PHB_ITEM pSuperArray, PHB_SYMB pClassFunc,
                            HB_BOOL fModuleFriendly );
```

`pSuperArray` is an array of numeric class handles. The first superclass's
methods are COPIED; additional ones are MERGED. Methods can be added to a
class at any time via `hb_clsAddMsg()` (classes are not locked by default).

---

## 2. Proposed Changes

### 2.1 New Static Symbols

```c
/* Near line 296 in classes.c */
static HB_SYMB s___msgToString    = { "TOSTRING",     {HB_FS_MESSAGE}, {HB_FUNCNAME( msgToString )},    NULL };
static HB_SYMB s___msgIsScalar    = { "ISSCALAR",     {HB_FS_MESSAGE}, {HB_FUNCNAME( msgIsScalar )},    NULL };
static HB_SYMB s___msgIsNil       = { "ISNIL",        {HB_FS_MESSAGE}, {HB_FUNCNAME( msgIsNil )},       NULL };
static HB_SYMB s___msgValType     = { "VALTYPE",      {HB_FS_MESSAGE}, {HB_FUNCNAME( msgValType )},     NULL };
static HB_SYMB s___msgCompareTo   = { "COMPARETO",    {HB_FS_MESSAGE}, {HB_FUNCNAME( msgCompareTo )},   NULL };
static HB_SYMB s___msgIsComparable= { "ISCOMPARABLE", {HB_FS_MESSAGE}, {HB_FUNCNAME( msgIsComparable )},NULL };
```

### 2.2 New Static Variable

```c
static HB_USHORT s_uiDrydockObjectClass = 0;
```

### 2.3 Built-In Message Implementations

```c
HB_FUNC_STATIC( msgToString )
{
   HB_STACK_TLS_PRELOAD
   PHB_ITEM pSelf = hb_stackSelfItem();

   if( HB_IS_STRING( pSelf ) )
      hb_itemReturn( pSelf );
   else if( HB_IS_NUMERIC( pSelf ) )
   {
      char * s = hb_itemStr( pSelf, NULL, NULL );
      if( s )
      {
         hb_retc( hb_strLTrim( s ) );
         hb_xfree( s );
      }
   }
   else if( HB_IS_DATE( pSelf ) )
      hb_retc( hb_itemGetDS( pSelf, NULL ) ? hb_parc( -1 ) : "" );
   else if( HB_IS_TIMESTAMP( pSelf ) )
   {
      char szBuf[ 24 ];
      hb_retc( hb_timeStampStr( szBuf, pSelf->item.asDateTime.julian,
                                        pSelf->item.asDateTime.time ) );
   }
   else if( HB_IS_LOGICAL( pSelf ) )
      hb_retc( hb_itemGetL( pSelf ) ? ".T." : ".F." );
   else if( HB_IS_NIL( pSelf ) )
      hb_retc( "NIL" );
   else if( HB_IS_ARRAY( pSelf ) )
      hb_retc( "{ ... }" );
   else if( HB_IS_HASH( pSelf ) )
      hb_retc( "{ => }" );
   else if( HB_IS_BLOCK( pSelf ) )
      hb_retc( "{ || ... }" );
   else if( HB_IS_SYMBOL( pSelf ) )
   {
      char szBuf[ HB_SYMBOL_NAME_LEN + 4 ];
      hb_snprintf( szBuf, sizeof( szBuf ), "@%s()",
                   pSelf->item.asSymbol.value->szName );
      hb_retc( szBuf );
   }
   else if( HB_IS_POINTER( pSelf ) )
      hb_retc( "<pointer>" );
   else
      hb_retc( hb_objGetClsName( pSelf ) );
}

HB_FUNC_STATIC( msgIsScalar )
{
   HB_STACK_TLS_PRELOAD
   hb_retl( ! HB_IS_OBJECT( hb_stackSelfItem() ) );
}

HB_FUNC_STATIC( msgIsNil )
{
   HB_STACK_TLS_PRELOAD
   hb_retl( HB_IS_NIL( hb_stackSelfItem() ) );
}

HB_FUNC_STATIC( msgValType )
{
   HB_STACK_TLS_PRELOAD
   char szType[ 2 ];
   szType[ 0 ] = hb_itemTypeChar( hb_stackSelfItem() );
   szType[ 1 ] = '\0';
   hb_retc( szType );
}

HB_FUNC_STATIC( msgCompareTo )
{
   HB_STACK_TLS_PRELOAD
   PHB_ITEM pSelf = hb_stackSelfItem();
   PHB_ITEM pOther = hb_param( 1, HB_IT_ANY );

   if( pOther == NULL )
   {
      hb_retni( 0 );
      return;
   }

   if( HB_IS_NUMERIC( pSelf ) && HB_IS_NUMERIC( pOther ) )
   {
      double d1 = hb_itemGetND( pSelf );
      double d2 = hb_itemGetND( pOther );
      hb_retni( d1 < d2 ? -1 : ( d1 > d2 ? 1 : 0 ) );
   }
   else if( HB_IS_STRING( pSelf ) && HB_IS_STRING( pOther ) )
   {
      int i = hb_itemStrCmp( pSelf, pOther, HB_TRUE );
      hb_retni( i < 0 ? -1 : ( i > 0 ? 1 : 0 ) );
   }
   else if( HB_IS_DATE( pSelf ) && HB_IS_DATE( pOther ) )
   {
      long l1 = pSelf->item.asDateTime.julian;
      long l2 = pOther->item.asDateTime.julian;
      hb_retni( l1 < l2 ? -1 : ( l1 > l2 ? 1 : 0 ) );
   }
   else if( HB_IS_TIMESTAMP( pSelf ) && HB_IS_TIMESTAMP( pOther ) )
   {
      long j1 = pSelf->item.asDateTime.julian;
      long j2 = pOther->item.asDateTime.julian;
      if( j1 != j2 )
         hb_retni( j1 < j2 ? -1 : 1 );
      else
      {
         long t1 = pSelf->item.asDateTime.time;
         long t2 = pOther->item.asDateTime.time;
         hb_retni( t1 < t2 ? -1 : ( t1 > t2 ? 1 : 0 ) );
      }
   }
   else if( HB_IS_LOGICAL( pSelf ) && HB_IS_LOGICAL( pOther ) )
   {
      HB_BOOL l1 = hb_itemGetL( pSelf );
      HB_BOOL l2 = hb_itemGetL( pOther );
      hb_retni( l1 == l2 ? 0 : ( l1 ? 1 : -1 ) );
   }
   else
      hb_ret(); /* NIL — types are not comparable */
}

HB_FUNC_STATIC( msgIsComparable )
{
   HB_STACK_TLS_PRELOAD
   PHB_ITEM pSelf = hb_stackSelfItem();
   hb_retl( HB_IS_NUMERIC( pSelf ) || HB_IS_STRING( pSelf ) ||
            HB_IS_DATE( pSelf ) || HB_IS_TIMESTAMP( pSelf ) ||
            HB_IS_LOGICAL( pSelf ) );
}
```

### 2.4 Initialization Sequence

Add to `hb_clsInit()` AFTER the class pool is allocated (after line 1145):

```c
/* Create DrydockObject root class */
hb_clsInitDrydockObject();
```

New function:
```c
static void hb_clsInitDrydockObject( void )
{
   PHB_ITEM pSuper;

   /* Register dynsyms for new built-in messages */
   s___msgToString.pDynSym    = hb_dynsymGetCase( s___msgToString.szName );
   s___msgIsScalar.pDynSym    = hb_dynsymGetCase( s___msgIsScalar.szName );
   s___msgIsNil.pDynSym       = hb_dynsymGetCase( s___msgIsNil.szName );
   s___msgValType.pDynSym     = hb_dynsymGetCase( s___msgValType.szName );
   s___msgCompareTo.pDynSym   = hb_dynsymGetCase( s___msgCompareTo.szName );
   s___msgIsComparable.pDynSym= hb_dynsymGetCase( s___msgIsComparable.szName );

   /* Create root class with universal methods */
   s_uiDrydockObjectClass = hb_clsCreate( 0, "DrydockObject" );
   hb_clsAdd( s_uiDrydockObjectClass, "TOSTRING",     HB_FUNCNAME( msgToString ) );
   hb_clsAdd( s_uiDrydockObjectClass, "CLASSNAME",    HB_FUNCNAME( msgClassName ) );
   hb_clsAdd( s_uiDrydockObjectClass, "CLASSH",       HB_FUNCNAME( msgClassH ) );
   hb_clsAdd( s_uiDrydockObjectClass, "ISSCALAR",     HB_FUNCNAME( msgIsScalar ) );
   hb_clsAdd( s_uiDrydockObjectClass, "ISNIL",        HB_FUNCNAME( msgIsNil ) );
   hb_clsAdd( s_uiDrydockObjectClass, "VALTYPE",      HB_FUNCNAME( msgValType ) );
   hb_clsAdd( s_uiDrydockObjectClass, "COMPARETO",    HB_FUNCNAME( msgCompareTo ) );
   hb_clsAdd( s_uiDrydockObjectClass, "ISCOMPARABLE", HB_FUNCNAME( msgIsComparable ) );

   /* Set as default parent for all user classes */
   s_uiObjectClass = s_uiDrydockObjectClass;

   /* Create scalar classes inheriting from DrydockObject */
   pSuper = hb_itemArrayNew( 1 );
   hb_arraySetNI( pSuper, 1, s_uiDrydockObjectClass );

   s_uiArrayClass     = hb_clsNew( "ARRAY",     0, pSuper, NULL, HB_FALSE );
   s_uiBlockClass     = hb_clsNew( "BLOCK",     0, pSuper, NULL, HB_FALSE );
   s_uiCharacterClass = hb_clsNew( "CHARACTER", 0, pSuper, NULL, HB_FALSE );
   s_uiDateClass      = hb_clsNew( "DATE",      0, pSuper, NULL, HB_FALSE );
   s_uiTimeStampClass = hb_clsNew( "TIMESTAMP", 0, pSuper, NULL, HB_FALSE );
   s_uiHashClass      = hb_clsNew( "HASH",      0, pSuper, NULL, HB_FALSE );
   s_uiLogicalClass   = hb_clsNew( "LOGICAL",   0, pSuper, NULL, HB_FALSE );
   s_uiNilClass       = hb_clsNew( "NIL",       0, pSuper, NULL, HB_FALSE );
   s_uiNumericClass   = hb_clsNew( "NUMERIC",   0, pSuper, NULL, HB_FALSE );
   s_uiSymbolClass    = hb_clsNew( "SYMBOL",    0, pSuper, NULL, HB_FALSE );
   s_uiPointerClass   = hb_clsNew( "POINTER",   0, pSuper, NULL, HB_FALSE );

   hb_itemRelease( pSuper );
}
```

### 2.5 Default Message Check in hb_objGetMethod()

Add to the default messages section (near line 2200):

```c
else if( pMsg == s___msgToString.pDynSym )
   return &s___msgToString;
else if( pMsg == s___msgIsScalar.pDynSym )
   return &s___msgIsScalar;
else if( pMsg == s___msgIsNil.pDynSym )
   return &s___msgIsNil;
else if( pMsg == s___msgValType.pDynSym )
   return &s___msgValType;
```

### 2.6 hb_clsDoInit() Modification

The existing `hb_clsDoInit()` searches for PRG factory functions and stores
class handles. After this change, the scalar class handles are ALREADY set
by `hb_clsInitDrydockObject()`. The factory functions (when linked) should
EXTEND the existing classes, not create new ones.

The simplest approach: skip the handle assignment if already non-zero:

```c
/* In hb_clsDoInit, inside the loop: */
if( *( s_puiHandles[ i ] ) == 0 )  /* Not already set by C init */
{
   if( HB_IS_OBJECT( pReturn ) )
      *( s_puiHandles[ i ] ) = pReturn->item.asArray.value->uiClass;
}
/* else: class already exists from C init; PRG factory methods
   will extend it via __clsAddMsg() during class creation */
```

---

## 3. Memory Layout Impact

**None.** No struct changes. Classes are created using existing APIs.

---

## 4. Alternatives Considered

### Alternative A: Modify hb_objGetMethod only (no real classes)

Add toString/isScalar as default messages without creating actual scalar
classes. Simpler but doesn't make scalars real objects — `ClassH()` still
returns 0.

**Rejected:** Half-measure. Doesn't achieve "every value is an object."

### Alternative B: Embed class handle in HB_ITEM

Add a `uiClass` field to the HB_ITEM union so every item carries its class.

**Rejected:** ABI break. Increases sizeof(HB_ITEM). Affects GC. Massive change.

### Alternative C: Create classes in PRG, force linking via hbextern

Move the ENABLE TYPE CLASS ALL into the standard extern file so all
executables link the scalar classes.

**Rejected:** Still depends on PRG linking. Doesn't work for minimal
executables. Doesn't provide universal toString().

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · **DESIGN** · [ARCH](ARCHITECTURE.md) · [API](C_API.md) · [COMPAT](COMPAT.md) · [PLAN](IMPLEMENTATION_PLAN.md) · [TESTS](TEST_PLAN.md) · [AUDIT](AUDIT.md)
