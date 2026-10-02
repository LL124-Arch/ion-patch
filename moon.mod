// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "LL124-Arch/ion-patch"

version = "0.0.1"

readme = "README.md"

repository = "https://github.com/LL124-Arch/ion-patch"

license = "Apache-2.0"

keywords = [ ]

preferred_target = "wasm"

description = "Scaffold for Ion-aware structural differences and atomic patches"

import {
  "LL124-Arch/amazon-ion-moonbit-core@0.1.2",
}
