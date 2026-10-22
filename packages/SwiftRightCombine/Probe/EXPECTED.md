# SwiftRightCombine probe (#88)

`main.swift` is written against Apple's Combine. It builds unchanged on macOS (system Combine) and on Windows (this package), Swift 6.4, 22 Oct 2026.

macOS 27:
`cl=0/a | cl3=0atrue | will | will | cl3=1atrue | cl=1/a | c2=2 | will | will | cl3=1atrue | cl=1/a | will | will | cl=1/b | cl3=1btrue | merge=[9, 2] | note | main=2 | deb=2 | ticks>=5:true | derived=1-b`

Windows (Dell):
`cl=0/a | cl3=0atrue | will | cl3=1atrue | will | c2=2 | cl=1/a | will | cl3=1atrue | will | cl=1/a | will | cl=1/b | cl3=1btrue | will | merge=[9, 2] | note | main=2 | deb=2 | ticks>=5:true | derived=1-b`

Same values, same count of each event. Difference: the ORDER in which several subscribers of one `@Published` property hear a change (Apple does not document it). Code that depends on that order is not portable.
