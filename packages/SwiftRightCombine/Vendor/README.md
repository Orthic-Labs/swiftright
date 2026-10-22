# Vendored OpenCombine

OpenCombine 0.14.0 (https://github.com/OpenCombine/OpenCombine, revision 8576f0d579b27020beccbccc3ea6844f3ddfc2c2), MIT licence (`OpenCombine-LICENSE`).
Sources copied unchanged except one edit: every `canImport(Combine)` is replaced by `SWIFTRIGHT_APPLE_COMBINE`, a flag that is never defined.

Why: upstream adds the Apple-named API (DispatchQueue/RunLoop/OperationQueue as Schedulers, NotificationCenter.publisher, Timer.publish, URLSession
publishers) only `#if !canImport(Combine)`. SwiftRightCombine itself is a module named `Combine`, so in the same build that check is true or false
depending on build order (measured 22 Oct 2026: the Dell build lacked the conformances, the CI build had them and rejected ours as redundant). With
the flag the Apple-named API is always compiled in, deterministically.
