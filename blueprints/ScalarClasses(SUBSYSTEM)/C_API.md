# C_API -- ScalarClasses (SUBSYSTEM)

## New Functions

### `hb_objGetScalarClass()` -- NEW
- **Header**: `include/hbapicls.h`
- **Signature**: `extern HB_EXPORT HB_USHORT hb_objGetScalarClass( PHB_ITEM pItem );`
- **Purpose**: Returns the class handle for any item, including scalar types.
  Unlike `hb_objGetClass()` (which returns 0 for non-objects), this function
  resolves scalar class handles (s_uiCharacterClass, s_uiNumericClass, etc.).
- **Thread Safety**: Safe — read-only after VM init. Scalar class handles are
  static variables initialized during `hb_clsDoInit()` and never modified after.
- **Implementation**: Thin wrapper over the existing internal `hb_objGetClassH()`.
- **Availability**: Always (not gated behind compile flag).

## Unchanged Functions

All existing public functions in `hbapicls.h` retain their current behavior:

- `hb_objGetClass()` — still returns 0 for non-objects (no change)
- `hb_objGetClsName()` — already returns scalar class names (no change)
- `hb_objHasMsg()` — already resolves scalar methods (no change)
- `hb_objSendMsg()` — already dispatches to scalar methods (no change)

## No Removed Functions

No existing public symbols are removed or changed.

## ABI Compatibility

**Full ABI compatibility.** One new exported symbol added. No existing symbols
changed. C extensions compiled against current headers continue to work without
recompilation.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · [DESIGN](DESIGN.md) · **API** · [COMPAT](COMPAT.md) · [PLAN](IMPLEMENTATION_PLAN.md) · [TESTS](TEST_PLAN.md) · [MATRIX](TRACEABILITY.md) · [AUDIT](AUDIT.md)
