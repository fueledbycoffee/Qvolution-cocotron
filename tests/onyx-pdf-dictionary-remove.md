# Physical PDF dictionary deletion

`onyx-pdf-dictionary-remove` checks removal, lookup absence, a missing-key no-op,
unrelated-key preservation, and removal after reinsertion. The method is an owned
Onyx2D helper using this tree's NSMapRemove contract, not an Apple private API.

The regression was frozen before implementation. Root's Stage35 source-control
before executable fails because the selector is absent; after passes with the
exact production method compiled as a category on the existing owned class.
No duplicate class or substitute dictionary implementation is linked. All seven
PDF model controls also pass with this exact method, with no timeout and exact
prefix shutdown zero. Normal installed-method/framework linkage is separate.

PDF null dictionary values have absent-value semantics, but physically deleting
obsolete optional XRefStm/stream trailer keys preserves the absent representation
and avoids strict-reader incompatibility. The actual updated PDF then passes the
unchanged pypdf strict reader's page/annotation/reference/content checks.
