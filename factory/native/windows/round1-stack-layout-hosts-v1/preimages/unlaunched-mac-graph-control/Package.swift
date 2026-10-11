// swift-tools-version: 6.0
import PackageDescription
let package=Package(name:"GraphControls",dependencies:[.package(name:"fresh-runtime",path:"/Volumes/D/claude/swiftright/factory/native/windows/module-origin-37429120-20261011/runtime")],targets:[.executableTarget(name:"GraphControls",dependencies:[.product(name:"SwiftRightRuntime",package:"fresh-runtime")])])
