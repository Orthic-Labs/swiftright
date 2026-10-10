#if compiler(>=5.3) && $InlineAlways
print("selected=InlineAlways")
#else
print("selected=else")
#endif
