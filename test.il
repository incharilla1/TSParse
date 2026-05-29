%t = opaque ; TypeAlias
%t = opaque ; TypeAlias
%t = opaque ; TypeAlias
%t = opaque ; TypeAlias
%t = opaque ; TypeAlias
%t = opaque ; TypeAlias
func parse(input):
endfunc parse
func parse(input, strict):
endfunc parse
func parse(input, strict):
%t = const true
%t = seq strict, %t
branch %t, L, L
L:
%t = field JSON.parse
%t = call %t(input)
ret %t
L:
L:
%t = field JSON.parse
%t = call %t(input)
ret %t
jump L
L:
%t = const null
ret %t
L:
endfunc parse
%t = opaque ; TypeAlias
%t = opaque ; TypeAlias
func tupleTest(args):
%t = add s, n
%t = field rest.length
%t = add %t, %t
ret %t
endfunc tupleTest
%t = opaque ; TypeAlias
func getValue(flag):
endfunc getValue
%t = const 0
i = mov %t ; let
%t = const 10
%t = lt i, %t
%t = mov i
%t = add i, 1
i = mov %t
%t = const 0
j = mov %t ; let
%t = const 10
%t = lt j, %t
%t = mov j
%t = add j, 1
j = mov %t
%t = const 5
%t = gt j, %t
branch %t, L, L
L:
jump <continue>
L:
ret input
%t = const 1
%t = const 2
%t = const 3
%t = add %t, %t
%t = shl %t, %t
tricky = mov %t ; const
%t = const 10
%t = const 2
%t = div %t, %t
%t = const 3
%t = mul %t, %t
%t = const 4
%t = sub %t, %t
%t = const 1
%t = add %t, %t
mixed = mov %t ; const
func Log(target, key, descriptor):
%t = field descriptor.value
original = mov %t ; const
%t = opaque ; FunctionDeclaration
%t = field descriptor.value
%t = mov %t
ret descriptor
endfunc Log
%t = opaque ; ClassDeclaration
%t = opaque ; NamespaceDeclaration
%t = opaque ; TypeAlias
%t = opaque ; TypeAlias
%t = opaque ; TypeAlias
%t = opaque ; TypeAlias
%t = const dynamic_key
key = mov %t ; const
%t = object {}
%t = const 123
%t.System.Collections.Hashtable = mov %t
%t = const value
%t.System.Collections.Hashtable = mov %t
obj = mov %t ; const
%t = opaque ; TypeAlias
%t = opaque ; TypeAlias
func stream(limit):
%t = const 0
i = mov %t ; let
L:
%t = lt i, limit
branch %t, L, L
L:
%t = opaque ; YieldExpression
jump L
L:
endfunc stream
%t = opaque ; TypeAlias
%t = const 200
%t = const OK
%t = object {}
%t = const true
%t.ok = mov %t
%t = array [%t, %t, %t]
res = mov %t ; const
%t = opaque ; ExportNamed
